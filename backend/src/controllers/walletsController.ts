import { MAX_AMOUNT } from '../utils/financeMath';
import { WalletModel } from '../models/WalletModel';
import { sql } from '../config/db';
import { emitToUser } from '../socket';
import { notifyIfPaidOff } from '../services/payoffService';
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

/**
 * Month-end money on hand for the dashboard's 6-month chart, on the same basis
 * as the headline — so tapping the last point shows the headline's number.
 */
export async function getBalanceHistory(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const requested = Number(req.query.months);
  const months = Number.isInteger(requested) && requested >= 1 && requested <= 24 ? requested : 6;
  const currency = await preferredCurrency(userId);
  const points = await WalletModel.moneyOnHandHistory(userId, currency, months);
  return res.json({ points, currency });
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
  if (!Number.isFinite(amt) || amt <= 0 || amt > MAX_AMOUNT) {
    return res.status(400).json({ message: 'Enter a valid amount' });
  }

  // Both real wallets must exist and belong to the user (id 0 = default bucket).
  const lookup = async (id: number): Promise<{ name: string; isLiability: boolean } | null> => {
    if (id === 0) return { name: 'Default', isLiability: false };
    const w = await WalletModel.findById(userId, id);
    return w ? { name: w.name, isLiability: WalletModel.isLiabilityType(w.type) } : null;
  };
  const [from, to] = await Promise.all([lookup(fromId), lookup(toId)]);
  if (!from || !to) {
    return res.status(404).json({ message: 'Wallet not found' });
  }

  // Name what actually happened when a debt account is involved, matching the
  // wording the transfer hint shows: paying a loan/card is a repayment, taking
  // money out of one is borrowing — "Transfer to X" describes neither.
  let titles: { from: string; to: string } | undefined;
  if (to.isLiability && !from.isLiability) {
    titles = { from: `Repayment — ${to.name}`, to: `Repayment from ${from.name}` };
  } else if (from.isLiability && !to.isLiability) {
    titles = { from: `Borrowed — ${from.name}`, to: `Borrowed from ${from.name}` };
  }

  const currency = await preferredCurrency(userId);

  // A repayment can clear the debt entirely — remember what was owed so the
  // payoff celebration fires exactly on the crossing.
  let owedBefore = 0;
  if (to.isLiability) {
    owedBefore = Math.max(0, -(await WalletModel.balanceOf(userId, toId, currency)));
  }

  const { transferId } = await WalletModel.transfer(
    userId, fromId, toId, Math.round(amt * 100) / 100, currency, from.name, to.name, titles,
  );
  const fromName = from.name;
  const toName = to.name;

  if (to.isLiability) {
    void notifyIfPaidOff(userId, toId, owedBefore, currency);
  }

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

/**
 * Creates a wallet, optionally seeded with what's already in it. `opening_balance`
 * arrives as a positive magnitude and is signed by wallet type: liabilities
 * (credit/card/loan) seed NEGATIVE — that's the debt owed — assets seed positive.
 * The seed is a transfer-excluded transaction, so it never inflates
 * earnings/spending; only the balance and net worth move.
 */
export async function createWallet(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { name, type, currency, opening_balance, drawdown_wallet_id, credit_limit } = req.body ?? {};

  const cleanName = typeof name === 'string' ? name.trim() : '';
  if (!cleanName) return res.status(400).json({ message: 'Wallet name is required' });
  if (cleanName.length > 100) return res.status(400).json({ message: 'Wallet name is too long' });
  // Reject rather than let normalizeType quietly turn a typo into a cash wallet.
  if (type !== undefined && !WalletModel.isKnownType(type)) {
    return res.status(400).json({ message: 'Unknown wallet type' });
  }
  const cur = typeof currency === 'string' && currency.trim() ? currency.trim().toUpperCase().slice(0, 10) : 'LKR';

  let opening = 0;
  if (opening_balance !== undefined && opening_balance !== null && opening_balance !== '') {
    opening = Number(opening_balance);
    if (!Number.isFinite(opening) || opening < 0 || opening > MAX_AMOUNT) {
      return res.status(400).json({ message: 'Enter a valid opening balance' });
    }
    opening = Math.round(opening * 100) / 100;
  }

  // Spending ceiling. For credit/card it's the classic credit limit; for a
  // loan it's an optional "maximum owed" cap — interest can legitimately grow
  // a loan past its principal, but the user can draw a line it may not cross.
  let creditLimit: number | null = null;
  if (credit_limit !== undefined && credit_limit !== null && credit_limit !== '') {
    if (!['credit', 'card', 'loan'].includes(WalletModel.normalizeType(type))) {
      return res.status(400).json({ message: 'Only credit, card and loan wallets take a limit' });
    }
    creditLimit = Number(credit_limit);
    if (!Number.isFinite(creditLimit) || creditLimit <= 0 || creditLimit > MAX_AMOUNT) {
      return res.status(400).json({ message: 'Enter a valid credit limit' });
    }
    creditLimit = Math.round(creditLimit * 100) / 100;
  }

  // Where a new loan's money landed. Only meaningful for a liability being
  // seeded: an asset's opening balance IS the money, and a seeded card is
  // already-charged, so there's no cash to place.
  let drawdown: { walletId: number; walletName: string } | undefined;
  if (drawdown_wallet_id !== undefined && drawdown_wallet_id !== null && opening > 0) {
    if (!WalletModel.isLiabilityType(type)) {
      return res.status(400).json({ message: 'Only a debt account can put borrowed money into a wallet' });
    }
    const destId = Number(drawdown_wallet_id);
    if (!Number.isInteger(destId) || destId < 0) {
      return res.status(400).json({ message: 'Choose where the borrowed money landed' });
    }
    const destName = destId === 0 ? 'Default' : (await WalletModel.findById(userId, destId))?.name;
    if (!destName) return res.status(404).json({ message: 'Wallet not found' });
    drawdown = { walletId: destId, walletName: destName };
  }

  try {
    // Always through createWithOpening, including for 0 — it records the answer
    // as 0 (and writes no seed), which is what keeps "the user told us it's
    // empty" distinct from NULL, "this wallet predates the question".
    const wallet = await WalletModel.createWithOpening(userId, cleanName, type, cur, opening, drawdown, creditLimit);
    if (opening > 0) emitToUser(userId, 'tx:summary:invalidate', { user_id: userId });
    emitToUser(userId, 'wallet:changed', { wallet });
    return res.status(201).json({ wallet });
  } catch (err: any) {
    if (/duplicate key/i.test(String(err?.message))) {
      return res.status(409).json({ message: 'You already have a wallet with that name' });
    }
    throw err;
  }
}

/**
 * Renames/retypes a wallet. Two changes are refused once the wallet holds
 * money, because the sign and currency of every stored row were fixed when it
 * was written and nothing can restate them safely:
 *
 * - **asset ↔ liability**: the balance flips meaning. A cash wallet seeded
 *   +100,000 becomes a loan reporting "credit 100,000" and counting as an
 *   asset. Re-signing just the seed doesn't rescue it either — repayments are
 *   positive too, so loan→cash would turn debt repayments into cash and invent
 *   money.
 * - **currency**: stored amounts keep their old currency, so the wallet's
 *   figures would be silently reinterpreted at the new one's rate.
 *
 * Same-side moves (cash↔bank↔investment, card↔credit↔loan) are always fine.
 */
export async function updateWallet(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const { name, type, currency, credit_limit } = req.body ?? {};

  const existing = await WalletModel.findById(userId, id);
  if (!existing) return res.status(404).json({ message: 'Wallet not found' });

  const nextType = typeof type === 'string' ? type : undefined;
  if (nextType !== undefined && !WalletModel.isKnownType(nextType)) {
    return res.status(400).json({ message: 'Unknown wallet type' });
  }

  // Credit limit: undefined = unchanged, null/'' = cleared, number = set.
  let nextLimit: number | null | undefined = undefined;
  if (credit_limit !== undefined) {
    if (credit_limit === null || credit_limit === '') {
      nextLimit = null;
    } else {
      const effectiveType = WalletModel.normalizeType(nextType ?? existing.type);
      if (!['credit', 'card', 'loan'].includes(effectiveType)) {
        return res.status(400).json({ message: 'Only credit, card and loan wallets take a limit' });
      }
      const lim = Number(credit_limit);
      if (!Number.isFinite(lim) || lim <= 0 || lim > MAX_AMOUNT) {
        return res.status(400).json({ message: 'Enter a valid credit limit' });
      }
      nextLimit = Math.round(lim * 100) / 100;
    }
  }
  const nextCurrency =
    typeof currency === 'string' && currency.trim() ? currency.trim().toUpperCase().slice(0, 10) : undefined;

  const crossesSides =
    nextType !== undefined &&
    WalletModel.isLiabilityType(nextType) !== WalletModel.isLiabilityType(existing.type);
  const changesCurrency = nextCurrency !== undefined && nextCurrency !== existing.currency;

  if (crossesSides || changesCurrency) {
    if (await WalletModel.hasTransactions(userId, id)) {
      return res.status(409).json({
        message: crossesSides
          ? 'This wallet already has transactions, so it can\'t switch between an asset and a debt account. Create a new wallet and move the money across.'
          : 'This wallet already has transactions in ' + existing.currency +
            ', so its currency can\'t change. Create a new wallet and move the money across.',
      });
    }
  }

  const wallet = await WalletModel.update(userId, id, {
    name: typeof name === 'string' && name.trim() ? name.trim().slice(0, 100) : undefined,
    type: nextType,
    currency: nextCurrency,
    credit_limit: nextLimit,
  });
  if (!wallet) return res.status(404).json({ message: 'Wallet not found' });
  emitToUser(userId, 'wallet:changed', { wallet });
  return res.json({ wallet });
}

/**
 * Corrects the wallet's opening balance — what it held (or owed) when it was
 * created. Separate from updateWallet because it rewrites transactions, not
 * just wallet columns: the seed is replaced, so the wallet's balance moves.
 */
export async function correctOpeningBalance(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const { opening_balance, drawdown_wallet_id } = req.body ?? {};

  const wallet = await WalletModel.findById(userId, id);
  if (!wallet) return res.status(404).json({ message: 'Wallet not found' });

  const opening = Number(opening_balance);
  if (!Number.isFinite(opening) || opening < 0 || opening > MAX_AMOUNT) {
    return res.status(400).json({ message: 'Enter a valid opening balance' });
  }
  const rounded = Math.round(opening * 100) / 100;

  let drawdown: { walletId: number; walletName: string } | undefined;
  if (drawdown_wallet_id !== undefined && drawdown_wallet_id !== null && rounded > 0) {
    if (!WalletModel.isLiabilityType(wallet.type)) {
      return res.status(400).json({ message: 'Only a debt account can put borrowed money into a wallet' });
    }
    const destId = Number(drawdown_wallet_id);
    if (!Number.isInteger(destId) || destId < 0 || destId === id) {
      return res.status(400).json({ message: 'Choose where the borrowed money landed' });
    }
    // The destination may have been deleted since the drawdown was recorded, in
    // which case there's nowhere to put the cash leg back.
    const destName = destId === 0 ? 'Default' : (await WalletModel.findById(userId, destId))?.name;
    if (!destName) {
      return res.status(404).json({ message: 'That wallet no longer exists — pick another one for the money.' });
    }
    drawdown = { walletId: destId, walletName: destName };
  }

  const updated = await WalletModel.replaceOpening(userId, wallet, rounded, drawdown);
  if (!updated) return res.status(404).json({ message: 'Wallet not found' });

  emitToUser(userId, 'wallet:changed', { wallet: updated });
  emitToUser(userId, 'tx:summary:invalidate', { user_id: userId });
  return res.json({ wallet: updated });
}

/**
 * Deleting a wallet moves its transactions to the default bucket. That reads
 * fine for an asset — the cash is still yours — but the default bucket is typed
 * 'cash', so a debt's negative rows would land there and be counted as money on
 * hand, quietly dragging the balance negative with no wallet to explain it. An
 * outstanding debt has to be settled (or transferred) before the wallet goes.
 */
export async function deleteWallet(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  const wallet = await WalletModel.findById(userId, id);
  if (!wallet) return res.status(404).json({ message: 'Wallet not found' });

  if (WalletModel.isLiabilityType(wallet.type)) {
    const cur = await preferredCurrency(userId);
    const balance = await WalletModel.balanceOf(userId, id, cur);
    if (balance < -0.01) {
      return res.status(409).json({
        message: `${wallet.name} still owes ${Math.abs(balance).toFixed(0)} ${cur}. ` +
          'Pay it off (transfer from another wallet) before deleting it.',
      });
    }
  }

  const ok = await WalletModel.delete(userId, id);
  if (!ok) return res.status(404).json({ message: 'Wallet not found' });
  emitToUser(userId, 'wallet:changed', { id });
  return res.json({ message: 'Wallet deleted. Its transactions moved to the default wallet.' });
}
