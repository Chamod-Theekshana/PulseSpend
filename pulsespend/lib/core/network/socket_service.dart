import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';
import '../storage/secure_storage.dart';

/// High-level connection state exposed to the UI so it can show a subtle
/// reconnecting indicator and trigger a data resync when the link is restored.
enum SocketStatus { disconnected, connecting, connected, reconnecting }

/// Thin wrapper around socket_io_client matching the backend's `socket.ts`.
///
/// Server-side auth: the JWT access token is sent via the handshake's
/// `auth.token` field (see `io.use(...)` in socket.ts), NOT a header.
/// On connect, the server joins the socket to room `user:<id>` and emits
/// events scoped to that room via `emitToUser()`.
///
/// Events emitted by the backend (verified against controllers):
///  - tx:new, tx:updated, tx:deleted, tx:summary:invalidate
///  - budget:created, budget:updated, budget:deleted, budget:alert
///  - goal:completed
///  - recurring:created, recurring:deleted
///  - reminder:created, reminder:updated, reminder:deleted
///  - profile:updated, profile:password:updated
class SocketService {
  SocketService._internal();
  static final SocketService instance = SocketService._internal();

  io.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

  final Map<String, List<void Function(dynamic)>> _listeners = {};

  /// Broadcasts the live connection status. The UI (and a resync coordinator)
  /// listen to this to show a reconnecting banner and refetch on recovery.
  final ValueNotifier<SocketStatus> status =
      ValueNotifier<SocketStatus>(SocketStatus.disconnected);

  /// Called after the socket reconnects following an unexpected drop (NOT on
  /// the first connect, and NOT after an explicit [disconnect]). A coordinator
  /// uses this to resync all data that may have changed while offline.
  void Function()? onReconnected;

  bool _hasConnectedOnce = false;

  Future<void> connect() async {
    final token = await SecureStorageService.instance.accessToken;
    if (token == null) return;

    disconnect();
    status.value = SocketStatus.connecting;

    _socket = io.io(
      ApiConfig.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(1 << 30)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setAuth({'token': token})
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      final wasReconnecting = status.value == SocketStatus.reconnecting;
      status.value = SocketStatus.connected;
      debugPrint('[Socket] Connected');
      // Only resync on a genuine reconnection (missed events while offline).
      if (wasReconnecting && _hasConnectedOnce) {
        onReconnected?.call();
      }
      _hasConnectedOnce = true;
    });

    _socket!.onDisconnect((_) {
      // The client auto-retries, so surface this as "reconnecting" rather than
      // a hard disconnect (a hard disconnect only happens via [disconnect]).
      if (status.value != SocketStatus.disconnected) {
        status.value = SocketStatus.reconnecting;
      }
      debugPrint('[Socket] Disconnected — attempting to reconnect');
    });

    _socket!.onConnectError((err) {
      if (status.value == SocketStatus.connecting) {
        status.value = SocketStatus.reconnecting;
      }
      debugPrint('[Socket] Connect error: $err');
    });

    // Re-attach any listeners registered before connect() was called.
    for (final entry in _listeners.entries) {
      for (final cb in entry.value) {
        _socket!.on(entry.key, cb);
      }
    }
  }

  /// Subscribe to a server event. Safe to call before [connect].
  void on(String event, void Function(dynamic data) callback) {
    _listeners.putIfAbsent(event, () => []).add(callback);
    _socket?.on(event, callback);
  }

  void off(String event) {
    _listeners.remove(event);
    _socket?.off(event);
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _hasConnectedOnce = false;
    status.value = SocketStatus.disconnected;
  }
}
