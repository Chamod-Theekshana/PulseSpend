import { sql } from '../config/db';
import { sendPushToUser } from './pushService';
import { withRetries } from './retry';
import { scheduleDailyPerUser, scheduleMonthlyPerUser } from './zonedScheduler';

let inactivityRunning = false;
let monthResetRunning = false;

/**
 * Gentle re-engagement nudges:
 *  - Inactivity: when a user's most recent transaction is exactly 3 days old
 *    (so it fires once, the day they cross the 3-day mark — no extra tracking
 *    table needed, and it stops as soon as they log something).
 *  - New month: on the 1st, remind users with budgets that their category
 *    budgets have reset for the fresh month.
 *
 * Type is `reengagement`, gated only by the master push toggle.
 */
export class ReengagementScheduler {
  static start(): void {
    scheduleDailyPerUser('Reengagement/inactivity', 10, async (user, localDate) => {
      await ReengagementScheduler.runInactivityNudge(user.id, localDate);
    });
    scheduleMonthlyPerUser('Reengagement/month', 1, 9, async (user) => {
      await ReengagementScheduler.runNewMonthNudge(user.id);
    });
  }

  /**
   * @param onlyUserId  Scope to one user (the per-timezone path).
   * @param localDate   That user's local `YYYY-MM-DD`. `CURRENT_DATE` is the
   *                    *database* date, so using it here meant the "exactly 3
   *                    days idle" window was measured against Greenwich rather
   *                    than against the user's own calendar.
   */
  static async runInactivityNudge(onlyUserId?: string, localDate?: string): Promise<void> {
    if (!onlyUserId) {
      if (inactivityRunning) return;
      inactivityRunning = true;
    }
    try {
      const anchor = localDate ?? null;
      const rows = await sql`
        SELECT user_id
        FROM transactions
        WHERE deleted_at IS NULL
          AND (${onlyUserId ?? null}::text IS NULL OR user_id = ${onlyUserId ?? null}::text)
        GROUP BY user_id
        HAVING MAX(created_at)::date
             = (COALESCE(${anchor}::date, CURRENT_DATE) - INTERVAL '3 days')::date
      `;
      if (!rows.length) return;
      if (!onlyUserId) console.log(`[Reengagement] Sending inactivity nudge to ${rows.length} user(s)`);
      for (const row of rows) {
        await withRetries(
          () => sendPushToUser(
            String((row as any).user_id),
            'We miss you 👋',
            "You haven't logged an expense in 3 days. A quick check-in keeps your budget on track.",
            { type: 'reengagement', reason: 'inactivity' },
          ),
          { retries: 1, delayMs: 500 },
        );
      }
    } catch (err) {
      console.error('[Reengagement] Inactivity nudge failed:', err);
    } finally {
      if (!onlyUserId) inactivityRunning = false;
    }
  }

  static async runNewMonthNudge(onlyUserId?: string): Promise<void> {
    if (!onlyUserId) {
      if (monthResetRunning) return;
      monthResetRunning = true;
    }
    try {
      const rows = await sql`
        SELECT DISTINCT user_id FROM budgets
        WHERE deleted_at IS NULL
          AND (${onlyUserId ?? null}::text IS NULL OR user_id = ${onlyUserId ?? null}::text)
      `;
      if (!rows.length) return;
      if (!onlyUserId) console.log(`[Reengagement] Sending new-month nudge to ${rows.length} user(s)`);
      for (const row of rows) {
        await withRetries(
          () => sendPushToUser(
            String((row as any).user_id),
            'New month, fresh start 🗓️',
            'Your category budgets have reset for the new month. Set the tone with your first entry!',
            { type: 'reengagement', reason: 'month_reset' },
          ),
          { retries: 1, delayMs: 500 },
        );
      }
    } catch (err) {
      console.error('[Reengagement] New-month nudge failed:', err);
    } finally {
      if (!onlyUserId) monthResetRunning = false;
    }
  }
}
