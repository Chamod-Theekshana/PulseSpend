import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/reminder_model.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/reminders_provider.dart';
import '../../../providers/transactions_provider.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_list.dart';
import 'add_reminder_screen.dart';
import '../../../l10n/l10n_ext.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, ReminderModel reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text('"${reminder.title}" will no longer send notifications.'),
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
      await ref.read(remindersControllerProvider.notifier).delete(reminder.id);
    } catch (e) {
      if (!context.mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    }
  }

  /// "Paid ✓": logs the bill as an expense transaction (today) and deactivates
  /// the reminder so it stops nagging — pure composition of existing endpoints.
  Future<void> _markPaid(BuildContext context, WidgetRef ref, ReminderModel reminder) async {
    final amountLabel = CurrencyFormatter.format(reminder.amount, reminder.currency);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as paid?'),
        content: Text(
          'This logs a $amountLabel expense in "${reminder.category}" today and '
          'stops reminders for "${reminder.title}".',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.actionCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark Paid'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(transactionsControllerProvider.notifier).create(
            TransactionModel(
              id: 0,
              userId: reminder.userId,
              title: reminder.title,
              amount: -reminder.amount.abs(),
              currency: reminder.currency,
              category: reminder.category,
              createdAt: DateTime.now(),
            ),
          );
      await ref.read(remindersControllerProvider.notifier).update(
            reminder.id,
            ReminderModel(
              id: reminder.id,
              userId: reminder.userId,
              title: reminder.title,
              amount: reminder.amount,
              currency: reminder.currency,
              category: reminder.category,
              dueDate: reminder.dueDate,
              remindDaysBefore: reminder.remindDaysBefore,
              isActive: false,
            ),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paid & logged ✓'), backgroundColor: AppColors.income),
      );
    } catch (e) {
      if (!context.mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(remindersControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bill Reminders')),
      body: state.isLoading && state.items.isEmpty
          ? const ShimmerList()
          : state.items.isEmpty
              ? EmptyState(
                  icon: Icons.notifications_active_outlined,
                  title: 'No reminders yet',
                  message: 'Get notified before bills are due so you never miss a payment.',
                  actionLabel: 'Add Reminder',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddReminderScreen()),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(remindersControllerProvider.notifier).refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    children: [
                      if (state.overdue.isNotEmpty) ...[
                        _SectionLabel(text: 'Overdue', color: AppColors.expense),
                        ...state.overdue.map((r) => _ReminderTile(
                              reminder: r,
                              onDelete: () => _confirmDelete(context, ref, r),
                              onMarkPaid: () => _markPaid(context, ref, r),
                            )),
                        const SizedBox(height: 12),
                      ],
                      if (state.upcoming.isNotEmpty) ...[
                        _SectionLabel(text: 'Upcoming', color: AppColors.lightTextSecondary),
                        ...state.upcoming.map((r) => _ReminderTile(
                              reminder: r,
                              onDelete: () => _confirmDelete(context, ref, r),
                              onMarkPaid: () => _markPaid(context, ref, r),
                            )),
                      ],
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddReminderScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final ReminderModel reminder;
  final VoidCallback onDelete;
  final VoidCallback onMarkPaid;

  const _ReminderTile({
    required this.reminder,
    required this.onDelete,
    required this.onMarkPaid,
  });

  @override
  Widget build(BuildContext context) {
    final daysLeft = reminder.daysUntilDue;
    final dueLabel = reminder.isOverdue
        ? '${daysLeft.abs()} day${daysLeft.abs() == 1 ? '' : 's'} overdue'
        : daysLeft == 0
            ? 'Due today'
            : 'Due in $daysLeft day${daysLeft == 1 ? '' : 's'}';

    return Dismissible(
      key: ValueKey('reminder-${reminder.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.expenseBg, borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.expense),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: reminder.isOverdue ? AppColors.expense.withValues(alpha: 0.3) : AppColors.lightBorder),
        ),
        child: Row(
          children: [
            CategoryIcon(category: reminder.category),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reminder.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '$dueLabel · ${DateFormatter.display(reminder.dueDate)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: reminder.isOverdue ? AppColors.expense : AppColors.lightTextSecondary,
                      fontWeight: reminder.isOverdue ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              CurrencyFormatter.format(reminder.amount, reminder.currency),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            // "Paid ✓" — logs the expense and silences this reminder.
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onMarkPaid,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.income.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_rounded, size: 18, color: AppColors.income),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
