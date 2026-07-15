import { TransactionModel } from '../models/TransactionModel';
import { BudgetModel } from '../models/BudgetModel';
import { GroupModel } from '../models/GroupModel';
import { UserModel } from '../models/UserModel';
import { sql } from '../config/db';
import { emitToUser } from '../socket';
import { sendPushToUser } from '../services/pushService';
import { convert } from '../services/exchangeRateService';
import { parseTransactionFilters } from '../middleware/validators';
import { csvCell, sanitizeImportRows } from '../utils/financeMath';
import { collectMonthlyReportData, renderMonthlyReportPdf } from '../services/pdfReportService';
import cloudinary from '../config/cloudinary';
import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';

/**
 * Accepts either a ready URL or a base64 data-URI for a receipt. Data-URIs are
 * uploaded to Cloudinary (same pattern as profile photos) and swapped for the
 * hosted URL. Returns null on empty input; throws only on a failed upload so
 * the caller can surface a clean 500 message.
 */
async function resolveReceiptUrl(receipt: unknown): Promise<string | null> {
  if (!receipt || typeof receipt !== 'string') return null;
  if (!receipt.startsWith('data:image/')) return receipt;
  const uploadResponse = await cloudinary.uploader.upload(receipt, {
    folder: 'pulsespend/receipts',
  });
  return uploadResponse.secure_url;
}

// Expenses at or above this magnitude (in the transaction's own currency) notify
// the user's shared-group members. A heuristic to surface "big" spends without
// spamming a notification for every small purchase.
const GROUP_BIG_EXPENSE_THRESHOLD = 2000;

/**
 * Round-up savings: if the user has a round-up rule, the spare change between
 * an expense and the next multiple of `roundup_to` is auto-contributed to
 * their chosen goal. Fire-and-forget — must never slow or fail the create.
 */
async function applyRoundUp(userId: string, amount: number): Promise<void> {
  if (amount >= 0) return; // expenses only
  try {
    const rows = await sql`SELECT roundup_goal_id, roundup_to FROM users WHERE id = ${userId}`;
    const goalId = Number((rows[0] as any)?.roundup_goal_id);
    const roundTo = Number((rows[0] as any)?.roundup_to);
    if (!Number.isInteger(goalId) || goalId <= 0 || !Number.isInteger(roundTo) || roundTo <= 0) return;

    const spent = Math.abs(amount);
    const spare = Math.round((roundTo - (spent % roundTo)) * 100) / 100;
    if (spare <= 0 || spare >= roundTo) return; // already a clean multiple

    const { GoalModel } = await import('../models/GoalModel');
    const goal = await GoalModel.addContribution(userId, goalId, spare, 'roundup');
    if (goal) emitToUser(userId, 'goal:updated', { goal });
  } catch (err) {
    console.error('[RoundUp] failed:', err);
  }
}

/**
 * When a member logs a sizeable expense, let the other members of their shared
 * group(s) know. Best-effort and fire-and-forget so it never slows or fails a
 * transaction create.
 */
async function notifyGroupsOfExpense(
  userId: string,
  amount: number,
  title: string,
  currency: string,
): Promise<void> {
  if (amount >= 0 || Math.abs(amount) < GROUP_BIG_EXPENSE_THRESHOLD) return;
  try {
    const groups = await GroupModel.listByUser(userId);
    if (!groups.length) return;
    const actor = await UserModel.displayName(userId);
    const amountLabel = `${Math.abs(amount).toFixed(0)} ${currency || 'LKR'}`;
    for (const group of groups) {
      const memberIds = await GroupModel.memberIds(group.id);
      for (const memberId of memberIds) {
        if (memberId === userId) continue;
        await sendPushToUser(
          memberId,
          `New expense in ${group.name}`,
          `${actor} added ${amountLabel} · ${title}`,
          { type: 'group_activity', groupId: String(group.id) },
        );
      }
    }
  } catch (err) {
    console.error('[Groups] expense notification failed:', err);
  }
}

