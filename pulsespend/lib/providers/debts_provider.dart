import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/api_exception.dart';
import '../core/network/socket_service.dart';
import '../core/storage/local_cache.dart';
import '../core/storage/outbox_service.dart';
import '../models/debt_model.dart';
import 'auth_provider.dart';
import 'repository_providers.dart';
import 'transactions_provider.dart';
import 'wallets_provider.dart';

class DebtsState {
  final List<DebtModel> items;
  final bool isLoading;
  final String? error;

  const DebtsState({this.items = const [], this.isLoading = false, this.error});

  DebtsState copyWith({List<DebtModel>? items, bool? isLoading, String? error}) {
    return DebtsState(items: items ?? this.items, isLoading: isLoading ?? this.isLoading, error: error);
  }

  List<DebtModel> get open => items.where((d) => d.isOpen).toList();
  List<DebtModel> get owedToMe => open.where((d) => d.owedToMe).toList();
  List<DebtModel> get iOwe => open.where((d) => !d.owedToMe).toList();

  /// Net position across open IOUs, ignoring currency differences (a display
  /// heuristic — most users track debts in one currency).
  double get net =>
      owedToMe.fold<double>(0, (a, d) => a + d.amount) -
      iOwe.fold<double>(0, (a, d) => a + d.amount);
}

/// Drives the 1:1 IOUs list. Offline-first: creates/settles queue in the
/// shared outbox (entity 'debt', replayed by TransactionsController.flushOutbox)
/// and the last fetch is cached for offline reads.
class DebtsController extends Notifier<DebtsState> {
  int _opSeq = 0;
  int _localSeq = 0;

  @override
  DebtsState build() {
    final sub = SocketService.instance.on('debt:changed', (_) => refresh());
    ref.onDispose(sub.cancel);
    Future.microtask(() async {
      await _hydrateFromCache();
      await refresh();
    });
    return const DebtsState(isLoading: true);
  }

  String? get _userId => ref.read(authControllerProvider).userId;
  String get _cacheKey => 'debts_${_userId ?? 'anon'}';

  Future<void> _hydrateFromCache() async {
    final cached = await LocalCache.instance.readList(_cacheKey);
    if (cached == null || state.items.isNotEmpty) return;
    try {
      state = state.copyWith(
        items: cached.map(DebtModel.fromJson).toList(),
        isLoading: false,
      );
    } catch (_) {}
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await ref.read(debtRepositoryProvider).list();
      state = state.copyWith(items: items, isLoading: false);
      await LocalCache.instance.write(_cacheKey, items.map((d) => d.toCacheJson()).toList());
    } catch (e) {
      final offline = e is ApiException && e.isNetworkError;
      state = state.copyWith(
        isLoading: false,
        error: offline && state.items.isNotEmpty ? null : e.toString(),
      );
    }
  }

  Future<void> create({
    required String counterpartyName,
    required double amount,
    required String currency,
    required String direction,
    String? note,
  }) async {
    final userId = _userId ?? '';
    final opId = 'debt-$userId-${DateTime.now().microsecondsSinceEpoch}-${_opSeq++}';
    final body = {
      'counterparty_name': counterpartyName,
      'amount': amount,
      'currency': currency,
      'direction': direction,
      if (note != null && note.isNotEmpty) 'note': note,
      'client_op_id': opId,
    };
    try {
      final created = await ref.read(debtRepositoryProvider).createRaw(body);
      state = state.copyWith(items: [created, ...state.items]);
      // An open IOU is a receivable/payable — net worth counts it immediately.
      ref.invalidate(netWorthProvider);
    } on ApiException catch (e) {
      if (!e.isNetworkError) rethrow;
      await OutboxService.instance.add(OutboxOp(
        opId: opId,
        userId: userId,
        entity: 'debt',
        type: 'create',
        body: body,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      // Optimistic local entry (negative id = not yet synced).
      final optimistic = DebtModel(
        id: -(++_localSeq + DateTime.now().millisecondsSinceEpoch),
        counterpartyName: counterpartyName,
        amount: amount,
        currency: currency,
        direction: direction,
        note: note,
        createdAt: DateTime.now(),
      );
      state = state.copyWith(items: [optimistic, ...state.items]);
    }
  }

  Future<void> settle(int id, {int? walletId}) async {
    if (id < 0) {
      // Not yet synced — just drop the optimistic row and its queued create.
      state = state.copyWith(items: state.items.where((d) => d.id != id).toList());
      return;
    }
    final userId = _userId ?? '';
    try {
      final settled = await ref.read(debtRepositoryProvider).settle(id, walletId: walletId);
      state = state.copyWith(
        items: [for (final d in state.items) if (d.id == id) settled else d],
      );
      // Settling moves real money (wallet leg) and always moves net worth (the
      // open receivable/payable disappears). The headline is money on hand, so
      // it moves too whenever a wallet was involved.
      ref.invalidate(netWorthProvider);
      if (walletId != null) {
        ref.invalidate(walletBalancesProvider);
        ref.invalidate(transactionSummaryProvider);
      }
    } on ApiException catch (e) {
      if (!e.isNetworkError) rethrow;
      await OutboxService.instance.add(OutboxOp(
        opId: 'debt-settle-$userId-$id',
        userId: userId,
        entity: 'debt',
        type: 'update', // settle — idempotent server-side
        body: {'id': id, if (walletId != null) 'wallet_id': walletId},
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      state = state.copyWith(
        items: [
          for (final d in state.items)
            if (d.id == id)
              DebtModel(
                id: d.id,
                counterpartyName: d.counterpartyName,
                amount: d.amount,
                currency: d.currency,
                direction: d.direction,
                note: d.note,
                status: 'settled',
                createdAt: d.createdAt,
                settledAt: DateTime.now(),
              )
            else
              d,
        ],
      );
    }
  }

  Future<void> delete(int id) async {
    if (id < 0) {
      state = state.copyWith(items: state.items.where((d) => d.id != id).toList());
      return;
    }
    await ref.read(debtRepositoryProvider).delete(id);
    state = state.copyWith(items: state.items.where((d) => d.id != id).toList());
  }
}

final debtsControllerProvider =
    NotifierProvider<DebtsController, DebtsState>(DebtsController.new);
