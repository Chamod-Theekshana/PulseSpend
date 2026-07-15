import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/recurring_model.dart';
import 'repository_providers.dart';

class RecurringState {
  final List<RecurringModel> items;
  final bool isLoading;
  final String? error;

  const RecurringState({this.items = const [], this.isLoading = false, this.error});

  RecurringState copyWith({List<RecurringModel>? items, bool? isLoading, String? error}) {
    return RecurringState(items: items ?? this.items, isLoading: isLoading ?? this.isLoading, error: error);
  }
}

class RecurringController extends Notifier<RecurringState> {
  @override
  RecurringState build() {
    final subs = [
      SocketService.instance.on('recurring:created', (_) => refresh()),
      SocketService.instance.on('recurring:deleted', (_) => refresh()),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    Future.microtask(refresh);
    return const RecurringState();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await ref.read(recurringRepositoryProvider).list();
      state = state.copyWith(items: result.items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> create(RecurringModel rule) async {
    final created = await ref.read(recurringRepositoryProvider).create(rule);
    state = state.copyWith(items: [...state.items, created]);
  }

  Future<void> update(int id, RecurringModel rule) async {
    final updated = await ref.read(recurringRepositoryProvider).update(id, rule);
    state = state.copyWith(items: [for (final r in state.items) if (r.id == id) updated else r]);
  }

  Future<void> toggleActive(int id, bool isActive) async {
    final updated = await ref.read(recurringRepositoryProvider).toggleActive(id, isActive);
    state = state.copyWith(items: [for (final r in state.items) if (r.id == id) updated else r]);
  }

  Future<void> delete(int id) async {
    await ref.read(recurringRepositoryProvider).delete(id);
    state = state.copyWith(items: state.items.where((r) => r.id != id).toList());
  }
}

final recurringControllerProvider =
    NotifierProvider<RecurringController, RecurringState>(RecurringController.new);

/// Subscription-like series detected from real history (badges on the
/// Recurring screen). Refreshes when transactions change.
final detectedSubscriptionsProvider =
    FutureProvider.autoDispose<List<DetectedSubscription>>((ref) async {
  final sub = SocketService.instance.on('tx:new', (_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return ref.read(recurringRepositoryProvider).detected();
});
