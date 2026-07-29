import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/goal_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/goals_provider.dart';
import '../../../providers/wallets_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/shimmer_list.dart';
import 'add_goal_screen.dart';
import 'contribute_goal_sheet.dart';
import 'goal_detail_sheet.dart';
import '../../../l10n/l10n_ext.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, GoalModel goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete goal?'),
        content: Text('"${goal.name}" will be removed permanently.'),
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
      await ref.read(goalsControllerProvider.notifier).delete(goal.id);
    } catch (e) {
      if (!context.mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    }
  }

  void _openContribute(BuildContext context, GoalModel goal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ContributeGoalSheet(goal: goal),
    );
  }

  void _openDetail(BuildContext context, GoalModel goal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => GoalDetailSheet(goal: goal),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(goalsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings Goals'),
        actions: [
          IconButton(
            tooltip: 'Round-up savings',
            icon: const Icon(Icons.currency_exchange_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const _RoundupSettingsSheet(),
            ),
          ),
        ],
      ),
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
                              onTap: () => _openDetail(context, g),
                            )),
                      ],
                      if (state.completed.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Completed',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary,
                                ),
                          ),
                        ),
                        ...state.completed.map((g) => _GoalCard(
                              goal: g,
                              onContribute: () => _openContribute(context, g),
                              onDelete: () => _confirmDelete(context, ref, g),
                              onTap: () => _openDetail(context, g),
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
  final VoidCallback onTap;

  const _GoalCard({
    required this.goal,
    required this.onContribute,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (goal.progressPercentage.clamp(0, 100)) / 100;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          CircularPercentIndicator(
            radius: 32,
            lineWidth: 7,
            percent: pct.toDouble(),
            center: Text('${(pct * 100).round()}%',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: textPrimary)),
            progressColor: goal.isCompleted ? AppColors.income : AppColors.primary,
            backgroundColor: border,
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
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15, color: textPrimary),
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
                  style: TextStyle(fontSize: 13, color: textSecondary),
                ),
                if (goal.deadline != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Due ${DateFormatter.display(goal.deadline!)}',
                      style: TextStyle(fontSize: 12, color: textTertiary),
                    ),
                  ),
                // Pace insight: what it takes per week to hit the deadline.
                if (goal.requiredPerWeek != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (goal.onTrack ?? true)
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded,
                          size: 13,
                          color: (goal.onTrack ?? true) ? AppColors.income : AppColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${CurrencyFormatter.formatCompact(goal.requiredPerWeek!, goal.currency)}/week'
                            '${goal.onTrack == false ? ' · behind pace' : ' · on track'}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: (goal.onTrack ?? true) ? AppColors.income : AppColors.warning,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
                icon: Icon(Icons.delete_outline_rounded, color: textTertiary, size: 20),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
        ),
      ),
    );
  }
}

/// Round-up savings settings: pick a goal + rounding unit; every expense then
/// rounds up to that unit and the spare change auto-contributes to the goal.
class _RoundupSettingsSheet extends ConsumerStatefulWidget {
  const _RoundupSettingsSheet();

  @override
  ConsumerState<_RoundupSettingsSheet> createState() => _RoundupSettingsSheetState();
}

class _RoundupSettingsSheetState extends ConsumerState<_RoundupSettingsSheet> {
  int? _goalId;
  int _roundTo = 100;
  /// Wallet the spare change comes from (0 = default). Required to enable —
  /// without a debit the goal would grow out of nothing.
  int? _walletId;
  bool _enabled = false;
  bool _saving = false;
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final goals = ref.watch(goalsControllerProvider).active;
    final user = ref.watch(profileControllerProvider).user;

    // Seed once from the profile's saved rule.
    if (!_seeded && user != null) {
      _seeded = true;
      _goalId = user.roundupGoalId;
      _roundTo = user.roundupTo ?? 100;
      _walletId = user.roundupWalletId;
      _enabled = user.roundupGoalId != null;
    }

    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

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
          const Text('Round-up savings', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Round every expense up and save the spare change. E.g. rounding to 100: '
            'a 1,340 expense saves 60 into your goal.',
            style: TextStyle(fontSize: 12.5, color: textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable round-ups', style: TextStyle(fontWeight: FontWeight.w700)),
            value: _enabled,
            activeThumbColor: AppColors.primary,
            onChanged: goals.isEmpty ? null : (v) => setState(() => _enabled = v),
          ),
          if (goals.isEmpty)
            Text('Create a savings goal first.', style: TextStyle(fontSize: 12, color: AppColors.warning)),
          if (_enabled && goals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Save into', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in goals)
                  ChoiceChip(
                    label: Text(g.name),
                    selected: _goalId == g.id,
                    onSelected: (_) => setState(() => _goalId = g.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Take the spare change from', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Consumer(builder: (context, ref, _) {
              // Spendable wallets only — savings can't come out of a debt.
              final wallets = ref
                  .watch(walletsControllerProvider)
                  .items
                  .where((w) => !w.isLiability)
                  .toList();
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Default'),
                    selected: _walletId == 0,
                    onSelected: (_) => setState(() => _walletId = 0),
                  ),
                  for (final w in wallets)
                    ChoiceChip(
                      label: Text(w.name),
                      selected: _walletId == w.id,
                      onSelected: (_) => setState(() => _walletId = w.id),
                    ),
                ],
              );
            }),
            const SizedBox(height: 12),
            Text('Round up to nearest', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final r in const [10, 50, 100, 500])
                  ChoiceChip(
                    label: Text('$r'),
                    selected: _roundTo == r,
                    onSelected: (_) => setState(() => _roundTo = r),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Save',
            isLoading: _saving,
            onPressed: () async {
              if (_enabled && _goalId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pick a goal for the spare change')),
                );
                return;
              }
              if (_enabled && _walletId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pick which wallet the spare change comes from')),
                );
                return;
              }
              setState(() => _saving = true);
              try {
                final userId = ref.read(currentUserIdProvider);
                await ref.read(profileRepositoryProvider).updateRoundup(
                      userId,
                      goalId: _enabled ? _goalId : null,
                      roundTo: _enabled ? _roundTo : null,
                      walletId: _enabled ? _walletId : null,
                    );
                await ref.read(profileControllerProvider.notifier).refresh();
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
            },
          ),
        ],
      ),
    );
  }
}
