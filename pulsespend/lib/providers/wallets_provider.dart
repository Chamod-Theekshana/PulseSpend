import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/transaction_model.dart';
import '../models/wallet_model.dart';
import 'auth_provider.dart';
import 'repository_providers.dart';
import 'transactions_provider.dart';

class WalletsState {
  final List<WalletModel> items;
  final bool isLoading;
  final String? error;

  const WalletsState({this.items = const [], this.isLoading = false, this.error});

  WalletsState copyWith({List<WalletModel>? items, bool? isLoading, String? error}) {
    return WalletsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class WalletsController extends Notifier<WalletsState> {
  @override
  WalletsState build() {
    final sub = SocketService.instance.on('wallet:changed', (_) => refresh());
    ref.onDispose(sub.cancel);
    Future.microtask(refresh);
    return const WalletsState(isLoading: true);
  }

  
  void seed(List<WalletModel> data) {
    state = state.copyWith(items: data, isLoading: false, error: null);
  }

Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await ref.read(walletRepositoryProvider).list();
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> create({
    required String name,
    required String type,
    required String currency,
    double? openingBalance,
    int? drawdownWalletId,
    double? creditLimit,
  }) async {
    await ref.read(walletRepositoryProvider).create(
          name: name,
          type: type,
          currency: currency,
          openingBalance: openingBalance,
          drawdownWalletId: drawdownWalletId,
          creditLimit: creditLimit,
        );
    await refresh();
    ref.invalidate(walletBalancesProvider);
    // An opening balance seeds a transaction, so net worth and the dashboard's
    // money-on-hand headline both move.
    ref.invalidate(netWorthProvider);
    ref.invalidate(transactionSummaryProvider);
  }

  /// Corrects the wallet's create-time opening balance by replacing its seed.
  Future<void> correctOpeningBalance(
    int id, {
    required double openingBalance,
    int? drawdownWalletId,
  }) async {
    await ref.read(walletRepositoryProvider).correctOpeningBalance(
          id,
          openingBalance: openingBalance,
          drawdownWalletId: drawdownWalletId,
        );
    await refresh();
    ref.invalidate(walletBalancesProvider);
    ref.invalidate(netWorthProvider);
    ref.invalidate(transactionSummaryProvider);
  }

  Future<void> update(
    int id, {
    String? name,
    String? type,
    String? currency,
    bool setCreditLimit = false,
    double? creditLimit,
  }) async {
    await ref.read(walletRepositoryProvider).update(
          id,
          name: name,
          type: type,
          currency: currency,
          setCreditLimit: setCreditLimit,
          creditLimit: creditLimit,
        );
    await refresh();
    ref.invalidate(walletBalancesProvider);
  }

  Future<void> delete(int id) async {
    await ref.read(walletRepositoryProvider).delete(id);
    state = state.copyWith(items: state.items.where((w) => w.id != id).toList());
    ref.invalidate(walletBalancesProvider);
  }
}

final walletsControllerProvider =
    NotifierProvider<WalletsController, WalletsState>(WalletsController.new);

/// Assets − liabilities snapshot for the dashboard. Same refresh triggers as
/// the balances (wallet + transaction events).
final netWorthProvider = FutureProvider.autoDispose<NetWorth>((ref) async {
  final subs = [
    SocketService.instance.on('wallet:changed', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:new', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:updated', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:deleted', (_) => ref.invalidateSelf()),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });
  return ref.read(walletRepositoryProvider).netWorth();
});

/// Recent transactions for one wallet (id 0 = the default bucket), for the
/// wallet detail screen. Deliberately separate from the global transactions
/// controller so opening a wallet doesn't leave the Transactions tab filtered.
final walletTransactionsProvider =
    FutureProvider.autoDispose.family<List<TransactionModel>, int>((ref, walletId) async {
  final subs = [
    SocketService.instance.on('tx:new', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:updated', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:deleted', (_) => ref.invalidateSelf()),
    // Goal funding, IOU legs and payoffs write rows announced only via
    // wallet:changed — without this the header balance updated while the list
    // below it kept missing the newest row.
    SocketService.instance.on('wallet:changed', (_) => ref.invalidateSelf()),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });
  final res = await ref.read(transactionRepositoryProvider).list(
        userId: ref.read(currentUserIdProvider),
        limit: 30,
        filters: TransactionFilters(walletId: walletId),
      );
  return res.items;
});

/// Month-end money on hand for the dashboard's 6-month chart. Server-computed
/// on the same basis as the headline, so the last point equals it.
final balanceHistoryProvider =
    FutureProvider.autoDispose<List<BalanceHistoryPoint>>((ref) async {
  final subs = [
    SocketService.instance.on('wallet:changed', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:new', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:updated', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:deleted', (_) => ref.invalidateSelf()),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });
  return ref.read(walletRepositoryProvider).balanceHistory();
});

/// Per-wallet balances for the dashboard cards. Refreshes when transactions or
/// wallets change (socket events fire for both).
final walletBalancesProvider = FutureProvider.autoDispose<List<WalletBalance>>((ref) async {
  final subs = [
    SocketService.instance.on('wallet:changed', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:new', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:updated', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:deleted', (_) => ref.invalidateSelf()),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });
  return ref.read(walletRepositoryProvider).balances();
});
