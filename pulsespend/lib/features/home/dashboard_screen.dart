import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
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

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(transactionSummaryProvider);
    // Unfiltered feed dedicated to the dashboard — the shared transactions
    // controller carries the Transactions screen's filters (search, heatmap
    // day-taps, "view transactions" deep-links) and must not drive the charts.
    final dashboardTxAsync = ref.watch(dashboardTransactionsProvider);
    final txItems = dashboardTxAsync.asData?.value ?? const <TransactionModel>[];
    final txLoading = dashboardTxAsync.isLoading && txItems.isEmpty;
    final budgetsState = ref.watch(budgetsControllerProvider);
    final goalsState = ref.watch(goalsControllerProvider);
    final profile = ref.watch(profileControllerProvider);
    final unreadCount = ref.watch(notificationsControllerProvider).unreadCount;
    final money = ref.watch(moneyFormatterProvider);

    ref.listen(budgetsControllerProvider, (previous, next) {
      final alert = next.latestAlert;
      if (alert != null && previous?.latestAlert != alert) {
        final isExceeded = alert.level == 'exceeded';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: isExceeded ? AppColors.expense : AppColors.warning,
            content: Text(
              isExceeded
                  ? '🚨 ${alert.category} budget exceeded (${alert.percentage}%)'
                  : '⚠️ ${alert.category} budget at ${alert.percentage}%',
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
        // Screenshot එකේ තියෙන ලා අළු/සුදු පසුබිම
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? const Color(0xFF121212) 
            : const Color(0xFFF8F9FA),
        body: RefreshIndicator(
          color: AppColors.primary,
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
            slivers: [
              // ── 1. Top Header (Avatar + Greeting + Bell) ──
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

              // ── 1.5 Deletion grace-window banner (rare) ──
              const SliverToBoxAdapter(child: _RestoreAccountBanner()),

              // ── 2. Total Balance & Vector Area Chart (No Card Wrapper!) ──
              SliverToBoxAdapter(
                child: summaryAsync.when(
                  data: (summary) => _BalanceOverviewSection(
                    summary: summary,
                    transactions: txItems,
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
                      incomeCount: txItems.where((t) => t.amount > 0).length,
                      expenseCount: txItems.where((t) => t.amount < 0).length,
                    ),
                    loading: () => const _EarningsRowSkeleton(),
                    error: (_, __) => const _EarningsRowSkeleton(),
                  ),
                ),
              ),

              // ── 3.2 Wallet balances (only when wallets exist) ──
              const SliverToBoxAdapter(
                child: _WalletBalancesSection(),
              ),

              // ── 3.5 Insights & Weekly Recap ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: _InsightsSection(money: money),
                ),
              ),

              // ── 4. Top Spending Categories ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: _TopSpendingSection(
                    transactions: txItems,
                    money: money,
                  ),
                ),
              ),

              // ── 5. Budget Overview ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
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
                  padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
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
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
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
// 1. TOP HEADER (Updated to match image)
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              // Circular Avatar
              GestureDetector(
                onTap: onProfileTap,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                    image: profilePhoto != null
                        ? DecorationImage(image: getProfileImageProvider(profilePhoto!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: profilePhoto == null
                      ? Center(
                          child: Text(
                            userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 20),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    userName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Notification Button (Squircle card with soft shadow)
          GestureDetector(
            onTap: onNotificationTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.notifications_outlined,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    size: 24,
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30), // Badge Red
                          shape: unreadCount > 9 ? BoxShape.rectangle : BoxShape.circle,
                          borderRadius: unreadCount > 9 ? BorderRadius.circular(8) : null,
                          border: Border.all(
                            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              height: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// 2. BALANCE & VECTOR CHART SECTION — Interactive Real-Data Chart
// ──────────────────────────────────────────────────────────

/// A data-point for one month in the balance history chart.
class _ChartPoint {
  final String label;   // e.g. "Jan"
  final DateTime month; // first day of that month
  final double balance; // running balance at end of month
  const _ChartPoint({required this.label, required this.month, required this.balance});
}

class _BalanceOverviewSection extends StatefulWidget {
  final TransactionSummary summary;
  final List<TransactionModel> transactions;
  final MoneyFormatter money;

  const _BalanceOverviewSection({
    required this.summary,
    required this.transactions,
    required this.money,
  });

  @override
  State<_BalanceOverviewSection> createState() => _BalanceOverviewSectionState();
}

class _BalanceOverviewSectionState extends State<_BalanceOverviewSection>
    with SingleTickerProviderStateMixin {
  int? _selectedIndex;
  late AnimationController _tooltipAnim;
  late Animation<double> _tooltipFade;

  // Build last-6-months running balance from transaction list
  List<_ChartPoint> _buildChartPoints() {
    final now = DateTime.now();
    final points = <_ChartPoint>[];
    const monthLabels = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    // Running balance: start from 0, accumulate all transactions up to end of each month
    for (int i = 5; i >= 0; i--) {
      final targetMonth = DateTime(now.year, now.month - i, 1);
      final endOfMonth = DateTime(targetMonth.year, targetMonth.month + 1, 1)
          .subtract(const Duration(milliseconds: 1));

      double balance = widget.transactions
          .where((tx) => tx.createdAt.isBefore(endOfMonth) ||
              tx.createdAt.isAtSameMomentAs(endOfMonth))
          .fold(0.0, (sum, tx) => sum + widget.money.convert(tx.amount, tx.currency));

      points.add(_ChartPoint(
        label: monthLabels[targetMonth.month - 1],
        month: targetMonth,
        balance: balance,
      ));
    }
    return points;
  }

  @override
  void initState() {
    super.initState();
    _tooltipAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _tooltipFade = CurvedAnimation(parent: _tooltipAnim, curve: Curves.easeOut);
    // Default: select the last (most recent) point
    _selectedIndex = 5;
    _tooltipAnim.forward();
  }

  @override
  void dispose() {
    _tooltipAnim.dispose();
    super.dispose();
  }

  void _onChartTap(Offset localPos, Size chartSize, List<_ChartPoint> points) {
    const n = 6;
    // Find nearest x index
    int nearest = 0;
    double minDist = double.infinity;
    for (int i = 0; i < n; i++) {
      final px = (i / (n - 1)) * chartSize.width;
      final dist = (localPos.dx - px).abs();
      if (dist < minDist) {
        minDist = dist;
        nearest = i;
      }
    }
    setState(() {
      _selectedIndex = nearest;
    });
    _tooltipAnim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chartPoints = _buildChartPoints();
    final selectedPoint = _selectedIndex != null ? chartPoints[_selectedIndex!] : null;
    final now = DateTime.now();
    final dateStr = selectedPoint != null
        ? '${["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][selectedPoint.month.month - 1]} ${selectedPoint.month.year}'
        : DateFormat('MMM dd, yyyy').format(now);

    // Balances are converted into the display currency (chart points already
    // are; convert the summary too so index 5 matches).
    final convertedSummaryBalance =
        widget.money.convert(widget.summary.balance, widget.summary.currency);
    final displayBalance = _selectedIndex == 5
        ? convertedSummaryBalance
        : (selectedPoint?.balance ?? convertedSummaryBalance);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Balance',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      'Amount as of $dateStr',
                      key: ValueKey(dateStr),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              // Calendar accent chip
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: isDark ? 0.20 : 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Animated balance display
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              CurrencyFormatter.format(displayBalance, widget.money.displayCurrency),
              key: ValueKey(displayBalance.toStringAsFixed(2)),
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Interactive chart with GestureDetector
        SizedBox(
          height: 210,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chartSize = Size(constraints.maxWidth, 210);
              return GestureDetector(
                onTapUp: (details) =>
                    _onChartTap(details.localPosition, chartSize, chartPoints),
                onPanUpdate: (details) =>
                    _onChartTap(details.localPosition, chartSize, chartPoints),
                behavior: HitTestBehavior.opaque,
                child: FadeTransition(
                  opacity: _tooltipFade,
                  child: CustomPaint(
                    painter: _VectorAreaChartPainter(
                      color: AppColors.primary,
                      isDark: isDark,
                      chartPoints: chartPoints,
                      selectedIndex: _selectedIndex,
                      currency: widget.money.displayCurrency,
                    ),
                    size: chartSize,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// Real-data interactive chart painter
class _VectorAreaChartPainter extends CustomPainter {
  final Color color;
  final bool isDark;
  final List<_ChartPoint> chartPoints;
  final int? selectedIndex;
  final String currency;

  _VectorAreaChartPainter({
    required this.color,
    required this.isDark,
    required this.chartPoints,
    required this.selectedIndex,
    required this.currency,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = chartPoints.length;
    if (n < 2) return;

    const labelAreaHeight = 28.0;
    const topPad = 14.0;
    final chartH = size.height - labelAreaHeight - topPad;

    // ── 1. Normalize balances ──
    final values = chartPoints.map((p) => p.balance).toList();
    final maxVal = values.reduce(math.max);
    final minVal = values.reduce(math.min);
    final range = (maxVal - minVal).abs();

    // All-zero guard: show flat midline
    List<double> normalized;
    if (range < 1) {
      normalized = List.filled(n, 0.5);
    } else {
      normalized = values.map((v) => (v - minVal) / range).toList();
    }

    // ── 2. Grid Lines ──
    final gridPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.05)
          : const Color(0xFFEBEBEB)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = topPad + i * (chartH / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // ── 3. Compute pixel positions ──
    final pts = <Offset>[];
    for (int i = 0; i < n; i++) {
      final x = (i / (n - 1)) * size.width;
      final y = topPad + (1.0 - normalized[i]) * chartH;
      pts.add(Offset(x, y));
    }

    // ── 4. Build smooth path (catmull-rom-like cubic) ──
    final path = Path();
    final fillPath = Path();
    path.moveTo(pts[0].dx, pts[0].dy);
    fillPath.moveTo(pts[0].dx, topPad + chartH);
    fillPath.lineTo(pts[0].dx, pts[0].dy);

    for (int i = 0; i < n - 1; i++) {
      final cp1 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i].dy);
      final cp2 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i + 1].dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pts[i + 1].dx, pts[i + 1].dy);
      fillPath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pts[i + 1].dx, pts[i + 1].dy);
    }

    fillPath.lineTo(size.width, topPad + chartH);
    fillPath.close();

    // ── 5. Fill gradient ──
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
    );
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = gradient.createShader(Rect.fromLTWH(0, topPad, size.width, chartH))
        ..style = PaintingStyle.fill,
    );

    // ── 6. Main stroke ──
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // ── 7. Unselected dots (subtle) ──
    for (int i = 0; i < n; i++) {
      if (i == selectedIndex) continue;
      canvas.drawCircle(
        pts[i],
        3.0,
        Paint()..color = color.withValues(alpha: 0.35),
      );
    }

    // ── 8. Selected point highlight + tooltip ──
    if (selectedIndex != null && selectedIndex! < n) {
      final si = selectedIndex!;
      final sx = pts[si].dx;
      final sy = pts[si].dy;

      // Vertical guide line
      canvas.drawLine(
        Offset(sx, topPad),
        Offset(sx, topPad + chartH),
        Paint()
          ..color = const Color(0xFFD5C8FF)
          ..strokeWidth = 1.5,
      );

      // Outer glow ring
      canvas.drawCircle(
        Offset(sx, sy),
        10.0,
        Paint()..color = color.withValues(alpha: 0.15),
      );
      // Filled dot
      canvas.drawCircle(Offset(sx, sy), 6.0, Paint()..color = color);
      // White inner dot
      canvas.drawCircle(Offset(sx, sy), 3.0, Paint()..color = Colors.white);

      // ── Tooltip box (matches reference design) ──
      final pt = chartPoints[si];
      final balStr = CurrencyFormatter.format(pt.balance, currency);
      const monthLabels = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final monthStr = '${monthLabels[pt.month.month - 1]} ${pt.month.year}';

      // Measure texts first so box width auto-fits content
      final tp1 = TextPainter(
        text: TextSpan(
          text: balStr,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: -0.3,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 200);

      final tp2 = TextPainter(
        text: TextSpan(
          text: monthStr,
          style: TextStyle(
            color: isDark ? Colors.grey[500] : const Color(0xFF9E9E9E),
            fontWeight: FontWeight.w400,
            fontSize: 11,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 200);

      const hPad = 16.0; // horizontal inner padding
      const vPad = 12.0; // vertical inner padding
      const gap  =  5.0; // gap between text lines
      const tipW = 8.0;  // triangle width
      const tipH = 8.0;  // triangle half-height
      const r    = 14.0; // corner radius — matches image

      final textW = tp1.width > tp2.width ? tp1.width : tp2.width;
      final boxW  = textW + hPad * 2;
      final boxH  = vPad + tp1.height + gap + tp2.height + vPad;

      // Tooltip sits above the dot, slightly to the right
      // Triangle tail points LEFT (bottom-left of card) — matches image
      final bool placeRight = sx + tipW + boxW + 4 <= size.width;

      double boxLeft;
      if (placeRight) {
        boxLeft = sx + tipW + 4;
      } else {
        boxLeft = sx - tipW - 4 - boxW;
      }

      // Vertically: center on dot, clamp inside chart
      double boxTop = (sy - boxH / 2).clamp(topPad, topPad + chartH - boxH);

      final tooltipRect  = Rect.fromLTWH(boxLeft, boxTop, boxW, boxH);
      final tooltipRRect = RRect.fromRectAndRadius(tooltipRect, const Radius.circular(r));

      // ── Drop shadow ──
      canvas.drawRRect(
        tooltipRRect.shift(const Offset(0, 3)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.09)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );

      // ── White (or dark) card fill ──
      canvas.drawRRect(
        tooltipRRect,
        Paint()..color = isDark ? const Color(0xFF2C2C2E) : Colors.white,
      );

      // ── Pointer triangle — centered vertically on card ──
      final tipMidY = boxTop + boxH / 2;
      final tipPath = Path();
      if (placeRight) {
        // Triangle points LEFT from left edge of box
        tipPath
          ..moveTo(boxLeft, tipMidY - tipH)
          ..lineTo(boxLeft - tipW, tipMidY)
          ..lineTo(boxLeft, tipMidY + tipH)
          ..close();
      } else {
        // Triangle points RIGHT from right edge
        tipPath
          ..moveTo(boxLeft + boxW, tipMidY - tipH)
          ..lineTo(boxLeft + boxW + tipW, tipMidY)
          ..lineTo(boxLeft + boxW, tipMidY + tipH)
          ..close();
      }
      canvas.drawPath(
        tipPath,
        Paint()..color = isDark ? const Color(0xFF2C2C2E) : Colors.white,
      );

      // ── Text ──
      final textX = boxLeft + hPad;
      tp1.paint(canvas, Offset(textX, boxTop + vPad));
      tp2.paint(canvas, Offset(textX, boxTop + vPad + tp1.height + gap));

    }


    // ── 9. X-axis month labels ──
    final labelStyle = TextStyle(
      color: isDark ? AppColors.darkTextTertiary : const Color(0xFF888888),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );
    for (int i = 0; i < n; i++) {
      final tp = TextPainter(
        text: TextSpan(text: chartPoints[i].label, style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final lx = pts[i].dx;
      final dx = (lx - tp.width / 2).clamp(0.0, size.width - tp.width);
      // Highlight selected label
      if (i == selectedIndex) {
        final hlPainter = TextPainter(
          text: TextSpan(
            text: chartPoints[i].label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        hlPainter.paint(canvas, Offset(dx, topPad + chartH + 10));
      } else {
        tp.paint(canvas, Offset(dx, topPad + chartH + 10));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VectorAreaChartPainter old) =>
      old.selectedIndex != selectedIndex ||
      old.isDark != isDark ||
      old.chartPoints != chartPoints;
}

class _BalanceSectionSkeleton extends StatelessWidget {
  final String? error;
  const _BalanceSectionSkeleton({this.error});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: error != null
          ? Center(child: Text(error!, textAlign: TextAlign.center))
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

// ──────────────────────────────────────────────────────────
// 3. REMAINING WIDGETS (Unchanged)
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
        const SizedBox(width: 12),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isIncome ? AppColors.income : AppColors.expense;
    final bgColor = isIncome ? AppColors.incomeBg : AppColors.expenseBg;
    final sign = isIncome ? '+' : '-';
    final icon = isIncome ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFF1F1F1),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$sign${CurrencyFormatter.format(amount, currency)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '$count ${isIncome ? 'income' : 'expense'}${count == 1 ? '' : 's'} added',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
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
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkSurfaceAlt
                  : AppColors.lightSurfaceAlt,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkSurfaceAlt
                  : AppColors.lightSurfaceAlt,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown only while the account is inside its 7-day deletion grace window
/// (the user deleted the account, then signed back in). One tap restores it.
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.expense.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.expense.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.expense, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Account scheduled for deletion on '
                '${deleteOn.day}/${deleteOn.month}/${deleteOn.year}.',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35),
              ),
            ),
            TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final userId = ref.read(currentUserIdProvider);
                  await ref.read(profileRepositoryProvider).cancelDeletion(userId);
                  await ref.read(profileControllerProvider.notifier).refresh();
                  messenger.showSnackBar(const SnackBar(
                    content: Text('Account restored ✓'),
                    backgroundColor: AppColors.income,
                  ));
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
                  );
                }
              },
              child: const Text('Restore', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal per-wallet balance cards. Renders nothing until the user has
/// created wallets (or has unassigned activity), so the dashboard is unchanged
/// for users who don't use the feature.
class _WalletBalancesSection extends ConsumerWidget {
  const _WalletBalancesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final balances = ref.watch(walletBalancesProvider).asData?.value ?? const <WalletBalance>[];
    final hasRealWallets = balances.any((b) => b.wallet.id != 0);
    if (!hasRealWallets) return const SizedBox.shrink();

    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wallets',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textPrimary),
                    ),
                    Text(
                      'Balance per account',
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WalletsScreen()),
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'Manage',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── Net worth strip (assets − liabilities) ──
          Consumer(builder: (context, ref, _) {
            final nw = ref.watch(netWorthProvider).asData?.value;
            if (nw == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFF1F1F1)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Net worth', style: TextStyle(fontSize: 11, color: textSecondary)),
                          const SizedBox(height: 2),
                          Text(
                            CurrencyFormatter.formatCompact(nw.netWorth, nw.currency),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: nw.netWorth < 0 ? AppColors.expense : textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _NetWorthStat(label: 'Assets', value: CurrencyFormatter.formatCompact(nw.assets, nw.currency), color: AppColors.income),
                    const SizedBox(width: 16),
                    _NetWorthStat(label: 'Liabilities', value: CurrencyFormatter.formatCompact(nw.liabilities, nw.currency), color: AppColors.expense),
                  ],
                ),
              ),
            );
          }),
          SizedBox(
            height: 96,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: balances.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final b = balances[i];
                return Container(
                  width: 170,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFF1F1F1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(b.wallet.icon, size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              b.wallet.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        CurrencyFormatter.formatCompact(b.balance, b.displayCurrency),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
      ],
    );
  }
}

/// Weekly recap tile (mirrors the scheduled push digest) + a short list of
/// templated spending insights. Both come from the analytics endpoints and
/// fail quietly (render nothing) so a hiccup never breaks the dashboard.
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

    // Nothing to show yet (still loading first time, or genuinely empty).
    final hasDigest = digest != null && digest.transactionCount > 0;
    if (insights.isEmpty && !hasDigest) return const SizedBox.shrink();

    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Insights',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textPrimary),
        ),
        Text(
          'Smart tips from your spending',
          style: TextStyle(fontSize: 11, color: textSecondary),
        ),
        const SizedBox(height: 14),

        // Weekly recap tile
        if (hasDigest) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.insights_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'This week',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RecapStat(
                        label: 'Spent',
                        value: money.formatCompact(digest.expense, digest.currency),
                      ),
                    ),
                    Expanded(
                      child: _RecapStat(
                        label: 'Earned',
                        value: money.formatCompact(digest.income, digest.currency),
                      ),
                    ),
                    Expanded(
                      child: _RecapStat(
                        label: 'Saved',
                        value: '${digest.savingsRate.round()}%',
                      ),
                    ),
                  ],
                ),
                if (digest.topCategoryName != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Top category: ${digest.topCategoryName} · ${money.formatCompact(digest.topCategoryAmount, digest.currency)}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Insight cards
        for (final insight in insights.take(3)) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFF1F1F1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _toneColor(insight.tone).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_toneIcon(insight.tone), color: _toneColor(insight.tone), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insight.title,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        insight.body,
                        style: TextStyle(fontSize: 12, height: 1.35, color: textSecondary),
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
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
        ),
      ],
    );
  }
}

