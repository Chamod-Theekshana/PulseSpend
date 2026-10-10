import 'package:flutter/material.dart';
import '../../shared/widgets/app_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../design_system/ds.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/analytics_model.dart';
import '../../models/budget_model.dart';
import '../../models/goal_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../models/wallet_model.dart';
import '../../providers/profile_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/wallets_provider.dart';
import '../../l10n/l10n_ext.dart';
import '../../shared/utils/image_utils.dart';

import '../../shared/widgets/category_icon.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/profile_drawer.dart';
import '../budgets/screens/budgets_screen.dart';
import '../goals/screens/goals_screen.dart';
import '../wallets/screens/wallets_screen.dart';
import '../notifications/screens/notifications_screen.dart';
import '../transactions/screens/transaction_detail_screen.dart';
import '../transactions/screens/transactions_screen.dart';
import 'widgets/month_calendar_sheet.dart';
import 'widgets/net_worth_breakdown_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(transactionSummaryProvider);
    final dashboardTxAsync = ref.watch(dashboardTransactionsProvider);
    final txItems = dashboardTxAsync.asData?.value ?? const <TransactionModel>[];
    final txLoading = dashboardTxAsync.isLoading && txItems.isEmpty;
    final budgetsState = ref.watch(budgetsControllerProvider);
    final goalsState = ref.watch(goalsControllerProvider);
    final profile = ref.watch(profileControllerProvider);
    final unreadCount = ref.watch(notificationsControllerProvider).unreadCount;
    final money = ref.watch(moneyFormatterProvider);

    // Listen for budget alerts and display polished SnackBars
    ref.listen(budgetsControllerProvider, (previous, next) {
      final alert = next.latestAlert;
      if (alert != null && previous?.latestAlert != alert) {
        final isExceeded = alert.level == 'exceeded';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating, // Floating for modern UX
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: isExceeded ? AppColors.expense : AppColors.warning,
            content: Row(
              children: [
                Icon(
                  isExceeded ? Icons.error_outline : Icons.warning_amber_rounded,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isExceeded
                        ? '${alert.category} budget exceeded (${alert.percentage}%)'
                        : '${alert.category} budget at ${alert.percentage}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
        ref.read(budgetsControllerProvider.notifier).dismissAlert();
      }
    });

    final user = profile.user;
    final greeting = _getGreeting(context);
    final userName = user?.fullName ?? 'User';

    return Builder(
      builder: (drawerCtx) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: Theme.of(context).cardColor,
          onRefresh: () async {
            ref.invalidate(dashboardTransactionsProvider);
            ref.invalidate(walletBalancesProvider);
            ref.invalidate(insightsProvider);
            ref.invalidate(weeklyDigestProvider);
            await Future.wait([
              ref.read(transactionsControllerProvider.notifier).refresh(),
              ref.read(budgetsControllerProvider.notifier).refresh(),
              ref.read(goalsControllerProvider.notifier).refresh(),
            ]);
          },
          child: CustomScrollView(
            // Adds a premium iOS-style bounce effect to the entire dashboard
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // ── 1. Top Header ──
              SliverToBoxAdapter(
                child: _DashboardHeader(
                  greeting: greeting,
                  userName: userName,
                  profilePhoto: user?.profilePhoto,
                  unreadCount: unreadCount,
                  onProfileTap: () => ProfileDrawerController.open(drawerCtx),
                  onNotificationTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                  ),
                ),
              ),

              // ── 1.5 Deletion grace-window banner ──
              const SliverToBoxAdapter(child: _RestoreAccountBanner()),

              // ── 2. Total Balance & Vector Area Chart ──
              SliverToBoxAdapter(
                child: summaryAsync.when(
                  data: (summary) => _BalanceOverviewSection(
                    summary: summary,
                    history: ref.watch(balanceHistoryProvider).asData?.value ?? const [],
                    money: money,
                  ),
                  loading: () => const _BalanceSectionSkeleton(),
                  error: (e, __) => _BalanceSectionSkeleton(error: e.toString()),
                ),
              ),

              // ── 3. Earnings / Spendings Row ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: summaryAsync.when(
                    data: (summary) => _EarningsSpendingsRow(
                      summary: summary,
                      money: money,
                      incomeCount: txItems.where((t) => !t.isTransfer && t.amount > 0).length,
                      expenseCount: txItems.where((t) => !t.isTransfer && t.amount < 0).length,
                    ),
                    loading: () => const _EarningsRowSkeleton(),
                    error: (_, __) => const _EarningsRowSkeleton(),
                  ),
                ),
              ),

              // ── 3.2 Wallet balances ──
              const SliverToBoxAdapter(
                child: _WalletBalancesSection(),
              ),

              // ── 3.5 Insights & Weekly Recap ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                  child: _InsightsSection(money: money),
                ),
              ),

              // ── 4. Top Spending Categories ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                  child: _TopSpendingSection(
                    transactions: txItems,
                    money: money,
                  ),
                ),
              ),

              // ── 5. Budget Overview ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 32, 0, 0),
                  child: _BudgetOverviewSection(
                    state: budgetsState,
                    money: money,
                    onManage: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BudgetsScreen()),
                    ),
                  ),
                ),
              ),

              // ── 6. Savings Goals ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 32, 0, 0),
                  child: _SavingsGoalsSection(
                    state: goalsState,
                    money: money,
                    onManage: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GoalsScreen()),
                    ),
                  ),
                ),
              ),

              // ── 7. Recent Transactions Header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                  child: _RecentTransactionsHeader(
                    onViewAll: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TransactionsScreen()),
                    ),
                  ),
                ),
              ),

              // ── Recent Transactions List ──
              if (txLoading)
                const SliverToBoxAdapter(child: SizedBox(height: 200))
              else if (txItems.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: context.l10n.noTransactionsTitle,
                      message: context.l10n.noTransactionsBody,
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final tx = txItems.take(6).toList()[i];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: _TransactionRow(
                          transaction: tx,
                          money: money,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TransactionDetailScreen(transaction: tx),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: txItems.take(6).length,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }

  String _getGreeting(BuildContext context) {
    final l = context.l10n;
    final hour = DateTime.now().hour;
    if (hour < 12) return l.greetingMorning;
    if (hour < 17) return l.greetingAfternoon;
    return l.greetingEvening;
  }
}

