import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/chat_message_model.dart';
import '../../../providers/currency_provider.dart';

/// What the settle button should currently offer for a shared-expense bubble.
enum SettleState {
  /// This is my own expense — there is nothing for me to settle.
  mine,

  /// I owe the payer something for this; the button is live.
  owed,

  /// Balance with this payer is clear (already settled, or they owe me).
  settled,

  /// Balances haven't loaded yet.
  loading,
}

/// A shared-expense bubble in the group chat.
///
/// Previously this widget hardcoded `AppColors.surfaceDark` as the background
/// for received bubbles regardless of the active theme, so in light mode it
/// rendered a near-black card behind the theme's dark body text — effectively
/// unreadable. It also hardcoded a `$` prefix while the rest of the app formats
/// through [MoneyFormatter], so a group working in LKR saw dollar amounts.
class ExpenseBubbleWidget extends ConsumerWidget {
  final ChatMessage message;
  final bool isMe;

  /// The state of the viewer's obligation for this expense.
  final SettleState settleState;

  /// What the viewer would settle right now, in the bubble's currency.
  final double settleAmount;

  /// Fired when the viewer taps the settle button. Null disables it.
  final VoidCallback? onSettlePressed;

  /// True while a settle request for this bubble is in flight.
  final bool isSettling;

  const ExpenseBubbleWidget({
    super.key,
    required this.message,
    required this.isMe,
    required this.settleState,
    required this.settleAmount,
    this.onSettlePressed,
    this.isSettling = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final money = ref.watch(moneyFormatterProvider);

    final metadata = message.metadata ?? const <String, dynamic>{};
    final double amount = (metadata['amount'] as num?)?.toDouble() ?? 0.0;
    final String currency = (metadata['currency'] as String?) ?? money.displayCurrency;
    final String title = (metadata['title'] as String?) ?? 'Shared Expense';
    final String splitWith = (metadata['splitWith'] as String?) ?? 'the group';
    final String? payerName = metadata['payerName'] as String?;

    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    // Sent bubbles get a tinted card; received bubbles follow the surface for
    // the CURRENT theme, so text contrast holds in both light and dark mode.
    final bg = isMe
        ? AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.10)
        : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt);
    final borderColor = isMe
        ? AppColors.primary.withValues(alpha: 0.55)
        : (isDark ? AppColors.darkBorder : AppColors.lightBorder);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        // No left margin for incoming bubbles — the chat's avatar gutter
        // already provides that inset, and doubling it would misalign these
        // against the plain text bubbles beside them.
        margin: EdgeInsets.only(top: 6, bottom: 6, left: isMe ? 12 : 0, right: 12),
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16.0),
            topRight: const Radius.circular(16.0),
            bottomLeft: Radius.circular(isMe ? 16.0 : 4.0),
            bottomRight: Radius.circular(isMe ? 4.0 : 16.0),
          ),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    money.format(amount, currency),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isMe
                  ? 'You paid · split with $splitWith'
                  : '${payerName ?? 'They'} paid · split with $splitWith',
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _settleControl(money, currency, textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _settleControl(MoneyFormatter money, String currency, Color textSecondary) {
    switch (settleState) {
      case SettleState.mine:
        // Nothing to settle with yourself. Showing a live button here was one
        // of the ways the old stub looked functional while doing nothing.
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Others settle their share with you',
                style: TextStyle(fontSize: 11.5, color: textSecondary),
              ),
            ),
          ],
        );

      case SettleState.loading:
        return SizedBox(
          height: 38,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: textSecondary),
            ),
          ),
        );

      case SettleState.settled:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 15, color: AppColors.income),
            const SizedBox(width: 6),
            Text(
              'Settled up',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
          ],
        );

      case SettleState.owed:
        return SizedBox(
          width: double.infinity,
          height: 38,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            // Disabled while a request is in flight, so an impatient double-tap
            // can't post two settlements for the same debt.
            onPressed: isSettling ? null : onSettlePressed,
            child: isSettling
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Settle ${money.format(settleAmount, currency)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
          ),
        );
    }
  }
}
