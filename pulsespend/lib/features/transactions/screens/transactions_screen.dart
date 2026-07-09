import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/transactions_provider.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_list.dart';
import 'add_transaction_screen.dart';
import 'transaction_detail_screen.dart';

enum _Bucket { today, yesterday, thisWeek, earlier }

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
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 200) {
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

  _Bucket _bucketFor(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return _Bucket.today;
    if (diff == 1) return _Bucket.yesterday;
    if (diff < 7) return _Bucket.thisWeek;
    return _Bucket.earlier;
  }

  /// Ordered, non-empty buckets → their transactions.
  List<MapEntry<_Bucket, List<TransactionModel>>> _group(List<TransactionModel> items) {
    final map = <_Bucket, List<TransactionModel>>{};
    for (final tx in items) {
      map.putIfAbsent(_bucketFor(tx.createdAt), () => []).add(tx);
    }
    return [
      for (final b in _Bucket.values)
        if (map[b] != null) MapEntry(b, map[b]!),
    ];
  }

  String _bucketLabel(BuildContext context, _Bucket b) {
    final l = context.l10n;
    return switch (b) {
      _Bucket.today => l.sectionToday,
      _Bucket.yesterday => l.sectionYesterday,
      _Bucket.thisWeek => l.sectionThisWeek,
      _Bucket.earlier => l.sectionEarlier,
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionsControllerProvider);
    final money = ref.watch(moneyFormatterProvider);
    final l = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _applyFilters(state.items);
    final groups = _group(filtered);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          l.transactionsTitle,
          style: TextStyle(
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '${l.transactionsTitle}…',
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
                _FilterChip(
                  label: 'All',
                  selected: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: l.earnings,
                  selected: _filter == 'income',
                  onTap: () => setState(() => _filter = 'income'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: l.spendings,
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
                : state.error != null && state.items.isEmpty
                    ? _ErrorState(
                        message: state.error!,
                        onRetry: () =>
                            ref.read(transactionsControllerProvider.notifier).refresh(),
                      )
                    : filtered.isEmpty
                        ? EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: l.noTransactionsTitle,
                            message: l.noTransactionsBody,
                          )
                        : RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: () =>
                                ref.read(transactionsControllerProvider.notifier).refresh(),
                            child: CustomScrollView(
                              controller: _scrollController,
                              slivers: [
                                for (final group in groups) ...[
                                  SliverPersistentHeader(
                                    pinned: true,
                                    delegate: _SectionHeaderDelegate(
                                      label: _bucketLabel(context, group.key),
                                      isDark: isDark,
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        (context, i) {
                                          final tx = group.value[i];
                                          return _FadeSlideIn(
                                            key: ValueKey(tx.id),
                                            child: _TransactionTile(
                                              transaction: tx,
                                              money: money,
                                            ),
                                          );
                                        },
                                        childCount: group.value.length,
                                      ),
                                    ),
                                  ),
                                ],
                                if (state.isLoadingMore)
                                  const SliverToBoxAdapter(
                                    child: Padding(
                                      padding: EdgeInsets.all(20),
                                      child: Center(child: CircularProgressIndicator()),
                                    ),
                                  ),
                                const SliverToBoxAdapter(child: SizedBox(height: 100)),
                              ],
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

/// Pinned, theme-aware section header for each date bucket.
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  final bool isDark;

  _SectionHeaderDelegate({required this.label, required this.isDark});

  @override
  double get minExtent => 44;
  @override
  double get maxExtent => 44;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13.5,
          letterSpacing: 0.2,
          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeaderDelegate old) =>
      old.label != label || old.isDark != isDark;
}

/// Plays a one-off fade + slide-up when a tile first mounts, so transactions
/// (including ones that arrive live) animate in rather than snapping.
class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  const _FadeSlideIn({super.key, required this.child});

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.08),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'Couldn\'t load transactions',
      message: message,
      actionLabel: context.l10n.actionRetry,
      onAction: onRetry,
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final MoneyFormatter money;

  const _TransactionTile({required this.transaction, required this.money});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final amountColor = transaction.isExpense ? AppColors.expense : AppColors.income;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: transaction)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                              style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (transaction.isSplit)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(Icons.call_split_rounded,
                                  size: 14, color: textSecondary),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        transaction.category,
                        style: TextStyle(fontSize: 12, color: textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  money.format(transaction.amount, transaction.currency, showSign: true),
                  style: TextStyle(fontWeight: FontWeight.w800, color: amountColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
