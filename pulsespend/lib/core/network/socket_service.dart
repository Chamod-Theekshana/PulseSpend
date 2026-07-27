import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';
import '../storage/outbox_service.dart';
import '../storage/secure_storage.dart';

/// Connection status exposed as a [ValueNotifier] so both Riverpod providers
/// and imperative code (ConnectivityBanner, auth flow) can react to it.
enum SocketStatus { disconnected, connecting, connected, reconnecting }

final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService.instance;
});

class SocketSubscription {
  final void Function() cancel;
  SocketSubscription(this.cancel);
}

class SocketService {
  SocketService._();

  /// Global singleton — used across providers, auth controller, etc.
  static final SocketService instance = SocketService._();

  io.Socket? _socket;
  final Map<String, List<Function(dynamic)>> _eventListeners = {};

  /// Observable connection state. [SocketStatusController] bridges this into
  /// Riverpod; other code can listen directly.
  final ValueNotifier<SocketStatus> status =
      ValueNotifier(SocketStatus.disconnected);

  /// Set by [SocketStatusController] so a successful reconnect triggers
  /// a full data resync (session_sync.dart).
  VoidCallback? onReconnected;

  bool get isConnected => _socket?.connected ?? false;

  /// Connects to the backend using the stored auth token. Called by
  /// [AuthController] after sign-in / bootstrap / account-switch.
  Future<void> connect() async {
    if (_socket != null && _socket!.connected) return;

    final token = await SecureStorageService.instance.accessToken;
    if (token == null || token.isEmpty) return;

    status.value = SocketStatus.connecting;

    _socket?.dispose();
    _socket = io.io(
      ApiConfig.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      final wasReconnecting = status.value == SocketStatus.reconnecting;
      status.value = SocketStatus.connected;
      if (wasReconnecting) onReconnected?.call();
      _flushOutbox();
    });

    _socket!.onDisconnect((_) {
      if (status.value != SocketStatus.disconnected) {
        status.value = SocketStatus.reconnecting;
      }
    });

    // Re-register any listeners that were added before this connect() call
    // (e.g. by providers that build before auth completes).
    for (final entry in _eventListeners.entries) {
      for (final cb in entry.value) {
        _socket!.on(entry.key, cb);
      }
    }
  }

  /// Cleanly tears down the socket. Called on logout / account-switch.
  void disconnect() {
    status.value = SocketStatus.disconnected;
    _socket?.dispose();
    _socket = null;
  }

  /// Registers an event listener. Returns a tear-down object suitable for
  /// `sub.cancel()`. If the socket isn't connected yet the listener is still
  /// recorded and will be attached on the next [connect()].
  SocketSubscription on(String event, Function(dynamic) callback) {
    _socket?.on(event, callback);
    _eventListeners.putIfAbsent(event, () => []).add(callback);
    return SocketSubscription(() => off(event, callback));
  }

  void off(String event, [Function(dynamic)? callback]) {
    if (callback != null) {
      _socket?.off(event, callback);
      _eventListeners[event]?.remove(callback);
    } else {
      _socket?.off(event);
      _eventListeners.remove(event);
    }
  }

  @visibleForTesting
  void simulateEvent(String event, dynamic data) {
    final listeners = _eventListeners[event] ?? [];
    for (final callback in listeners) {
      callback(data);
    }
  }

  void emitWithAck(String event, Map<String, dynamic> data, Function(Map<String, dynamic>) ack) {
    if (_socket != null && _socket!.connected) {
      _socket!.emitWithAck(event, data, ack: (response) {
        if (response is Map) {
          ack(Map<String, dynamic>.from(response));
        } else {
          ack({'status': 'unknown', 'raw': response});
        }
      });
    } else {
      OutboxService.instance.savePendingEvent(event, data);
      ack({'status': 'pending_offline', 'localId': data['localId']});
    }
  }

  Future<void> _flushOutbox() async {
    final pendingEvents = await OutboxService.instance.getPendingEvents();
    if (pendingEvents.isEmpty) return;

    for (final event in pendingEvents) {
      if (_socket == null || !_socket!.connected) break;
      _socket!.emitWithAck(event.eventName, event.payload, ack: (response) async {
        if (response is Map && response['status'] == 'success') {
          await OutboxService.instance.removeEvent(event.id);
        }
      });
    }
  }

  void dispose() {
    disconnect();
  }
}