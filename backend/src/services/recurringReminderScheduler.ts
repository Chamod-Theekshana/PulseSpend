import cron from 'node-cron';
import { RecurringModel } from '../models/RecurringModel';
import { WalletModel } from '../models/WalletModel';
import { sql } from '../config/db';
import { convert } from './exchangeRateService';
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

      // Preferred currency per user, memoized across the loop.
      const currencyCache = new Map<string, string>();
      const preferredCurrency = async (userId: string): Promise<string> => {
        if (currencyCache.has(userId)) return currencyCache.get(userId)!;
        const rows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
        const cur = ((rows[0] as any)?.currency as string) || 'LKR';
        currencyCache.set(userId, cur);
        return cur;
      };

      for (const item of due) {
        const amountLabel = `${Math.abs(Number(item.amount)).toFixed(2)} ${item.currency || 'LKR'}`;
        const verb = Number(item.amount) < 0 ? 'charges' : 'pays';
        let title = 'Upcoming recurring charge 🔄';
        let body = `${item.title} ${verb} tomorrow • ${amountLabel} • ${item.category}`;

        // Low-balance warning: an expense charging tomorrow whose target wallet
        // can't cover it → tell the user so they can top up in time. Liability
        // wallets are skipped: a credit line's balance is SUPPOSED to be
        // negative, so "low balance, avoid an overdraft" would fire on every
        // card charge forever.
        if (Number(item.amount) < 0 && item.wallet_id) {
          try {
            const wallet = await WalletModel.findById(String(item.user_id), Number(item.wallet_id));
            if (wallet && !WalletModel.isLiabilityType(wallet.type)) {
              const preferred = await preferredCurrency(String(item.user_id));
              const balance = await WalletModel.balanceOf(String(item.user_id), Number(item.wallet_id), preferred);
              const charge = await convert(Math.abs(Number(item.amount)), item.currency || 'LKR', preferred);
              if (balance + 0.0001 < charge) {
                title = '⚠️ Low balance for tomorrow\'s charge';
                body = `${item.title} charges ${charge.toFixed(0)} ${preferred} tomorrow, but ${wallet.name} ` +
                  `only has ${balance.toFixed(0)} ${preferred}. Top it up to avoid an overdraft.`;
              }
            }
          } catch (err) {
            console.error('[Recurring Reminder] balance check failed for rule', item.id, err);
          }
        }

        await withRetries(
          () => sendPushToUser(String(item.user_id), title, body, {
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
