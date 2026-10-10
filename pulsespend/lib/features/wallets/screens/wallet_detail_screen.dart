import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../design_system/ds.dart';
import '../../../models/wallet_model.dart';
import '../../../providers/wallets_provider.dart';
import '../../../shared/widgets/category_icon.dart';
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
      return const Scaffold(
        appBar: DsTitleAppBar(title: 'Wallet'),
        body: EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Wallet not found',
          message: 'It may have been deleted. Its transactions moved to the default wallet.',
        ),
      );
    }

    final txs = ref.watch(walletTransactionsProvider(walletId));

    return Scaffold(
      appBar: DsTitleAppBar(
        title: wallet.name,
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
        padding: const EdgeInsets.fromLTRB(
          AppTokens.screenPadding,
          AppTokens.space12,
          AppTokens.screenPadding,
          AppTokens.space32,
        ),
        children: [
          _HeaderCard(wallet: wallet, balance: balance),
          const SizedBox(height: AppTokens.space24),
          const DsSectionHeader(
            title: 'Recent transactions',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppTokens.space12),
          txs.when(
            loading: () => const DsTransactionSkeleton(count: 4),
            error: (e, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTokens.space16),
              child: DsInlineError(message: 'Couldn\'t load transactions.'),
            ),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppTokens.space32),
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Nothing here yet',
                      message: 'Transactions assigned to this wallet will show up here.',
                    ),
                  )
                : Column(
                    children: [
                      for (final t in items)
                        DsCard(
                          margin: const EdgeInsets.only(bottom: AppTokens.space8),
                          padding: EdgeInsets.zero,
                          radius: AppTokens.radiusCardSm,
                          child: DsTransactionTile(
                            title: t.title,
                            subtitle: t.category,
                            amountText: CurrencyFormatter.format(t.amount, t.currency),
                            amount: t.amount,
                            icon: Icons.receipt_long_rounded,
                            iconColor: AppColors.categoryColor(t.category),
                            leading: CategoryIcon(category: t.category, size: 44),
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
    final tk = context.tokens;
    final theme = Theme.of(context);
    final b = balance;
    final isLiability = wallet.isLiability;
    final cur = b?.displayCurrency ?? wallet.currency;
    final progress = b?.payoffProgress;

    // The headline used to carry the semantic colour; on a payment card the
    // figure is white, so the gradient carries it instead — green once a debt is
    // cleared or in credit, red while money is owed or a wallet is overdrawn,
    // brand blue for an ordinary balance.
    final isSettled = b != null && (b.isOverpaid || b.isPaidOff);
    final isNegative = !isSettled && (isLiability || (b != null && b.balance < 0));
    final Gradient cardGradient = isSettled || isNegative
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [isSettled ? tk.success : tk.danger, AppColors.heroNavy],
          )
        : tk.heroGradient;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DsBankCard(
          height: 196,
          gradient: cardGradient,
          brandLogo: Icon(wallet.icon, color: Colors.white, size: 26),
          brandLabel: '${wallet.type[0].toUpperCase()}${wallet.type.substring(1)} · ${wallet.currency}'
              '${isLiability ? ' · liability' : ''}',
          balanceLabel:
              // Overpaying flips the headline to credit; clearing it entirely
              // flips it to finished (loan) / settled (card).
              b != null && b.isOverpaid
                  ? 'In credit'
                  : b != null && b.isPaidOff
                      ? (wallet.type == 'loan' ? 'Paid off 🎉' : 'All clear ✓')
                      : (isLiability ? 'You owe' : 'Balance'),
          balance: b == null
              ? '—'
              : CurrencyFormatter.format(
                  isLiability ? (b.isOverpaid ? b.creditBalance : b.amountOwed) : b.balance,
                  cur,
                ),
          holderName: wallet.name,
          // The wallet model has no card number, so the slot stays empty rather
          // than showing a fabricated one.
          maskedNumber: null,
        ),
        if (b != null) ...[
          const SizedBox(height: AppTokens.space16),
          DsCard(
            padding: const EdgeInsets.all(AppTokens.space16),
            child: Column(
              // Stretch so the payoff bar spans the card instead of collapsing
              // to its own filled fraction.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A debt has three flows, not two: what it started at, what's
                // been added since, and what's been paid back. An asset only has
                // in/out.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLiability && b.borrowed > 0)
                      Expanded(
                        child: _Flow(
                          label: 'Borrowed',
                          value: CurrencyFormatter.format(b.borrowed, cur),
                          color: tk.danger,
                          icon: Icons.south_west_rounded,
                        ),
                      ),
                    Expanded(
                      child: _Flow(
                        label: isLiability ? 'Charged' : 'In',
                        value: CurrencyFormatter.format(isLiability ? b.charged : b.income, cur),
                        color: isLiability ? tk.danger : tk.success,
                        icon: Icons.arrow_upward_rounded,
                      ),
                    ),
                    Expanded(
                      child: _Flow(
                        label: isLiability ? 'Repaid' : 'Out',
                        value: CurrencyFormatter.format(isLiability ? b.repaid : b.expense, cur),
                        color: isLiability ? tk.success : tk.danger,
                        icon: Icons.arrow_downward_rounded,
                      ),
                    ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: AppTokens.space16),
                  DsProgressBar(
                    value: progress,
                    // Paying a debt down is progress, so the bar stays green all
                    // the way up rather than running the budget warning ramp.
                    color: tk.success,
                    trackColor: tk.dangerBg,
                    height: 7,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}% paid off of '
                    '${CurrencyFormatter.format(b.borrowed, cur)} borrowed'
                    '${b.charged > 0 ? ' + ${CurrencyFormatter.format(b.charged, cur)} charges' : ''}',
                    style: theme.textTheme.labelSmall?.copyWith(color: tk.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
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
    final tk = context.tokens;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DsIconChip(icon: icon, color: color, size: 26, iconSize: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: tk.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
