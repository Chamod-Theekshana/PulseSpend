import { WalletModel } from '../models/WalletModel';
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
 *
 * The spare is DEBITED from the configured round-up wallet as a transfer-tagged
 * leg, exactly like a manual contribution. Without that debit the goal — and
 * net worth — grows out of nothing on every rounded expense, which is how this
 * used to behave. Consequently: no wallet configured → the rule is paused, and
 * a wallet that can't cover the spare skips this round (it's small change; a
 * skipped round-up isn't worth a notification).
 */
async function applyRoundUp(userId: string, amount: number, currency: string): Promise<void> {
  if (amount >= 0) return; // expenses only
  try {
    const rows = await sql`SELECT roundup_goal_id, roundup_to, roundup_wallet_id, currency FROM users WHERE id = ${userId}`;
    const goalId = Number((rows[0] as any)?.roundup_goal_id);
    const roundTo = Number((rows[0] as any)?.roundup_to);
    const walletRaw = (rows[0] as any)?.roundup_wallet_id;
    const preferred = ((rows[0] as any)?.currency as string) || 'LKR';
    if (!Number.isInteger(goalId) || goalId <= 0 || !Number.isInteger(roundTo) || roundTo <= 0) return;
    if (walletRaw === null || walletRaw === undefined) return; // paused until a wallet is chosen
    const walletId = Number(walletRaw);

    const spent = Math.abs(amount);
    const spare = Math.round((roundTo - (spent % roundTo)) * 100) / 100;
    if (spare <= 0 || spare >= roundTo) return; // already a clean multiple

    // Can the wallet cover it? Same guard as manual contributions.
    const balance = await WalletModel.balanceOf(userId, walletId, preferred);
    let needed = spare;
    try {
      needed = await convert(spare, currency || 'LKR', preferred);
    } catch {}
    if (needed > balance + 0.0001) return; // skip this round

    const { GoalModel } = await import('../models/GoalModel');
    // Contribution first: near the target the goal clamps, and the wallet must
    // only be debited by what the goal actually received.
    const goal = await GoalModel.addContribution(userId, goalId, spare, 'roundup');
    if (goal && goal.applied_delta > 0) {
      await WalletModel.recordGoalMovement(userId, walletId, -goal.applied_delta, currency || 'LKR', goal.name);
      emitToUser(userId, 'goal:updated', { goal });
      emitToUser(userId, 'wallet:changed', { roundup: true });
    }
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
 * Check if a transaction's category has a budget and send alerts at 80%/100%
 * thresholds. Exported: recurring materialization and goal-spend create real
 * expenses outside this controller and must trip the same alerts.
 */
export async function checkBudgetAlert(userId: string, category: string): Promise<void> {
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
        // Transfer legs (openings, goal/IOU moves, repayments) are money
        // changing pockets — labelling them Income/Expense made the export's
        // Type column double-count against the app's own analytics.
        (tx as any).transfer_id ? 'Transfer' : Number(tx.amount) < 0 ? 'Expense' : 'Income',
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

/**
 * Transfer legs, opening-balance seeds and goal movements all carry a
 * transfer_id and only make sense as a set: editing or deleting one leg leaves
 * the other stranded, permanently desyncing two wallets with no way to notice.
 * They're maintained through the flow that created them, not the generic
 * transaction endpoints.
 */
const TRANSFER_ROW_LOCKED =
  'This entry is part of a transfer, an opening balance or a goal movement. ' +
  'Undo it from the wallet or goal it belongs to instead.';

/** True when the row is one of those linked entries. */
async function isTransferRow(userId: string, transactionId: string): Promise<boolean> {
  const rows = await sql`
    SELECT 1 FROM transactions
    WHERE id = ${transactionId} AND user_id = ${userId} AND transfer_id IS NOT NULL
    LIMIT 1
  `;
  return rows.length > 0;
}

/**
 * A SOFT credit-limit check: warns (but never blocks) a charge that would push a
 * credit/card/loan wallet past its limit — a limit is a ceiling to be aware of,
 * not a wall, matching the app's warn+allow overdraft and warn-only loan
 * behaviour. [addOwed] is how much the operation INCREASES the amount owed,
 * already in the user's preferred currency — for a create that's the converted
 * expense, for an edit it's the owed-delta versus the old row. Returns a warning
 * message to surface, or null when the charge fits within the limit.
 */
async function creditLimitWarning(
  userId: string,
  walletId: number | null,
  addOwed: number,
  preferred: string,
): Promise<string | null> {
  if (!walletId || addOwed <= 0.005) return null;
  const balances = await WalletModel.balances(userId, preferred);
  const b = balances.find((x) => Number(x.id) === walletId);
  if (!b || !['credit', 'card', 'loan'].includes(b.type) || b.credit_limit === null) return null;
  const owed = Math.max(0, -b.balance);
  if (owed + addOwed > b.credit_limit + 0.01) {
    const available = Math.max(0, b.credit_limit - owed);
    return `Heads up — this puts ${b.name} over its available credit ` +
      `(only ${available.toFixed(0)} ${preferred} left of the ${b.credit_limit.toFixed(0)} limit). Recorded anyway.`;
  }
  return null;
}

/** The user's display currency — the basis every balance comparison runs on. */
async function preferredCurrencyOf(userId: string): Promise<string> {
  const rows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
  return ((rows[0] as any)?.currency as string) || 'LKR';
}

/** How much a signed amount adds to a wallet's owed figure, in [preferred]. */
async function owedContribution(signedAmount: number, currency: string, preferred: string): Promise<number> {
  if (signedAmount >= 0) return 0;
  const abs = Math.abs(signedAmount);
  try {
    return await convert(abs, currency || 'LKR', preferred);
  } catch {
    return abs;
  }
}

/**
 * Wallet ids are global SERIALs, so a request body can name any user's wallet.
 * `balances()` scopes by user_id, so a transaction pointed at someone else's
 * wallet matches no wallet of the owner's and is silently dropped from every
 * total — the money just vanishes. Verify ownership before it's stored.
 * Returns true when the id is usable (0/null = the default bucket).
 */
async function walletBelongsToUser(userId: string, walletId: number | null): Promise<boolean> {
  if (walletId === null || walletId === 0) return true;
  return (await WalletModel.findById(userId, walletId)) !== null;
}

export async function createTransaction(req: AuthedRequest, res: Response) {
  const { title, amount, category, created_at, currency, receipt_url, splits, notes, tags, client_op_id, wallet_id, group_id } = req.body;
  const user_id = String(req.user!.id);

  const walletId = Number.isFinite(Number(wallet_id)) ? Number(wallet_id) : null;
  if (!(await walletBelongsToUser(user_id, walletId))) {
    return res.status(400).json({ message: 'Wallet not found' });
  }

  // A charge on a credit/card wallet over its limit is warned about, not blocked
  // — the limit is a soft ceiling (see creditLimitWarning). The note rides back
  // on the success response.
  let creditWarning: string | null = null;
  if (walletId && Number(amount) < 0) {
    const preferred = await preferredCurrencyOf(user_id);
    const addOwed = await owedContribution(Number(amount), String(currency || 'LKR'), preferred);
    creditWarning = await creditLimitWarning(user_id, walletId, addOwed, preferred);
  }

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
    walletId,
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
  void applyRoundUp(user_id, Number(transaction.amount), String(transaction.currency || 'LKR'));

  // Explicitly shared with a group → stamp it + freeze the per-member split +
  // notify THAT group. Expenses AND income can be shared (income splits in
  // reverse: the receiver owes the others their share); only a zero amount /
  // transfer can't. Otherwise keep the legacy heuristic: big expenses ping all
  // the user's groups.
  const sharedGroupId = Number(group_id);
  if (
    Number.isInteger(sharedGroupId) && sharedGroupId > 0 &&
    Number(transaction.amount) !== 0 &&
    (await GroupModel.isMember(sharedGroupId, user_id))
  ) {
    const split = req.body?.group_split;
    const applied = await GroupModel.applyExpenseSplit(
      user_id,
      Number(transaction.id),
      sharedGroupId,
      Math.abs(Number(transaction.amount)),
      String(transaction.currency || 'LKR'),
      split?.mode,
      split?.participants,
    );
    if (!applied.ok) {
      // The transaction is created but not shared — surface the split error so
      // the client can fix it, leaving a plain personal expense behind.
      return res.status(400).json({ message: applied.error, transaction });
    }
    (transaction as any).group_id = sharedGroupId;
    emitToUser(user_id, 'group:changed', { groupId: sharedGroupId });
    void (async () => {
      try {
        const actor = await UserModel.displayName(user_id);
        const group = await GroupModel.findById(sharedGroupId);
        const amountLabel = `${Math.abs(Number(transaction.amount)).toFixed(0)} ${transaction.currency || 'LKR'}`;
        const kind = Number(transaction.amount) < 0 ? 'expense' : 'income';
        for (const memberId of await GroupModel.memberIds(sharedGroupId)) {
          if (memberId === user_id) continue;
          await sendPushToUser(
            memberId,
            `Shared ${kind} in ${group?.name ?? 'your group'}`,
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

  return res.status(201).json({
    message: 'Transaction created successfully',
    transaction,
    ...(creditWarning ? { credit_warning: creditWarning } : {}),
  });
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
    SELECT user_id, title, amount, transfer_id FROM transactions WHERE id = ${transactionId}
  `;

  const found = row?.[0] as any;
  if (!found || String(found.user_id) !== authedUserId) {
    return res.status(404).json({ message: 'Transaction not found' });
  }
  if (found.transfer_id) {
    return res.status(409).json({ message: TRANSFER_ROW_LOCKED });
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

/**
 * The dashboard headline.
 *
 * `balance` is **money on hand** — what's actually in the user's wallets right
 * now — which is what the card claims ("Total Balance / Amount as of <today>").
 * It used to be all-time income minus expense, a lifetime cash-flow net that
 * ignored opening balances entirely: seeding a bank wallet with 50,000 left the
 * headline reading 0.
 *
 * `income`/`expense` stay lifetime totals with transfers excluded — they feed
 * "Earnings"/"Spendings", which are labelled for exactly that, and which must
 * never absorb an opening balance (money you had is not money you earned).
 * So the two no longer share a basis, on purpose: `balance != income + expense`.
 */
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

  const balance = await WalletModel.moneyOnHand(userId, preferredCurrency);

  return res.status(200).json({
    balance,
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
  const { title, amount, category, created_at, currency, receipt_url, splits, notes, tags, wallet_id, group_id } = req.body;

  if (await isTransferRow(authed, id)) {
    return res.status(409).json({ message: TRANSFER_ROW_LOCKED });
  }

  // The pre-edit group_id, so un-sharing can notify the old group.
  const priorGroupRows = await sql`SELECT group_id FROM transactions WHERE id = ${id} AND user_id = ${authed}`;
  const priorGroupId = (priorGroupRows[0] as any)?.group_id ?? null;

  const walletId =
    wallet_id !== undefined ? (Number.isFinite(Number(wallet_id)) ? Number(wallet_id) : null) : undefined;
  if (walletId !== undefined && !(await walletBelongsToUser(authed, walletId))) {
    return res.status(400).json({ message: 'Wallet not found' });
  }

  // Credit-limit check on the OWED DELTA: the old row is already inside the
  // wallet's owed figure, so only the increase this edit causes is tested. A
  // soft warning (never a block) — the note rides back on the response.
  let creditWarning: string | null = null;
  {
    const oldRows = await sql`
      SELECT amount, currency, wallet_id FROM transactions
      WHERE id = ${id} AND user_id = ${authed} AND deleted_at IS NULL
    `;
    const old = oldRows[0] as any;
    if (old) {
      const effectiveWallet =
        walletId !== undefined ? walletId : (old.wallet_id === null ? null : Number(old.wallet_id));
      if (effectiveWallet) {
        const newSigned = amount !== undefined ? Number(amount) : Number(old.amount);
        const newCurrency = String((currency !== undefined ? currency : old.currency) || 'LKR');
        const preferred = await preferredCurrencyOf(authed);
        const newContribution = await owedContribution(newSigned, newCurrency, preferred);
        const oldContribution =
          (old.wallet_id === null ? null : Number(old.wallet_id)) === effectiveWallet
            ? await owedContribution(Number(old.amount), String(old.currency || 'LKR'), preferred)
            : 0;
        creditWarning = await creditLimitWarning(
          authed, effectiveWallet, newContribution - oldContribution, preferred,
        );
      }
    }
  }

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
    walletId,
  );

  if (!tx) return res.status(404).json({ message: 'Transaction not found' });

  // Group sharing on edit: re-freeze the split from the (possibly new) amount,
  // move it between groups, or un-share it. Skipped when group_id isn't in the
  // body (a partial edit leaves existing sharing untouched).
  if (group_id !== undefined) {
    const gid = Number(group_id);
    const totalAbs = Math.abs(Number(tx.amount));
    if (Number.isInteger(gid) && gid > 0 && Number(tx.amount) !== 0 && (await GroupModel.isMember(gid, authed))) {
      const split = req.body?.group_split;
      const applied = await GroupModel.applyExpenseSplit(
        authed, Number(tx.id), gid, totalAbs, String(tx.currency || 'LKR'), split?.mode, split?.participants,
      );
      if (!applied.ok) return res.status(400).json({ message: applied.error, transaction: tx });
      (tx as any).group_id = gid;
      emitToUser(authed, 'group:changed', { groupId: gid });
    } else {
      // Cleared (null/0) or a zero amount → un-share it.
      await GroupModel.clearExpenseSplit(authed, Number(tx.id));
      (tx as any).group_id = null;
      if (Number.isInteger(Number(priorGroupId))) {
        emitToUser(authed, 'group:changed', { groupId: Number(priorGroupId) });
      }
    }
  }

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

  return res.json({
    message: 'Transaction updated successfully',
    transaction: tx,
    ...(creditWarning ? { credit_warning: creditWarning } : {}),
  });
}

export async function bulkDeleteTransactions(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const ids = (req.body as any)?.ids as number[];

  const deletedCount = await TransactionModel.bulkDeleteByUser(userId, ids);

  // tx:deleted is what wallet balances / net worth / the 6-month chart /
  // dashboard-recent listen for — without it a bulk delete updated the list
  // but left every aggregate stale.
  emitToUser(userId, 'tx:deleted', {
    title: 'Transactions deleted',
    body: `${deletedCount} transaction(s) removed`,
  });
  emitToUser(userId, 'tx:summary:invalidate', { user_id: userId });
  emitToUser(userId, 'analytics:invalidate', { user_id: userId });

  return res.json({ message: 'Transactions deleted', deleted: deletedCount });
}
