import cron from 'node-cron';
import { GoalModel } from '../models/GoalModel';
import { WalletModel } from '../models/WalletModel';
import { sql } from '../config/db';
import { convert } from './exchangeRateService';
import { sendPushToUser } from './pushService';
import { emitToUser } from '../socket';
import { withRetries } from './retry';

let isRunning = false;

/**
 * Monthly auto-contributions: every day at 08:15 the rules whose auto_day is
 * today fire once (the NOT EXISTS guard in listDueAutoRules makes reruns and
 * restarts safe). auto_day is capped at 28 client-side so every month has it.
 */
export class GoalAutoContributeScheduler {
  static start(): void {
    console.log('[GoalAuto] Scheduling daily auto-contribution run (08:15)');
    cron.schedule('15 8 * * *', () => {
      void GoalAutoContributeScheduler.run();
    });
  }

  static async run(): Promise<void> {
    if (isRunning) return;
    isRunning = true;
    try {
      const due = await GoalModel.listDueAutoRules(new Date().getDate());
      if (!due.length) return;
      console.log(`[GoalAuto] Applying ${due.length} auto-contribution(s)`);

      for (const rule of due) {
        const userId = String((rule as any).user_id);
        const goalId = Number((rule as any).id);
        const amount = Number((rule as any).auto_amount);
        const goalCurrency = ((rule as any).currency as string) || 'LKR';
        const walletRaw = (rule as any).auto_wallet_id;
        try {
          // A contribution must come FROM somewhere: without a wallet debit the
          // goal — and net worth — grows out of nothing. No wallet = paused.
          if (walletRaw === null || walletRaw === undefined) continue;
          const walletId = Number(walletRaw);

          // Same overdraft guard as manual contributions; on a shortfall, skip
          // and say so — a silent skip reads as "the app forgot my savings".
          const userRows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
          const preferred = ((userRows[0] as any)?.currency as string) || 'LKR';
          const balance = await WalletModel.balanceOf(userId, walletId, preferred);
          let needed = amount;
          try {
            needed = await convert(amount, goalCurrency, preferred);
          } catch {}
          if (needed > balance + 0.0001) {
            await withRetries(
              () => sendPushToUser(
                userId,
                'Auto-save skipped ⏸️',
                `Couldn't move ${amount.toFixed(0)} ${goalCurrency} to "${(rule as any).name}" — ` +
                  `the wallet only has ${balance.toFixed(0)} ${preferred}.`,
                { type: 'goal_reminder', goalId: String(goalId) },
              ),
              { retries: 1, delayMs: 500 },
            );
            continue;
          }

          // Contribution first: near the target it clamps, and the wallet must
          // only be debited by what the goal actually received.
          const goal = await GoalModel.addContribution(userId, goalId, amount, 'auto');
          if (!goal || goal.applied_delta <= 0) continue;
          await WalletModel.recordGoalMovement(
            userId, walletId, -goal.applied_delta, goalCurrency, String((rule as any).name || 'goal'),
          );
          emitToUser(userId, 'goal:updated', { goal });
          emitToUser(userId, 'wallet:changed', { goal_auto: true });
          await withRetries(
            () => sendPushToUser(
              userId,
              'Auto-contribution added 💰',
              `${amount.toFixed(0)} ${(rule as any).currency || 'LKR'} moved to "${(rule as any).name}" — now ${Number(goal.progress_percentage || 0).toFixed(0)}% funded.`,
              { type: 'goal_reminder', goalId: String(goalId) },
            ),
            { retries: 1, delayMs: 500 },
          );
        } catch (err) {
          console.error('[GoalAuto] failed for goal', goalId, err);
        }
      }
    } catch (err) {
      console.error('[GoalAuto] run failed:', err);
    } finally {
      isRunning = false;
    }
  }
}
