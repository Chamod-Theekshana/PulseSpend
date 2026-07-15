import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/analytics_model.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/transactions_provider.dart';
import '../../transactions/screens/transactions_screen.dart';

/// Bottom-sheet month calendar tinted by daily spend. Reuses the same
/// [dailyTotalsProvider] data + tinting as the analytics Spending Heatmap;
/// tapping a day opens the Transactions screen filtered to that day (mirrors
/// the heatmap's `_openRange`).
class MonthCalendarSheet extends ConsumerStatefulWidget {
  const MonthCalendarSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MonthCalendarSheet(),
    );
  }

  @override
  ConsumerState<MonthCalendarSheet> createState() => _MonthCalendarSheetState();
}

class _MonthCalendarSheetState extends ConsumerState<MonthCalendarSheet> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  /// Close the sheet, then open Transactions filtered to [from]..[to] on the
  /// same navigator (mirrors the heatmap's _openRange).
  void _openDay(DateTime day) {
    final navigator = Navigator.of(context);
    ref.read(transactionsControllerProvider.notifier).setFilters(
          TransactionFilters(from: day, to: day),
        );
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => const TransactionsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final currency = ref.watch(profileControllerProvider).currency;
    final dailyAsync = ref.watch(dailyTotalsProvider((_month.year, _month.month)));
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: secondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('Spending calendar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textColor)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.chevron_left_rounded, color: secondary),
                onPressed: () => _shiftMonth(-1),
              ),
              Text(
                '${_monthNames[_month.month - 1]} ${_month.year}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textColor),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.chevron_right_rounded, color: secondary),
                // Don't navigate into the future.
                onPressed: isCurrentMonth ? null : () => _shiftMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          dailyAsync.when(
            data: (days) => _buildGrid(days, currency, textColor, secondary),
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            ),
            error: (e, _) => SizedBox(
              height: 100,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Couldn't load daily data",
                        style: TextStyle(color: secondary, fontSize: 12)),
                    TextButton(
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
    );
  }

  Widget _buildGrid(List<DailyTotal> days, String currency, Color textColor, Color secondary) {
    final expenseByDay = <int, double>{
      for (final d in days)
        if (d.date.year == _month.year && d.date.month == _month.month) d.date.day: d.expense,
    };
    final monthTotal = expenseByDay.values.fold<double>(0, (a, b) => a + b);
    final maxExpense = expenseByDay.values.fold<double>(0, (a, b) => a > b ? a : b);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = _month.weekday - 1; // Monday-first grid
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Spent this month: ${CurrencyFormatter.format(monthTotal, currency)}',
          style: TextStyle(fontSize: 12.5, color: secondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 6.0;
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
                                fontSize: 10, fontWeight: FontWeight.w700, color: secondary),
                          ),
                        ),
                      ),
                      if (i < 6) const SizedBox(width: spacing),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (var i = 0; i < leadingBlanks; i++) SizedBox(width: cell, height: cell),
                    for (var day = 1; day <= daysInMonth; day++)
                      _dayCell(day, cell, expenseByDay[day] ?? 0, maxExpense, now, secondary),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Less ', style: TextStyle(fontSize: 10, color: secondary)),
                    for (final a in const [0.10, 0.30, 0.55, 0.85])
                      Container(
                        width: 11,
                        height: 11,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: AppColors.expense.withValues(alpha: a),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    Text(' More', style: TextStyle(fontSize: 10, color: secondary)),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _dayCell(
      int day, double size, double expense, double maxExpense, DateTime now, Color secondary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isToday = now.year == _month.year && now.month == _month.month && now.day == day;
    final ratio = maxExpense > 0 ? (expense / maxExpense).clamp(0.0, 1.0) : 0.0;
    final color = expense > 0
        ? AppColors.expense.withValues(alpha: 0.12 + 0.73 * ratio)
        : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openDay(DateTime(_month.year, _month.month, day)),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: isToday ? Border.all(color: AppColors.primary, width: 1.6) : null,
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ratio > 0.55 ? Colors.white : secondary,
            ),
          ),
        ),
      ),
    );
  }
}
