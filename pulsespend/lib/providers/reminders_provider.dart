import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/reminder_model.dart';
import 'repository_providers.dart';

class RemindersState {
  final List<ReminderModel> items;
  final bool isLoading;
  final String? error;

  const RemindersState({this.items = const [], this.isLoading = false, this.error});

  RemindersState copyWith({List<ReminderModel>? items, bool? isLoading, String? error}) {
    return RemindersState(items: items ?? this.items, isLoading: isLoading ?? this.isLoading, error: error);
  }

  List<ReminderModel> get upcoming =>
      items.where((r) => r.isActive && !r.isOverdue).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  List<ReminderModel> get overdue => items.where((r) => r.isActive && r.isOverdue).toList();
}

class RemindersController extends Notifier<RemindersState> {
  @override
  RemindersState build() {
    SocketService.instance.on('reminder:created', (_) => refresh());
    SocketService.instance.on('reminder:updated', (_) => refresh());
    SocketService.instance.on('reminder:deleted', (_) => refresh());
    Future.microtask(refresh);
    return const RemindersState();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await ref.read(reminderRepositoryProvider).list();
      state = state.copyWith(items: result.items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> create(ReminderModel reminder) async {
    final created = await ref.read(reminderRepositoryProvider).create(reminder);
    state = state.copyWith(items: [...state.items, created]);
  }

  Future<void> update(int id, ReminderModel reminder) async {
    final updated = await ref.read(reminderRepositoryProvider).update(id, reminder);
    state = state.copyWith(items: [for (final r in state.items) if (r.id == id) updated else r]);
  }

  Future<void> delete(int id) async {
    await ref.read(reminderRepositoryProvider).delete(id);
    state = state.copyWith(items: state.items.where((r) => r.id != id).toList());
  }
}

final remindersControllerProvider =
    NotifierProvider<RemindersController, RemindersState>(RemindersController.new);
