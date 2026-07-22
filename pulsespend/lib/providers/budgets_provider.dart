import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/budget_model.dart';
import 'repository_providers.dart';

class BudgetsState {
  final List<BudgetModel> items;
  final bool isLoading;
  final String? error;
  /// Most recent live alert pushed via socket (budget:alert) — surfaced as
  /// a transient banner/snackbar by the UI, then cleared.
  final BudgetAlert? latestAlert;

  const BudgetsState({this.items = const [], this.isLoading = false, this.error, this.latestAlert});

  BudgetsState copyWith({
    List<BudgetModel>? items,
    bool? isLoading,
    String? error,
    BudgetAlert? latestAlert,
    bool clearAlert = false,
  }) {
    return BudgetsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      latestAlert: clearAlert ? null : (latestAlert ?? this.latestAlert),
    );
  }
}

class BudgetAlert {
  final String category;
  final int percentage;
  final double spent;
  final double limit;
  final String level; // 'warning' | 'exceeded'

  const BudgetAlert({
    required this.category,
    required this.percentage,
    required this.spent,
    required this.limit,
    required this.level,
  });

  factory BudgetAlert.fromSocket(Map<String, dynamic> json) {
    return BudgetAlert(
      category: json['category'] as String,
      percentage: int.parse(json['percentage'].toString()),
      spent: double.parse(json['spent'].toString()),
      limit: double.parse(json['limit'].toString()),
      level: json['level'] as String,
    );
  }
}

/// Drives the budgets screen using the enriched `/status` endpoint (spent,
/// percentage, remaining) and listens for `budget:alert` pushed in real time
/// whenever a new transaction crosses the 80%/100% threshold server-side.
class BudgetsController extends Notifier<BudgetsState> {
  @override
  BudgetsState build() {
    _attachSocketListeners();
    Future.microtask(refresh);
    return const BudgetsState();
  }

  void _attachSocketListeners() {
    final subs = [
      SocketService.instance.on('budget:alert', (data) {
        if (data is Map<String, dynamic>) {
          state = state.copyWith(latestAlert: BudgetAlert.fromSocket(data));
        }
        refresh();
      }),
      SocketService.instance.on('budget:created', (_) => refresh()),
      SocketService.instance.on('budget:updated', (_) => refresh()),
      SocketService.instance.on('budget:deleted', (_) => refresh()),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
  }

  void dismissAlert() => state = state.copyWith(clearAlert: true);

  void seed(List<BudgetModel> items) {
    state = state.copyWith(items: items, isLoading: false, error: null);
  }

  Future<void> refresh({int? year, int? month, int? day}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await ref.read(budgetRepositoryProvider).status(year: year, month: month, day: day);
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> create(BudgetModel budget) async {
    await ref.read(budgetRepositoryProvider).create(budget);
    await refresh();
  }

  Future<void> updateAmount(int id, double amount) async {
    await ref.read(budgetRepositoryProvider).updateAmount(id, amount);
    await refresh();
  }

  Future<void> delete(int id) async {
    await ref.read(budgetRepositoryProvider).delete(id);
    state = state.copyWith(items: state.items.where((b) => b.id != id).toList());
  }
}

final budgetsControllerProvider = NotifierProvider<BudgetsController, BudgetsState>(BudgetsController.new);

/// Overall monthly budget cap vs actual. Re-fetches when budgets or
/// transactions change so the master ring stays live.
final totalBudgetStatusProvider = FutureProvider.autoDispose<TotalBudgetStatus>((ref) async {
  final subs = [
    SocketService.instance.on('budget:updated', (_) => ref.invalidateSelf()),
    SocketService.instance.on('budget:created', (_) => ref.invalidateSelf()),
    SocketService.instance.on('budget:deleted', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:new', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:updated', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:deleted', (_) => ref.invalidateSelf()),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });
  return ref.read(budgetRepositoryProvider).totalStatus();
});
