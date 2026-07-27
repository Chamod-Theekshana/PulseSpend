import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../../shared/widgets/app_loader.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/analytics_model.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../providers/transactions_provider.dart';
import '../../budgets/screens/budgets_screen.dart';
import '../../goals/screens/goals_screen.dart';
import '../../transactions/screens/transactions_screen.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final period = ref.watch(analyticsPeriodProvider);
    final analyticsAsync = ref.watch(analyticsSummaryProvider(period));

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Analytics',
          style: TextStyle(
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          // Manual recovery path: re-pull every analytics source (the socket
          // usually keeps these live, but a missed event shouldn't strand them).
          ref.invalidate(analyticsSummaryProvider);
          ref.invalidate(dailyTotalsProvider);
          ref.invalidate(insightsProvider);
          await ref.read(analyticsSummaryProvider(period).future);
        },
        child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _PeriodTabBar(
              selectedPeriod: period,
              onSelect: (p) => ref.read(analyticsPeriodProvider.notifier).setPeriod(p),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            sliver: SliverToBoxAdapter(
              child: analyticsAsync.when(
                data: (data) => Column(
                  children: [
                    _IncomeExpenseCard(trend: data.trend, isDark: isDark, currency: data.currency, period: period),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _SavingsRateCard(
                            savingsRate: data.savingsRate,
                            income: data.trend.totalIncome,
                            expense: data.trend.totalExpense,
                            currency: data.currency,
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: _CategorySpendingCard(categories: data.topCategories, isDark: isDark, currency: data.currency)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SpendingHeatmapCard(isDark: isDark),
                    const SizedBox(height: 100), // Padding for bottom nav
                  ],
                ),
                loading: () => const Center(child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: AppLoader(size: 40),
                )),
                error: (e, _) => Center(child: Text(DioClient.toApiException(e).localizedMessage(context))),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _PeriodTabBar extends StatelessWidget {
  final String selectedPeriod;
  final Function(String) onSelect;

  const _PeriodTabBar({required this.selectedPeriod, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final periods = ['day', 'week', 'month', 'year'];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: periods.map((p) {
          final isSelected = selectedPeriod == p;
          return GestureDetector(
            onTap: () => onSelect(p),
            child: Column(
              children: [
                Text(
                  p.toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected
                        ? (isDark ? Colors.white : AppColors.primary)
                        : (isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 3,
                  width: 16,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _IncomeExpenseCard extends ConsumerStatefulWidget {
  final IncomeExpenseTrend trend;
  final bool isDark;
  final String currency;
  final String period;

  const _IncomeExpenseCard({required this.trend, required this.isDark, required this.currency, required this.period});

  @override
  ConsumerState<_IncomeExpenseCard> createState() => _IncomeExpenseCardState();
}

class _IncomeExpenseCardState extends ConsumerState<_IncomeExpenseCard> {
  final GlobalKey _captureKey = GlobalKey();
  bool _capturing = false; // hides the ⋮ while screenshotting
  bool _busy = false;

  String _formatAmount(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }

  String _getPeriodLabel() {
    switch (widget.period) {
      case 'day': return 'Today';
      case 'week': return 'This Week';
      case 'month': return 'This Month';
      case 'year': return 'This Year';
      default: return 'Selected Period';
    }
  }

  /// The date window the chart currently shows (period start → now).
  (DateTime, DateTime) _periodRange() {
    final now = DateTime.now();
    switch (widget.period) {
      case 'day':
        return (DateTime(now.year, now.month, now.day), now);
      case 'week':
        final start = now.subtract(Duration(days: now.weekday - 1));
        return (DateTime(start.year, start.month, start.day), now);
      case 'year':
        return (DateTime(now.year, 1, 1), now);
      case 'month':
      default:
        return (DateTime(now.year, now.month, 1), now);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.expense),
    );
  }

  Future<void> _openMenu() async {
    final chartType = ref.read(analyticsChartTypeProvider);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.isDark ? AppColors.darkBorder : AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.file_download_outlined, color: AppColors.primary),
              title: const Text('Export CSV'),
              subtitle: Text('${_getPeriodLabel()} transactions'),
              onTap: () {
                Navigator.pop(ctx);
                _exportCsv();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded, color: AppColors.primary),
              title: const Text('Share as image'),
              onTap: () {
                Navigator.pop(ctx);
                _shareImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
              title: const Text('View transactions'),
              onTap: () {
                Navigator.pop(ctx);
                _viewTransactions();
              },
            ),
            const Divider(height: 8),
            ListTile(
              leading: const Icon(Icons.show_chart_rounded),
              title: const Text('Line chart'),
              trailing: chartType == AnalyticsChartType.line
                  ? const Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                ref.read(analyticsChartTypeProvider.notifier).set(AnalyticsChartType.line);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded),
              title: const Text('Bar chart'),
              trailing: chartType == AnalyticsChartType.bar
                  ? const Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                ref.read(analyticsChartTypeProvider.notifier).set(AnalyticsChartType.bar);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final (from, to) = _periodRange();
      final userId = ref.read(currentUserIdProvider);
      final csv = await ref.read(transactionRepositoryProvider).exportCsv(
            userId: userId,
            filters: TransactionFilters(from: from, to: to),
          );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/pulsespend_${widget.period}_transactions.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)], text: 'My ${widget.period} transactions');
    } catch (e) {
      _showError(DioClient.toApiException(e).localizedMessage(context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareImage() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _capturing = true;
    });
    try {
      // Let the frame without the ⋮ button paint before we snapshot.
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/pulsespend_income_vs_expenses.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: 'My income vs expenses');
    } catch (e) {
      _showError(DioClient.toApiException(e).localizedMessage(context));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _capturing = false;
        });
      }
    }
  }

  void _viewTransactions() {
    final (from, to) = _periodRange();
    ref.read(transactionsControllerProvider.notifier).setFilters(
          TransactionFilters(from: from, to: to),
        );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TransactionsScreen()),
    );
  }

  /// Grouped bars (income + expense per label) — the alternative to the line
  /// chart, toggled from the ⋮ menu. Axes mirror the line chart's config.
  Widget _buildBarChart(double maxY, Color textColor, Color secondaryTextColor) {
    final trend = widget.trend;
    final isDark = widget.isDark;
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY * 1.1,
        minY: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY > 0 ? maxY / 4 : 25,
          getDrawingHorizontalLine: (value) => FlLine(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.15),
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= trend.labels.length) return const SizedBox.shrink();
                final isHighlighted = index == trend.labels.length - 1;
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    trend.labels[index],
                    style: TextStyle(
                      color: isHighlighted ? textColor : secondaryTextColor,
                      fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY > 0 ? maxY / 4 : 25,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  _formatAmount(value),
                  style: TextStyle(color: secondaryTextColor, fontSize: 11, fontWeight: FontWeight.w500),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(trend.labels.length, (i) {
          final income = i < trend.incomeData.length ? trend.incomeData[i] : 0.0;
          final expense = i < trend.expenseData.length ? trend.expenseData[i] : 0.0;
          return BarChartGroupData(
            x: i,
            barsSpace: 3,
            barRods: [
              BarChartRodData(toY: income, color: AppColors.income, width: 6, borderRadius: BorderRadius.circular(3)),
              BarChartRodData(toY: expense, color: AppColors.expense, width: 6, borderRadius: BorderRadius.circular(3)),
            ],
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trend = widget.trend;
    final isDark = widget.isDark;
    final currency = widget.currency;
    final chartType = ref.watch(analyticsChartTypeProvider);
    final cardColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    // Find max value to set maxY appropriately
    double maxY = 0;
    for (var val in trend.incomeData) { if (val > maxY) maxY = val; }
    for (var val in trend.expenseData) { if (val > maxY) maxY = val; }
    if (maxY == 0) maxY = 100; // default if no data

    return RepaintBoundary(
      key: _captureKey,
      child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Income vs Expenses',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getPeriodLabel(),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: secondaryTextColor),
                  ),
                ],
              ),
              if (!_capturing)
                _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: AppLoader(size: 18),
                      )
                    : InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _openMenu,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.more_vert, color: secondaryTextColor, size: 20),
                        ),
                      ),
            ],
          ),
          const SizedBox(height: 30),
          SizedBox(
            height: 180,
            child: chartType == AnalyticsChartType.line
                ? LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 4 : 25,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.15),
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= trend.labels.length) return const SizedBox.shrink();
                        // Highlight Friday ('F') or last item for visual flair
                        final isHighlighted = index == trend.labels.length - 1;
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            trend.labels[index],
                            style: TextStyle(
                              color: isHighlighted ? textColor : secondaryTextColor,
                              fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: maxY > 0 ? maxY / 4 : 25,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Text(
                          _formatAmount(value),
                          style: TextStyle(color: secondaryTextColor, fontSize: 11, fontWeight: FontWeight.w500),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: trend.labels.length.toDouble() - 1,
                minY: 0,
                maxY: maxY * 1.1, // 10% padding on top
                lineBarsData: [
                  LineChartBarData(
                    spots: trend.incomeData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                    isCurved: true,
                    color: AppColors.income,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, barData) => spot.x == barData.spots.last.x,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 5,
                          color: Colors.white,
                          strokeWidth: 3,
                          strokeColor: AppColors.income,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(show: true, color: AppColors.income.withOpacity(0.1)),
                  ),
                  LineChartBarData(
                    spots: trend.expenseData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                    isCurved: true,
                    color: AppColors.expense,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, barData) => spot.x == barData.spots.last.x,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 5,
                          color: Colors.white,
                          strokeWidth: 3,
                          strokeColor: AppColors.expense,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(show: true, color: AppColors.expense.withOpacity(0.1)),
                  ),
                ],
              ),
            )
                : _buildBarChart(maxY, textColor, secondaryTextColor),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _LegendItem(
                  icon: Icons.trending_up,
                  label: 'Income',
                  amount: trend.totalIncome,
                  currency: currency,
                  trend: trend.incomeTrend,
                  isDark: isDark,
                  color: AppColors.income,
                ),
              ),
              Expanded(
                child: _LegendItem(
                  icon: Icons.trending_down,
                  label: 'Expenses',
                  amount: trend.totalExpense,
                  currency: currency,
                  trend: trend.expenseTrend,
                  isDark: isDark,
                  color: AppColors.expense,
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final double amount;
  final String currency;
  final double trend;
  final bool isDark;
  final Color color;

  const _LegendItem({
    required this.icon,
    required this.label,
    required this.amount,
    required this.currency,
    required this.trend,
    required this.isDark,
    required this.color,
  });

  String _formatAmount(double amt) {
    if (amt >= 1000000) {
      return '${(amt / 1000000).toStringAsFixed(1)}M';
    } else if (amt >= 1000) {
      return '${(amt / 1000).toStringAsFixed(1)}K';
    }
    return amt.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final trendColor = trend >= 0 ? AppColors.income : AppColors.expense;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: secondaryTextColor, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Row(
              children: [
                Text('${_formatAmount(amount)} $currency', style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(trend >= 0 ? Icons.arrow_upward : Icons.arrow_downward, color: trendColor, size: 10),
                Text('${trend.abs().toStringAsFixed(1)}%', style: TextStyle(color: trendColor, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Shared "screenshot this card and share it" behaviour for the analytics
/// cards. The host wraps its body in `RepaintBoundary(key: shareKey)` and hides
/// its ⋮ while [capturing] so it isn't in the image.
mixin _ShareableCard<T extends StatefulWidget> on State<T> {
  final GlobalKey shareKey = GlobalKey();
  bool capturing = false;
  bool busy = false;

  Future<void> shareCardImage(String text) async {
    if (busy) return;
    setState(() {
      busy = true;
      capturing = true;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/pulsespend_analytics.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context)), backgroundColor: AppColors.expense),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          capturing = false;
        });
      }
    }
  }
}

/// The ⋮ button used in the analytics card headers — hidden while screenshotting,
/// a spinner while an action runs, otherwise a tappable more-vert icon.
class _CardMenuButton extends StatelessWidget {
  final bool capturing;
  final bool busy;
  final VoidCallback onTap;
  final Color color;

  const _CardMenuButton({
    required this.capturing,
    required this.busy,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (capturing) return const SizedBox.shrink();
    if (busy) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: AppLoader(size: 18),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(Icons.more_vert, color: color, size: 18),
      ),
    );
  }
}

class _SavingsRateCard extends ConsumerStatefulWidget {
  final double savingsRate;
  final double income;
  final double expense;
  final String currency;
  final bool isDark;

  const _SavingsRateCard({
    required this.savingsRate,
    required this.income,
    required this.expense,
    required this.currency,
    required this.isDark,
  });

  @override
  ConsumerState<_SavingsRateCard> createState() => _SavingsRateCardState();
}

class _SavingsRateCardState extends ConsumerState<_SavingsRateCard> with _ShareableCard {
  String _money(double v) => '${v.toStringAsFixed(0)} ${widget.currency}';

  Future<void> _openMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            _SheetGrip(isDark: widget.isDark),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: AppColors.primary),
              title: const Text('What is savings rate?'),
              onTap: () {
                Navigator.pop(ctx);
                _explain();
              },
            ),
            ListTile(
              leading: const Icon(Icons.savings_outlined, color: AppColors.primary),
              title: const Text('Savings goals'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GoalsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.lightbulb_outline_rounded, color: AppColors.primary),
              title: const Text('Tips to save more'),
              onTap: () {
                Navigator.pop(ctx);
                _showTips();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded, color: AppColors.primary),
              title: const Text('Share as image'),
              onTap: () {
                Navigator.pop(ctx);
                shareCardImage('My savings rate: ${widget.savingsRate.toStringAsFixed(1)}%');
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _explain() {
    final net = widget.income - widget.expense;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Savings rate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The share of your income you kept instead of spending:'),
            const SizedBox(height: 12),
            const Text(
              'Savings rate = (Income − Expenses) ÷ Income',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text('Income: ${_money(widget.income)}'),
            Text('Expenses: ${_money(widget.expense)}'),
            Text('Kept: ${_money(net)}'),
            const SizedBox(height: 8),
            Text(
              'That\'s ${widget.savingsRate.toStringAsFixed(1)}% this period.',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
        ],
      ),
    );
  }

  void _showTips() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _InsightsSheet(isDark: widget.isDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    final savingsRate = widget.savingsRate;
    final isDark = widget.isDark;
    final cardColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return RepaintBoundary(
      key: shareKey,
      child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Savings Rate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor),
                ),
              ),
              _CardMenuButton(capturing: capturing, busy: busy, onTap: _openMenu, color: secondaryTextColor),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              height: 100,
              width: 100,
              child: Stack(
                children: [
                  Center(
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        value: savingsRate > 0 ? savingsRate / 100 : 0,
                        strokeWidth: 10,
                        backgroundColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF0F2F8),
                        valueColor: AlwaysStoppedAnimation<Color>(savingsRate >= 20 ? AppColors.income : (savingsRate > 0 ? AppColors.primary : AppColors.expense)),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${savingsRate.toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _CategorySpendingCard extends ConsumerStatefulWidget {
  final List<CategorySpending> categories;
  final bool isDark;
  final String currency;

  const _CategorySpendingCard({required this.categories, required this.isDark, required this.currency});

  @override
  ConsumerState<_CategorySpendingCard> createState() => _CategorySpendingCardState();
}

class _CategorySpendingCardState extends ConsumerState<_CategorySpendingCard> with _ShareableCard {
  Future<void> _openMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            _SheetGrip(isDark: widget.isDark),
            ListTile(
              leading: const Icon(Icons.list_alt_rounded, color: AppColors.primary),
              title: const Text('View all categories'),
              onTap: () {
                Navigator.pop(ctx);
                _viewAll();
              },
            ),
            ListTile(
              leading: const Icon(Icons.pie_chart_outline_rounded, color: AppColors.primary),
              title: const Text('Set a budget'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BudgetsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
              title: const Text('View transactions by category'),
              onTap: () {
                Navigator.pop(ctx);
                _pickCategoryForTransactions();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded, color: AppColors.primary),
              title: const Text('Share as image'),
              onTap: () {
                Navigator.pop(ctx);
                shareCardImage('My top spending categories');
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _viewAll() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CategoryListSheet(
        title: 'All categories',
        categories: widget.categories,
        currency: widget.currency,
        isDark: widget.isDark,
      ),
    );
  }

  void _pickCategoryForTransactions() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CategoryListSheet(
        title: 'View transactions in…',
        categories: widget.categories,
        currency: widget.currency,
        isDark: widget.isDark,
        onTap: (name) {
          Navigator.pop(ctx);
          ref.read(transactionsControllerProvider.notifier).setFilters(
                TransactionFilters(category: name),
              );
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TransactionsScreen()),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories.take(5).toList();
    final isDark = widget.isDark;
    final currency = widget.currency;
    final cardColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return RepaintBoundary(
      key: shareKey,
      child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Top Categories',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor),
                ),
              ),
              _CardMenuButton(capturing: capturing, busy: busy, onTap: _openMenu, color: secondaryTextColor),
            ],
          ),
          const SizedBox(height: 24),
          if (categories.isEmpty)
            const SizedBox(
              height: 100,
              child: Center(
                child: Text('No spending data', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            )
          else ...[
            SizedBox(
              height: 100,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 100,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => isDark ? const Color(0xFF333333) : Colors.white,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${categories[group.x.toInt()].name}\n${categories[group.x.toInt()].amount.toStringAsFixed(0)} $currency',
                          TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 10),
                        );
                      },
                    ),
                  ),
                  titlesData: const FlTitlesData(show: false),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: categories.asMap().entries.map((e) {
                    final color = AppColors.categoryColor(e.value.name);
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.percentage,
                          color: color,
                          width: 8,
                          borderRadius: BorderRadius.circular(4),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: 100,
                            color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF0F2F8),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
                spacing: 12,
                runSpacing: 8,
                children: categories.map((cat) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.categoryColor(cat.name),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        cat.name,
                        style: TextStyle(color: secondaryTextColor, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
        ],
      ),
      ),
    );
  }
}

