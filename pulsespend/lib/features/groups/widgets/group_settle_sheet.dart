import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/wallets_provider.dart';

/// Result of [GroupSettleSheet] — which wallet the payer's cash came from.
class GroupSettleResult {
  /// null = the default cash bucket; >0 = a specific wallet the cash left from.
  final int? walletId;
  const GroupSettleResult(this.walletId);
}

/// Asks which wallet the payer's settle-up cash came from, then settles. The
/// chosen wallet moves by the amount via a transfer-excluded leg (not counted as
/// spending); "Default" uses the untracked cash bucket. The payee's side always
/// lands in their own default bucket, since we can't know their wallets.
///
/// Lives here rather than inside a screen because BOTH the group detail screen
/// and the group chat's expense bubble settle through it. Keeping one copy is
/// what stops the two paths drifting apart — the chat path previously had no
/// implementation at all, and the temptation was to write a second, simpler
/// one that skipped the wallet question and silently mis-recorded where the
/// money came from.
class GroupSettleSheet extends ConsumerStatefulWidget {
  final String toName;
  final double amount;
  final String currency;

  /// Optional context line, e.g. the expense this settles a share of.
  final String? subtitle;

  const GroupSettleSheet({
    super.key,
    required this.toName,
    required this.amount,
    required this.currency,
    this.subtitle,
  });

  @override
  ConsumerState<GroupSettleSheet> createState() => _GroupSettleSheetState();
}

class _GroupSettleSheetState extends ConsumerState<GroupSettleSheet> {
  /// 0 = the default bucket; >0 = a specific wallet id.
  int _selection = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final money = ref.watch(moneyFormatterProvider);
    // The cash has to sit somewhere spendable, so debt accounts are excluded.
    final wallets = ref
        .watch(walletsControllerProvider)
        .items
        .where((w) => !w.isLiability)
        .toList();

    Widget chip(String label, int value) {
      final selected = _selection == value;
      return GestureDetector(
        onTap: () => setState(() => _selection = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: selected ? Colors.white : textSecondary,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Settle up?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'You paid ${widget.toName} ${money.format(widget.amount, widget.currency)}. '
            'This settles the balance right away.',
            style: TextStyle(fontSize: 13, color: textSecondary),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.subtitle!,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text('Which wallet did it come from?',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('Default', 0),
              for (final w in wallets) chip(w.name, w.id),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'The wallet drops by the amount — without counting as spending, because '
            'settling a shared debt is money changing hands, not an expense.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  Navigator.pop(context, GroupSettleResult(_selection == 0 ? null : _selection)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Settle up'),
            ),
          ),
        ],
      ),
    );
  }
}
