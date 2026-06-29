import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/recurring_model.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/recurring_provider.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.message)));
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
                  onRefresh: () => ref.read(recurringControllerProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final rule = state.items[i];
                      return _RecurringTile(
                        rule: rule,
                        currency: currency,
                        onToggle: (v) => ref.read(recurringControllerProvider.notifier).toggleActive(rule.id, v),
                        onDelete: () => _confirmDelete(context, ref, rule),
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

class _RecurringTile extends StatelessWidget {
  final RecurringModel rule;
  final String currency;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _RecurringTile({
    required this.rule,
    required this.currency,
    required this.onToggle,
    required this.onDelete,
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
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.lightBorder),
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
                    style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(rule.amount, currency, showSign: true),
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
    );
  }
}
