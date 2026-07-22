import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/goal_model.dart';
import '../models/group_model.dart';
import 'repository_providers.dart';

/// Subscribes a group family provider to `group:changed` for [groupId] so it
/// refreshes live when any member shares an expense, settles, joins, or is
/// removed — the group paths had no realtime before this.
void _onGroupChanged(Ref ref, int groupId) {
  final sub = SocketService.instance.on('group:changed', (data) {
    final changed = data is Map ? int.tryParse('${data['groupId']}') : null;
    if (changed == groupId) ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
}

class GroupsState {
  final List<GroupModel> items;
  final bool isLoading;
  final String? error;

  const GroupsState({this.items = const [], this.isLoading = false, this.error});

  GroupsState copyWith({List<GroupModel>? items, bool? isLoading, String? error}) {
    return GroupsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class GroupsController extends Notifier<GroupsState> {
  @override
  GroupsState build() {
    final sub = SocketService.instance.on('group:changed', (_) => refresh());
    ref.onDispose(sub.cancel);
    Future.microtask(refresh);
    return const GroupsState(isLoading: true);
  }

  
  void seed(List<GroupModel> data) {
    state = state.copyWith(items: data, isLoading: false, error: null);
  }

Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await ref.read(groupRepositoryProvider).list();
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<GroupModel> create(String name) async {
    final group = await ref.read(groupRepositoryProvider).create(name);
    await refresh();
    return group;
  }

  Future<GroupModel> join(String inviteCode) async {
    final group = await ref.read(groupRepositoryProvider).join(inviteCode);
    await refresh();
    return group;
  }

  Future<void> leave(int groupId) async {
    await ref.read(groupRepositoryProvider).leave(groupId);
    state = state.copyWith(items: state.items.where((g) => g.id != groupId).toList());
  }

  Future<String> exportCsv(int groupId) async {
    return await ref.read(groupRepositoryProvider).exportCsv(groupId);
  }

  Future<List<int>> exportPdf(int groupId) async {
    return await ref.read(groupRepositoryProvider).exportPdf(groupId);
  }

  Future<void> rename(int groupId, String name) async {
    await ref.read(groupRepositoryProvider).rename(groupId, name);
    await refresh();
  }

  Future<void> transferOwnership(int groupId, String newOwnerId) async {
    await ref.read(groupRepositoryProvider).transferOwnership(groupId, newOwnerId);
    await refresh();
    ref.invalidate(groupMembersProvider(groupId));
  }

  Future<void> removeMember(int groupId, String userId) async {
    await ref.read(groupRepositoryProvider).removeMember(groupId, userId);
    ref.invalidate(groupMembersProvider(groupId));
    ref.invalidate(groupBalancesProvider(groupId));
  }

  Future<void> undoSettlement(int groupId, int settlementId) async {
    await ref.read(groupRepositoryProvider).undoSettlement(groupId, settlementId);
    ref.invalidate(groupSettlementsProvider(groupId));
    ref.invalidate(groupBalancesProvider(groupId));
  }
}

final groupsControllerProvider =
    NotifierProvider<GroupsController, GroupsState>(GroupsController.new);

/// Combined feed + summary for a single group.
final groupFeedProvider =
    FutureProvider.autoDispose.family<GroupFeed, int>((ref, groupId) async {
  _onGroupChanged(ref, groupId);
  return ref.read(groupRepositoryProvider).feed(groupId);
});

/// Full detail for a single shared transaction.
final groupTransactionDetailProvider = FutureProvider.autoDispose
    .family<GroupTransactionDetail, ({int groupId, int txId})>((ref, args) async {
  _onGroupChanged(ref, args.groupId);
  return ref.read(groupRepositoryProvider).transactionDetail(args.groupId, args.txId);
});

/// Member roster for a single group.
final groupMembersProvider =
    FutureProvider.autoDispose.family<List<GroupMember>, int>((ref, groupId) async {
  _onGroupChanged(ref, groupId);
  return ref.read(groupRepositoryProvider).members(groupId);
});

/// Group activity analytics.
final groupAnalyticsProvider =
    FutureProvider.autoDispose.family<GroupAnalytics, int>((ref, groupId) async {
  _onGroupChanged(ref, groupId);
  return ref.read(groupRepositoryProvider).analytics(groupId);
});

/// Splitwise-lite balances + settle-up suggestions for a group.
final groupBalancesProvider =
    FutureProvider.autoDispose.family<GroupBalances, int>((ref, groupId) async {
  _onGroupChanged(ref, groupId);
  return ref.read(groupRepositoryProvider).balances(groupId);
});

/// Savings goals shared with a group.
final groupGoalsProvider =
    FutureProvider.autoDispose.family<List<GoalModel>, int>((ref, groupId) async {
  _onGroupChanged(ref, groupId);
  return ref.read(groupRepositoryProvider).goals(groupId);
});

/// Settle-up history for a group.
final groupSettlementsProvider =
    FutureProvider.autoDispose.family<List<GroupSettlement>, int>((ref, groupId) async {
  _onGroupChanged(ref, groupId);
  return ref.read(groupRepositoryProvider).settlements(groupId);
});
