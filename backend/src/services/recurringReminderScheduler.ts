import cron from 'node-cron';
import { RecurringModel } from '../models/RecurringModel';
import { sendPushToUser } from './pushService';
import { emitToUser } from '../socket';
import { withRetries } from './retry';

let isRunning = false;

function toISODate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/**
 * Day-before reminder for recurring charges: every day at 08:00, notifies about
 * rules that materialize tomorrow so a charge never surprises the user. Deduped
 * via last_reminded_on. The push type contains "recurring" so it's gated by the
 * user's `recurring_alerts` preference (see NotificationPreferenceModel).
 */
export class RecurringReminderScheduler {
  static start(): void {
    console.log('[Recurring Reminder] Scheduling daily upcoming-charge reminders (08:00)');
    cron.schedule('0 8 * * *', () => {
      void RecurringReminderScheduler.run();
    });
  }

  static async run(): Promise<void> {
    if (isRunning) return;
    isRunning = true;
    try {
      const now = new Date();
      const today = toISODate(now);
      const tmr = new Date(now);
      tmr.setDate(tmr.getDate() + 1);
      const tomorrow = toISODate(tmr);

      const due = await RecurringModel.listDueForReminder(tomorrow, today);
      if (!due.length) return;
      console.log(`[Recurring Reminder] Sending ${due.length} upcoming-charge reminder(s)`);

      for (const item of due) {
        const amountLabel = `${Math.abs(Number(item.amount)).toFixed(2)} ${item.currency || 'LKR'}`;
        const verb = Number(item.amount) < 0 ? 'charges' : 'pays';
        const body = `${item.title} ${verb} tomorrow • ${amountLabel} • ${item.category}`;

        await withRetries(
          () => sendPushToUser(String(item.user_id), 'Upcoming recurring charge 🔄', body, {
            type: 'recurring_alert',
            recurringId: String(item.id),
          }),
          { retries: 1, delayMs: 500 },
        );

        emitToUser(String(item.user_id), 'recurring:reminder', { body, recurring: item });

        await withRetries(
          () => RecurringModel.markReminded(Number(item.id), today),
          { retries: 2, delayMs: 500 },
        );
      }
    } catch (err) {
      console.error('[Recurring Reminder] run failed:', err);
    } finally {
      isRunning = false;
    }
  }
}
