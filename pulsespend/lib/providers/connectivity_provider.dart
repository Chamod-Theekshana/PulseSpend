import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import 'session_sync.dart';

/// Bridges the imperative [SocketService.status] ValueNotifier into Riverpod so
/// the UI can react to connection changes, and wires the reconnect → resync
/// recovery so no updates are missed after the link drops and restores.
class SocketStatusController extends Notifier<SocketStatus> {
  @override
  SocketStatus build() {
    final svc = SocketService.instance;

    void listener() => state = svc.status.value;
    svc.status.addListener(listener);
    ref.onDispose(() => svc.status.removeListener(listener));

    // On a genuine reconnection, refetch everything that may have changed
    // while we were offline.
    svc.onReconnected = () => ref.read(sessionSyncProvider.notifier).resync();
    ref.onDispose(() => svc.onReconnected = null);

    return svc.status.value;
  }
}

final socketStatusProvider =
    NotifierProvider<SocketStatusController, SocketStatus>(SocketStatusController.new);
