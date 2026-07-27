import { MAX_AMOUNT } from '../utils/financeMath';
import { DebtModel, DebtDirection, Debt } from '../models/DebtModel';
import { WalletModel } from '../models/WalletModel';
import { emitToUser } from '../socket';
import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';

/**
 * Parses an optional wallet id from a request body: undefined/null = the money
 * isn't tracked in any wallet, 0 = the default bucket, >0 must be the caller's
 * wallet. Returns { error } for anything invalid.
 */
async function parseOptionalWallet(
  userId: string,
  raw: unknown,
): Promise<{ walletId: number | null; error?: string }> {
  if (raw === undefined || raw === null) return { walletId: null };
  const id = Number(raw);
  if (!Number.isInteger(id) || id < 0) return { walletId: null, error: 'Invalid wallet' };
  if (id > 0 && !(await WalletModel.findById(userId, id))) {
    return { walletId: null, error: 'Wallet not found' };
  }
  return { walletId: id };
}

/** The signed cash movement an IOU event causes, and how the ledger names it. */
function debtLeg(debt: Debt, event: 'create' | 'settle'): { amount: number; title: string } {
  const abs = Math.abs(Number(debt.amount));
  if (event === 'create') {
    return debt.direction === 'owed_to_me'
      ? { amount: -abs, title: `Lent to ${debt.counterparty_name}` }
      : { amount: abs, title: `Borrowed from ${debt.counterparty_name}` };
  }
  return debt.direction === 'owed_to_me'
    ? { amount: abs, title: `Repaid by ${debt.counterparty_name}` }
    : { amount: -abs, title: `Repaid to ${debt.counterparty_name}` };
}

export async function listDebts(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const debts = await DebtModel.listByUser(userId);
  return res.json({ debts });
}

/**
 * Creates an IOU. `wallet_id` (optional) names where the cash physically moved:
 * lending debits it, borrowing credits it — one transfer-excluded leg, so the
 * wallet is right and nothing counts as earning/spending. Skipping the wallet
 * means the money isn't tracked in the app (cash under the mattress) — the open
 * IOU still enters net worth either way.
 */
export async function createDebt(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { counterparty_name, amount, currency, direction, note, client_op_id, wallet_id } = req.body ?? {};

  const name = typeof counterparty_name === 'string' ? counterparty_name.trim().slice(0, 120) : '';
  if (!name) return res.status(400).json({ message: 'Who is this debt with? Name is required' });

  const amt = Number(amount);
  if (!Number.isFinite(amt) || amt <= 0 || amt > MAX_AMOUNT) {
    return res.status(400).json({ message: 'Amount must be a positive number' });
  }

  const { walletId, error } = await parseOptionalWallet(userId, wallet_id);
  if (error) return res.status(404).json({ message: error });

  const dir: DebtDirection = direction === 'i_owe' ? 'i_owe' : 'owed_to_me';
  const cur = typeof currency === 'string' && currency.trim()
    ? currency.trim().toUpperCase().slice(0, 10)
    : 'LKR';
  const cleanNote = typeof note === 'string' && note.trim() ? note.trim().slice(0, 500) : null;

  const { debt, isNew } = await DebtModel.create(
    userId,
    name,
    Math.round(amt * 100) / 100,
    cur,
    dir,
    cleanNote,
    typeof client_op_id === 'string' ? client_op_id : null,
  );

  // Fresh insert only — an offline replay must not move the cash twice.
  if (isNew && walletId !== null) {
    const leg = debtLeg(debt, 'create');
    await WalletModel.recordDebtMovement(userId, walletId, leg.amount, cur, leg.title);
    emitToUser(userId, 'wallet:changed', { debt_id: debt.id });
  }

  emitToUser(userId, 'debt:changed', { debt });
  return res.status(201).json({ debt });
}

/**
 * Settles an open IOU. `wallet_id` (optional) is where the repayment landed
 * (owed-to-me) or left from (i-owe) — recorded as a transfer-excluded leg, so
 * Earnings/Spendings never move. This replaces the old client-side "Settle +
 * log" flow, which posted the repayment as plain income/expense and inflated
 * lifetime earnings with every settled loan.
 */
export async function settleDebt(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  const { walletId, error } = await parseOptionalWallet(userId, req.body?.wallet_id);
  if (error) return res.status(404).json({ message: error });

  const existing = await DebtModel.findById(userId, id);
  if (!existing) return res.status(404).json({ message: 'Debt not found' });

  // One-shot transition: null here means it was already settled, and the money
  // must not move again.
  const debt = await DebtModel.settle(userId, id);
  if (!debt) return res.json({ debt: existing });

  if (walletId !== null) {
    const leg = debtLeg(debt, 'settle');
    await WalletModel.recordDebtMovement(userId, walletId, leg.amount, debt.currency || 'LKR', leg.title);
    emitToUser(userId, 'wallet:changed', { debt_id: debt.id });
  }

  emitToUser(userId, 'debt:changed', { debt });
  return res.json({ debt });
}

export async function deleteDebt(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const ok = await DebtModel.delete(userId, id);
  if (!ok) return res.status(404).json({ message: 'Debt not found' });
  emitToUser(userId, 'debt:changed', { id });
  return res.json({ message: 'Debt deleted' });
}
