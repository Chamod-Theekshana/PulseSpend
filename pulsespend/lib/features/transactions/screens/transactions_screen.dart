import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../providers/transactions_provider.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_list.dart';
import 'add_transaction_screen.dart';
import 'csv_import_screen.dart';
import 'transaction_detail_screen.dart';
import 'transaction_filter_sheet.dart';

enum _Bucket { today, yesterday, thisWeek, earlier }

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  bool _isExporting = false;

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
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  TransactionsController get _controller =>
      ref.read(transactionsControllerProvider.notifier);

  /// Debounced free-text search — server-side, so it hits the whole history.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final current = ref.read(transactionsControllerProvider).filters;
      _controller.setFilters(current.copyWith(query: value));
    });
  }

  void _setType(String type) {
    final current = ref.read(transactionsControllerProvider).filters;
    _controller.setFilters(current.copyWith(type: type));
  }

  Future<void> _openFilterSheet() async {
    final current = ref.read(transactionsControllerProvider).filters;
    final result = await showTransactionFilterSheet(context, current);
    if (result != null) {
      await _controller.setFilters(result);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _isExporting = true);
    try {
      final csv = await _controller.exportCsv();
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File('${dir.path}/pulsespend_transactions_$stamp.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)], text: 'My PulseSpend transactions');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context)), backgroundColor: AppColors.expense),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Server-rendered PDF report for the current month — summary, category
  /// breakdown, budgets vs actual and net worth. Shared like the CSV export.
  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    try {
      final userId = ref.read(currentUserIdProvider);
      final now = DateTime.now();
      final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final bytes = await ref
          .read(transactionRepositoryProvider)
          .reportPdf(userId: userId, month: month);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/pulsespend_report_$month.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'PulseSpend report $month');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context)), backgroundColor: AppColors.expense),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
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
    final filters = state.filters;
    final groups = _group(state.items);

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
        actions: [
          IconButton(
            tooltip: 'Import CSV',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CsvImportScreen()),
            ),
            icon: const Icon(Icons.file_download_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Export',
            enabled: !_isExporting,
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
            onSelected: (v) => v == 'pdf' ? _exportPdf() : _exportCsv(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: Icon(Icons.table_view_rounded),
                  title: Text('Export CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_rounded),
                  title: Text('PDF report (this month)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: '${l.transactionsTitle}…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: filters.query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _debounce?.cancel();
                                _searchController.clear();
                                _controller.setFilters(filters.copyWith(query: ''));
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _FilterButton(
                  count: filters.advancedCount,
                  onTap: _openFilterSheet,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: filters.type == 'all',
                  onTap: () => _setType('all'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: l.earnings,
                  selected: filters.type == 'income',
                  onTap: () => _setType('income'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: l.spendings,
                  selected: filters.type == 'expense',
                  onTap: () => _setType('expense'),
                ),
              ],
            ),
          ),
          if (state.pendingSyncCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: _PendingSyncBanner(count: state.pendingSyncCount),
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
                    : state.items.isEmpty
                        ? EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: filters.isActive ? 'No matches' : l.noTransactionsTitle,
                            message: filters.isActive
                                ? 'No transactions match your search or filters.'
                                : l.noTransactionsBody,
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

/// Shown while offline-created/deleted transactions are waiting to sync.
class _PendingSyncBanner extends StatelessWidget {
  final int count;
  const _PendingSyncBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count change${count == 1 ? '' : 's'} will sync when you\'re back online',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

/// Square button that opens the advanced filter sheet, badged with the number
/// of active advanced filters.
class _FilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _FilterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = count > 0;
    return Material(
      color: active
          ? AppColors.primary
          : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.tune_rounded,
                color: active
                    ? Colors.white
                    : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
              ),
              if (active)
                Positioned(
                  right: -8,
                  top: -8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: AppColors.expense, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
