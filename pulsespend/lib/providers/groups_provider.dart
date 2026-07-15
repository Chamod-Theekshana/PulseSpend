import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/goal_model.dart';
import '../models/group_model.dart';
import 'repository_providers.dart';

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
    Future.microtask(refresh);
    return const GroupsState(isLoading: true);
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
}

final groupsControllerProvider =
    NotifierProvider<GroupsController, GroupsState>(GroupsController.new);

/// Combined feed + summary for a single group.
final groupFeedProvider =
    FutureProvider.autoDispose.family<GroupFeed, int>((ref, groupId) async {
  return ref.read(groupRepositoryProvider).feed(groupId);
});

/// Member roster for a single group.
final groupMembersProvider =
    FutureProvider.autoDispose.family<List<GroupMember>, int>((ref, groupId) async {
  return ref.read(groupRepositoryProvider).members(groupId);
});

/// Splitwise-lite balances + settle-up suggestions for a group.
final groupBalancesProvider =
    FutureProvider.autoDispose.family<GroupBalances, int>((ref, groupId) async {
  return ref.read(groupRepositoryProvider).balances(groupId);
});

/// Savings goals shared with a group.
final groupGoalsProvider =
    FutureProvider.autoDispose.family<List<GoalModel>, int>((ref, groupId) async {
  return ref.read(groupRepositoryProvider).goals(groupId);
});
