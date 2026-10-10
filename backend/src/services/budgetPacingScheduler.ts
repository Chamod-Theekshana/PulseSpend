import { BudgetModel } from '../models/BudgetModel';
import { sendPushToUser } from './pushService';
import { emitToUser } from '../socket';
import { withRetries } from './retry';
import { scheduleDailyPerUser } from './zonedScheduler';

let isRunning = false;

/** Fraction of the period elapsed so far (inclusive of today), in (0, 1]. */
function elapsedFraction(startDate: string, endDate: string, now: Date): number {
  const start = new Date(`${startDate}T00:00:00`).getTime();
  const end = new Date(`${endDate}T00:00:00`).getTime();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const totalDays = Math.round((end - start) / 86400000) + 1;
  const elapsedDays = Math.round((today - start) / 86400000) + 1;
  if (totalDays <= 0) return 1;
  return Math.min(1, Math.max(0, elapsedDays / totalDays));
}

/**
 * Proactive "on track to overspend" alerts. Every day at 09:30, for each budget
 * we project end-of-period spend from the pace so far; if that projection blows
 * the limit (and we haven't already alerted this period, and the budget isn't
 * already exceeded — the threshold alert covers that), we push once. Gated by
 * the budget_alerts preference; deduped via budgets.pace_alerted.
 */
export class BudgetPacingScheduler {
  /**
   * 09:00 in each user's own timezone. (The old 09:30 half-hour offset can't be
   * preserved: the zoned scheduler ticks hourly, which is what lets +05:30 and
   * +05:45 zones land on their own local hour.)
   */
  static start(): void {
    scheduleDailyPerUser('Budget Pacing', 9, async (user, localDate) => {
      await BudgetPacingScheduler.run(user.id, localDate);
    });
  }

  /**
   * @param onlyUserId Scope to one user (the per-timezone path).
   * @param localDate  That user's local `YYYY-MM-DD`. The pacing projection
   *                   divides elapsed days by total days in the period, so
   *                   being a day out at a month boundary skews every alert.
   */
  static async run(onlyUserId?: string, localDate?: string): Promise<void> {
    if (!onlyUserId) {
      if (isRunning) return;
      isRunning = true;
    }
    try {
      const now = localDate ? new Date(`${localDate}T12:00:00`) : new Date();
      const budgets = await BudgetModel.listAllActive(onlyUserId);
      if (!budgets.length) return;

      for (const b of budgets) {
        try {
          const period = b.period || 'monthly';
          const { startDate, endDate } = BudgetModel.periodWindow(period, now);

          // Already alerted for this window? skip.
          if (b.pace_alerted === true && b.alert_period === startDate) continue;

          const frac = elapsedFraction(startDate, endDate, now);
          // Need enough of the period elapsed for a meaningful projection.
          if (frac < 0.25) continue;

          const limit = Number(b.amount);
          if (!(limit > 0)) continue;

          const spent = await BudgetModel.getCategorySpent(
            String(b.user_id), String(b.category), String(b.currency || 'LKR'), startDate, endDate,
          );

          // Already over is handled by the threshold alert; pacing is a warning
          // BEFORE you hit the cap.
          if (spent >= limit) continue;

          const projected = spent / frac;
          if (projected <= limit) continue;

          const pct = Math.round((projected / limit) * 100);
          await withRetries(
            () => sendPushToUser(
              String(b.user_id),
              `📈 On track to overspend: ${b.category}`,
              `At your current pace you'll hit about ${projected.toFixed(0)} ${b.currency} on ${b.category} ` +
                `this ${period === 'weekly' ? 'week' : period === 'yearly' ? 'year' : 'month'} — ` +
                `${pct}% of your ${limit.toFixed(0)} budget.`,
              { type: 'budget_alert', category: String(b.category), level: 'pacing' },
            ),
            { retries: 1, delayMs: 500 },
          );
          emitToUser(String(b.user_id), 'budget:alert', {
            category: b.category,
            percentage: pct,
            spent,
            limit,
            level: 'pacing',
          });

          await withRetries(
            () => BudgetModel.markPaceAlerted(Number(b.id), startDate),
            { retries: 2, delayMs: 500 },
          );
        } catch (err) {
          console.error('[Budget Pacing] failed for budget', (b as any).id, err);
        }
      }
    } catch (err) {
      console.error('[Budget Pacing] sweep failed:', err);
    } finally {
      if (!onlyUserId) isRunning = false;
    }
  }
}
