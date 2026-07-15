import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/errors/api_exception.dart';
import '../core/network/socket_service.dart';
import '../core/storage/local_cache.dart';
import '../core/storage/outbox_service.dart';
import '../core/widget/home_widget_service.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';
import 'connectivity_provider.dart';
import 'debts_provider.dart';
import 'repository_providers.dart';

/// Server-side filter set for the transactions list + CSV export. `type` is
/// 'all' | 'income' | 'expense'; the advanced fields are optional. Maps to the
/// query params parsed by parseTransactionFilters on the backend.
class TransactionFilters {
  final String query;
  final String type; // all | income | expense
  final String? category;
  final DateTime? from;
  final DateTime? to;
  final double? minAmount;
  final double? maxAmount;

  /// Wallet filter: null = all wallets, 0 = the default (unassigned) wallet,
  /// otherwise a wallet id.
  final int? walletId;

  const TransactionFilters({
    this.query = '',
    this.type = 'all',
    this.category,
    this.from,
    this.to,
    this.minAmount,
    this.maxAmount,
    this.walletId,
  });

  /// Number of *advanced* (bottom-sheet) filters active — used to badge the
  /// filter button. Query text and the type chips are shown separately.
  int get advancedCount =>
      [category, from, to, minAmount, maxAmount, walletId].where((e) => e != null).length;

  bool get isActive => query.trim().isNotEmpty || type != 'all' || advancedCount > 0;

  /// copyWith only overrides scalar fields (query/type). Advanced nullable
  /// fields are preserved — to change them, build a fresh instance (the filter
  /// sheet does exactly that so it can also clear them).
  TransactionFilters copyWith({String? query, String? type}) {
    return TransactionFilters(
      query: query ?? this.query,
      type: type ?? this.type,
      category: category,
      from: from,
      to: to,
      minAmount: minAmount,
      maxAmount: maxAmount,
      walletId: walletId,
    );
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toQueryParams() {
    final p = <String, dynamic>{};
    if (query.trim().isNotEmpty) p['q'] = query.trim();
    if (type == 'income' || type == 'expense') p['type'] = type;
    if (category != null && category!.trim().isNotEmpty) p['category'] = category!.trim();
    if (from != null) p['from'] = _isoDate(from!);
    if (to != null) p['to'] = _isoDate(to!);
    if (minAmount != null) p['minAmount'] = minAmount;
    if (maxAmount != null) p['maxAmount'] = maxAmount;
    if (walletId != null) p['wallet_id'] = walletId;
    return p;
  }
}

class TransactionsState {
  final List<TransactionModel> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final TransactionFilters filters;
  final int pendingSyncCount;

  const TransactionsState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.filters = const TransactionFilters(),
    this.pendingSyncCount = 0,
  });

  TransactionsState copyWith({
    List<TransactionModel>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    TransactionFilters? filters,
    int? pendingSyncCount,
  }) {
    return TransactionsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      filters: filters ?? this.filters,
      pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
    );
  }
}

/// Drives the transactions list screen. Subscribes to the backend's
/// `tx:new` / `tx:updated` / `tx:deleted` socket events (emitted from
/// transactionsController.ts) so other devices' edits show up live.
class TransactionsController extends Notifier<TransactionsState> {
  static const _pageSize = 30;

  int _opSeq = 0;

  @override
  TransactionsState build() {
    _attachSocketListeners();
    // Flush the offline queue whenever the realtime link (re)connects.
    ref.listen(socketStatusProvider, (prev, next) {
      if (next == SocketStatus.connected) {
        flushOutbox();
      }
    });
    Future.microtask(() async {
      await _hydrateFromCache();
      await refresh();
      await _loadPendingCount();
      await flushOutbox();
    });
    return const TransactionsState();
  }

  String get _cacheKey => 'transactions_${_userIdOrNull ?? 'anon'}';

