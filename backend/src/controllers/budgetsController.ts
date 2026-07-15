import type { Response } from 'express';
import { BudgetModel } from '../models/BudgetModel';
import { emitToUser } from '../socket';
import type { AuthedRequest } from '../middleware/requireAuth';

export async function listBudgets(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { limit, offset } = (req as any).pagination || { limit: 50, offset: 0 };
  const [rows, total] = await Promise.all([
    BudgetModel.listByUser(userId, limit, offset),
    BudgetModel.countByUser(userId),
  ]);
  return res.json({ budgets: rows, page: { limit, offset, total } });
}

export async function getBudgetStatus(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const year = req.query.year ? Number(req.query.year) : undefined;
  const month = req.query.month ? Number(req.query.month) : undefined;
  const day = req.query.day ? Number(req.query.day) : undefined;

  // Validate query params
  if (year !== undefined && (isNaN(year) || year < 2000 || year > 2100)) {
    return res.status(400).json({ message: 'Invalid year' });
  }
  if (month !== undefined && (isNaN(month) || month < 1 || month > 12)) {
    return res.status(400).json({ message: 'Invalid month' });
  }
  if (day !== undefined && (isNaN(day) || day < 1 || day > 31)) {
    return res.status(400).json({ message: 'Invalid day' });
  }

  const statuses = await BudgetModel.getStatusByUser(userId, year, month, day);
  return res.json({ budgets: statuses });
}

/** GET /api/budgets/total-status — overall month spend vs the total-budget cap. */
export async function getTotalBudgetStatus(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const status = await BudgetModel.getTotalStatus(userId);
  return res.json(status);
}

/** PUT /api/budgets/total — set/clear the overall monthly budget ({amount} null/0 = off). */
export async function setTotalBudget(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const raw = req.body?.amount;
  const num = Number(raw);
  const enabled = Number.isFinite(num) && num > 0;
  if (raw !== null && raw !== undefined && String(raw) !== '' && !Number.isFinite(num)) {
    return res.status(400).json({ message: 'amount must be a number' });
  }
  if (enabled && num > 1_000_000_000) {
    return res.status(400).json({ message: 'Amount is too large' });
  }
  await BudgetModel.setTotalBudget(userId, enabled ? Math.round(num * 100) / 100 : null);
  const status = await BudgetModel.getTotalStatus(userId);
  emitToUser(userId, 'budget:updated', { total: true });
  return res.json(status);
}

export async function createBudget(req: AuthedRequest, res: Response) {
  try {
    const userId = String(req.user!.id);
    const { category, amount, currency, period } = req.body || {};
    const row = await BudgetModel.create(userId, category, amount, currency, period);

    // Real-time update for all devices
    emitToUser(userId, 'budget:created', { budget: row });

    return res.status(201).json({ budget: row });
  } catch (e: any) {
    const msg = String(e?.message || '');
    if (msg.includes('duplicate') || msg.includes('unique')) {
      return res.status(409).json({ message: 'A budget already exists for this category' });
    }
    console.error('[Budgets] createBudget error:', e);
    return res.status(500).json({ message: 'Failed to create budget' });
  }
}

export async function updateBudget(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const { amount } = req.body || {};

  const row = await BudgetModel.update(userId, id, amount);
  if (!row) return res.status(404).json({ message: 'Budget not found' });

  emitToUser(userId, 'budget:updated', { budget: row });

  return res.json({ budget: row });
}

export async function deleteBudget(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  const ok = await BudgetModel.delete(userId, id);
  if (!ok) return res.status(404).json({ message: 'Budget not found' });

  emitToUser(userId, 'budget:deleted', { id });

  return res.json({ message: 'Budget deleted' });
}

export async function bulkDeleteBudgets(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const ids = (req.body as { ids: number[] }).ids;
  const deletedCount = await BudgetModel.bulkDeleteByUser(userId, ids);
  return res.json({ message: 'Budgets deleted', deletedCount });
}
