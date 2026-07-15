import { RecurringModel } from '../models/RecurringModel';
import { TransactionModel } from '../models/TransactionModel';
import { sendPushToUser } from './pushService';
import { emitToUser } from '../socket';
import { withRetries } from './retry';

let isRunning = false;

/**
 * Process all due recurring transactions.
 */
async function processRecurringTransactions(): Promise<void> {
  if (isRunning) {
    console.warn('[Recurring] Previous run still in progress, skipping.');
    return;
  }
  isRunning = true;
  try {
    const dueItems = await RecurringModel.getDueRecurrences();

    if (dueItems.length === 0) {
      console.log('[Recurring] No due recurrences found.');
      return;
    }

    console.log(`[Recurring] Processing ${dueItems.length} due recurrence(s)...`);

    for (const item of dueItems) {
      try {
        const tx = await withRetries(
          () => TransactionModel.create(
            item.user_id,
            item.title,
            Number(item.amount),
            item.category,
            new Date().toISOString().slice(0, 10),
            item.currency || 'LKR',
            null,        // receiptUrl
            undefined,   // splits
            null,        // notes
            undefined,   // tags
            null,        // clientOpId
            item.wallet_id ?? null, // post into the rule's wallet
          ),
          { retries: 2, delayMs: 500 }
        );

        await withRetries(
          () => RecurringModel.advanceNextRun(item.id, item.frequency),
          { retries: 2, delayMs: 500 }
        );

        emitToUser(item.user_id, 'tx:new', {
          title: 'Recurring transaction created',
          body: `${item.title} (${Math.abs(Number(item.amount)).toFixed(2)})`,
          transaction: tx,
        });
        emitToUser(item.user_id, 'tx:summary:invalidate', { user_id: item.user_id });

        await withRetries(
          () => sendPushToUser(
            item.user_id,
            `🔄 Recurring: ${item.title}`,
            `${Number(item.amount) < 0 ? 'Expense' : 'Income'} of ${Math.abs(Number(item.amount)).toFixed(2)} ${item.currency || 'LKR'} for ${item.category} has been recorded.`,
            { type: 'recurring_tx', transactionId: String(tx.id) }
          ),
          { retries: 1, delayMs: 500 }
        );

        console.log(`[Recurring] Created tx for recurrence #${item.id} (${item.title}) user=${item.user_id}`);
      } catch (err) {
        console.error(`[Recurring] Error processing recurrence #${item.id}:`, err);
      }
    }
  } catch (err) {
    console.error('[Recurring] Error fetching due recurrences:', err);
  } finally {
    isRunning = false;
  }
}

/**
 * Calculate ms until the next occurrence of a specific time (HH:MM).
 */
function msUntilNextDailyTime(hour: number, minute: number): number {
  const now = new Date();
  const next = new Date(now);
  next.setHours(hour, minute, 0, 0);

  if (next <= now) {
    next.setDate(next.getDate() + 1);
  }

  return next.getTime() - now.getTime();
}

/**
 * Schedule recurring processing at a specific daily time, then repeat every 24h.
 */
function scheduleDailyAt(hour: number, minute: number): void {
  const delay = msUntilNextDailyTime(hour, minute);
  const nextRun = new Date(Date.now() + delay);
  console.log(`[Recurring] Next check scheduled at ${nextRun.toISOString()}`);

  setTimeout(async () => {
    try {
      await processRecurringTransactions();
    } catch (err) {
      console.error('[Recurring] Error in daily run:', err);
    } finally {
      scheduleDailyAt(hour, minute);
    }
  }, delay);
}

/**
 * Start the recurring scheduler — runs daily at 9:00 AM.
 * Also processes immediately on startup to catch any missed runs.
 */
export async function startRecurringScheduler(): Promise<void> {
  console.log('[Recurring] Scheduler started — runs daily at 9:00 AM.');

  // Process immediately on startup to catch missed runs (e.g. server was down)
  try {
    await processRecurringTransactions();
  } catch (err) {
    console.error('[Recurring] Error in startup run:', err);
  }

  scheduleDailyAt(9, 0);
}