/**
 * Check if a transaction's category has a budget and send alerts at 80%/100% thresholds.
 */
async function checkBudgetAlert(userId: string, category: string): Promise<void> {
  try {
    const budget = await BudgetModel.findByCategory(userId, category);
    if (!budget) return;

    // Measure spend over the budget's own period window (weekly/monthly/yearly).
    const { startDate, endDate } = BudgetModel.periodWindow(budget.period || 'monthly');
    const spent = await BudgetModel.getCategorySpent(userId, category, budget.currency, startDate, endDate);
    const percentage = budget.amount > 0 ? Math.round((spent / Number(budget.amount)) * 100) : 0;

    const level = percentage >= 100 ? 100 : percentage >= 80 ? 80 : 0;
    if (level === 0) return;

    // Dedupe: within one period window, only alert when crossing a NEW, higher
    // threshold — so repeated spending doesn't re-ping the same 80%/100% alert.
    const state = await BudgetModel.getAlertState(budget.id);
    if (state.period === startDate && state.level >= level) return;

    const isExceeded = level === 100;
    emitToUser(userId, 'budget:alert', {
      category,
      percentage,
      spent,
      limit: Number(budget.amount),
      level: isExceeded ? 'exceeded' : 'warning',
    });
    await sendPushToUser(
      userId,
      isExceeded ? `🚨 Budget Exceeded: ${category}` : `⚠️ Budget Warning: ${category}`,
      isExceeded
        ? `You've spent ${spent.toFixed(2)} of your ${Number(budget.amount).toFixed(2)} ${category} budget (${percentage}%).`
        : `You've used ${percentage}% of your ${category} budget (${spent.toFixed(2)} / ${Number(budget.amount).toFixed(2)}).`,
      { type: 'budget_alert', category, level: isExceeded ? 'exceeded' : 'warning' }
    );

    await BudgetModel.setAlertLevel(budget.id, startDate, level);
  } catch (err) {
    console.error('[BudgetAlert] Error checking budget:', err);
  }
}

function getExpenseCategoriesForBudgetChecks(
  amount: number,
  fallbackCategory: string,
  splits?: Array<{ category: string }>,
): string[] {
  if (amount >= 0) return [];

  if (splits && splits.length > 0) {
    const unique = new Set(
      splits
        .map((split) => String(split.category || '').trim())
        .filter((category) => category.length > 0),
    );
    if (unique.size > 0) return Array.from(unique);
  }

  const cleanFallback = String(fallbackCategory || '').trim();
  return cleanFallback ? [cleanFallback] : [];
}

export async function getTransactionByUserId(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { limit, offset } = (req as any).pagination || { limit: 50, offset: 0 };
  const filters = parseTransactionFilters(req);
  const [transactions, total] = await Promise.all([
    TransactionModel.listByUserFiltered(userId, filters, limit, offset),
    TransactionModel.countByUserFiltered(userId, filters),
  ]);
  return res.status(200).json({
    message: 'Transactions fetched successfully',
    transactions,
    page: { limit, offset, total },
  });
}

const CSV_EXPORT_LIMIT = 10000;

/**
 * Streams the user's transactions as a CSV download. Honours the same filter
 * params as the list endpoint (q/category/from/to/minAmount/maxAmount/type) so
 * users can export exactly what they're viewing.
 */
