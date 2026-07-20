import { MAX_AMOUNT } from '../utils/financeMath';
import { GoalModel } from '../models/GoalModel';
import { WalletModel } from '../models/WalletModel';
import { sql } from '../config/db';
import { emitToUser } from '../socket';
import { sendPushToUser } from '../services/pushService';
import { checkBudgetAlert } from './transactionsController';
import type { AuthedRequest } from '../middleware/requireAuth';

/** Celebration notification sent the first time a goal crosses 100%. */
async function notifyGoalReached(userId: string, goal: any): Promise<void> {
  try {
    const amount = `${Number(goal.target_amount).toFixed(0)} ${goal.currency || 'LKR'}`;
    await sendPushToUser(
      userId,
      'Goal reached! 🎉',
      `You hit your "${goal.name}" goal of ${amount}. Amazing work — time to set the next one!`,
      { type: 'goal_completed', goalId: String(goal.id) },
    );
  } catch (err) {
    console.error('[Goals] Failed to send goal-reached notification:', err);
  }
}

const MILESTONES = [75, 50, 25];

/**
 * Fires a 25/50/75% milestone push when a contribution crosses one, using
 * goals.last_milestone so each fires exactly once. Withdrawals lower the
 * stored milestone so re-crossing later celebrates again.
 */
async function checkMilestones(userId: string, goal: any, lastMilestone: number): Promise<void> {
  try {
    const pct = Number(goal.progress_percentage || 0);
    const reached = MILESTONES.find((m) => pct >= m) ?? 0;

    if (reached > lastMilestone && pct < 100) {
      const label = reached === 25 ? 'A quarter of the way' : reached === 50 ? 'Halfway there' : 'Three quarters done';
      await sendPushToUser(
        userId,
        `${label}! 🎯`,
        `"${goal.name}" is at ${pct.toFixed(0)}% — ${Number(goal.current_amount).toFixed(0)} of ${Number(goal.target_amount).toFixed(0)} ${goal.currency || 'LKR'}.`,
        { type: 'goal_reminder', goalId: String(goal.id) },
      );
    }
    if (reached !== lastMilestone) {
      const { sql } = await import('../config/db');
      await sql`UPDATE goals SET last_milestone = ${reached} WHERE id = ${goal.id} AND user_id = ${userId}`;
    }
  } catch (err) {
    console.error('[Goals] milestone check failed:', err);
  }
}

export async function listGoals(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const { limit, offset } = (req as any).pagination || { limit: 50, offset: 0 };
  const [goals, total] = await Promise.all([
    GoalModel.listByUser(userId, limit, offset),
    GoalModel.countByUser(userId),
  ]);
  return res.json({ goals, page: { limit, offset, total } });
}

export async function createGoal(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const { name, target_amount, currency, deadline, group_id } = req.body;

  // Sharing with a group requires membership.
  let groupId: number | null = null;
  const rawGroup = Number(group_id);
  if (Number.isInteger(rawGroup) && rawGroup > 0) {
    const { GroupModel } = await import('../models/GroupModel');
    if (!(await GroupModel.isMember(rawGroup, userId))) {
      return res.status(403).json({ message: 'You are not a member of that group' });
    }
    groupId = rawGroup;
  }

  const goal = await GoalModel.create(
    userId,
    name,
    Number(target_amount),
    currency || 'LKR',
    deadline || null,
    groupId,
  );
  emitToUser(userId, 'goal:created', { goal });
  return res.status(201).json({ goal });
}

export async function updateGoal(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  const { name, target_amount, currency, deadline } = req.body;

  const goal = await GoalModel.update(userId, id, name, Number(target_amount), currency || 'LKR', deadline || null);
  if (!goal) return res.status(404).json({ message: 'Not found' });
  emitToUser(userId, 'goal:updated', { goal });
  return res.json({ goal });
}

/** After a GROUP goal completes, celebrate with every member. */
async function notifyGroupGoalReached(goal: any, byUserId: string): Promise<void> {
  if (!goal.group_id) return;
  try {
    const { GroupModel } = await import('../models/GroupModel');
    for (const memberId of await GroupModel.memberIds(Number(goal.group_id))) {
      if (memberId === byUserId) continue;
      await sendPushToUser(
        memberId,
        'Group goal reached! 🎉',
        `"${goal.name}" is fully funded — great teamwork!`,
        { type: 'group_activity', goalId: String(goal.id) },
      );
    }
  } catch (err) {
    console.error('[Goals] group goal-reached notification failed:', err);
  }
}

