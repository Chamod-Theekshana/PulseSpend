import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/goal_model.dart';
import '../../../providers/goals_provider.dart';

/// Contribution timeline for a goal (deposits, auto-contributions, round-ups,
/// withdrawals) + a Withdraw action. Opened by tapping a goal card.
class GoalDetailSheet extends ConsumerWidget {
  final GoalModel goal;
  const GoalDetailSheet({super.key, required this.goal});

  IconData _sourceIcon(GoalContribution c) {
    if (c.amount < 0) return Icons.undo_rounded;
    return switch (c.source) {
      'auto' => Icons.schedule_rounded,
      'roundup' => Icons.currency_exchange_rounded,
      _ => Icons.add_rounded,
    };
  }

  String _sourceLabel(GoalContribution c) {
    if (c.amount < 0) return 'Withdrawal';
    return switch (c.source) {
      'auto' => 'Auto-contribution',
      'roundup' => 'Round-up savings',
      _ => 'Deposit',
    };
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw from goal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount (${goal.currency})',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    // Sheet-owned dialogs: dispose after the dismiss animation settles.
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (amount == null || amount <= 0) return;

    try {
      await ref.read(goalsControllerProvider.notifier).contribute(
            id: goal.id,
            amount: -amount,
            currency: goal.currency,
          );
      ref.invalidate(goalContributionsProvider(goal.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Withdrew ${CurrencyFormatter.format(amount, goal.currency)}'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
        );
      }
    }
  }

  Future<void> _editAutoRule(BuildContext context, WidgetRef ref) async {
    final amountController =
        TextEditingController(text: goal.autoAmount?.toStringAsFixed(0) ?? '');
    var day = goal.autoDay ?? 1;

    final result = await showDialog<({double? amount, int day})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Auto-contribution'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount (${goal.currency}) — empty to turn off',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Every month on day'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: day,
                    items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d'))],
                    onChanged: (v) => setState(() => day = v ?? 1),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                (amount: double.tryParse(amountController.text.trim()), day: day),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 1), amountController.dispose);
    if (result == null) return;

    try {
      await ref.read(goalsControllerProvider.notifier).setAutoRule(
            goal.id,
            amount: result.amount != null && result.amount! > 0 ? result.amount : null,
            day: result.day,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.amount != null && result.amount! > 0
                ? 'Auto-contribution saved ✓'
                : 'Auto-contribution turned off'),
          ),
        );
        Navigator.pop(context); // reopen shows the fresh rule
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final contributionsAsync = ref.watch(goalContributionsProvider(goal.id));
    final perWeek = goal.requiredPerWeek;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    goal.name,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${goal.progressPercentage.toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${CurrencyFormatter.format(goal.currentAmount, goal.currency)} of '
              '${CurrencyFormatter.format(goal.targetAmount, goal.currency)}'
              '${goal.deadline != null ? ' · by ${DateFormatter.display(goal.deadline!)}' : ''}',
              style: TextStyle(fontSize: 12.5, color: textSecondary),
            ),
            if (perWeek != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (goal.onTrack ?? true)
                      ? AppColors.income.withValues(alpha: 0.10)
                      : AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      (goal.onTrack ?? true) ? Icons.check_circle_outline : Icons.info_outline,
                      size: 16,
                      color: (goal.onTrack ?? true) ? AppColors.income : AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Save ${CurrencyFormatter.formatCompact(perWeek, goal.currency)}/week to hit your deadline'
                        '${goal.onTrack == false ? ' — currently behind pace' : ''}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            // ── Auto-contribute rule ──
            if (!goal.isCompleted)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _editAutoRule(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          goal.autoAmount != null
                              ? 'Auto-contributes ${CurrencyFormatter.formatCompact(goal.autoAmount!, goal.currency)} on day ${goal.autoDay} monthly'
                              : 'Set up monthly auto-contribution',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                        ),
                      ),
                      Icon(Icons.edit_rounded, size: 14, color: textSecondary),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('History', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: textPrimary)),
                if (!goal.isCompleted && goal.currentAmount > 0)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _withdraw(context, ref),
                    child: const Text('Withdraw', style: TextStyle(fontSize: 12.5, color: AppColors.expense)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            contributionsAsync.when(
              data: (contributions) => contributions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No contributions yet.', style: TextStyle(color: textSecondary, fontSize: 12.5)),
                    )
                  : Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: contributions.length,
                        itemBuilder: (context, i) {
                          final c = contributions[i];
                          final isWithdrawal = c.amount < 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(_sourceIcon(c), size: 17,
                                    color: isWithdrawal ? AppColors.expense : AppColors.income),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          // For group goals, show who contributed.
                                          c.contributorName != null && c.source == 'manual'
                                              ? '${_sourceLabel(c)} · ${c.contributorName}'
                                              : _sourceLabel(c),
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
                                      if (c.createdAt != null)
                                        Text(DateFormatter.relative(c.createdAt!),
                                            style: TextStyle(fontSize: 11, color: textSecondary)),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${isWithdrawal ? '−' : '+'}${CurrencyFormatter.format(c.amount.abs(), goal.currency)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: isWithdrawal ? AppColors.expense : AppColors.income,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text("Couldn't load history", style: TextStyle(color: textSecondary, fontSize: 12.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
