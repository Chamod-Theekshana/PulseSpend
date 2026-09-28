import { ReminderModel } from '../models/ReminderModel';
import { sendPushToUser } from './pushService';
import { emitToUser } from '../socket';
import { withRetries } from './retry';
import { scheduleDailyPerUser } from './zonedScheduler';
import { toISODateHost } from '../utils/time';

let isRunning = false;

/** @deprecated Host-zone date. Kept only for the manual `checkAndSendReminders()` path. */
const toISODate = toISODateHost;

function formatDueDateLabel(isoDate: string): string {
  const d = new Date(isoDate);
  if (Number.isNaN(d.getTime())) return isoDate;
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

function buildReminderBody(item: {
  title: string;
  amount: number;
  currency: string;
  category: string;
  due_date: string;
  remind_days_before: number;
}): string {
  const dueLabel = formatDueDateLabel(item.due_date);
  const amountLabel = `${Number(item.amount).toFixed(2)} ${item.currency || 'LKR'}`;

  if (item.remind_days_before === 0) {
    return `${item.title} is due today (${dueLabel}) • ${amountLabel} • ${item.category}`;
  }

  if (item.remind_days_before === 1) {
    return `${item.title} is due tomorrow (${dueLabel}) • ${amountLabel} • ${item.category}`;
  }

  return `${item.title} is due in ${item.remind_days_before} days (${dueLabel}) • ${amountLabel} • ${item.category}`;
}

export class BillReminderScheduler {
  /**
   * Fires at 09:00 **in each user's own timezone**.
   *
   * Previously this was a single `cron.schedule('0 9 * * *')`, i.e. 09:00 in the
   * server's zone — 14:30 for a Colombo user and 04:00 for a New York one. The
   * zoned scheduler runs hourly instead and hands each user their own local
   * date, so the `due_date - today = remind_days_before` arithmetic below is
   * evaluated against the day the user is actually living in.
   */
  static startDailyReminders(): void {
    scheduleDailyPerUser('Bill Reminder', 9, async (user, localDate) => {
      await BillReminderScheduler.checkAndSendReminders(localDate, user.id);
    });
  }

  /**
   * @param forDate  The user's local `YYYY-MM-DD`. Defaults to the host date,
   *                 which is only correct for a manual/ops invocation.
   * @param userId   Scope to one user. Omitted means every user (ops path).
   */
  static async checkAndSendReminders(forDate?: string, userId?: string): Promise<void> {
    // The re-entrancy guard only applies to the un-scoped ops path; per-user
    // runs are already serialised one user at a time by the zoned scheduler,
    // and blocking them here would drop every user after the first each hour.
    if (!userId) {
      if (isRunning) {
        console.warn('[Bill Reminder] Previous run still in progress, skipping.');
        return;
      }
      isRunning = true;
    }
    try {
      const today = forDate ?? toISODate(new Date());
      const dueRows = await ReminderModel.listDueForReminderDate(today, userId);

      // NOTE: this used to `return` early when there were no upcoming reminders,
      // which meant the overdue sweep further down only ran on days that also
      // happened to have a lead-time reminder. Most days have neither, so
      // overdue bills went unnotified. Now the two passes are independent.
      if (dueRows.length) {
        console.log(`[Bill Reminder] Sending ${dueRows.length} reminder notification(s) for ${today}`);
      }

      for (const item of dueRows) {
        const title = item.remind_days_before === 0 ? 'Bill Due Today' : 'Upcoming Bill Reminder';
        const body = buildReminderBody(item);

        await withRetries(
          () => sendPushToUser(String(item.user_id), title, body, {
            type: 'bill_reminder',
            reminderId: String(item.id),
            dueDate: String(item.due_date),
            remindDaysBefore: String(item.remind_days_before),
          }),
          { retries: 1, delayMs: 500 }
        );

        emitToUser(String(item.user_id), 'reminder:due', {
          title,
          body,
          reminder: item,
        });

        await withRetries(
          () => ReminderModel.markNotified(Number(item.id), today),
          { retries: 2, delayMs: 500 }
        );
      }

      // ── Overdue bills: fire once when a due date has passed unpaid ──
      const overdueRows = await ReminderModel.listOverdue(today, userId);
      if (overdueRows.length) {
        console.log(`[Bill Reminder] Sending ${overdueRows.length} overdue notification(s) for ${today}`);
        for (const item of overdueRows) {
          const amountLabel = `${Number(item.amount).toFixed(2)} ${item.currency || 'LKR'}`;
          const body = `${item.title} was due on ${formatDueDateLabel(String(item.due_date))} • ${amountLabel} • ${item.category}. It looks overdue.`;

          await withRetries(
            () => sendPushToUser(String(item.user_id), 'Bill overdue ⏰', body, {
              type: 'bill_reminder',
              reminderId: String(item.id),
              dueDate: String(item.due_date),
              overdue: 'true',
            }),
            { retries: 1, delayMs: 500 },
          );

          emitToUser(String(item.user_id), 'reminder:due', { title: 'Bill overdue', body, reminder: item });

          await withRetries(
            () => ReminderModel.markNotified(Number(item.id), today),
            { retries: 2, delayMs: 500 },
          );
        }
      }
    } catch (err) {
      console.error('[Bill Reminder] Error while checking reminders:', err);
    } finally {
      if (!userId) isRunning = false;
    }
  }
}
