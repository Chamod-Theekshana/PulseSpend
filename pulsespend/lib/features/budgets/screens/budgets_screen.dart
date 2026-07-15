import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/budget_model.dart';
import '../../../providers/budgets_provider.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_list.dart';
import 'add_budget_screen.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, BudgetModel budget) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete budget?'),
        content: Text('The ${budget.category} budget will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(budgetsControllerProvider.notifier).delete(budget.id);
    } catch (e) {
      if (!context.mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(budgetsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: state.isLoading && state.items.isEmpty
          ? const ShimmerList(itemHeight: 110)
          : state.items.isEmpty
              ? EmptyState(
                  icon: Icons.pie_chart_outline_rounded,
                  title: 'No budgets yet',
                  message: 'Set a monthly spending limit per category to stay on track.',
                  actionLabel: 'Create Budget',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddBudgetScreen()),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(budgetsControllerProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      final budget = state.items[i];
                      return _BudgetCard(
                        budget: budget,
                        onDelete: () => _confirmDelete(context, ref, budget),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddBudgetScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final BudgetModel budget;
  final VoidCallback onDelete;

  const _BudgetCard({required this.budget, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final pct = budget.percentage.clamp(0, 999) / 100;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final color = budget.isExceeded
        ? AppColors.expense
        : (budget.isWarning ? AppColors.warning : AppColors.primary);

    return Dismissible(
      key: ValueKey('budget-${budget.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.expenseBg, borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.expense),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryIcon(category: budget.category, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(budget.category, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(
                        'Monthly budget',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ],
                  ),
                ),
                if (budget.conversionError)
                  Tooltip(
                    message: 'Some spending could not be converted to ${budget.currency}',
                    child: const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
                  ),
                Text(
                  '${budget.percentage.round()}%',
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct.clamp(0, 1).toDouble(),
                minHeight: 8,
                backgroundColor: border,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${CurrencyFormatter.format(budget.spent, budget.currency)} spent',
                  style: TextStyle(fontSize: 13, color: textSecondary),
                ),
                Text(
                  '${CurrencyFormatter.format(budget.amount, budget.currency)} limit',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
