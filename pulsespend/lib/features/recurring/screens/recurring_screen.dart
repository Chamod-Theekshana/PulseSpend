import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/recurring_model.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/recurring_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_list.dart';
import 'add_recurring_screen.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, RecurringModel rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recurring rule?'),
        content: Text('"${rule.title}" will no longer auto-generate transactions.'),
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
      await ref.read(recurringControllerProvider.notifier).delete(rule.id);
    } catch (e) {
      if (!context.mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recurringControllerProvider);
    final currency = ref.watch(profileControllerProvider).currency;

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      body: state.isLoading && state.items.isEmpty
          ? const ShimmerList()
          : state.items.isEmpty
              ? EmptyState(
                  icon: Icons.autorenew_rounded,
                  title: 'No recurring transactions',
                  message: 'Automate bills, subscriptions, or salary so you never log them manually.',
                  actionLabel: 'Create Rule',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddRecurringScreen()),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(detectedSubscriptionsProvider);
                    await ref.read(recurringControllerProvider.notifier).refresh();
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: state.items.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _RecurringCommitmentCard(),
                            _UpcomingChargesSection(),
                            _DetectedSubscriptionsSection(),
                          ],
                        );
                      }
                      final rule = state.items[i - 1];
                      return _RecurringTile(
                        rule: rule,
                        currency: currency,
                        onToggle: (v) => ref.read(recurringControllerProvider.notifier).toggleActive(rule.id, v),
                        onDelete: () => _confirmDelete(context, ref, rule),
                        onEdit: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => AddRecurringScreen(existing: rule)),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddRecurringScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

/// Summary of active recurring rules as one monthly-equivalent figure, so the
/// user sees their fixed recurring load at a glance. Hidden when no active
/// rules exist.
class _RecurringCommitmentCard extends ConsumerWidget {
  const _RecurringCommitmentCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currency = ref.watch(profileControllerProvider).currency;
    final active = ref.watch(recurringControllerProvider).items.where((r) => r.isActive);
    if (active.isEmpty) return const SizedBox.shrink();

    var monthlyExpense = 0.0;
    var monthlyIncome = 0.0;
    for (final r in active) {
      final m = r.monthlyEquivalent;
      if (m < 0) {
        monthlyExpense += -m;
      } else {
        monthlyIncome += m;
      }
    }
    if (monthlyExpense == 0 && monthlyIncome == 0) return const SizedBox.shrink();

    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: isDark ? 0.28 : 0.12),
            AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.autorenew_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text('Recurring commitments',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            CurrencyFormatter.format(monthlyExpense, currency),
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            'in recurring bills per month'
            '${monthlyIncome > 0 ? ' · +${CurrencyFormatter.format(monthlyIncome, currency)} income' : ''}',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Active recurring rules charging within the next 7 days, so upcoming bills
/// are visible before they hit. Hidden when nothing is due soon.
class _UpcomingChargesSection extends ConsumerWidget {
  const _UpcomingChargesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileCurrency = ref.watch(profileControllerProvider).currency;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final horizon = today.add(const Duration(days: 7));

    final upcoming = ref
        .watch(recurringControllerProvider)
        .items
        .where((r) => r.isActive)
        .where((r) {
          final d = DateTime(r.nextRun.year, r.nextRun.month, r.nextRun.day);
          return !d.isBefore(today) && !d.isAfter(horizon);
        })
        .toList()
      ..sort((a, b) => a.nextRun.compareTo(b.nextRun));

    if (upcoming.isEmpty) return const SizedBox.shrink();

    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    String whenLabel(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      final diff = day.difference(today).inDays;
      if (diff <= 0) return 'today';
      if (diff == 1) return 'tomorrow';
      return 'in $diff days';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Next 7 days',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: textPrimary)),
        const SizedBox(height: 8),
        for (final r in upcoming)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: textPrimary),
                          overflow: TextOverflow.ellipsis),
                      Text('${whenLabel(r.nextRun)} · ${DateFormatter.display(r.nextRun)}',
                          style: TextStyle(fontSize: 11.5, color: textSecondary)),
                    ],
                  ),
                ),
                Text(
                  CurrencyFormatter.format(r.amount, r.currency ?? profileCurrency, showSign: true),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: r.isExpense ? AppColors.expense : AppColors.income,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _RecurringTile extends StatelessWidget {
  final RecurringModel rule;
  final String currency;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _RecurringTile({
    required this.rule,
    required this.currency,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  String _frequencyLabel(String f) {
    switch (f) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      case 'yearly':
        return 'Yearly';
      case 'monthly':
      default:
        return 'Monthly';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    return Dismissible(
      key: ValueKey('recurring-${rule.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.expenseBg, borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.expense),
      ),
      child: Material(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                CategoryIcon(category: rule.category),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rule.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${_frequencyLabel(rule.frequency)} · Next: ${DateFormatter.display(rule.nextRun)}',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.format(rule.amount, rule.currency ?? currency, showSign: true),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: rule.isExpense ? AppColors.expense : AppColors.income,
                      ),
                    ),
                    Switch(
                      value: rule.isActive,
                      onChanged: onToggle,
                      activeTrackColor: AppColors.primary,
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

/// "Detected subscriptions" — subscription-like series found in real spending
/// history (>=3 monthly charges with the same name). Highlights price jumps
/// and offers one-tap tracking as a recurring rule.
class _DetectedSubscriptionsSection extends ConsumerWidget {
  const _DetectedSubscriptionsSection();

  static String _cadenceLabel(String c) => switch (c) {
        'weekly' => 'Weekly',
        'yearly' => 'Yearly',
        _ => 'Monthly',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final detected = ref.watch(detectedSubscriptionsProvider).asData?.value ?? const [];
    if (detected.isEmpty) return const SizedBox.shrink();

    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detected subscriptions',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: textPrimary),
        ),
        Text(
          'Found in your spending history',
          style: TextStyle(fontSize: 11, color: textSecondary),
        ),
        const SizedBox(height: 10),
        for (final s in detected.take(5))
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: s.priceIncreased
                    ? AppColors.warning.withValues(alpha: 0.5)
                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  s.priceIncreased ? Icons.trending_up_rounded : Icons.autorenew_rounded,
                  size: 20,
                  color: s.priceIncreased ? AppColors.warning : AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.priceIncreased
                            ? 'Price up ${s.changePct.toStringAsFixed(0)}%: ${s.previousAmount.toStringAsFixed(2)} -> ${s.lastAmount.toStringAsFixed(2)} ${s.currency}'
                            : '${_cadenceLabel(s.cadenceLabel)} · ${s.lastAmount.toStringAsFixed(2)} ${s.currency} (x${s.occurrences})',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: s.priceIncreased ? AppColors.warning : textSecondary,
                          fontWeight: s.priceIncreased ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddRecurringScreen(
                        initialTitle: s.name,
                        initialAmount: s.lastAmount,
                      ),
                    ),
                  ),
                  child: const Text('Track', style: TextStyle(fontSize: 12.5)),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: textSecondary,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () async {
                    try {
                      await ref.read(recurringRepositoryProvider).dismissDetected(s.name);
                      ref.invalidate(detectedSubscriptionsProvider);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Your rules',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: textPrimary),
        ),
      ],
    );
  }
}
