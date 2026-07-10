import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/notification_model.dart';
import 'repository_providers.dart';

class NotificationsState {
  final List<NotificationModel> items;
  final int unreadCount;
  final bool isLoading;
  final String? error;

  const NotificationsState({
    this.items = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.error,
  });

  NotificationsState copyWith({
    List<NotificationModel>? items,
    int? unreadCount,
    bool? isLoading,
    String? error,
  }) {
    return NotificationsState(
      items: items ?? this.items,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Drives the notification inbox (Facebook/Instagram-style). Every domain
/// socket event (tx:new, budget:alert, goal:completed, reminder:created...)
/// also lands a row server-side, so a light refresh on ANY of those keeps
/// the bell badge accurate without a dedicated event per type.
class NotificationsController extends Notifier<NotificationsState> {
  static const _liveEvents = [
    'tx:new',
    'tx:updated',
    'tx:deleted',
    'budget:alert',
    'budget:created',
    'goal:completed',
    'recurring:created',
    'recurring:deleted',
    'reminder:created',
    'reminder:updated',
    'reminder:deleted',
  ];

  @override
  NotificationsState build() {
    final subs = [
      for (final event in _liveEvents) SocketService.instance.on(event, (_) => refresh()),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    Future.microtask(refresh);
    return const NotificationsState();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await ref.read(notificationRepositoryProvider).history();
      state = state.copyWith(
        items: result.items,
        unreadCount: result.unreadCount,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> markAllRead() async {
    await ref.read(notificationRepositoryProvider).markAllRead();
    state = state.copyWith(
      items: state.items.map((n) => n.copyWith(read: true)).toList(),
      unreadCount: 0,
    );
  }

  Future<void> markOneRead(int id) async {
    await ref.read(notificationRepositoryProvider).markOneRead(id);
    state = state.copyWith(
      items: [for (final n in state.items) if (n.id == id) n.copyWith(read: true) else n],
      unreadCount: (state.unreadCount - 1).clamp(0, 1 << 30),
    );
  }

  Future<void> clearAll() async {
    await ref.read(notificationRepositoryProvider).clear();
    state = state.copyWith(items: [], unreadCount: 0);
  }
}

final notificationsControllerProvider =
    NotifierProvider<NotificationsController, NotificationsState>(NotificationsController.new);
