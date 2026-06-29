import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/analytics_model.dart';
import '../../../providers/analytics_provider.dart';

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
      body: CustomScrollView(
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
                        Expanded(child: _SavingsRateCard(savingsRate: data.savingsRate, isDark: isDark)),
                        const SizedBox(width: 16),
                        Expanded(child: _CategorySpendingCard(categories: data.topCategories, isDark: isDark, currency: data.currency)),
                      ],
                    ),
                    const SizedBox(height: 100), // Padding for bottom nav
                  ],
                ),
                loading: () => const Center(child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(color: AppColors.primary),
                )),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ),
        ],
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

class _IncomeExpenseCard extends StatelessWidget {
  final IncomeExpenseTrend trend;
  final bool isDark;
  final String currency;
  final String period;

  const _IncomeExpenseCard({required this.trend, required this.isDark, required this.currency, required this.period});

  String _formatAmount(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }

  String _getPeriodLabel() {
    switch (period) {
      case 'day': return 'Today';
      case 'week': return 'This Week';
      case 'month': return 'This Month';
      case 'year': return 'This Year';
      default: return 'Selected Period';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    // Find max value to set maxY appropriately
    double maxY = 0;
    for (var val in trend.incomeData) { if (val > maxY) maxY = val; }
    for (var val in trend.expenseData) { if (val > maxY) maxY = val; }
    if (maxY == 0) maxY = 100; // default if no data

    return Container(
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
              Icon(Icons.more_vert, color: secondaryTextColor, size: 20),
            ],
          ),
          const SizedBox(height: 30),
          SizedBox(
            height: 180,
            child: LineChart(
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
            ),
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

class _SavingsRateCard extends StatelessWidget {
  final double savingsRate;
  final bool isDark;

  const _SavingsRateCard({required this.savingsRate, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
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
              Text('Savings Rate', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
              Icon(Icons.more_vert, color: secondaryTextColor, size: 18),
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
    );
  }
}

class _CategorySpendingCard extends StatelessWidget {
  final List<CategorySpending> categories;
  final bool isDark;
  final String currency;

  const _CategorySpendingCard({required this.categories, required this.isDark, required this.currency});

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
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
              Text('Top Categories', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
              Icon(Icons.more_vert, color: secondaryTextColor, size: 18),
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
    );
  }
}
