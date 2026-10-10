import { sql } from '../config/db';
import { sendPushToUser } from './pushService';
import { withRetries } from './retry';
import { scheduleDailyPerUser } from './zonedScheduler';

let isRunning = false;

export class GoalReminderService {
  /**
   * Starts the cron job to check for goals approaching their deadlines.
   * Runs every day at 9:00 AM server time.
   */
  /** 09:00 in each user's own timezone — not 09:00 UTC. */
  static startDailyReminders(): void {
    scheduleDailyPerUser('Goal Reminder', 9, async (user, localDate) => {
      await GoalReminderService.checkAndSendReminders(user.id, localDate);
    });
  }

  /**
   * @param onlyUserId Scope to one user (the per-timezone path).
   * @param localDate  That user's local `YYYY-MM-DD`, used as "today" when
   *                   computing days-to-deadline. Using the server's midnight
   *                   made a goal look a day closer or further away depending
   *                   on which side of UTC the user lived.
   */
  static async checkAndSendReminders(onlyUserId?: string, localDate?: string): Promise<void> {
    if (!onlyUserId) {
      if (isRunning) {
        console.warn('[Goal Reminder] Previous run still in progress, skipping.');
        return;
      }
      isRunning = true;
    }
    try {
      const rows = await sql`
        SELECT
          id, user_id, name, target_amount, current_amount, deadline,
          CASE WHEN target_amount > 0
               THEN ROUND((current_amount / target_amount) * 100, 1)
               ELSE 0
          END AS progress_percentage
        FROM goals
        WHERE is_completed = false
          AND (${onlyUserId ?? null}::text IS NULL OR user_id = ${onlyUserId ?? null}::text)
      `;

      if (!rows || rows.length === 0) {
        console.log('[Goal Reminder] No active goals to remind today.');
        return;
      }

      console.log(`[Goal Reminder] Found ${rows.length} active goal(s). Sending daily notifications...`);

      // Midnight on the *user's* calendar day, expressed in UTC fields so the
      // day arithmetic below matches how `goals.deadline` (a DATE) round-trips.
      const now = localDate
        ? new Date(`${localDate}T00:00:00Z`)
        : (() => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; })();

      for (const row of rows as any[]) {
        let messageBody = '';

        if (row.deadline) {
          const deadlineDate = new Date(row.deadline);
          deadlineDate.setHours(0, 0, 0, 0);

          const diffTime = deadlineDate.getTime() - now.getTime();
          const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));

          if (diffDays < 0) {
            messageBody = `Your goal "${row.name}" deadline has passed. Keep pushing to reach it!`;
          } else if (diffDays === 0) {
            messageBody = `Your goal "${row.name}" is due today! You're ${row.progress_percentage}% there.`;
          } else if (diffDays === 1) {
            messageBody = `Your goal "${row.name}" is due tomorrow! You're ${row.progress_percentage}% there.`;
          } else if (diffDays <= 7) {
            messageBody = `Only ${diffDays} days left for "${row.name}"! You're ${row.progress_percentage}% there.`;
          } else {
            messageBody = `Keep saving for "${row.name}"! You're ${row.progress_percentage}% there (${diffDays} days left).`;
          }
        } else {
          messageBody = `Keep saving for "${row.name}"! You're ${row.progress_percentage}% there.`;
        }

        await withRetries(
          () => sendPushToUser(
            String(row.user_id),
            'Goal Reminder 🎯',
            messageBody,
            { type: 'goal_reminder', goalId: String(row.id) }
          ),
          { retries: 1, delayMs: 500 }
        );
      }
    } catch (err) {
      console.error('[Goal Reminder] Error checking goals:', err);
    } finally {
      if (!onlyUserId) isRunning = false;
    }
  }
}