export async function exportTransactionsCsv(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const filters = parseTransactionFilters(req);
  const transactions = await TransactionModel.listByUserFiltered(userId, filters, CSV_EXPORT_LIMIT, 0);

  const header = ['Date', 'Title', 'Category', 'Amount', 'Currency', 'Type', 'Notes', 'Tags'];
  const lines = [header.map(csvCell).join(',')];

  for (const tx of transactions) {
    const date =
      tx.created_at instanceof Date
        ? tx.created_at.toISOString().slice(0, 10)
        : String(tx.created_at).slice(0, 10);
    lines.push(
      [
        date,
        tx.title,
        tx.category,
        Number(tx.amount).toFixed(2),
        tx.currency,
        Number(tx.amount) < 0 ? 'Expense' : 'Income',
        tx.notes ?? '',
        (tx.tags ?? []).join(' '),
      ]
        .map(csvCell)
        .join(','),
    );
  }

  // Prepend a UTF-8 BOM so Excel opens non-ASCII (e.g. රු, ₹) correctly.
  const csv = '﻿' + lines.join('\r\n');
  const filename = `pulsespend_transactions_${new Date().toISOString().slice(0, 10)}.csv`;

  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  return res.status(200).send(csv);
}

/**
 * Streams a monthly PDF report (?month=YYYY-MM, default: current month) —
 * income/expense/net, category breakdown, budget-vs-actual and a net-worth
 * snapshot. Numbers match the analytics screen (transfers excluded).
 */
export async function exportMonthlyReportPdf(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);

  const raw = String(req.query.month || '');
  const match = /^(\d{4})-(\d{2})$/.exec(raw);
  const now = new Date();
  const year = match ? Number(match[1]) : now.getFullYear();
  const month = match ? Number(match[2]) : now.getMonth() + 1;
  if (month < 1 || month > 12 || year < 2000 || year > 2100) {
    return res.status(400).json({ message: 'month must be YYYY-MM' });
  }

  const data = await collectMonthlyReportData(userId, year, month);
  const doc = renderMonthlyReportPdf(data);

  const filename = `pulsespend_report_${year}-${String(month).padStart(2, '0')}.pdf`;
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  doc.pipe(res);
  return;
}

export async function createTransaction(req: AuthedRequest, res: Response) {
  const { title, amount, category, created_at, currency, receipt_url, splits, notes, tags, client_op_id, wallet_id, group_id } = req.body;
  const user_id = String(req.user!.id);

  let resolvedReceipt: string | null;
  try {
    resolvedReceipt = await resolveReceiptUrl(receipt_url);
  } catch (err) {
    console.error('[Tx] Receipt upload failed:', err);
    return res.status(500).json({ message: 'Failed to upload receipt image' });
  }

  const transaction = await TransactionModel.create(
    user_id,
    title,
    amount,
    category,
    created_at,
    currency,
    resolvedReceipt,
    splits,
    notes,
    tags,
    client_op_id || null,
    Number.isFinite(Number(wallet_id)) ? Number(wallet_id) : null,
  );

  emitToUser(user_id, 'tx:new', {
    title: 'New transaction',
    body: `${title} (${amount})`,
    transaction,
  });
  emitToUser(user_id, 'tx:summary:invalidate', { user_id });
  emitToUser(user_id, 'analytics:invalidate', { user_id });

  const affectedCategories = getExpenseCategoriesForBudgetChecks(
    Number(transaction.amount),
    String(transaction.category || category),
    transaction.splits,
  );
  for (const affectedCategory of affectedCategories) {
    await checkBudgetAlert(user_id, affectedCategory);
  }

  // Spare-change savings (only for interactively created expenses — the bulk
  // importer doesn't run through this endpoint, so imports never round up).
  void applyRoundUp(user_id, Number(transaction.amount));

  // Explicitly shared with a group → mark it + notify THAT group (any amount).
  // Otherwise keep the legacy heuristic: big expenses ping all the user's groups.
  const sharedGroupId = Number(group_id);
  if (Number.isInteger(sharedGroupId) && sharedGroupId > 0 && (await GroupModel.isMember(sharedGroupId, user_id))) {
    await sql`UPDATE transactions SET group_id = ${sharedGroupId} WHERE id = ${transaction.id} AND user_id = ${user_id}`;
    (transaction as any).group_id = sharedGroupId;
    void (async () => {
      try {
        const actor = await UserModel.displayName(user_id);
        const group = await GroupModel.findById(sharedGroupId);
        const amountLabel = `${Math.abs(Number(transaction.amount)).toFixed(0)} ${transaction.currency || 'LKR'}`;
        for (const memberId of await GroupModel.memberIds(sharedGroupId)) {
          if (memberId === user_id) continue;
          await sendPushToUser(
            memberId,
            `Shared expense in ${group?.name ?? 'your group'}`,
            `${actor} added ${amountLabel} · ${transaction.title}`,
            { type: 'group_activity', groupId: String(sharedGroupId) },
          );
        }
      } catch (err) {
        console.error('[Groups] shared-expense notification failed:', err);
      }
    })();
  } else {
    void notifyGroupsOfExpense(user_id, Number(transaction.amount), String(transaction.title || title), String(transaction.currency || currency || 'LKR'));
  }

  return res.status(201).json({ message: 'Transaction created successfully', transaction });
}