// ──────────────────────────────────────────────────────────
// REUSABLE UI COMPONENTS (Added for consistency & beauty)
// ──────────────────────────────────────────────────────────

/// A reusable, highly polished section header used across the dashboard
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onManage;
  final String manageLabel;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.onManage,
    this.manageLabel = 'Manage',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18, // Slightly larger for better hierarchy
                  letterSpacing: -0.3, // Modern typography feel
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
        if (onManage != null)
          InkWell(
            onTap: onManage,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    manageLabel,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────
// 1. TOP HEADER
// ──────────────────────────────────────────────────────────
class _DashboardHeader extends StatelessWidget {
  final String greeting;
  final String userName;
  final String? profilePhoto;
  final int unreadCount;
  final VoidCallback onNotificationTap;
  final VoidCallback onProfileTap;

  const _DashboardHeader({
    required this.greeting,
    required this.userName,
    required this.profilePhoto,
    required this.unreadCount,
    required this.onNotificationTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return DsIdentityAppBar(
      greeting: greeting,
      name: userName,
      avatar: profilePhoto == null ? null : getProfileImageProvider(profilePhoto!),
      onAvatarTap: onProfileTap,
      onNotificationTap: onNotificationTap,
      unreadCount: unreadCount,
      padding: const EdgeInsets.fromLTRB(
        AppTokens.screenPadding,
        AppTokens.space16,
        AppTokens.screenPadding,
        AppTokens.space20,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// 2. BALANCE & VECTOR CHART SECTION
// ──────────────────────────────────────────────────────────
class _ChartPoint {
  final String label;
  final DateTime month;
  final double balance;
  const _ChartPoint({required this.label, required this.month, required this.balance});
}

class _BalanceOverviewSection extends StatefulWidget {
  final TransactionSummary summary;
  final List<BalanceHistoryPoint> history;
  final MoneyFormatter money;

  const _BalanceOverviewSection({
    required this.summary,
    required this.history,
    required this.money,
  });

  @override
  State<_BalanceOverviewSection> createState() => _BalanceOverviewSectionState();
}

class _BalanceOverviewSectionState extends State<_BalanceOverviewSection> {
  int? _selectedIndex;

  static const _monthLabels =
      ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  List<_ChartPoint> _pointsFrom(List<BalanceHistoryPoint> history) {
    return [
      for (final p in history)
        _ChartPoint(
          label: _monthLabels[p.month.month - 1],
          month: p.month,
          balance: p.balance,
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.history.isEmpty ? null : widget.history.length - 1;
  }

  @override
  void didUpdateWidget(covariant _BalanceOverviewSection old) {
    super.didUpdateWidget(old);
    if (_selectedIndex == null && widget.history.isNotEmpty) {
      _selectedIndex = widget.history.length - 1;
    } else if (_selectedIndex != null && _selectedIndex! >= widget.history.length) {
      _selectedIndex = widget.history.isEmpty ? null : widget.history.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chartPoints = _pointsFrom(widget.history);
    final selectedPoint =
        (_selectedIndex != null && _selectedIndex! < chartPoints.length)
            ? chartPoints[_selectedIndex!]
            : null;
    final now = DateTime.now();
    final dateStr = selectedPoint != null
        ? '${_monthLabels[selectedPoint.month.month - 1]} ${selectedPoint.month.year}'
        : DateFormat('MMM dd, yyyy').format(now);

    final convertedSummaryBalance =
        widget.money.convert(widget.summary.balance, widget.summary.currency);
    final displayBalance = selectedPoint?.balance ?? convertedSummaryBalance;

    return DsHeroBalanceCard(
      balanceLabel: context.l10n.totalBalance,
      balance: CurrencyFormatter.format(
        displayBalance,
        widget.money.displayCurrency,
      ),
      periodLabel: dateStr,
      series: [
        for (final p in chartPoints)
          DsSeriesPoint(label: '${p.label} ${p.month.year}', value: p.balance),
      ],
      valueFormatter: (v) =>
          CurrencyFormatter.format(v, widget.money.displayCurrency),
      onPointSelected: (i) {
        setState(() {
          _selectedIndex = i ?? (chartPoints.isEmpty ? null : chartPoints.length - 1);
        });
      },
      trailing: DsHeaderIconButton(
        icon: Icons.calendar_month_outlined,
        onHero: true,
        onTap: () => MonthCalendarSheet.show(context),
      ),
    );
  }
}

class _BalanceSectionSkeleton extends StatelessWidget {
  final String? error;
  const _BalanceSectionSkeleton({this.error});

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.screenPadding),
        child: DsInlineError(message: error!),
      );
    }
    return const DsHeroSkeleton(height: 210);
  }
}

// ──────────────────────────────────────────────────────────
// 3. EARNINGS & SPENDINGS ROW
// ──────────────────────────────────────────────────────────
class _EarningsSpendingsRow extends StatelessWidget {
  final TransactionSummary summary;
  final MoneyFormatter money;
  final int incomeCount;
  final int expenseCount;

  const _EarningsSpendingsRow({
    required this.summary,
    required this.money,
    required this.incomeCount,
    required this.expenseCount,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Row(
      children: [
        Expanded(
          child: _EarningsCard(
            label: l.earnings,
            amount: money.convert(summary.income, summary.currency),
            currency: money.displayCurrency,
            count: incomeCount,
            isIncome: true,
          ),
        ),
        const SizedBox(width: 16), // Increased spacing slightly for better breathing room
        Expanded(
          child: _EarningsCard(
            label: l.spendings,
            amount: money.convert(summary.expense.abs(), summary.currency),
            currency: money.displayCurrency,
            count: expenseCount,
            isIncome: false,
          ),
        ),
      ],
    );
  }
}

class _EarningsCard extends StatelessWidget {
  final String label;
  final double amount;
  final String currency;
  final int count;
  final bool isIncome;

  const _EarningsCard({
    required this.label,
    required this.amount,
    required this.currency,
    required this.count,
    required this.isIncome,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final color = isIncome ? AppColors.income : AppColors.expense;
    final sign = isIncome ? '+' : '-';
    final icon = isIncome ? Icons.arrow_outward_rounded : Icons.call_received_rounded; // More modern icons

    return DsCard(
      padding: const EdgeInsets.all(AppTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Soft background circle for the icon makes it pop beautifully
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$sign${CurrencyFormatter.format(amount, currency)}',
              style: theme.textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: AppTokens.space12),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.6), 
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$count ${isIncome ? 'income' : 'expense'}${count == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EarningsRowSkeleton extends StatelessWidget {
  const _EarningsRowSkeleton();
  @override
  Widget build(BuildContext context) => const DsCardRowSkeleton(height: 104);
}

// ──────────────────────────────────────────────────────────
// GRACE WINDOW BANNER
// ──────────────────────────────────────────────────────────
class _RestoreAccountBanner extends ConsumerWidget {
  const _RestoreAccountBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(profileControllerProvider).user;
    final requestedAt = user?.deletionRequestedAt;
    if (requestedAt == null) return const SizedBox.shrink();

    final deleteOn = requestedAt.add(const Duration(days: 7));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.expense.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.expense.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.expense.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: AppColors.expense, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Account scheduled for deletion on\n${deleteOn.day}/${deleteOn.month}/${deleteOn.year}.',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AppColors.expense,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final userId = ref.read(currentUserIdProvider);
                  await ref.read(profileRepositoryProvider).cancelDeletion(userId);
                  await ref.read(profileControllerProvider.notifier).refresh();
                  messenger.showSnackBar(const SnackBar(
                    content: Text('Account restored ✓', style: TextStyle(fontWeight: FontWeight.w600)),
                    backgroundColor: AppColors.income,
                    behavior: SnackBarBehavior.floating,
                  ));
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(DioClient.toApiException(e).localizedMessage(context)),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Restore', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// 4. WALLET BALANCES SECTION
// ──────────────────────────────────────────────────────────
class _WalletBalancesSection extends ConsumerWidget {
  const _WalletBalancesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final balances = ref.watch(walletBalancesProvider).asData?.value ?? const <WalletBalance>[];
    final hasRealWallets = balances.any((b) => b.wallet.id != 0);
    if (!hasRealWallets) return const SizedBox.shrink();

    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SectionHeader(
              title: 'Wallets',
              subtitle: 'Balance per account',
              onManage: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WalletsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // ── Net worth strip (assets − liabilities) ──
          Consumer(builder: (context, ref, _) {
            final nw = ref.watch(netWorthProvider).asData?.value;
            if (nw == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Material(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(20), // More rounded corners
                // Added subtle shadow for depth
                elevation: isDark ? 0 : 2,
                shadowColor: Colors.black.withValues(alpha: 0.2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => NetWorthBreakdownSheet.show(context, nw),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? AppColors.darkBorder : Colors.transparent),
                      gradient: isDark ? null : LinearGradient(
                        colors: [Colors.white, Colors.grey.shade50],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.account_balance_wallet_rounded, size: 12, color: AppColors.primary),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Total Net Worth',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                CurrencyFormatter.formatCompact(nw.netWorth, nw.currency),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20, // Larger emphasis
                                  letterSpacing: -0.5,
                                  color: nw.netWorth < 0 ? AppColors.expense : textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _NetWorthStat(label: 'Assets', value: CurrencyFormatter.formatCompact(nw.assets, nw.currency), color: AppColors.income),
                            const SizedBox(height: 8),
                            _NetWorthStat(label: 'Liabilities', value: CurrencyFormatter.formatCompact(nw.liabilities, nw.currency), color: AppColors.expense),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // ── Wallet horizontal cards ──
          SizedBox(
            height: 104, // Slightly taller for better proportions
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: balances.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final b = balances[i];
                return Container(
                  width: 170,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder.withValues(alpha: 0.5)),
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(b.wallet.icon, size: 16, color: AppColors.primary),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              b.wallet.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        CurrencyFormatter.formatCompact(b.balance, b.displayCurrency),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.5,
                          color: b.balance < 0 ? AppColors.expense : textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NetWorthStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _NetWorthStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value, 
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────
// 5. INSIGHTS & RECAP SECTION
// ──────────────────────────────────────────────────────────
class _InsightsSection extends ConsumerWidget {
  final MoneyFormatter money;
  const _InsightsSection({required this.money});

  Color _toneColor(String tone) => switch (tone) {
        'positive' => AppColors.income,
        'warning' => AppColors.warning,
        _ => AppColors.primary,
      };

  IconData _toneIcon(String tone) => switch (tone) {
        'positive' => Icons.trending_up_rounded,
        'warning' => Icons.warning_amber_rounded,
        _ => Icons.lightbulb_outline_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final insightsAsync = ref.watch(insightsProvider);
    final digestAsync = ref.watch(weeklyDigestProvider);

    final insights = insightsAsync.asData?.value ?? const <Insight>[];
    final digest = digestAsync.asData?.value;

    final hasDigest = digest != null && digest.transactionCount > 0;
    if (insights.isEmpty && !hasDigest) return const SizedBox.shrink();

    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Insights',
          subtitle: 'Smart tips from your spending',
        ),
        const SizedBox(height: 16),

        // Weekly recap tile
        if (hasDigest) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.insights_rounded, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'This week\'s digest',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _RecapStat(
                        label: 'Spent',
                        value: money.formatCompact(digest.expense, digest.currency),
                      ),
                    ),
                    Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.2)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: _RecapStat(
                          label: 'Earned',
                          value: money.formatCompact(digest.income, digest.currency),
                        ),
                      ),
                    ),
                    Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.2)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: _RecapStat(
                          label: 'Saved',
                          value: '${digest.savingsRate.round()}%',
                        ),
                      ),
                    ),
                  ],
                ),
                if (digest.topCategoryName != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department_rounded, color: Colors.amber, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Top spend: ${digest.topCategoryName} (${money.formatCompact(digest.topCategoryAmount, digest.currency)})',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Insight cards
        for (final insight in insights.take(3)) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? AppColors.darkBorder : Colors.transparent),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _toneColor(insight.tone).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_toneIcon(insight.tone), color: _toneColor(insight.tone), size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insight.title,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        insight.body,
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RecapStat extends StatelessWidget {
  final String label;
  final String value;
  const _RecapStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.5),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────
// 6. TOP SPENDING SECTION
// ──────────────────────────────────────────────────────────
class _TopSpendingSection extends StatelessWidget {
  final List<TransactionModel> transactions;
  final MoneyFormatter money;

  const _TopSpendingSection({required this.transactions, required this.money});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Map<String, double> catMap = {};
    for (final tx in transactions) {
      if (tx.isTransfer) continue;
      if (tx.amount < 0) {
        final converted = money.convert(tx.amount, tx.currency).abs();
        catMap[tx.category] = (catMap[tx.category] ?? 0) + converted;
      }
    }
    final total = catMap.values.fold(0.0, (a, b) => a + b);
    final sorted = catMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Top Spending',
          subtitle: 'Highest categories for ${DateFormat('MMM yyyy').format(DateTime.now())}',
        ),
        const SizedBox(height: 16),
        
        if (top.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 30),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.pie_chart_outline_rounded, size: 40, color: (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary).withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                    'No spending data yet',
                    style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : Colors.transparent,
              ),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: Column(
              children: top.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                final pct = total > 0 ? (e.value / total) : 0.0;
                final color = AppColors.categoryPalette[
                    e.key.toLowerCase().codeUnits.fold<int>(0, (a, b) => a + b) %
                        AppColors.categoryPalette.length];
                final pctStr = '${(pct * 100).round()}%';
                
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.key,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: pct.clamp(0.0, 1.0),
                                    minHeight: 6,
                                    backgroundColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                                    valueColor: AlwaysStoppedAnimation(color),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                CurrencyFormatter.formatCompact(e.value, money.displayCurrency),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  pctStr,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (i < top.length - 1)
                      Divider(
                        height: 1,
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        indent: 20,
                        endIndent: 20,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────
// 7. BUDGET OVERVIEW SECTION
// ──────────────────────────────────────────────────────────
class _BudgetOverviewSection extends StatelessWidget {
  final BudgetsState state;
  final MoneyFormatter money;
  final VoidCallback onManage;

  const _BudgetOverviewSection({required this.state, required this.money, required this.onManage});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: _SectionHeader(
            title: 'Budget Overview',
            subtitle: 'Monitor your spending limits',
            onManage: onManage,
          ),
        ),
        if (state.isLoading && state.items.isEmpty)
          const SizedBox(
            height: 180,
            child: Center(child: AppLoader(size: 40)),
          )
        else if (state.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : Colors.transparent,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.pie_chart_outline_rounded, size: 40, color: AppColors.primary.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                    'No budgets set yet',
                    style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap Manage to create one and control spending.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            // FIXED 1px Overflow Bug: Increased height from 200 to 230 to provide enough space for varying text scales.
            height: 230,
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: state.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (ctx, i) => _BudgetCircleCard(budget: state.items[i], money: money),
            ),
          ),
      ],
    );
  }
}

class _BudgetCircleCard extends StatelessWidget {
  final BudgetModel budget;
  final MoneyFormatter money;

  const _BudgetCircleCard({required this.budget, required this.money});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final pct = (budget.percentage / 100).clamp(0.0, 1.0);
    final remaining = (100 - budget.percentage).clamp(0, 100);
    final color = budget.isExceeded
        ? t.danger
        : (budget.isWarning ? t.warningAccent : AppColors.primary);

    return Container(
      width: 165, // Slightly wider for comfort
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder.withValues(alpha: 0.5)),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      padding: const EdgeInsets.all(AppTokens.space16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        // Crucial fix for overflow inside the card
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            budget.category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          DsRingGauge(
            fraction: pct,
            size: 90,
            color: color,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$remaining%',
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                Text(
                  'remaining',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: t.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${money.formatCompact(budget.remaining, budget.currency)} remaining',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: t.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            '${money.formatCompact(budget.spent, budget.currency)} spent',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: budget.isExceeded ? t.danger : t.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// 8. SAVINGS GOALS SECTION
// ──────────────────────────────────────────────────────────
class _SavingsGoalsSection extends StatelessWidget {
  final GoalsState state;
  final MoneyFormatter money;
  final VoidCallback onManage;

  const _SavingsGoalsSection({
    required this.state,
    required this.money,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeGoals = state.active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: _SectionHeader(
            title: 'Savings Goals',
            subtitle: 'Track your future dreams',
            onManage: onManage,
          ),
        ),
        if (state.isLoading && state.items.isEmpty)
          const SizedBox(
            height: 180,
            child: Center(child: AppLoader(size: 40)),
          )
        else if (activeGoals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : Colors.transparent,
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.flag_circle_rounded, size: 40, color: AppColors.income.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                    'No savings goals yet',
                    style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap Manage to add a goal and start saving.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            // FIXED 1px Overflow Bug: Height changed from 200 to 230 to comfortably fit all child elements.
            height: 230,
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: activeGoals.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (ctx, i) => _GoalCircleCard(
                goal: activeGoals[i],
                money: money,
              ),
            ),
          ),
      ],
    );
  }
}

class _GoalCircleCard extends StatelessWidget {
  final GoalModel goal;
  final MoneyFormatter money;

  const _GoalCircleCard({required this.goal, required this.money});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final pct = (goal.progressPercentage / 100).clamp(0.0, 1.0);
    final remaining = (100 - goal.progressPercentage).clamp(0, 100).round();

    return Container(
      width: 165, // Consistent width with budget cards
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder.withValues(alpha: 0.5)),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      padding: const EdgeInsets.all(AppTokens.space16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        // Crucial fix for overflow inside the card
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            goal.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          DsRingGauge(
            fraction: pct,
            size: 90,
            color: t.success, // Saving is always positive
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$remaining%',
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                Text(
                  'remaining',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: t.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${money.formatCompact(goal.targetAmount - goal.currentAmount, goal.currency)} to go',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: t.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            '${money.formatCompact(goal.currentAmount, goal.currency)} saved',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.success),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// 9. RECENT TRANSACTIONS
// ──────────────────────────────────────────────────────────
class _RecentTransactionsHeader extends StatelessWidget {
  final VoidCallback onViewAll;
  const _RecentTransactionsHeader({required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return _SectionHeader(
      title: 'Recent Transactions',
      subtitle: 'Your latest financial activities',
      onManage: onViewAll,
      manageLabel: 'View All',
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final TransactionModel transaction;
  final MoneyFormatter money;
  final VoidCallback onTap;

  const _TransactionRow({
    required this.transaction,
    required this.money,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExpense = transaction.amount < 0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder.withValues(alpha: 0.5)),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      // Overriding standard DsCard here to integrate better styling
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: DsTransactionTile(
              title: transaction.title,
              subtitle: DateFormatter.relative(transaction.createdAt),
              amountText: money.format(
                transaction.amount,
                transaction.currency,
                showSign: true,
              ),
              amount: transaction.amount,
              neutral: transaction.isTransfer,
              icon: Icons.receipt_long_rounded,
              iconColor: AppColors.categoryColor(transaction.category),
              leading: CategoryIcon(category: transaction.category, size: 48),
              trailingBelow: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (transaction.isTransfer 
                      ? t.neutralShift 
                      : (isExpense ? t.danger : t.success)).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  transaction.isTransfer
                      ? 'Transfer'
                      : (isExpense ? 'Expense' : 'Income'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: transaction.isTransfer
                        ? t.neutralShift
                        : (isExpense ? t.danger : t.success),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}