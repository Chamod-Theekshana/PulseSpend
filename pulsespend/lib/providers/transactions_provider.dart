import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';
import 'repository_providers.dart';

class TransactionsState {
  final List<TransactionModel> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  const TransactionsState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  TransactionsState copyWith({
    List<TransactionModel>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
  }) {
    return TransactionsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

/// Drives the transactions list screen. Subscribes to the backend's
/// `tx:new` / `tx:updated` / `tx:deleted` socket events (emitted from
/// transactionsController.ts) so other devices' edits show up live.
class TransactionsController extends Notifier<TransactionsState> {
  static const _pageSize = 30;

  @override
  TransactionsState build() {
    _attachSocketListeners();
    Future.microtask(refresh);
    return const TransactionsState();
  }

  void _attachSocketListeners() {
    SocketService.instance.on('tx:new', (_) => refresh());
    SocketService.instance.on('tx:updated', (_) => refresh());
    SocketService.instance.on('tx:deleted', (_) => refresh());
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final userId = ref.read(currentUserIdProvider);
      final result = await ref
          .read(transactionRepositoryProvider)
          .list(userId: userId, limit: _pageSize, offset: 0);
      state = state.copyWith(
        items: result.items,
        isLoading: false,
        hasMore: result.page.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
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
    final created = await ref.read(transactionRepositoryProvider).create(transaction);
    state = state.copyWith(items: [created, ...state.items]);
  }

  Future<void> update(int id, TransactionModel transaction) async {
    final updated = await ref.read(transactionRepositoryProvider).update(id, transaction);
    state = state.copyWith(
      items: [for (final t in state.items) if (t.id == id) updated else t],
    );
  }

  Future<void> delete(int id) async {
    await ref.read(transactionRepositoryProvider).delete(id);
    state = state.copyWith(items: state.items.where((t) => t.id != id).toList());
  }

  Future<void> bulkDelete(List<int> ids) async {
    await ref.read(transactionRepositoryProvider).bulkDelete(ids);
    state = state.copyWith(items: state.items.where((t) => !ids.contains(t.id)).toList());
  }
}

final transactionsControllerProvider =
    NotifierProvider<TransactionsController, TransactionsState>(TransactionsController.new);

/// Income/expense/balance summary card on the dashboard. Re-fetches whenever
/// the transactions list changes via socket events too.
final transactionSummaryProvider = FutureProvider.autoDispose<TransactionSummary>((ref) async {
  ref.watch(transactionsControllerProvider); // re-run when list refreshes
  final userId = ref.read(currentUserIdProvider);
  return ref.read(transactionRepositoryProvider).summary(userId);
});