export async function contributeToGoal(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  const { amount, currency, wallet_id, spend, category } = req.body;

  // Own goals AND goals shared with a group the user belongs to.
  const existing = await GoalModel.findAccessible(userId, id);
  if (!existing) return res.status(404).json({ message: 'Not found' });

  // Optional source/destination wallet for real money movement. 0 = the default
  // bucket; a positive id must be one of the user's own wallets.
  const rawWallet = Number(wallet_id);
  const walletId = Number.isInteger(rawWallet) && rawWallet > 0 ? rawWallet : null;
  if (walletId !== null && !(await WalletModel.findById(userId, walletId))) {
    return res.status(404).json({ message: 'Wallet not found' });
  }
  const walletProvided = wallet_id !== undefined && wallet_id !== null;
  const isSpend = spend === true;

  let contributionAmount = Number(amount);
  const fromCurrency = (currency || existing.currency || 'LKR').toUpperCase();
  const toCurrency = (existing.currency || 'LKR').toUpperCase();

  let conversionWarning: string | undefined;
  // Convert contribution to the goal's currency if they differ.
  if (fromCurrency !== toCurrency) {
    try {
      const { convert } = await import('../services/exchangeRateService');
      contributionAmount = await convert(contributionAmount, fromCurrency, toCurrency);
    } catch (e) {
      console.warn(`[Goals] Currency conversion ${fromCurrency}→${toCurrency} failed, using raw amount:`, e);
      conversionWarning = `Rate unavailable for ${fromCurrency}→${toCurrency}. Amount recorded as-is.`;
    }
  }

  const beforeAmount = Number(existing.current_amount);
  const targetAmount = Number(existing.target_amount);

  if (contributionAmount > 0) {
    // Completion guard: a full goal can't take more — raise the target instead.
    if (beforeAmount >= targetAmount - 0.0001) {
      return res.status(400).json({
        message: 'This goal is already complete — raise the target to keep saving.',
      });
    }
    // Overdraft guard: can't fund a goal with money a wallet doesn't hold.
    if (walletProvided) {
      const { convert } = await import('../services/exchangeRateService');
      const userRows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
      const preferred = ((userRows[0] as any)?.currency as string) || 'LKR';
      const balance = await WalletModel.balanceOf(userId, walletId ?? 0, preferred);
      let needed = contributionAmount;
      try {
        needed = await convert(contributionAmount, toCurrency, preferred);
      } catch { /* compare in goal currency as a fallback */ }
      if (needed > balance + 0.0001) {
        const walletName = walletId ? (await WalletModel.findById(userId, walletId))?.name ?? 'that wallet' : 'the default wallet';
        return res.status(400).json({
          message: `Not enough in ${walletName} — balance is ${balance.toFixed(2)} ${preferred}.`,
        });
      }
    }
  } else if (Math.abs(contributionAmount) > beforeAmount + 0.0001) {
    // Withdrawals can't exceed what's currently saved — reject rather than
    // silently capping at zero.
    return res.status(400).json({
      message: `You can only withdraw up to ${beforeAmount.toFixed(2)} ${toCurrency} — that's all this goal has.`,
    });
  }

  const goal = await GoalModel.addContributionById(id, userId, contributionAmount, 'manual', walletId);
  if (!goal) return res.status(404).json({ message: 'Not found' });

  // Move real money: the goal only changed by the clamped delta, so mirror
  // exactly that. A contribution/return debits or credits the wallet; a
  // "spend" withdrawal records the goal money as a real expense instead.
  // (The model now reports the clamped delta directly; the timeline logs the
  // same figure, so history, goal change and wallet movement always agree.)
  const appliedDelta = goal.applied_delta;
  if (appliedDelta < 0 && isSpend) {
    const cat = typeof category === 'string' && category.trim() ? category.trim().slice(0, 255) : 'Goal Savings';
    await WalletModel.recordGoalSpend(userId, appliedDelta, toCurrency, goal.name, cat);
    emitToUser(userId, 'wallet:changed', { goalId: id });
    // The spend leg is a REAL expense: tx:new refreshes the ledgers everywhere,
    // and it must trip budget alerts like any hand-entered expense.
    emitToUser(userId, 'tx:new', {
      title: 'Spent from goal',
      body: `${Math.abs(appliedDelta).toFixed(2)} ${toCurrency} spent from ${goal.name}`,
    });
    emitToUser(userId, 'tx:summary:invalidate', { user_id: userId });
    emitToUser(userId, 'analytics:invalidate', { user_id: userId });
    void checkBudgetAlert(userId, cat);
  } else if (walletProvided && appliedDelta !== 0) {
    await WalletModel.recordGoalMovement(userId, walletId, -appliedDelta, toCurrency, goal.name);
    emitToUser(userId, 'wallet:changed', { goalId: id });
    emitToUser(userId, 'tx:summary:invalidate', { user_id: userId });
  }

  emitToUser(userId, 'goal:updated', { goal });
  if (goal.is_completed) {
    emitToUser(userId, 'goal:completed', { goal });
    if (!existing.is_completed) {
      await notifyGoalReached(String(goal.user_id), goal);
      void notifyGroupGoalReached(goal, userId);
    }
  }
  void checkMilestones(String(goal.user_id), goal, Number((existing as any).last_milestone || 0));

  return res.json({ goal, ...(conversionWarning ? { conversion_warning: conversionWarning } : {}) });
}

