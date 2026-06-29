import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/transactions_provider.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_list.dart';
import 'add_transaction_screen.dart';
import 'transaction_detail_screen.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _query = '';
  String _filter = 'all'; // all | income | expense

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 200) {
        ref.read(transactionsControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<TransactionModel> _applyFilters(List<TransactionModel> items) {
    var filtered = items;
    if (_filter == 'income') {
      filtered = filtered.where((t) => t.isIncome).toList();
    } else if (_filter == 'expense') {
      filtered = filtered.where((t) => t.isExpense).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      filtered = filtered
          .where((t) =>
              t.title.toLowerCase().contains(q) ||
              t.category.toLowerCase().contains(q) ||
              t.tags.any((tag) => tag.contains(q)))
          .toList();
    }
    return filtered;
  }

  Map<String, List<TransactionModel>> _groupByDay(List<TransactionModel> items) {
    final map = <String, List<TransactionModel>>{};
    for (final tx in items) {
      final key = DateFormatter.dayHeader(tx.createdAt);
      map.putIfAbsent(key, () => []).add(tx);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionsControllerProvider);
    final currency = ref.watch(profileControllerProvider).currency;
    final filtered = _applyFilters(state.items);
    final grouped = _groupByDay(filtered);

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          _query = '';
                          _searchController.clear();
                        }),
                      )
                    : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _FilterChip(label: 'All', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Income',
                  selected: _filter == 'income',
                  onTap: () => setState(() => _filter = 'income'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Expense',
                  selected: _filter == 'expense',
                  onTap: () => setState(() => _filter = 'expense'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: state.isLoading && state.items.isEmpty
                ? const ShimmerList()
                : filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No transactions found',
                        message: 'Try a different filter or add a new transaction.',
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref.read(transactionsControllerProvider.notifier).refresh(),
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                          itemCount: grouped.length,
                          itemBuilder: (context, index) {
                            final day = grouped.keys.elementAt(index);
                            final txs = grouped[day]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                                  child: Text(
                                    day,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.lightTextSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                ...txs.map((tx) => _TransactionTile(transaction: tx, currency: currency)),
                              ],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.lightSurfaceAlt,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.lightTextSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final String currency;

  const _TransactionTile({required this.transaction, required this.currency});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: transaction)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CategoryIcon(category: transaction.category),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          transaction.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (transaction.isSplit)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.call_split_rounded, size: 14, color: AppColors.lightTextSecondary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    transaction.category,
                    style: const TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              CurrencyFormatter.format(transaction.amount, transaction.currency, showSign: true),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: transaction.isExpense ? AppColors.expense : AppColors.income,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
