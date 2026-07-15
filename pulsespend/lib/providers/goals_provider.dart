import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/goal_model.dart';
import 'repository_providers.dart';

class GoalsState {
  final List<GoalModel> items;
  final bool isLoading;
  final String? error;

  const GoalsState({this.items = const [], this.isLoading = false, this.error});

  GoalsState copyWith({List<GoalModel>? items, bool? isLoading, String? error}) {
    return GoalsState(items: items ?? this.items, isLoading: isLoading ?? this.isLoading, error: error);
  }

  List<GoalModel> get active => items.where((g) => !g.isCompleted).toList();
  List<GoalModel> get completed => items.where((g) => g.isCompleted).toList();
}

class GoalsController extends Notifier<GoalsState> {
  @override
  GoalsState build() {
    // Live sync across devices for every goal change.
    final subs = [
      for (final event in const [
        'goal:created',
        'goal:updated',
        'goal:deleted',
        'goal:completed',
      ])
        SocketService.instance.on(event, (_) => refresh()),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    Future.microtask(refresh);
    return const GoalsState();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await ref.read(goalRepositoryProvider).list();
      state = state.copyWith(items: result.items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> create(GoalModel goal) async {
    final created = await ref.read(goalRepositoryProvider).create(goal);
    state = state.copyWith(items: [created, ...state.items]);
  }

  Future<void> update(int id, GoalModel goal) async {
    final updated = await ref.read(goalRepositoryProvider).update(id, goal);
    state = state.copyWith(items: [for (final g in state.items) if (g.id == id) updated else g]);
  }

  /// Returns a non-null warning string if FX conversion failed server-side.
  Future<String?> contribute({required int id, required double amount, required String currency}) async {
    final result = await ref.read(goalRepositoryProvider).contribute(id: id, amount: amount, currency: currency);
    state = state.copyWith(items: [for (final g in state.items) if (g.id == id) result.goal else g]);
    return result.warning;
  }

  /// Set or clear (amount == null) the monthly auto-contribution rule.
  Future<void> setAutoRule(int id, {double? amount, int? day}) async {
    final goal = await ref.read(goalRepositoryProvider).setAutoRule(id, amount: amount, day: day);
    state = state.copyWith(items: [for (final g in state.items) if (g.id == id) goal else g]);
  }

  Future<void> delete(int id) async {
    await ref.read(goalRepositoryProvider).delete(id);
    state = state.copyWith(items: state.items.where((g) => g.id != id).toList());
  }
}

final goalsControllerProvider = NotifierProvider<GoalsController, GoalsState>(GoalsController.new);

/// Deposit/withdrawal timeline for one goal (the detail sheet).
final goalContributionsProvider =
    FutureProvider.autoDispose.family<List<GoalContribution>, int>((ref, goalId) async {
  return ref.read(goalRepositoryProvider).contributions(goalId);
});
