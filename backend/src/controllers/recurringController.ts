import type { Response } from 'express';
import { sql } from '../config/db';
import { RecurringModel } from '../models/RecurringModel';
import { detectForUser, dismissSubscription } from '../services/subscriptionDetector';
import type { AuthedRequest } from '../middleware/requireAuth';
import { emitToUser } from '../socket';

/** Advances a date string (YYYY-MM-DD) by one interval of the given frequency. */
function nextRunFrom(fromISO: string, frequency: string): string {
  const d = new Date(`${fromISO}T00:00:00`);
  if (frequency === 'daily') d.setDate(d.getDate() + 1);
  else if (frequency === 'weekly') d.setDate(d.getDate() + 7);
  else if (frequency === 'yearly') d.setFullYear(d.getFullYear() + 1);
  else d.setMonth(d.getMonth() + 1); // monthly
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** GET /api/recurring/detected — subscription-like series found in real history. */
export async function listDetectedSubscriptions(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const detected = await detectForUser(userId);
  return res.json({ detected });
}

/** POST /api/recurring/detected/dismiss — hide a detected series from the list. */
export async function dismissDetectedSubscription(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const name = req.body?.name;
  if (!name || typeof name !== 'string' || name.trim().length < 1) {
    return res.status(400).json({ message: 'name is required' });
  }
  await dismissSubscription(userId, name.trim());
  return res.json({ message: 'Subscription dismissed' });
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
  const { title, amount, category, frequency, startDate, currency, wallet_id } = req.body || {};

  const numAmount = Number(amount);
  const freq = frequency || 'monthly';

  // Currency: use the supplied one, else fall back to the user's preferred
  // currency (never blindly LKR) so new rules post in the right currency.
  let cur = typeof currency === 'string' && currency.trim() ? currency.trim().toUpperCase().slice(0, 10) : '';
  if (!cur) {
    const rows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
    cur = ((rows[0] as any)?.currency as string) || 'LKR';
  }
  const walletId = Number.isInteger(Number(wallet_id)) && Number(wallet_id) > 0 ? Number(wallet_id) : null;

  // Calculate next_run as the first future date based on frequency
  const now = new Date();
  if (!startDate) {
    if (freq === 'daily') now.setDate(now.getDate() + 1);
    else if (freq === 'weekly') now.setDate(now.getDate() + 7);
    else if (freq === 'yearly') now.setFullYear(now.getFullYear() + 1);
    else now.setMonth(now.getMonth() + 1); // monthly default
  }
  const nextRun = startDate || `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;

  const row = await RecurringModel.create(userId, title, numAmount, category, freq, nextRun, cur, walletId);

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
  const { title, amount, category, frequency, is_active, currency, wallet_id } = req.body || {};

  const existing = await RecurringModel.findById(userId, id);
  if (!existing) return res.status(404).json({ message: 'Recurring transaction not found' });

  const fields: any = {};
  if (title !== undefined) fields.title = title;
  if (amount !== undefined) fields.amount = Number(amount);
  if (category !== undefined) fields.category = category;
  if (is_active !== undefined) fields.is_active = Boolean(is_active);
  if (currency !== undefined && String(currency).trim()) {
    fields.currency = String(currency).trim().toUpperCase().slice(0, 10);
  }
  if (wallet_id !== undefined) {
    fields.wallet_id = Number.isInteger(Number(wallet_id)) && Number(wallet_id) > 0 ? Number(wallet_id) : null;
  }
  if (frequency !== undefined) {
    fields.frequency = frequency;
    // Changing the cadence must reschedule the next charge, otherwise the old
    // next_run (computed for the previous frequency) would keep firing.
    if (frequency !== existing.frequency) {
      const today = new Date().toISOString().slice(0, 10);
      fields.next_run = nextRunFrom(today, frequency);
    }
  }

  const row = await RecurringModel.update(userId, id, fields);
  if (!row) return res.status(404).json({ message: 'Recurring transaction not found' });
  emitToUser(userId, 'recurring:created', { recurring: row }); // reuse refresh event
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
