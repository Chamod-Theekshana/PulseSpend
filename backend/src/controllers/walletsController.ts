import { WalletModel } from '../models/WalletModel';
import { sql } from '../config/db';
import { emitToUser } from '../socket';
import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';

async function preferredCurrency(userId: string): Promise<string> {
  const rows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
  return ((rows[0] as any)?.currency as string) || 'LKR';
}

export async function listWallets(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const wallets = await WalletModel.listByUser(userId);
  return res.json({ wallets });
}

export async function getWalletBalances(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const balances = await WalletModel.balances(userId, await preferredCurrency(userId));
  return res.json({ balances });
}

export async function getNetWorth(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const netWorth = await WalletModel.netWorth(userId, await preferredCurrency(userId));
  return res.json(netWorth);
}

/**
 * Moves money between two wallets. Creates a −/+ transaction pair sharing a
 * transfer uuid; legs shift wallet balances but stay out of income/expense
 * analytics. Wallet id 0 = the virtual default bucket.
 */
export async function transferBetweenWallets(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { from_wallet_id, to_wallet_id, amount } = req.body ?? {};

  const fromId = Number(from_wallet_id);
  const toId = Number(to_wallet_id);
  const amt = Number(amount);

  if (!Number.isInteger(fromId) || !Number.isInteger(toId) || fromId < 0 || toId < 0) {
    return res.status(400).json({ message: 'from_wallet_id and to_wallet_id are required' });
  }
  if (fromId === toId) {
    return res.status(400).json({ message: 'Choose two different wallets' });
  }
  if (!Number.isFinite(amt) || amt <= 0 || amt > 1_000_000_000) {
    return res.status(400).json({ message: 'Enter a valid amount' });
  }

  // Both real wallets must exist and belong to the user (id 0 = default bucket).
  const nameOf = async (id: number): Promise<string | null> => {
    if (id === 0) return 'Default';
    const w = await WalletModel.findById(userId, id);
    return w ? w.name : null;
  };
  const [fromName, toName] = await Promise.all([nameOf(fromId), nameOf(toId)]);
  if (!fromName || !toName) {
    return res.status(404).json({ message: 'Wallet not found' });
  }

  const currency = await preferredCurrency(userId);
  const { transferId } = await WalletModel.transfer(
    userId, fromId, toId, Math.round(amt * 100) / 100, currency, fromName, toName,
  );

  emitToUser(userId, 'wallet:changed', { transfer_id: transferId });
  emitToUser(userId, 'tx:new', {
    title: 'Transfer complete',
    body: `${amt.toFixed(2)} ${currency} moved ${fromName} → ${toName}`,
  });
  emitToUser(userId, 'tx:summary:invalidate', { user_id: userId });

  return res.status(201).json({
    message: 'Transfer complete',
    transfer_id: transferId,
  });
}

export async function createWallet(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { name, type, currency } = req.body ?? {};

  const cleanName = typeof name === 'string' ? name.trim() : '';
  if (!cleanName) return res.status(400).json({ message: 'Wallet name is required' });
  if (cleanName.length > 100) return res.status(400).json({ message: 'Wallet name is too long' });
  const cur = typeof currency === 'string' && currency.trim() ? currency.trim().toUpperCase().slice(0, 10) : 'LKR';

  try {
    const wallet = await WalletModel.create(userId, cleanName, type, cur);
    emitToUser(userId, 'wallet:changed', { wallet });
    return res.status(201).json({ wallet });
  } catch (err: any) {
    if (/duplicate key/i.test(String(err?.message))) {
      return res.status(409).json({ message: 'You already have a wallet with that name' });
    }
    throw err;
  }
}

export async function updateWallet(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const { name, type, currency } = req.body ?? {};

  const wallet = await WalletModel.update(userId, id, {
    name: typeof name === 'string' && name.trim() ? name.trim().slice(0, 100) : undefined,
    type: typeof type === 'string' ? type : undefined,
    currency: typeof currency === 'string' && currency.trim() ? currency.trim().toUpperCase().slice(0, 10) : undefined,
  });
  if (!wallet) return res.status(404).json({ message: 'Wallet not found' });
  emitToUser(userId, 'wallet:changed', { wallet });
  return res.json({ wallet });
}

export async function deleteWallet(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const ok = await WalletModel.delete(userId, id);
  if (!ok) return res.status(404).json({ message: 'Wallet not found' });
  emitToUser(userId, 'wallet:changed', { id });
  return res.json({ message: 'Wallet deleted. Its transactions moved to the default wallet.' });
}
