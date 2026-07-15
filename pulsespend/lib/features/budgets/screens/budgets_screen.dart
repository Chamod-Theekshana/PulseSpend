import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/budget_model.dart';
import '../../../providers/budgets_provider.dart';
import '../../../providers/repository_providers.dart';
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

  Future<void> _openEditSheet(BuildContext context, WidgetRef ref, BudgetModel budget) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BudgetEditSheet(budget: budget),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(budgetsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: Column(
        children: [
          const _TotalBudgetCard(),
          Expanded(child: _buildContent(context, ref, state)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddBudgetScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, BudgetsState state) {
    return state.isLoading && state.items.isEmpty
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
                  onRefresh: () async {
                    ref.invalidate(totalBudgetStatusProvider);
                    await ref.read(budgetsControllerProvider.notifier).refresh();
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      final budget = state.items[i];
                      return _BudgetCard(
                        budget: budget,
                        onDelete: () => _confirmDelete(context, ref, budget),
                        onEdit: () => _openEditSheet(context, ref, budget),
                      );
                    },
                  ),
                );
  }
}

/// Overall monthly budget cap (independent of per-category budgets). Shows a
/// progress card when set, otherwise a "set a total budget" CTA. Tap to edit.
class _TotalBudgetCard extends ConsumerWidget {
  const _TotalBudgetCard();

  Future<void> _openEdit(BuildContext context, TotalBudgetStatus? status) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TotalBudgetEditSheet(current: status),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(totalBudgetStatusProvider);
    final status = async.asData?.value;
    if (status == null) return const SizedBox.shrink(); // loading/error → no jank

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    if (!status.isSet) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Material(
          color: AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.07),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openEdit(context, status),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.savings_outlined, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Set an overall monthly budget',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                    ),
                  ),
                  Icon(Icons.add_rounded, color: AppColors.primary, size: 20),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final pct = (status.percentage.clamp(0, 999) / 100).toDouble();
    final color = status.isExceeded
        ? AppColors.expense
        : (status.isWarning ? AppColors.warning : AppColors.primary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Material(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openEdit(context, status),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.savings_rounded, color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Total monthly budget',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)),
                    ),
                    Text('${status.percentage.round()}%',
                        style: TextStyle(fontWeight: FontWeight.w800, color: color)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0, 1).toDouble(),
                    minHeight: 8,
                    backgroundColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${CurrencyFormatter.format(status.spent, status.currency)} spent',
                        style: TextStyle(fontSize: 13, color: textSecondary)),
                    Text('${CurrencyFormatter.format(status.amount!, status.currency)} cap',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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

/// Sheet to set or turn off the overall monthly budget.
class _TotalBudgetEditSheet extends ConsumerStatefulWidget {
  final TotalBudgetStatus? current;
  const _TotalBudgetEditSheet({required this.current});

  @override
  ConsumerState<_TotalBudgetEditSheet> createState() => _TotalBudgetEditSheetState();
}

class _TotalBudgetEditSheetState extends ConsumerState<_TotalBudgetEditSheet> {
  late final _amountController = TextEditingController(
    text: (widget.current?.amount != null) ? widget.current!.amount!.toStringAsFixed(0) : '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save({required bool clear}) async {
    double? amount;
    if (!clear) {
      amount = double.tryParse(_amountController.text.trim());
      if (amount == null || amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await ref.read(budgetRepositoryProvider).setTotalBudget(clear ? null : amount);
      ref.invalidate(totalBudgetStatusProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.current?.currency ?? '';
    final isSet = widget.current?.isSet ?? false;
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
          const Row(
            children: [
              Icon(Icons.savings_rounded, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Total monthly budget',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text('One overall spending cap across every category for the month.',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              )),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: currency.isEmpty ? 'Monthly cap' : 'Monthly cap ($currency)',
              prefixIcon: const Icon(Icons.savings_outlined),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : () => _save(clear: false),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
          if (isSet)
            TextButton(
              onPressed: _saving ? null : () => _save(clear: true),
              child: const Text('Turn off total budget', style: TextStyle(color: AppColors.expense)),
            ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final BudgetModel budget;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _BudgetCard({required this.budget, required this.onDelete, required this.onEdit});

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
      child: Material(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
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
                            '${budget.periodLabel} budget',
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
                // Remaining budget spread over the days left in the period.
                if (!budget.isExceeded && budget.dailyAllowance > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${CurrencyFormatter.format(budget.dailyAllowance, budget.currency)}/day left '
                    '· ${budget.daysLeftInPeriod} days',
                    style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                  ),
                ],
                // Proactive pacing warning when not already at 80%+.
                if (budget.isPacingOver && !budget.isWarning && !budget.isExceeded) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.trending_up_rounded, size: 15, color: AppColors.warning),
                      const SizedBox(width: 6),
                      Text('On track to overspend',
                          style: TextStyle(
                              fontSize: 11.5, color: AppColors.warning, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Edit sheet for an existing budget's limit. Category/currency/period are set
/// at creation (backend update is amount-only); this owns its controller so it
/// survives the sheet's dismiss animation.
class _BudgetEditSheet extends ConsumerStatefulWidget {
  final BudgetModel budget;
  const _BudgetEditSheet({required this.budget});

  @override
  ConsumerState<_BudgetEditSheet> createState() => _BudgetEditSheetState();
}

class _BudgetEditSheetState extends ConsumerState<_BudgetEditSheet> {
  late final _amountController =
      TextEditingController(text: widget.budget.amount.toStringAsFixed(0));
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(budgetsControllerProvider.notifier).updateAmount(widget.budget.id, amount);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.budget;
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
          Row(
            children: [
              CategoryIcon(category: b.category, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Edit ${b.category} budget',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '${b.periodLabel} limit (${b.currency})',
              prefixIcon: const Icon(Icons.pie_chart_outline_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Spent so far: ${CurrencyFormatter.format(b.spent, b.currency)}',
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }
}