const BULK_IMPORT_MAX_ROWS = 500;

/**
 * POST /api/transaction/bulk-import — bank-statement CSV import.
 * Validates each row leniently (bad rows are skipped, not fatal) and inserts
 * everything in ONE UNNEST query — row-by-row inserts over Neon's HTTP driver
 * would take minutes for a big statement. `client_op_id` + the partial unique
 * index make re-importing the same file a no-op instead of duplicating.
 * Budget alerts are intentionally skipped (a 300-row import would spam push).
 */
export async function bulkImportTransactions(req: AuthedRequest, res: Response) {
  const user_id = String(req.user!.id);
  const rows = (req.body as any)?.rows;

  if (!Array.isArray(rows) || rows.length === 0) {
    return res.status(400).json({ message: 'rows must be a non-empty array' });
  }
  if (rows.length > BULK_IMPORT_MAX_ROWS) {
    return res.status(400).json({ message: `A maximum of ${BULK_IMPORT_MAX_ROWS} rows per import` });
  }

  const { valid, skipped } = sanitizeImportRows(rows);
  if (valid.length === 0) {
    return res.status(400).json({ message: 'No valid rows to import', skipped });
  }

  const titles = valid.map((r) => r.title);
  const amounts = valid.map((r) => r.amount);
  const categories = valid.map((r) => r.category);
  const dates = valid.map((r) => r.created_at);
  const currencies = valid.map((r) => r.currency);
  const opIds: (string | null)[] = valid.map((r) => r.client_op_id);

  const inserted = await sql`
    INSERT INTO transactions (user_id, title, amount, category, currency, created_at, client_op_id)
    SELECT ${user_id}, t.title, t.amount, t.category, t.currency, t.created_at::date, t.client_op_id
    FROM UNNEST(
      ${titles}::text[],
      ${amounts}::numeric[],
      ${categories}::text[],
      ${currencies}::text[],
      ${dates}::text[],
      ${opIds}::text[]
    ) AS t(title, amount, category, currency, created_at, client_op_id)
    ON CONFLICT (user_id, client_op_id) WHERE client_op_id IS NOT NULL DO NOTHING
    RETURNING id
  `;

  emitToUser(user_id, 'tx:new', { title: 'Import complete', body: `${inserted.length} transactions imported` });
  emitToUser(user_id, 'tx:summary:invalidate', { user_id });
  emitToUser(user_id, 'analytics:invalidate', { user_id });

  return res.status(201).json({
    message: 'Import complete',
    imported: inserted.length,
    duplicates: titles.length - inserted.length,
    skipped,
  });
}

