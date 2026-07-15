import type { Response } from 'express';
import { RecurringModel } from '../models/RecurringModel';
import { detectForUser } from '../services/subscriptionDetector';
import type { AuthedRequest } from '../middleware/requireAuth';
import { emitToUser } from '../socket';

/** GET /api/recurring/detected — subscription-like series found in real history. */
export async function listDetectedSubscriptions(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const detected = await detectForUser(userId);
  return res.json({ detected });
}

export async function listRecurring(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { limit, offset } = (req as any).pagination || { limit: 50, offset: 0 };
  const [rows, total] = await Promise.all([
    RecurringModel.listByUser(userId, limit, offset),
    RecurringModel.countByUser(userId),
  ]);
  return res.json({ recurring: rows, page: { limit, offset, total } });
}

export async function createRecurring(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { title, amount, category, frequency, startDate } = req.body || {};

  const numAmount = Number(amount);
  const freq = frequency || 'monthly';

  // Calculate next_run as the first future date based on frequency
  const now = new Date();
  if (!startDate) {
    if (freq === 'daily') now.setDate(now.getDate() + 1);
    else if (freq === 'weekly') now.setDate(now.getDate() + 7);
    else if (freq === 'yearly') now.setFullYear(now.getFullYear() + 1);
    else now.setMonth(now.getMonth() + 1); // monthly default
  }
  const nextRun = startDate || `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;

  const row = await RecurringModel.create(userId, title, numAmount, category, freq, nextRun);

  // Socket notification (foreground/local only)
  emitToUser(userId, 'recurring:created', {
    title: '🔄 Recurring Added',
    body: `${title} (${freq}) — ${formatAmount(numAmount)}`,
    recurring: row,
  });

  return res.status(201).json({ recurring: row });
}

export async function updateRecurring(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const { title, amount, category, frequency, is_active } = req.body || {};

  const fields: any = {};
  if (title !== undefined) fields.title = title;
  if (amount !== undefined) fields.amount = Number(amount);
  if (category !== undefined) fields.category = category;
  if (frequency !== undefined) fields.frequency = frequency;
  if (is_active !== undefined) fields.is_active = Boolean(is_active);

  const row = await RecurringModel.update(userId, id, fields);
  if (!row) return res.status(404).json({ message: 'Recurring transaction not found' });
  return res.json({ recurring: row });
}

export async function deleteRecurring(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  const existing = await RecurringModel.findById(userId, id);
  const ok = await RecurringModel.delete(userId, id);
  if (!ok) return res.status(404).json({ message: 'Recurring transaction not found' });

  // Socket notification (foreground/local only)
  const ruleTitle = existing?.title || 'Recurring rule';
  emitToUser(userId, 'recurring:deleted', {
    title: '🗑️ Recurring Removed',
    body: `${ruleTitle} has been removed`,
    id,
  });

  return res.json({ message: 'Recurring transaction deleted' });
}

export async function bulkDeleteRecurring(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const ids = (req.body as { ids: number[] }).ids;
  const deletedCount = await RecurringModel.bulkDeleteByUser(userId, ids);
  return res.json({ message: 'Recurring rules deleted', deletedCount });
}

function formatAmount(amount: number): string {
  const abs = Math.abs(amount).toFixed(2);
  return amount < 0 ? `-₨.${abs}` : `₨.${abs}`;
}
