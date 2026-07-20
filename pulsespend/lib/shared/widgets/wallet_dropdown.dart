import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/wallet_model.dart';
import '../../providers/wallets_provider.dart';

/// Wallet chooser for the places money moves between wallets — the transfer
/// sheet and the Add Transaction transfer tab. Each option carries its balance
/// so the user can see what they're moving before they move it. Wallet id 0 is
/// the virtual "Default" bucket.
class WalletDropdown extends ConsumerWidget {
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  /// Wallet to leave out — pass the other side of a transfer so the two ends
  /// can never be the same wallet.
  final int? excludeId;

  const WalletDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.excludeId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final async = ref.watch(walletBalancesProvider);
    final balances = async.asData?.value ?? const <WalletBalance>[];

    // walletBalancesProvider is autoDispose, so reaching a transfer from a
    // screen that wasn't already watching it means a fetch starts here. Say so
    // — an empty dropdown reads as "you have no wallets", not "hang on".
    if (balances.isEmpty && async.isLoading) {
      return _Shell(
        isDark: isDark,
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading wallets…',
              style: TextStyle(
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // The Default bucket (id 0) is a legitimate transfer end even when it has
    // no activity yet — balances() only synthesizes it once it's non-empty, so
    // add a zero row here when it's missing. Without this a user whose every
    // transaction is wallet-assigned can never move money into Default.
    final withDefault = balances.any((b) => b.wallet.id == 0)
        ? balances
        : [
            WalletBalance(
              wallet: const WalletModel(id: 0, name: 'Default', type: 'cash', currency: 'LKR'),
              income: 0,
              expense: 0,
              balance: 0,
              displayCurrency: balances.isNotEmpty ? balances.first.displayCurrency : 'LKR',
            ),
            ...balances,
          ];
    final options = withDefault.where((b) => b.wallet.id != excludeId).toList();

    // A selection that's just been excluded (user picked it on the other side)
    // must not stay as the dropdown's value or it throws.
    final safeValue = options.any((b) => b.wallet.id == value) ? value : null;

    return _Shell(
      isDark: isDark,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: safeValue,
          hint: Text(label),
          isExpanded: true,
          items: [
            for (final b in options)
              DropdownMenuItem(
                value: b.wallet.id,
                child: Row(
                  children: [
                    Icon(b.wallet.icon, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(b.wallet.name, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      // Liabilities read as debt, so show what's owed rather than
                      // a negative balance that looks like an empty wallet.
                      b.wallet.isLiability
                          ? 'owe ${b.amountOwed.toStringAsFixed(0)}'
                          : b.balance.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: b.wallet.isLiability
                            ? AppColors.expense
                            : (isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// The bordered box both states share, so the field doesn't resize or shift
/// when the balances finish loading.
class _Shell extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _Shell({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
