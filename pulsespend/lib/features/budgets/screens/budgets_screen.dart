import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../design_system/ds.dart';
import '../../../models/budget_model.dart';
import '../../../providers/budgets_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/empty_state.dart';
import 'add_budget_screen.dart';
import '../../../l10n/l10n_ext.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, BudgetModel budget) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete budget?'),
        content: Text('The ${budget.category} budget will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.actionCancel)),
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
          ? const _BudgetListSkeleton()
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
                    padding: const EdgeInsets.fromLTRB(
                      AppTokens.screenPadding,
                      AppTokens.space8,
                      AppTokens.screenPadding,
                      100,
                    ),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppTokens.space12),
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

/// Loading placeholder shaped like the budget cards it stands in for, so the
/// list does not jump when the real data lands.
class _BudgetListSkeleton extends StatelessWidget {
  const _BudgetListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.screenPadding,
        AppTokens.space8,
        AppTokens.screenPadding,
        100,
      ),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: AppTokens.space12),
      itemBuilder: (_, __) => const DsSkeletonBox(
        height: 118,
        radius: AppTokens.radiusCard,
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

    final t = context.tokens;
    final theme = Theme.of(context);

    if (!status.isSet) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.screenPadding,
          AppTokens.space12,
          AppTokens.screenPadding,
          0,
        ),
        child: DsCard(
          emphasis: DsCardEmphasis.outlined,
          color: AppColors.primary.withValues(alpha: t.isDark ? 0.16 : 0.07),
          borderColor: AppColors.primary.withValues(alpha: 0.24),
          radius: AppTokens.radiusCardSm,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space16,
            vertical: AppTokens.space12,
          ),
          onTap: () => _openEdit(context, status),
          child: Row(
            children: [
              const DsIconChip(
                icon: Icons.savings_outlined,
                color: AppColors.primary,
                size: 38,
                iconSize: 19,
              ),
              const SizedBox(width: AppTokens.space12),
              Expanded(
                child: Text(
                  'Set an overall monthly budget',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const Icon(Icons.add_rounded, color: AppColors.primary, size: 20),
            ],
          ),
        ),
      );
    }

    final pct = (status.percentage.clamp(0, 999) / 100).toDouble();
    final color = status.isExceeded
        ? t.danger
        : (status.isWarning ? t.warningAccent : AppColors.primary);

    // The screen's one summary figure, so it carries hero weight: a full card
    // with the semicircular gauge, against the flat progress rows below it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.screenPadding,
        AppTokens.space12,
        AppTokens.screenPadding,
        0,
      ),
      child: DsCard(
        onTap: () => _openEdit(context, status),
        padding: const EdgeInsets.fromLTRB(
          AppTokens.space20,
          AppTokens.space20,
          AppTokens.space20,
          AppTokens.space16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DsIconChip(
                  icon: Icons.savings_rounded,
                  color: color,
                  size: 38,
                  iconSize: 19,
                ),
                const SizedBox(width: AppTokens.space12),
                Expanded(
                  child: Text(
                    'Total monthly budget',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: AppTokens.space8),
                DsBadge(label: '${status.percentage.round()}%', color: color),
              ],
            ),
            const SizedBox(height: AppTokens.space12),
            Center(
              child: DsSpendGauge(
                fraction: pct,
                // Blue while on track, amber at 80%, red once breached — the
                // same status ramp the category rows use.
                color: color,
                icon: Icons.savings_rounded,
                amountText:
                    CurrencyFormatter.format(status.spent, status.currency),
                caption: 'spent',
              ),
            ),
            const SizedBox(height: AppTokens.space8),
            Center(
              child: Text(
                'of ${CurrencyFormatter.format(status.amount!, status.currency)} cap',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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
    final t = context.tokens;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppTokens.screenPadding,
        right: AppTokens.screenPadding,
        top: AppTokens.space16,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppTokens.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const DsIconChip(
                icon: Icons.savings_rounded,
                color: AppColors.primary,
                size: 38,
                iconSize: 19,
              ),
              const SizedBox(width: AppTokens.space12),
              Expanded(
                child: Text('Total monthly budget',
                    style: theme.textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space8),
          Text('One overall spending cap across every category for the month.',
              style: theme.textTheme.bodySmall?.copyWith(color: t.textSecondary)),
          const SizedBox(height: AppTokens.space16),
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: currency.isEmpty ? 'Monthly cap' : 'Monthly cap ($currency)',
              prefixIcon: const Icon(Icons.savings_outlined),
            ),
          ),
          const SizedBox(height: AppTokens.space20),
          DsPrimaryButton(
            label: _saving ? 'Saving…' : 'Save',
            onPressed: _saving ? null : () => _save(clear: false),
          ),
          if (isSet)
            TextButton(
              onPressed: _saving ? null : () => _save(clear: true),
              child: Text('Turn off total budget',
                  style: theme.textTheme.labelLarge?.copyWith(color: t.danger)),
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
    final t = context.tokens;
    final theme = Theme.of(context);
    final color = budget.isExceeded
        ? t.danger
        : (budget.isWarning ? t.warningAccent : AppColors.primary);

    return Dismissible(
      key: ValueKey('budget-${budget.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppTokens.space20),
        decoration: BoxDecoration(
          color: t.dangerBg,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        ),
        child: Icon(Icons.delete_outline_rounded, color: t.danger),
      ),
      // A list row: standard card weight, lighter than the total-budget hero
      // above it. Same grammar as [DsBudgetProgressCard] — chip, figures, bar,
      // percentage pill — kept assembled here so this screen's extra
      // affordances (the conversion tooltip, the pacing warning) survive.
      child: DsCard(
        onTap: onEdit,
        padding: const EdgeInsets.all(AppTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryIcon(category: budget.category, size: AppTokens.iconChipSize),
                const SizedBox(width: AppTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        budget.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${budget.periodLabel} budget',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: t.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (budget.conversionError)
                  Tooltip(
                    message: 'Some spending could not be converted to ${budget.currency}',
                    child: Icon(Icons.info_outline_rounded, size: 18, color: t.warningAccent),
                  ),
                const SizedBox(width: AppTokens.space8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      CurrencyFormatter.format(budget.spent, budget.currency),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${CurrencyFormatter.format(budget.amount, budget.currency)} limit',
                      style: theme.textTheme.labelSmall?.copyWith(color: t.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppTokens.space12),
            Row(
              children: [
                // Colour tracks the model's own warning/exceeded thresholds
                // rather than the bar's default ramp, so the pill, the bar and
                // the category chip never disagree.
                Expanded(child: DsProgressBar(value: pct.toDouble(), color: color)),
                const SizedBox(width: AppTokens.space8),
                DsBadge(
                  label: '${budget.percentage.round()}%',
                  color: color,
                  dense: true,
                ),
              ],
            ),
            // Remaining budget spread over the days left in the period.
            if (!budget.isExceeded && budget.dailyAllowance > 0) ...[
              const SizedBox(height: AppTokens.space8),
              Text(
                '${CurrencyFormatter.format(budget.dailyAllowance, budget.currency)}/day left '
                '· ${budget.daysLeftInPeriod} days',
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
            // Proactive pacing warning when not already at 80%+.
            if (budget.isPacingOver && !budget.isWarning && !budget.isExceeded) ...[
              const SizedBox(height: AppTokens.space8),
              DsBadge(
                label: 'On track to overspend',
                color: t.warningAccent,
                icon: Icons.trending_up_rounded,
                dense: true,
              ),
            ],
          ],
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
    final t = context.tokens;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppTokens.screenPadding,
        right: AppTokens.screenPadding,
        top: AppTokens.space16,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppTokens.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryIcon(category: b.category, size: 38),
              const SizedBox(width: AppTokens.space12),
              Expanded(
                child: Text('Edit ${b.category} budget',
                    style: theme.textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space16),
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '${b.periodLabel} limit (${b.currency})',
              prefixIcon: const Icon(Icons.pie_chart_outline_rounded),
            ),
          ),
          const SizedBox(height: AppTokens.space8),
          Text(
            'Spent so far: ${CurrencyFormatter.format(b.spent, b.currency)}',
            style: theme.textTheme.bodySmall?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppTokens.space20),
          DsPrimaryButton(
            label: _saving ? 'Saving…' : 'Save',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
