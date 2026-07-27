import 'package:flutter/material.dart';
import '../../../shared/widgets/app_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/wallet_model.dart';
import '../../../providers/wallets_provider.dart';
import '../../../shared/widgets/empty_state.dart';
import 'opening_balance_sheet.dart';
import 'wallets_screen.dart';

/// One wallet's story: what's in it (or owed on it), the two flows behind that
/// number, and the transactions that produced them. Liability wallets are framed
/// as debt — charges push the balance down, repayments pull it back up.
class WalletDetailScreen extends ConsumerWidget {
  final int walletId;
  const WalletDetailScreen({super.key, required this.walletId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref
        .watch(walletsControllerProvider)
        .items
        .where((w) => w.id == walletId)
        .firstOrNull;
    final balance = ref
        .watch(walletBalancesProvider)
        .asData
        ?.value
        .where((b) => b.wallet.id == walletId)
        .firstOrNull;

    // Deleted from another device while open.
    if (wallet == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wallet')),
        body: const EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Wallet not found',
          message: 'It may have been deleted. Its transactions moved to the default wallet.',
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final txs = ref.watch(walletTransactionsProvider(walletId));

    return Scaffold(
      appBar: AppBar(
        title: Text(wallet.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') {
                WalletEditorSheet.show(context, existing: wallet);
              } else {
                OpeningBalanceSheet.show(context, wallet: wallet, balance: balance);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit wallet'),
                ),
              ),
              PopupMenuItem(
                value: 'opening',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: Text(wallet.isLiability ? 'Correct amount owed' : 'Correct balance'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _HeaderCard(wallet: wallet, balance: balance),
          const SizedBox(height: 20),
          Text(
            'Recent transactions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          txs.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: AppLoader(size: 40)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('Couldn\'t load transactions.',
                  style: TextStyle(color: AppColors.expense.withValues(alpha: 0.9))),
            ),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Nothing here yet',
                      message: 'Transactions assigned to this wallet will show up here.',
                    ),
                  )
                : Column(
                    children: [
                      for (final t in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurface : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(t.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600, fontSize: 13.5)),
                                      const SizedBox(height: 2),
                                      Text(
                                        t.category,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.format(t.amount, t.currency),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: t.isExpense ? AppColors.expense : AppColors.income,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final WalletModel wallet;
  final WalletBalance? balance;

  const _HeaderCard({required this.wallet, required this.balance});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final b = balance;
    final isLiability = wallet.isLiability;
    final cur = b?.displayCurrency ?? wallet.currency;
    final progress = b?.payoffProgress;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (isLiability ? AppColors.expense : AppColors.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(wallet.icon,
                    color: isLiability ? AppColors.expense : AppColors.primary, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${wallet.type[0].toUpperCase()}${wallet.type.substring(1)} · ${wallet.currency}'
                  '${isLiability ? ' · liability' : ''}',
                  style: TextStyle(fontSize: 12.5, color: textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            // Overpaying flips the headline to credit; clearing it entirely
            // flips it to finished (loan) / settled (card).
            b != null && b.isOverpaid
                ? 'In credit'
                : b != null && b.isPaidOff
                    ? (wallet.type == 'loan' ? 'Paid off 🎉' : 'All clear ✓')
                    : (isLiability ? 'You owe' : 'Balance'),
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            b == null
                ? '—'
                : CurrencyFormatter.format(
                    isLiability ? (b.isOverpaid ? b.creditBalance : b.amountOwed) : b.balance,
                    cur,
                  ),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: b != null && (b.isOverpaid || b.isPaidOff)
                  ? AppColors.income
                  : (isLiability
                      ? AppColors.expense
                      : (b != null && b.balance < 0 ? AppColors.expense : null)),
            ),
          ),
          if (b != null) ...[
            const SizedBox(height: 16),
            // A debt has three flows, not two: what it started at, what's been
            // added since, and what's been paid back. An asset only has in/out.
            Row(
              children: [
                if (isLiability && b.borrowed > 0)
                  Expanded(
                    child: _Flow(
                      label: 'Borrowed',
                      value: CurrencyFormatter.format(b.borrowed, cur),
                      color: AppColors.expense,
                      icon: Icons.south_west_rounded,
                    ),
                  ),
                Expanded(
                  child: _Flow(
                    label: isLiability ? 'Charged' : 'In',
                    value: CurrencyFormatter.format(isLiability ? b.charged : b.income, cur),
                    color: isLiability ? AppColors.expense : AppColors.income,
                    icon: Icons.arrow_upward_rounded,
                  ),
                ),
                Expanded(
                  child: _Flow(
                    label: isLiability ? 'Repaid' : 'Out',
                    value: CurrencyFormatter.format(isLiability ? b.repaid : b.expense, cur),
                    color: isLiability ? AppColors.income : AppColors.expense,
                    icon: Icons.arrow_downward_rounded,
                  ),
                ),
              ],
            ),
          ],
          if (progress != null && b != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: AppColors.expense.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation(AppColors.income),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(progress * 100).toStringAsFixed(0)}% paid off of '
              '${CurrencyFormatter.format(b.borrowed, cur)} borrowed'
              '${b.charged > 0 ? ' + ${CurrencyFormatter.format(b.charged, cur)} charges' : ''}',
              style: TextStyle(fontSize: 11.5, color: textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Flow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _Flow({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