export async function deleteTransaction(req: AuthedRequest, res: Response) {
  const authedUserId = String(req.user!.id);
  const transactionId = String(req.params.id);

  const row = await sql`
    SELECT user_id, title, amount FROM transactions WHERE id = ${transactionId}
  `;

  const found = row?.[0] as any;
  if (!found || String(found.user_id) !== authedUserId) {
    return res.status(404).json({ message: 'Transaction not found' });
  }

  await TransactionModel.deleteByUser(transactionId, authedUserId);

  emitToUser(authedUserId, 'tx:deleted', {
    title: 'Transaction deleted',
    body: found.title ? `${found.title} removed` : 'A transaction was removed',
    transaction_id: transactionId,
  });
  emitToUser(authedUserId, 'tx:summary:invalidate', { user_id: authedUserId });
  emitToUser(authedUserId, 'analytics:invalidate', { user_id: authedUserId });

  return res.status(200).json({ message: 'Transaction deleted successfully' });
}

export async function getTransactionSummaryByUserId(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const userRows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
  const preferredCurrency = (userRows[0] as any)?.currency as string || 'LKR';

  const transactions = await sql`
    SELECT amount, currency FROM transactions
    WHERE user_id = ${userId} AND deleted_at IS NULL AND transfer_id IS NULL
  `;

  let income = 0;
  let expense = 0;

  for (const tx of transactions) {
    const amt = Number((tx as any).amount);
    const txCurrency = ((tx as any).currency as string) || 'LKR';
    try {
      const converted = await convert(amt, txCurrency, preferredCurrency);
      if (converted > 0) income += converted;
      else expense += converted;
    } catch {
      // If conversion fails, use raw amount
      if (amt > 0) income += amt;
      else expense += amt;
    }
  }

  const balance = income + expense;

  return res.status(200).json({
    balance: Math.round(balance * 100) / 100,
    income: Math.round(income * 100) / 100,
    expense: Math.round(expense * 100) / 100,
    currency: preferredCurrency,
  });
}

export async function getTransactionById(req: AuthedRequest, res: Response) {
  const id = String(req.params.id);
  const authed = String(req.user!.id);
  const tx = await TransactionModel.findByIdAndUser(id, authed);
  if (!tx) return res.status(404).json({ message: 'Transaction not found' });
  return res.json({ transaction: tx });
}

export async function updateTransaction(req: AuthedRequest, res: Response) {
  const id = String(req.params.id);
  const authed = String(req.user!.id);
  const { title, amount, category, created_at, currency, receipt_url, splits, notes, tags, wallet_id } = req.body;

  let resolvedReceipt: string | null | undefined;
  try {
    resolvedReceipt = receipt_url !== undefined ? await resolveReceiptUrl(receipt_url) : undefined;
  } catch (err) {
    console.error('[Tx] Receipt upload failed:', err);
    return res.status(500).json({ message: 'Failed to upload receipt image' });
  }

  const tx = await TransactionModel.updateByUser(
    id,
    authed,
    title,
    amount,
    category,
    created_at,
    currency,
    resolvedReceipt,
    splits,
    notes,
    tags,
    wallet_id !== undefined ? (Number.isFinite(Number(wallet_id)) ? Number(wallet_id) : null) : undefined,
  );

  if (!tx) return res.status(404).json({ message: 'Transaction not found' });

  emitToUser(authed, 'tx:updated', {
    title: 'Transaction updated',
    body: `${title} (${amount})`,
    transaction: tx,
  });
  emitToUser(authed, 'tx:summary:invalidate', { user_id: authed });
  emitToUser(authed, 'analytics:invalidate', { user_id: authed });

  const affectedCategories = getExpenseCategoriesForBudgetChecks(
    Number(tx.amount),
    String(tx.category || category),
    tx.splits,
  );
  for (const affectedCategory of affectedCategories) {
    await checkBudgetAlert(authed, affectedCategory);
  }

  return res.json({ message: 'Transaction updated successfully', transaction: tx });
}

export async function bulkDeleteTransactions(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const ids = (req.body as any)?.ids as number[];

  const deletedCount = await TransactionModel.bulkDeleteByUser(userId, ids);

  emitToUser(userId, 'tx:summary:invalidate', { user_id: userId });
  emitToUser(userId, 'analytics:invalidate', { user_id: userId });

  return res.json({ message: 'Transactions deleted', deleted: deletedCount });
}