/// Small drag handle shown at the top of the analytics bottom sheets.
class _SheetGrip extends StatelessWidget {
  final bool isDark;
  const _SheetGrip({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Lists spending categories (colour dot + name + amount + %). When [onTap] is
/// provided each row is tappable (used to filter transactions by category).
class _CategoryListSheet extends StatelessWidget {
  final String title;
  final List<CategorySpending> categories;
  final String currency;
  final bool isDark;
  final void Function(String name)? onTap;

  const _CategoryListSheet({
    required this.title,
    required this.categories,
    required this.currency,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _SheetGrip(isDark: isDark)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textColor)),
            const SizedBox(height: 12),
            if (categories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('No spending data yet', style: TextStyle(color: secondaryTextColor)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                  itemBuilder: (context, i) {
                    final c = categories[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onTap == null ? null : () => onTap!(c.name),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: AppColors.categoryColor(c.name),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                c.name,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${c.amount.toStringAsFixed(0)} $currency',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: textColor),
                            ),
                            const SizedBox(width: 8),
                            Text('${c.percentage.round()}%', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                            if (onTap != null) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right_rounded, size: 18, color: secondaryTextColor),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet of natural-language saving tips (reuses insightsProvider).
class _InsightsSheet extends ConsumerWidget {
  final bool isDark;
  const _InsightsSheet({required this.isDark});

  IconData _toneIcon(String tone) => switch (tone) {
        'positive' => Icons.trending_up_rounded,
        'warning' => Icons.warning_amber_rounded,
        _ => Icons.lightbulb_outline_rounded,
      };

  Color _toneColor(String tone) => switch (tone) {
        'positive' => AppColors.income,
        'warning' => AppColors.warning,
        _ => AppColors.primary,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final insightsAsync = ref.watch(insightsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _SheetGrip(isDark: isDark)),
            const SizedBox(height: 4),
            Text('Tips to save more', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textColor)),
            const SizedBox(height: 12),
            insightsAsync.when(
              data: (insights) => insights.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Add a few transactions to unlock tips.', style: TextStyle(color: secondaryTextColor)),
                    )
                  : Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final ins in insights)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(_toneIcon(ins.tone), size: 18, color: _toneColor(ins.tone)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(ins.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: textColor)),
                                        const SizedBox(height: 2),
                                        Text(ins.body, style: TextStyle(fontSize: 12.5, height: 1.35, color: secondaryTextColor)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: AppLoader(size: 40)),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text("Couldn't load tips.", style: TextStyle(color: secondaryTextColor)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Month-grid spending heatmap: each day tinted by how much was spent that day.
/// Tap a day to see its transactions; ⋮ offers share-as-image + month view.
class _SpendingHeatmapCard extends ConsumerStatefulWidget {
  final bool isDark;
  const _SpendingHeatmapCard({required this.isDark});

  @override
  ConsumerState<_SpendingHeatmapCard> createState() => _SpendingHeatmapCardState();
}

class _SpendingHeatmapCardState extends ConsumerState<_SpendingHeatmapCard> with _ShareableCard {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  void _openRange(DateTime from, DateTime to) {
    ref.read(transactionsControllerProvider.notifier).setFilters(
          TransactionFilters(from: from, to: to),
        );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TransactionsScreen()),
    );
  }

  Future<void> _openMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            _SheetGrip(isDark: widget.isDark),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
              title: Text('View ${_monthNames[_month.month - 1]} transactions'),
              onTap: () {
                Navigator.pop(ctx);
                _openRange(_month, DateTime(_month.year, _month.month + 1, 0));
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded, color: AppColors.primary),
              title: const Text('Share as image'),
              onTap: () {
                Navigator.pop(ctx);
                shareCardImage('My ${_monthNames[_month.month - 1]} spending heatmap');
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cardColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final dailyAsync = ref.watch(dailyTotalsProvider((_month.year, _month.month)));
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;

    return RepaintBoundary(
      key: shareKey,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Spending Heatmap',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor),
                  ),
                ),
                _CardMenuButton(capturing: capturing, busy: busy, onTap: _openMenu, color: secondaryTextColor),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.chevron_left_rounded, color: secondaryTextColor),
                  onPressed: () => _shiftMonth(-1),
                ),
                Text(
                  '${_monthNames[_month.month - 1]} ${_month.year}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: textColor),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.chevron_right_rounded, color: secondaryTextColor),
                  // Don't navigate into the future.
                  onPressed: isCurrentMonth ? null : () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            dailyAsync.when(
              data: (days) => _buildGrid(days, secondaryTextColor),
              loading: () => const SizedBox(
                height: 160,
                child: Center(child: AppLoader(size: 40)),
              ),
              error: (e, s) => SizedBox(
                height: 80,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Couldn't load daily data",
                          style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        // Errors cache while this screen stays mounted in the
                        // tab bar — give the user a one-tap retry.
                        onPressed: () =>
                            ref.invalidate(dailyTotalsProvider((_month.year, _month.month))),
                        child: const Text('Retry', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<DailyTotal> days, Color secondaryTextColor) {
    final expenseByDay = <int, double>{
      for (final d in days)
        if (d.date.year == _month.year && d.date.month == _month.month) d.date.day: d.expense,
    };
    final maxExpense = expenseByDay.values.fold<double>(0, (a, b) => a > b ? a : b);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = _month.weekday - 1; // Monday-first grid
    final now = DateTime.now();

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 5.0;
        final cell = (constraints.maxWidth - spacing * 6) / 7;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  SizedBox(
                    width: cell,
                    child: Center(
                      child: Text(
                        const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700, color: secondaryTextColor),
                      ),
                    ),
                  ),
                  if (i < 6) const SizedBox(width: spacing),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (var i = 0; i < leadingBlanks; i++) SizedBox(width: cell, height: cell),
                for (var day = 1; day <= daysInMonth; day++)
                  _dayCell(day, cell, expenseByDay[day] ?? 0, maxExpense, now, secondaryTextColor),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Less ', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                for (final a in const [0.10, 0.30, 0.55, 0.85])
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: AppColors.expense.withValues(alpha: a),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                Text(' More', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _dayCell(
      int day, double size, double expense, double maxExpense, DateTime now, Color secondaryTextColor) {
    final isDark = widget.isDark;
    final isToday = now.year == _month.year && now.month == _month.month && now.day == day;
    final ratio = maxExpense > 0 ? (expense / maxExpense).clamp(0.0, 1.0) : 0.0;
    final color = expense > 0
        ? AppColors.expense.withValues(alpha: 0.12 + 0.73 * ratio)
        : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _openRange(
        DateTime(_month.year, _month.month, day),
        DateTime(_month.year, _month.month, day),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: isToday ? Border.all(color: AppColors.primary, width: 1.6) : null,
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: ratio > 0.55 ? Colors.white : secondaryTextColor,
            ),
          ),
        ),
      ),
    );
  }
}
