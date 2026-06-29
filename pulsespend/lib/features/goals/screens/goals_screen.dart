import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/goal_model.dart';
import '../../../providers/goals_provider.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_list.dart';
import 'add_goal_screen.dart';
import 'contribute_goal_sheet.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, GoalModel goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete goal?'),
        content: Text('"${goal.name}" will be removed permanently.'),
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
      await ref.read(goalsControllerProvider.notifier).delete(goal.id);
    } catch (e) {
      if (!context.mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.message)));
    }
  }

  void _openContribute(BuildContext context, GoalModel goal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ContributeGoalSheet(goal: goal),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(goalsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Savings Goals')),
      body: state.isLoading && state.items.isEmpty
          ? const ShimmerList(itemHeight: 140)
          : state.items.isEmpty
              ? EmptyState(
                  icon: Icons.flag_outlined,
                  title: 'No goals yet',
                  message: 'Set a savings target — like an emergency fund or a trip — and track progress.',
                  actionLabel: 'Create Goal',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddGoalScreen()),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(goalsControllerProvider.notifier).refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    children: [
                      if (state.active.isNotEmpty) ...[
                        ...state.active.map((g) => _GoalCard(
                              goal: g,
                              onContribute: () => _openContribute(context, g),
                              onDelete: () => _confirmDelete(context, ref, g),
                            )),
                      ],
                      if (state.completed.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Completed',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: AppColors.lightTextSecondary,
                                ),
                          ),
                        ),
                        ...state.completed.map((g) => _GoalCard(
                              goal: g,
                              onContribute: () => _openContribute(context, g),
                              onDelete: () => _confirmDelete(context, ref, g),
                            )),
                      ],
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddGoalScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final GoalModel goal;
  final VoidCallback onContribute;
  final VoidCallback onDelete;

  const _GoalCard({required this.goal, required this.onContribute, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final pct = (goal.progressPercentage.clamp(0, 100)) / 100;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Row(
        children: [
          CircularPercentIndicator(
            radius: 32,
            lineWidth: 7,
            percent: pct.toDouble(),
            center: Text('${(pct * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            progressColor: goal.isCompleted ? AppColors.income : AppColors.primary,
            backgroundColor: AppColors.lightBorder,
            circularStrokeCap: CircularStrokeCap.round,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        goal.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (goal.isCompleted)
                      const Icon(Icons.check_circle_rounded, color: AppColors.income, size: 18),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${CurrencyFormatter.format(goal.currentAmount, goal.currency)} of '
                  '${CurrencyFormatter.format(goal.targetAmount, goal.currency)}',
                  style: const TextStyle(fontSize: 13, color: AppColors.lightTextSecondary),
                ),
                if (goal.deadline != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Due ${DateFormatter.display(goal.deadline!)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.lightTextTertiary),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              if (!goal.isCompleted)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                  onPressed: onContribute,
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.lightTextTertiary, size: 20),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
