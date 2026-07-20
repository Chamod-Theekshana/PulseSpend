import { RecurringModel } from '../models/RecurringModel';
import { TransactionModel } from '../models/TransactionModel';
import { WalletModel } from '../models/WalletModel';
import { sql } from '../config/db';
import { convert } from './exchangeRateService';
import { notifyIfPaidOff, OWED_EPSILON } from './payoffService';
import { checkBudgetAlert } from '../controllers/transactionsController';
import { sendPushToUser } from './pushService';
import { emitToUser } from '../socket';
import { withRetries } from './retry';

/**
 * Materializes a recurring TRANSFER rule (to_wallet_id set): one −/+ pair,
 * transfer-tagged, so the money moves between wallets without ever counting as
 * income or spending. This is the correct shape for an EMI — Bank → Loan
 * shrinks the debt monthly, where an expense rule on the loan would grow it.
 *
 * Exported for the DB test suite: the clamp/stop/skip behavior below is
 * SQL-and-state logic that pure tests can't exercise.
 */
export async function materializeTransfer(item: any): Promise<void> {
  const userId = String(item.user_id);
  const fromId = Number(item.wallet_id ?? 0);
  const toId = Number(item.to_wallet_id);
  const amount = Math.abs(Number(item.amount));

  const nameOf = async (id: number): Promise<string | null> => {
    if (id === 0) return 'Default';
    const w = await WalletModel.findById(userId, id);
    return w ? w.name : null;
  };
  const [fromName, toName] = await Promise.all([nameOf(fromId), nameOf(toId)]);
  // A deleted end means the rule can't run any more — deactivate instead of
  // silently dropping money into a wallet that no longer exists.
  if (!fromName || !toName) {
    await RecurringModel.update(userId, Number(item.id), { is_active: false });
    await withRetries(
      () => sendPushToUser(
        userId,
        '⏸️ Recurring transfer paused',
        `${item.title}: one of its wallets was deleted. Edit the rule to resume.`,
        { type: 'recurring_tx', recurringId: String(item.id) },
      ),
      { retries: 1, delayMs: 500 },
    );
    return;
  }

  const toWallet = toId !== 0 ? await WalletModel.findById(userId, toId) : null;
  const toIsLiability = WalletModel.isLiabilityType(toWallet?.type);
  const toIsLoan = WalletModel.normalizeType(toWallet?.type) === 'loan';

  // Repayment rules must respect what's actually owed:
  //  - never overpay — the final installment clamps to the outstanding amount,
  //    so the debt lands exactly at zero instead of drifting into credit;
  //  - a LOAN at zero is finished → retire the rule (left active it would
  //    overpay a dead loan every run, forever);
  //  - a CARD at zero is merely settled → skip this run, keep the rule alive
  //    for next month's charges.
  let transferAmount = amount;
  let owedBefore = 0;
  if (toIsLiability) {
    const userRows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
    const preferred = ((userRows[0] as any)?.currency as string) || 'LKR';
    owedBefore = Math.max(0, -(await WalletModel.balanceOf(userId, toId, preferred)));

    // The rule's amount is in its own currency; compare on the preferred basis.
    let amountPreferred = amount;
    try {
      amountPreferred = await convert(amount, item.currency || 'LKR', preferred);
    } catch {}

    if (owedBefore <= OWED_EPSILON) {
      await withRetries(
        () => RecurringModel.advanceNextRun(item.id, item.frequency),
        { retries: 2, delayMs: 500 },
      );
      if (toIsLoan) {
        await RecurringModel.update(userId, Number(item.id), { is_active: false });
        await withRetries(
          () => sendPushToUser(
            userId,
            `✅ ${item.title} stopped`,
            `${toName} is paid off — the recurring repayment has been turned off.`,
            { type: 'recurring_tx', recurringId: String(item.id) },
          ),
          { retries: 1, delayMs: 500 },
        );
        emitToUser(userId, 'recurring:deleted', { id: item.id });
      } else {
        await withRetries(
          () => sendPushToUser(
            userId,
            `✓ Nothing to pay on ${toName}`,
            `${item.title}: the balance is already clear this cycle.`,
            { type: 'recurring_tx', recurringId: String(item.id) },
          ),
          { retries: 1, delayMs: 500 },
        );
      }
      return;
    }

    if (amountPreferred > owedBefore) {
      // Clamp in the rule's own currency so the legs stay in one currency.
      let owedInRuleCurrency = owedBefore;
      try {
        owedInRuleCurrency = await convert(owedBefore, preferred, item.currency || 'LKR');
      } catch {}
      transferAmount = Math.round(owedInRuleCurrency * 100) / 100;
    }
  }

  await withRetries(
    () => WalletModel.transfer(
      userId, fromId, toId, transferAmount, item.currency || 'LKR', fromName, toName,
      toIsLiability
        ? { from: `Repayment — ${toName}`, to: `Repayment from ${fromName}` }
        : undefined,
    ),
    { retries: 2, delayMs: 500 },
  );

  if (toIsLiability) {
    const userRows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
    const preferred = ((userRows[0] as any)?.currency as string) || 'LKR';
    const paidOff = await notifyIfPaidOff(userId, toId, owedBefore, preferred);
    if (paidOff && toIsLoan) {
      // The loan just finished — its repayment rule has nothing left to do.
      await RecurringModel.update(userId, Number(item.id), { is_active: false });
      emitToUser(userId, 'recurring:deleted', { id: item.id });
    }
  }

  await withRetries(
    () => RecurringModel.advanceNextRun(item.id, item.frequency),
    { retries: 2, delayMs: 500 },
  );

  emitToUser(userId, 'wallet:changed', { recurring_id: item.id });
  emitToUser(userId, 'tx:new', {
    title: 'Recurring transfer complete',
    body: `${item.title}: ${amount.toFixed(2)} ${item.currency || 'LKR'} moved ${fromName} → ${toName}`,
  });
  emitToUser(userId, 'tx:summary:invalidate', { user_id: userId });

  await withRetries(
    () => sendPushToUser(
      userId,
      `🔄 Recurring: ${item.title}`,
      `${amount.toFixed(2)} ${item.currency || 'LKR'} moved ${fromName} → ${toName}.`,
      { type: 'recurring_tx', recurringId: String(item.id) },
    ),
    { retries: 1, delayMs: 500 },
  );
}

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
        // Transfer-shaped rules move money between wallets instead of posting
        // a single income/expense leg.
        if (item.to_wallet_id !== null && item.to_wallet_id !== undefined) {
          await materializeTransfer(item);
          console.log(`[Recurring] Transferred for recurrence #${item.id} (${item.title}) user=${item.user_id}`);
          continue;
        }

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
        // A real income/expense row changed the analytics-period totals.
        emitToUser(item.user_id, 'analytics:invalidate', { user_id: item.user_id });

        // A recurring bill is real spending: it must trip budget alerts the
        // same as a hand-entered expense.
        if (Number(item.amount) < 0) {
          void checkBudgetAlert(String(item.user_id), item.category);
        }

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

  scheduleDailyAt(13, 39);
}