class _TopSpendingSection extends StatelessWidget {
  final List<TransactionModel> transactions;
  final MoneyFormatter money;

  const _TopSpendingSection({required this.transactions, required this.money});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Convert each transaction into the display currency before aggregating so
    // mixed-currency spending is compared on a level playing field.
    final Map<String, double> catMap = {};
    for (final tx in transactions) {
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Spending Categories',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                Text(
                  'Highest categories as per ${DateFormat('MMM dd, yyyy').format(DateTime.now())}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (top.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(child: Text('No spending data yet')),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : const Color(0xFFF1F1F1),
              ),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              e.key,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Column(
                              children: [
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: pct.clamp(0.0, 1.0),
                                    minHeight: 7,
                                    backgroundColor: isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder,
                                    valueColor: AlwaysStoppedAnimation(color),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            CurrencyFormatter.formatCompact(e.value, money.displayCurrency),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              pctStr,
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (i < top.length - 1)
                      Divider(
                        height: 1,
                        color: isDark ? AppColors.darkBorder : const Color(0xFFF1F1F1),
                        indent: 16,
                        endIndent: 16,
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Budget Overview',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  Text(
                    'Budget Overview by Category',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onManage,
                child: Row(
                  children: [
                    Text(
                      'Manage',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (state.isLoading && state.items.isEmpty)
          const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'No budgets set yet. Tap Manage to create one.',
                style: TextStyle(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 200,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: state.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pct = (budget.percentage / 100).clamp(0.0, 1.0);
    final remaining = (100 - budget.percentage).clamp(0, 100);
    final color = budget.isExceeded
        ? AppColors.expense
        : (budget.isWarning ? AppColors.warning : AppColors.primary);

    return Container(
      width: 158,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFF1F1F1),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            budget.category,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 90,
            height: 90,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 9,
                    backgroundColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    valueColor: AlwaysStoppedAnimation(color),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$remaining%',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    Text(
                      'remaining',
                      style: TextStyle(
                        fontSize: 9,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${money.formatCompact(budget.remaining, budget.currency)} remaining',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${money.formatCompact(budget.spent, budget.currency)} spent',
            style: const TextStyle(fontSize: 11, color: AppColors.expense),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Savings Goals',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  Text(
                    'Savings Goals Categorization',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onManage,
                child: Row(
                  children: [
                    const Text(
                      'Manage',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (state.isLoading && state.items.isEmpty)
          const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (activeGoals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'No savings goals yet. Tap Manage to add one.',
                style: TextStyle(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 200,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: activeGoals.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pct = (goal.progressPercentage / 100).clamp(0.0, 1.0);
    final remaining = (100 - goal.progressPercentage).clamp(0, 100).round();

    return Container(
      width: 158,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFF1F1F1),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            goal.name,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 90,
            height: 90,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 9,
                    backgroundColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    valueColor: const AlwaysStoppedAnimation(AppColors.income),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$remaining%',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    Text(
                      'remaining',
                      style: TextStyle(
                        fontSize: 9,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${money.formatCompact(goal.targetAmount - goal.currentAmount, goal.currency)} remaining',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${money.formatCompact(goal.currentAmount, goal.currency)} saved',
            style: const TextStyle(fontSize: 11, color: AppColors.income),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _RecentTransactionsHeader extends StatelessWidget {
  final VoidCallback onViewAll;

  const _RecentTransactionsHeader({required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Transactions',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Your Recent Earnings & Spendings',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: onViewAll,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'View All',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppColors.primary,
                  size: 13,
                ),
              ],
            ),
          ),
        ),
      ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExpense = transaction.amount < 0;
    final formattedDate = DateFormatter.relative(transaction.createdAt);

    final amountColor = isExpense ? AppColors.expense : AppColors.income;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Per-category coloured icon (theme-aware) — makes the list
                // scannable instead of a wall of identical purple chips.
                CategoryIcon(category: transaction.category, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      money.format(
                        transaction.amount,
                        transaction.currency,
                        showSign: true,
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: amountColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isExpense ? Icons.south_east_rounded : Icons.north_east_rounded,
                          color: amountColor,
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          isExpense ? 'Expense' : 'Income',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: amountColor.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}