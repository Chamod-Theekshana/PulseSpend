import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';
import '../storage/secure_storage.dart';

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

  Future<void> connect() async {
    final token = await SecureStorageService.instance.accessToken;
    if (token == null) return;

    disconnect();

    _socket = io.io(
      ApiConfig.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      // ignore: avoid_print
      print('[Socket] Connected');
    });

    _socket!.onDisconnect((_) {
      // ignore: avoid_print
      print('[Socket] Disconnected');
    });

    _socket!.onConnectError((err) {
      // ignore: avoid_print
      print('[Socket] Connect error: $err');
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
  }
}
