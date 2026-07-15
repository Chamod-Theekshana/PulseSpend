import { DebtModel, DebtDirection } from '../models/DebtModel';
import { emitToUser } from '../socket';
import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';

export async function listDebts(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const debts = await DebtModel.listByUser(userId);
  return res.json({ debts });
}

export async function createDebt(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { counterparty_name, amount, currency, direction, note, client_op_id } = req.body ?? {};

  const name = typeof counterparty_name === 'string' ? counterparty_name.trim().slice(0, 120) : '';
  if (!name) return res.status(400).json({ message: 'Who is this debt with? Name is required' });

  const amt = Number(amount);
  if (!Number.isFinite(amt) || amt <= 0 || amt > 1_000_000_000) {
    return res.status(400).json({ message: 'Amount must be a positive number' });
  }

  const dir: DebtDirection = direction === 'i_owe' ? 'i_owe' : 'owed_to_me';
  const cur = typeof currency === 'string' && currency.trim()
    ? currency.trim().toUpperCase().slice(0, 10)
    : 'LKR';
  const cleanNote = typeof note === 'string' && note.trim() ? note.trim().slice(0, 500) : null;

  const debt = await DebtModel.create(
    userId,
    name,
    Math.round(amt * 100) / 100,
    cur,
    dir,
    cleanNote,
    typeof client_op_id === 'string' ? client_op_id : null,
  );

  emitToUser(userId, 'debt:changed', { debt });
  return res.status(201).json({ debt });
}

export async function settleDebt(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const debt = await DebtModel.settle(userId, id);
  if (!debt) return res.status(404).json({ message: 'Debt not found' });
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
