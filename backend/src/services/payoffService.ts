import { WalletModel } from '../models/WalletModel';
import { sendPushToUser } from './pushService';
import { emitToUser } from '../socket';
import { withRetries } from './retry';

/** Owed amounts at or below this are "zero" — absorbs FX/rounding dust. */
export const OWED_EPSILON = 0.005;

/**
 * Fires the payoff celebration when a repayment has just brought a debt
 * account's owed amount to zero.
 *
 * The transition test ([owedBefore] > 0 → owed now ≤ 0) makes the push
 * exactly-once without any dedupe state: a repayment that lands on an already
 * clear wallet, or one that leaves debt outstanding, does nothing. Wording by
 * type — a loan at zero is FINISHED, a card at zero is merely settled and will
 * owe again next month.
 *
 * Returns true when the payoff transition happened, so callers (the recurring
 * scheduler) can retire a loan's repayment rule at the same moment.
 */
export async function notifyIfPaidOff(
  userId: string,
  walletId: number,
  owedBefore: number,
  preferredCurrency: string,
): Promise<boolean> {
  if (owedBefore <= OWED_EPSILON) return false;

  const wallet = await WalletModel.findById(userId, walletId);
  if (!wallet || !WalletModel.isLiabilityType(wallet.type)) return false;

  const balance = await WalletModel.balanceOf(userId, walletId, preferredCurrency);
  const owedNow = Math.max(0, -balance);
  if (owedNow > OWED_EPSILON) return false;

  const isLoan = WalletModel.normalizeType(wallet.type) === 'loan';
  await withRetries(
    () => sendPushToUser(
      userId,
      isLoan ? `🎉 ${wallet.name} paid off!` : `✓ ${wallet.name} fully settled`,
      isLoan
        ? `You've repaid everything on ${wallet.name}. It's done.`
        : `${wallet.name} is back to zero — nothing outstanding.`,
      { type: 'wallet_paid_off', walletId: String(walletId) },
    ),
    { retries: 1, delayMs: 500 },
  );
  emitToUser(userId, 'wallet:changed', { paid_off: walletId });
  return true;
}
