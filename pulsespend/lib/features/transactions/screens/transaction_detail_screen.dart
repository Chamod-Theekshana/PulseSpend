import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/transactions_provider.dart';
import '../../../shared/widgets/category_icon.dart';
import 'add_transaction_screen.dart';

class TransactionDetailScreen extends ConsumerWidget {
  final TransactionModel transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This cannot be undone.'),
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
      await ref.read(transactionsControllerProvider.notifier).delete(transaction.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AddTransactionScreen(existing: transaction)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Column(
                children: [
                  CategoryIcon(category: transaction.category, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    transaction.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    CurrencyFormatter.format(transaction.amount, transaction.currency, showSign: true),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: transaction.isExpense ? AppColors.expense : AppColors.income,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _DetailCard(
              children: [
                _DetailRow(icon: Icons.category_outlined, label: 'Category', value: transaction.category),
                _DetailRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date',
                  value: DateFormatter.display(transaction.createdAt),
                ),
                _DetailRow(
                  icon: Icons.payments_outlined,
                  label: 'Currency',
                  value: transaction.currency,
                ),
              ],
            ),
            if (transaction.isSplit) ...[
              const SizedBox(height: 16),
              Text('Split breakdown', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              _DetailCard(
                children: transaction.splits
                    .map((s) => _DetailRow(
                          icon: Icons.call_split_rounded,
                          label: s.category,
                          value: CurrencyFormatter.format(s.amount.abs(), transaction.currency),
                        ))
                    .toList(),
              ),
            ],
            if (transaction.notes != null && transaction.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Notes', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.lightSurfaceAlt,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(transaction.notes!),
              ),
            ],
            if (transaction.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Tags', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: transaction.tags.map((t) => Chip(label: Text('#$t'))).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final List<Widget> children;
  const _DetailCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.lightTextSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.lightTextSecondary))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
