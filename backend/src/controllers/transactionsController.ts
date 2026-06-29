import { TransactionModel } from '../models/TransactionModel';
import { BudgetModel } from '../models/BudgetModel';
import { sql } from '../config/db';
import { emitToUser } from '../socket';
import { sendPushToUser } from '../services/pushService';
import { convert } from '../services/exchangeRateService';
import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';

/**
 * Check if a transaction's category has a budget and send alerts at 80%/100% thresholds.
 */
async function checkBudgetAlert(userId: string, category: string): Promise<void> {
  try {
    const budget = await BudgetModel.findByCategory(userId, category);
    if (!budget) return;

    const spent = await BudgetModel.getCategorySpent(userId, category, budget.currency);
    const percentage = budget.amount > 0 ? Math.round((spent / Number(budget.amount)) * 100) : 0;

    if (percentage >= 100) {
      emitToUser(userId, 'budget:alert', {
        category,
        percentage,
        spent,
        limit: Number(budget.amount),
        level: 'exceeded',
      });
      await sendPushToUser(
        userId,
        `🚨 Budget Exceeded: ${category}`,
        `You've spent ${spent.toFixed(2)} of your ${Number(budget.amount).toFixed(2)} ${category} budget (${percentage}%).`,
        { type: 'budget_alert', category, level: 'exceeded' }
      );
    } else if (percentage >= 80) {
      emitToUser(userId, 'budget:alert', {
        category,
        percentage,
        spent,
        limit: Number(budget.amount),
        level: 'warning',
      });
      await sendPushToUser(
        userId,
        `⚠️ Budget Warning: ${category}`,
        `You've used ${percentage}% of your ${category} budget (${spent.toFixed(2)} / ${Number(budget.amount).toFixed(2)}).`,
        { type: 'budget_alert', category, level: 'warning' }
      );
    }
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
  const [transactions, total] = await Promise.all([
    TransactionModel.listByUser(userId, limit, offset),
    TransactionModel.countByUser(userId),
  ]);
  return res.status(200).json({
    message: 'Transactions fetched successfully',
    transactions,
    page: { limit, offset, total },
  });
}

export async function createTransaction(req: AuthedRequest, res: Response) {
  const { title, amount, category, created_at, currency, receipt_url, splits, notes, tags } = req.body;
  const user_id = String(req.user!.id);

  const transaction = await TransactionModel.create(
    user_id,
    title,
    amount,
    category,
    created_at,
    currency,
    receipt_url || null,
    splits,
    notes,
    tags,
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

  return res.status(201).json({ message: 'Transaction created successfully', transaction });
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
    WHERE user_id = ${userId} AND deleted_at IS NULL
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
  const { title, amount, category, created_at, currency, receipt_url, splits, notes, tags } = req.body;

  const tx = await TransactionModel.updateByUser(
    id,
    authed,
    title,
    amount,
    category,
    created_at,
    currency,
    receipt_url !== undefined ? receipt_url : undefined,
    splits,
    notes,
    tags,
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
