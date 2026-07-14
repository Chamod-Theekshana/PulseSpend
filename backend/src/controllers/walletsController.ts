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
