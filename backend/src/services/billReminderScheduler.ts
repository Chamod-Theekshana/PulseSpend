import cron from 'node-cron';
import { ReminderModel } from '../models/ReminderModel';
import { sendPushToUser } from './pushService';
import { emitToUser } from '../socket';
import { withRetries } from './retry';

let isRunning = false;

function toISODate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

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
  static startDailyReminders(): void {
    console.log('[Bill Reminder] Starting daily bill reminder cron job (09:00 AM)...');

    // 9:00 AM every day (server local time)
    cron.schedule('0 9 * * *', async () => {
      console.log('[Bill Reminder] Running daily reminder check...');
      await BillReminderScheduler.checkAndSendReminders();
    });
  }

  static async checkAndSendReminders(): Promise<void> {
    if (isRunning) {
      console.warn('[Bill Reminder] Previous run still in progress, skipping.');
      return;
    }
    isRunning = true;
    try {
      const today = toISODate(new Date());
      const dueRows = await ReminderModel.listDueForReminderDate(today);

      if (!dueRows.length) {
        console.log('[Bill Reminder] No due reminders for', today);
        return;
      }

      console.log(`[Bill Reminder] Sending ${dueRows.length} reminder notification(s) for ${today}`);

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
      const overdueRows = await ReminderModel.listOverdue(today);
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
      isRunning = false;
    }
  }
}
