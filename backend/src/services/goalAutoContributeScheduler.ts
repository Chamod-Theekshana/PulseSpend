import cron from 'node-cron';
import { GoalModel } from '../models/GoalModel';
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
        try {
          const goal = await GoalModel.addContribution(userId, goalId, amount, 'auto');
          if (!goal) continue;
          emitToUser(userId, 'goal:updated', { goal });
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
