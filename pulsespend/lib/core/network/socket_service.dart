import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';
import '../storage/outbox_service.dart';
import '../storage/secure_storage.dart';

enum SocketStatus { disconnected, connecting, connected, reconnecting }

final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService.instance;
});

class SocketSubscription {
  final void Function() cancel;
  SocketSubscription(this.cancel);
}

const _ephemeralEvents = {'join_group', 'leave_group'};

class OutboxFlushResult {
  final String eventName;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> response;
  const OutboxFlushResult(this.eventName, this.payload, this.response);
}

class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  io.Socket? _socket;
  final Map<String, List<Function(dynamic)>> _eventListeners = {};
  final Set<String> _joinedGroups = {};

  bool _flushingOutbox = false;
  bool _refreshingAuth = false;
  Timer? _flushTimer;

  final _outboxFlushController = StreamController<OutboxFlushResult>.broadcast();
  Stream<OutboxFlushResult> get outboxFlushed => _outboxFlushController.stream;

  Timer? _authRetryTimer;
  int _authRetryAttempt = 0;

  final ValueNotifier<SocketStatus> status = ValueNotifier(SocketStatus.disconnected);

  VoidCallback? onReconnected;
  VoidCallback? onSessionExpired;
  Future<bool> Function()? refreshAccessToken;

  bool get isConnected => _socket?.connected ?? false;

  Future<void> connect() async {
    if (_socket != null && _socket!.connected) return;

    final token = await SecureStorageService.instance.accessToken;
    if (token == null || token.isEmpty) return;

    status.value = SocketStatus.connecting;
    _socket?.dispose();

    final options = io.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .setAuth({'token': token})
        .enableAutoConnect()
        .enableReconnection()
        .setTimeout(20000)
        .build();

    options['reconnectionAttempts'] = 1 << 30;
    options['reconnectionDelay'] = 1000;
    options['reconnectionDelayMax'] = 15000;
    options['randomizationFactor'] = 0.5;

    _socket = io.io(ApiConfig.baseUrl, options);

    _socket!.on('connection_ready', (data) {
      final payload = data is List ? data.first : data;
      final wasReconnecting = status.value == SocketStatus.reconnecting;
      status.value = SocketStatus.connected;
      _authRetryAttempt = 0;
      _authRetryTimer?.cancel();

      final recovered = payload is Map && payload['recovered'] == true;
      if (recovered) {
        if (wasReconnecting) onReconnected?.call();
        _scheduleFlush();
      } else {
        _rejoinGroups();
        if (wasReconnecting) onReconnected?.call();
        // Delay flush so join_group packets reach the server first.
        // 500 ms is generous — on any network where the socket just
        // connected, one RTT is well under this.
        _scheduleFlush(delay: const Duration(milliseconds: 500));
      }
    });

    _socket!.onConnect((_) {
      // Intentionally empty — all logic is in connection_ready which
      // carries the `recovered` flag we need.
    });

    _socket!.onDisconnect((_) {
      if (status.value == SocketStatus.connected ||
          status.value == SocketStatus.connecting) {
        status.value = SocketStatus.reconnecting;
      }
    });

    _socket!.onConnectError((err) {
      final e = err is List ? err.first : err;
      final code = _errorCode(e);
      switch (code) {
        case 'TOKEN_EXPIRED':
        case 'TOKEN_MISSING':
          _refreshAndReconnect();
        case 'TOKEN_INVALID':
          disconnect();
          onSessionExpired?.call();
        case 'AUTH_UNAVAILABLE':
          _scheduleAuthRetry();
        default:
          if (status.value != SocketStatus.disconnected) {
            status.value = SocketStatus.reconnecting;
          }
      }
    });

    _socket!.onError((err) {
      if (kDebugMode) debugPrint('[Socket] error: $err');
    });

    // Re-attach any listeners registered before this connect() call.
    for (final entry in _eventListeners.entries) {
      for (final cb in entry.value) {
        _socket!.on(entry.key, cb);
      }
    }
  }

  // ── Group rooms ────────────────────────────────────────────────────────────

  void joinGroup(int groupId) {
    final id = groupId.toString();
    _joinedGroups.add(id);
    _emitJoin(id);
  }

  void leaveGroup(int groupId) {
    final id = groupId.toString();
    _joinedGroups.remove(id);
    if (_socket?.connected ?? false) {
      _socket!.emit('leave_group', {'groupId': id});
    }
  }

  void _emitJoin(String groupId) {
    if (!(_socket?.connected ?? false)) return;
    _socket!.emitWithAck('join_group', {'groupId': groupId}, ack: (response) {
      if (kDebugMode && !(response is Map && response['status'] == 'success')) {
        debugPrint('[Socket] join_group($groupId) failed: $response');
      }
    });
  }

  /// Fire-and-forget rejoin. Does NOT await acks — a lost ack must never
  /// block the outbox flush. The backend membership check uses the DB, so
  /// send_message succeeds even if join_group ack hasn't arrived yet.
  void _rejoinGroups() {
    for (final id in _joinedGroups) {
      _emitJoin(id);
    }
  }

  /// Schedules _flushOutbox after [delay]. Cancels any pending schedule so
  /// rapid connection_ready events don't stack up multiple flushes.
  void _scheduleFlush({Duration delay = Duration.zero}) {
    _flushTimer?.cancel();
    _flushTimer = Timer(delay, _flushOutbox);
  }

  // ── Listeners ──────────────────────────────────────────────────────────────

  SocketSubscription on(String event, Function(dynamic) callback) {
    _socket?.on(event, callback);
    _eventListeners.putIfAbsent(event, () => []).add(callback);
    return SocketSubscription(() => off(event, callback));
  }

  void off(String event, [Function(dynamic)? callback]) {
    if (callback != null) {
      _socket?.off(event, callback);
      _eventListeners[event]?.remove(callback);
      if (_eventListeners[event]?.isEmpty ?? false) {
        _eventListeners.remove(event);
      }
    } else {
      _socket?.off(event);
      _eventListeners.remove(event);
    }
  }

  @visibleForTesting
  void simulateEvent(String event, dynamic data) {
    final listeners = List<Function(dynamic)>.from(_eventListeners[event] ?? const []);
    for (final callback in listeners) {
      callback(data);
    }
  }

  void emitWithAck(
    String event,
    Map<String, dynamic> data,
    Function(Map<String, dynamic>) ack,
  ) {
    if (_socket != null && _socket!.connected) {
      _socket!.emitWithAck(event, data, ack: (response) {
        if (response is Map) {
          ack(Map<String, dynamic>.from(response));
        } else {
          ack({'status': 'unknown', 'raw': response});
        }
      });
    } else if (_ephemeralEvents.contains(event)) {
      ack({'status': 'offline', 'localId': data['localId']});
    } else {
      OutboxService.instance.savePendingEvent(event, data);
      ack({'status': 'pending_offline', 'localId': data['localId']});
    }
  }

  Future<void> _flushOutbox() async {
    if (_flushingOutbox) return;
    _flushingOutbox = true;
    try {
      final pendingEvents = await OutboxService.instance.getPendingEvents();
      if (pendingEvents.isEmpty) return;

      for (final event in pendingEvents) {
        if (_socket == null || !_socket!.connected) break;
        if (_ephemeralEvents.contains(event.eventName)) {
          await OutboxService.instance.removeEvent(event.id);
          continue;
        }
        // Use a timeout so a lost ack never stalls the entire outbox.
        final completer = Completer<void>();
        final timer = Timer(const Duration(seconds: 10), () {
          if (!completer.isCompleted) completer.complete();
        });
        _socket!.emitWithAck(event.eventName, event.payload, ack: (response) async {
          timer.cancel();
          final mapped = response is Map
              ? Map<String, dynamic>.from(response)
              : <String, dynamic>{'status': 'unknown', 'raw': response};
          if (mapped['status'] == 'success') {
            await OutboxService.instance.removeEvent(event.id);
          }
          _outboxFlushController.add(
            OutboxFlushResult(event.eventName, event.payload, mapped),
          );
          if (!completer.isCompleted) completer.complete();
        });
        await completer.future;
      }
    } finally {
      _flushingOutbox = false;
    }
  }

  // ── Auth helpers ───────────────────────────────────────────────────────────

  String? _errorCode(dynamic err) {
    if (err is Map) {
      final data = err['data'];
      if (data is Map && data['code'] is String) return data['code'] as String;
      final message = err['message'];
      if (message is String) return _codeFromMessage(message);
    }
    if (err is String) return _codeFromMessage(err);
    return null;
  }

  String? _codeFromMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('expired')) return 'TOKEN_EXPIRED';
    if (lower.contains('missing')) return 'TOKEN_MISSING';
    if (lower.contains('invalid token')) return 'TOKEN_INVALID';
    return null;
  }

  void _scheduleAuthRetry() {
    if (_authRetryTimer?.isActive ?? false) return;
    _authRetryAttempt = (_authRetryAttempt + 1).clamp(1, 6);
    final backoff = 1000 * (1 << (_authRetryAttempt - 1));
    final jitter = Random().nextInt(1000);
    status.value = SocketStatus.reconnecting;
    _authRetryTimer = Timer(Duration(milliseconds: backoff + jitter), () async {
      _socket?.dispose();
      _socket = null;
      await connect();
    });
  }

  Future<void> _refreshAndReconnect() async {
    if (_refreshingAuth) return;
    _refreshingAuth = true;
    try {
      final refresh = refreshAccessToken;
      final ok = refresh == null ? false : await refresh();
      if (!ok) {
        disconnect();
        onSessionExpired?.call();
        return;
      }
      _socket?.dispose();
      _socket = null;
      status.value = SocketStatus.reconnecting;
      await Future<void>.delayed(
        Duration(milliseconds: 200 + Random().nextInt(800)),
      );
      await connect();
    } finally {
      _refreshingAuth = false;
    }
  }

  void disconnect() {
    status.value = SocketStatus.disconnected;
    _authRetryTimer?.cancel();
    _authRetryTimer = null;
    _authRetryAttempt = 0;
    _flushTimer?.cancel();
    _flushTimer = null;
    _socket?.dispose();
    _socket = null;
    _joinedGroups.clear();
  }

  void dispose() {
    disconnect();
    unawaited(_outboxFlushController.close());
  }
}
 