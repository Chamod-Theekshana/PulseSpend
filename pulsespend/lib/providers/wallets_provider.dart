import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/wallet_model.dart';
import 'repository_providers.dart';

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

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await ref.read(walletRepositoryProvider).list();
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> create({required String name, required String type, required String currency}) async {
    await ref.read(walletRepositoryProvider).create(name: name, type: type, currency: currency);
    await refresh();
    ref.invalidate(walletBalancesProvider);
  }

  Future<void> update(int id, {String? name, String? type, String? currency}) async {
    await ref.read(walletRepositoryProvider).update(id, name: name, type: type, currency: currency);
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