  /// Shows the last successfully fetched page instantly (and offline) while
  /// the network refresh runs. Skipped if a fetch already landed.
  Future<void> _hydrateFromCache() async {
    final cached = await LocalCache.instance.readList(_cacheKey);
    if (cached == null || state.items.isNotEmpty) return;
    try {
      final items = cached.map(TransactionModel.fromJson).toList();
      if (state.items.isEmpty) {
        state = state.copyWith(items: items, isLoading: false);
      }
    } catch (_) {
      // Corrupt cache — ignore; the network refresh will overwrite it.
    }
  }

  void _attachSocketListeners() {
    final subs = [
      SocketService.instance.on('tx:new', (_) => refresh()),
      SocketService.instance.on('tx:updated', (_) => refresh()),
      SocketService.instance.on('tx:deleted', (_) => refresh()),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
  }

  String? get _userIdOrNull => ref.read(authControllerProvider).userId;

  Future<void> _loadPendingCount() async {
    final userId = _userIdOrNull;
    if (userId == null) return;
    final count = await OutboxService.instance.countForUser(userId);
    state = state.copyWith(pendingSyncCount: count);
  }

  String _newOpId(String userId) =>
      '$userId-${DateTime.now().microsecondsSinceEpoch}-${_opSeq++}';

  /// Builds an optimistic clone of [t] with the given local (negative) id so it
  /// renders immediately while the real create is queued for sync.
  TransactionModel _cloneWithId(TransactionModel t, int id, String userId) => TransactionModel(
        id: id,
        userId: userId,
        title: t.title,
        amount: t.amount,
        currency: t.currency,
        category: t.category,
        createdAt: t.createdAt,
        notes: t.notes,
        receiptUrl: t.receiptUrl,
        tags: t.tags,
        splits: t.splits,
      );

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final userId = ref.read(currentUserIdProvider);
      final result = await ref
          .read(transactionRepositoryProvider)
          .list(userId: userId, limit: _pageSize, offset: 0, filters: state.filters);
      state = state.copyWith(
        items: result.items,
        isLoading: false,
        hasMore: result.page.hasMore,
      );
      // Only the unfiltered first page is representative enough to cache for
      // offline hydration.
      if (!state.filters.isActive) {
        await LocalCache.instance.write(
          _cacheKey,
          result.items.map((t) => t.toCacheJson()).toList(),
        );
      }
    } catch (e) {
      // Offline with cached data already showing → keep it, no error banner.
      final offline = e is ApiException && e.isNetworkError;
      state = state.copyWith(
        isLoading: false,
        error: offline && state.items.isNotEmpty ? null : e.toString(),
      );
    }
  }

  /// Replaces the active filter set and reloads from the first page. All list
  /// filtering is server-side, so the whole history is searched — not just the
  /// pages already loaded.
  Future<void> setFilters(TransactionFilters filters) async {
    state = state.copyWith(filters: filters);
    await refresh();
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final userId = ref.read(currentUserIdProvider);
      final result = await ref.read(transactionRepositoryProvider).list(
            userId: userId,
            limit: _pageSize,
            offset: state.items.length,
            filters: state.filters,
          );
      state = state.copyWith(
        items: [...state.items, ...result.items],
        isLoadingMore: false,
        hasMore: result.page.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  Future<void> create(TransactionModel transaction) async {
    final userId = _userIdOrNull ?? '';
    final opId = _newOpId(userId);
    // Every create carries a stable idempotency key so that a lost response
    // (timeout after the server already saved it) doesn't create a duplicate
    // when the op is later replayed from the outbox.
    final body = {...transaction.toRequestJson(), 'client_op_id': opId};
    try {
      final created = await ref.read(transactionRepositoryProvider).createRaw(body);
      state = state.copyWith(items: [created, ...state.items]);
    } on ApiException catch (e) {
      if (!e.isNetworkError) rethrow;
      // Offline: queue for sync and show an optimistic entry immediately.
      await OutboxService.instance.add(OutboxOp(
        opId: opId,
        userId: userId,
        type: 'create',
        body: body,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      final optimistic = _cloneWithId(transaction, -DateTime.now().millisecondsSinceEpoch, userId);
      state = state.copyWith(
        items: [optimistic, ...state.items],
        pendingSyncCount: state.pendingSyncCount + 1,
      );
    }
  }

  Future<void> update(int id, TransactionModel transaction) async {
    final userId = _userIdOrNull ?? '';
    try {
      final updated = await ref.read(transactionRepositoryProvider).update(id, transaction);
      state = state.copyWith(
        items: [for (final t in state.items) if (t.id == id) updated else t],
      );
    } on ApiException catch (e) {
      if (!e.isNetworkError) rethrow;
      // Editing an optimistic (not-yet-synced) create: patch its queued create
      // op in place instead of queueing an update for a server id that doesn't
      // exist yet.
      if (id < 0) {
        await _patchQueuedCreate(id, transaction, userId);
        return;
      }
      await OutboxService.instance.add(OutboxOp(
        opId: _newOpId(userId),
        userId: userId,
        entity: 'transaction',
        type: 'update',
        body: {...transaction.toRequestJson(), 'id': id},
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      // Optimistic local edit so the list reflects the change immediately.
      final optimistic = _cloneWithId(transaction, id, userId);
      state = state.copyWith(
        items: [for (final t in state.items) if (t.id == id) optimistic else t],
        pendingSyncCount: state.pendingSyncCount + 1,
      );
    }
  }

  /// Offline edit of an offline-created row: rewrite the pending create op's
  /// body (keeping its idempotency key) rather than queueing an update.
  Future<void> _patchQueuedCreate(int localId, TransactionModel transaction, String userId) async {
    final ops = await OutboxService.instance.opsForUser(userId);
    // The optimistic local id isn't stored in the op, so match the newest
    // pending create — creates are FIFO and local edits target the latest.
    final create = ops.lastWhere(
      (o) => o.entity == 'transaction' && o.type == 'create',
      orElse: () => const OutboxOp(opId: '', userId: '', type: '', body: {}, createdAt: 0),
    );
    if (create.opId.isEmpty) return;
    await OutboxService.instance.remove(create.opId);
    await OutboxService.instance.add(OutboxOp(
      opId: create.opId, // keep the same idempotency key
      userId: userId,
      entity: 'transaction',
      type: 'create',
      body: {...transaction.toRequestJson(), 'client_op_id': create.body['client_op_id']},
      createdAt: create.createdAt,
    ));
    final optimistic = _cloneWithId(transaction, localId, userId);
    state = state.copyWith(
      items: [for (final t in state.items) if (t.id == localId) optimistic else t],
    );
  }

  Future<void> delete(int id) async {
    // A negative id is an optimistic, not-yet-synced create — just drop it from
    // the queue and the list; nothing exists server-side to delete.
    if (id < 0) {
      state = state.copyWith(items: state.items.where((t) => t.id != id).toList());
      return;
    }
    final userId = _userIdOrNull ?? '';
    try {
      await ref.read(transactionRepositoryProvider).delete(id);
      state = state.copyWith(items: state.items.where((t) => t.id != id).toList());
    } on ApiException catch (e) {
      if (!e.isNetworkError) rethrow;
      await OutboxService.instance.add(OutboxOp(
        opId: _newOpId(userId),
        userId: userId,
        type: 'delete',
        body: {'id': id},
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      // Optimistically remove; the delete will replay on reconnect.
      state = state.copyWith(
        items: state.items.where((t) => t.id != id).toList(),
        pendingSyncCount: state.pendingSyncCount + 1,
      );
    }
  }

  /// Replays every queued offline write for the current user, oldest first.
  /// Stops on the first network failure (still offline) and leaves the rest
  /// queued. Idempotency keys make re-running a partially-applied op safe.
  Future<void> flushOutbox() async {
    final userId = _userIdOrNull;
    if (userId == null) return;
    final ops = await OutboxService.instance.opsForUser(userId);
    if (ops.isEmpty) {
      if (state.pendingSyncCount != 0) state = state.copyWith(pendingSyncCount: 0);
      return;
    }

    var flushedAny = false;
    for (final op in ops) {
      try {
        await _replayOp(op);
        await OutboxService.instance.remove(op.opId);
        flushedAny = true;
      } on ApiException catch (e) {
        if (e.isNetworkError) break; // still offline — retry later
        // A non-network failure (e.g. the row was already deleted, 404): drop
        // the op so it doesn't wedge the queue forever.
        await OutboxService.instance.remove(op.opId);
        flushedAny = true;
      }
    }

    await _loadPendingCount();
    if (flushedAny) {
      await refresh();
      // Other offline-capable entities re-pull their lists after a flush too.
      ref.invalidate(debtsControllerProvider);
    }
  }

  Future<void> bulkDelete(List<int> ids) async {
    await ref.read(transactionRepositoryProvider).bulkDelete(ids);
    state = state.copyWith(items: state.items.where((t) => !ids.contains(t.id)).toList());
  }

  /// Replays one queued op against the right repository. New offline-capable
  /// entities (debts, goal contributions) register their branch here.
  Future<void> _replayOp(OutboxOp op) async {
    switch (op.entity) {
      case 'transaction':
        final repo = ref.read(transactionRepositoryProvider);
        switch (op.type) {
          case 'create':
            await repo.createRaw(op.body);
          case 'update':
            final body = Map<String, dynamic>.of(op.body)..remove('id');
            await repo.updateRaw((op.body['id'] as num).toInt(), body);
          case 'delete':
            await repo.delete((op.body['id'] as num).toInt());
        }
      case 'debt':
        final repo = ref.read(debtRepositoryProvider);
        switch (op.type) {
          case 'create':
            await repo.createRaw(op.body);
          case 'update': // settle (idempotent)
            await repo.settle((op.body['id'] as num).toInt());
          case 'delete':
            await repo.delete((op.body['id'] as num).toInt());
        }
      default:
        // Unknown entity (op written by a newer app version?) — drop it rather
        // than wedge the queue.
        return;
    }
  }

  /// Returns the CSV text for the transactions matching the active filters.
  Future<String> exportCsv() {
    final userId = ref.read(currentUserIdProvider);
    return ref
        .read(transactionRepositoryProvider)
        .exportCsv(userId: userId, filters: state.filters);
  }
}

final transactionsControllerProvider =
    NotifierProvider<TransactionsController, TransactionsState>(TransactionsController.new);

/// Income/expense/balance summary card on the dashboard. Re-fetches whenever
/// the transactions list changes via socket events too.
final transactionSummaryProvider = FutureProvider.autoDispose<TransactionSummary>((ref) async {
  ref.watch(transactionsControllerProvider); // re-run when list refreshes
  final userId = ref.read(currentUserIdProvider);
  final summary = await ref.read(transactionRepositoryProvider).summary(userId);
  // Keep the Android home-screen widget in sync (best-effort, fire & forget).
  unawaited(HomeWidgetService.update(summary));
  return summary;
});

/// UNFILTERED recent transactions for the dashboard (chart, top categories,
/// recent list). Deliberately separate from [transactionsControllerProvider]:
/// that controller carries the Transactions screen's server-side filters
/// (search, date/category/wallet, heatmap day-taps), which must never bleed
/// into the dashboard's charts.
final dashboardTransactionsProvider =
    FutureProvider.autoDispose<List<TransactionModel>>((ref) async {
  final subs = [
    SocketService.instance.on('tx:new', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:updated', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:deleted', (_) => ref.invalidateSelf()),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });

  final userId = ref.watch(authControllerProvider).userId;
  if (userId == null) return const [];
  final cacheKey = 'dashboard_tx_$userId';
  try {
    // 200 most-recent rows comfortably covers the 6-month balance chart.
    final result = await ref
        .read(transactionRepositoryProvider)
        .list(userId: userId, limit: 200, offset: 0);
    await LocalCache.instance.write(
      cacheKey,
      result.items.map((t) => t.toCacheJson()).toList(),
    );
    return result.items;
  } on ApiException catch (e) {
    // Offline → serve the last-known dashboard data instead of an error.
    if (e.isNetworkError) {
      final cached = await LocalCache.instance.readList(cacheKey);
      if (cached != null) {
        return cached.map(TransactionModel.fromJson).toList();
      }
    }
    rethrow;
  }
});