/** PUT /api/goals/:id/auto — set/clear the monthly auto-contribution rule. */
export async function setAutoRule(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const { auto_amount, auto_day, auto_wallet_id } = req.body ?? {};

  // Null/absent amount clears the rule entirely.
  if (auto_amount === null || auto_amount === undefined || Number(auto_amount) === 0) {
    const cleared = await GoalModel.setAutoRule(userId, id, null, null, null);
    if (!cleared) return res.status(404).json({ message: 'Not found' });
    emitToUser(userId, 'goal:updated', { goal: cleared });
    return res.json({ goal: cleared });
  }

  const amount = Number(auto_amount);
  const day = Number(auto_day);
  if (!Number.isFinite(amount) || amount <= 0 || amount > MAX_AMOUNT) {
    return res.status(400).json({ message: 'auto_amount must be a positive number' });
  }
  if (!Number.isInteger(day) || day < 1 || day > 28) {
    return res.status(400).json({ message: 'auto_day must be between 1 and 28' });
  }

  // The debited wallet is required: without one the contribution would grow the
  // goal — and net worth — out of nothing (the scheduler pauses NULL rules).
  const walletId = Number(auto_wallet_id);
  if (!Number.isInteger(walletId) || walletId < 0) {
    return res.status(400).json({ message: 'Choose which wallet the auto-save comes from' });
  }
  if (walletId > 0) {
    const wallet = await WalletModel.findById(userId, walletId);
    if (!wallet) return res.status(404).json({ message: 'Wallet not found' });
    if (WalletModel.isLiabilityType(wallet.type)) {
      return res.status(400).json({ message: 'Savings can\'t come out of a debt account' });
    }
  }

  const goal = await GoalModel.setAutoRule(userId, id, Math.round(amount * 100) / 100, day, walletId);
  if (!goal) return res.status(404).json({ message: 'Not found' });
  emitToUser(userId, 'goal:updated', { goal });
  return res.json({ goal });
}

/** GET /api/goals/:id/contributions — deposit/withdraw timeline, newest first. */
export async function listGoalContributions(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const goal = await GoalModel.findAccessible(userId, id);
  if (!goal) return res.status(404).json({ message: 'Not found' });
  const contributions = await GoalModel.listContributions(id);
  return res.json({ contributions });
}

export async function deleteGoal(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  await GoalModel.delete(userId, id);
  emitToUser(userId, 'goal:deleted', { id });
  return res.json({ message: 'Goal deleted successfully' });
}

export async function bulkDeleteGoals(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const ids = (req.body as { ids: number[] }).ids;
  const deletedCount = await GoalModel.bulkDeleteByUser(userId, ids);
  return res.json({ message: 'Goals deleted', deletedCount });
}
