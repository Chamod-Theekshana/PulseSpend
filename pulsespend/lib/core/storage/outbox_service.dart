import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'local_cache.dart';

final outboxServiceProvider = Provider<OutboxService>((ref) => OutboxService.instance);

/// A queued offline write operation. Providers queue these when a network call
/// fails due to connectivity; [TransactionsController.flushOutbox()] replays
/// them in FIFO order on reconnect.
class OutboxOp {
  final String opId;
  final String userId;
  final String entity;
  final String type; // create | update | delete
  final Map<String, dynamic> body;
  final int createdAt;

  const OutboxOp({
    required this.opId,
    required this.userId,
    this.entity = 'transaction',
    required this.type,
    required this.body,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'opId': opId,
        'userId': userId,
        'entity': entity,
        'type': type,
        'body': body,
        'createdAt': createdAt,
      };

  static OutboxOp? fromJson(Map<String, dynamic> json) {
    final opId = json['opId'];
    final userId = json['userId'];
    final type = json['type'];
    final body = json['body'];
    if (opId is! String || userId is! String || type is! String || body is! Map) {
      return null;
    }
    return OutboxOp(
      opId: opId,
      userId: userId,
      entity: (json['entity'] as String?) ?? 'transaction',
      type: type,
      body: Map<String, dynamic>.from(body),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class OutboxEvent {
  final String id;
  final String eventName;
  final Map<String, dynamic> payload;

  OutboxEvent({required this.id, required this.eventName, required this.payload});

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventName': eventName,
        'payload': payload,
      };

  static OutboxEvent? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final eventName = json['eventName'];
    final payload = json['payload'];
    if (id is! String || eventName is! String || payload is! Map) return null;
    return OutboxEvent(
      id: id,
      eventName: eventName,
      payload: Map<String, dynamic>.from(payload),
    );
  }
}

/// Durable offline event + op queue.
///
/// Two independent queues live here:
/// 1. **Socket events** (`OutboxEvent`) — fire-and-forget socket emits buffered
///    while offline and flushed by [SocketService] on reconnect.
/// 2. **CRUD ops** (`OutboxOp`) — idempotent REST writes buffered by providers
///    (transactions, debts) and replayed by [TransactionsController.flushOutbox].
///
/// Both were previously **in-memory only**, which quietly defeated the point of
/// having an outbox: a user who added an expense on the underground and then
/// closed the app lost the write entirely, with no error and no trace. Both
/// queues now persist to [LocalCache] (a JSON file under the app documents
/// directory) so they survive a kill, a crash, or an OS eviction.
///
/// Persistence is best-effort and never blocks the caller's happy path — the
/// in-memory list stays the source of truth for the running session, and disk
/// is written after each mutation.
class OutboxService {
  OutboxService._();

  /// Global singleton used by providers and SocketService.
  static final OutboxService instance = OutboxService._();

  static const _eventsKey = 'outbox_events';
  static const _opsKey = 'outbox_ops';

  /// Queued ops older than this are discarded on load rather than replayed.
  static const _maxAgeMs = 14 * 24 * 60 * 60 * 1000; // 14 days

  final List<OutboxEvent> _pendingEvents = [];
  final List<OutboxOp> _ops = [];
  final _uuid = const Uuid();

  bool _loaded = false;
  Future<void>? _loading;

  /// Rehydrates both queues from disk. Safe to call repeatedly; the work
  /// happens once. Call this during app bootstrap so a queued write from a
  /// previous session is replayed on the next reconnect.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final events = await LocalCache.instance.readList(_eventsKey);
      if (events != null) {
        _pendingEvents
          ..clear()
          ..addAll(events.map(OutboxEvent.fromJson).whereType<OutboxEvent>());
      }

      final ops = await LocalCache.instance.readList(_opsKey);
      if (ops != null) {
        final cutoff = DateTime.now().millisecondsSinceEpoch - _maxAgeMs;
        _ops
          ..clear()
          // Drop anything ancient. Replaying a two-week-old create would
          // resurrect a transaction the user has long since given up on, and
          // the server's idempotency key won't save us because it never got
          // there in the first place.
          ..addAll(ops
              .map(OutboxOp.fromJson)
              .whereType<OutboxOp>()
              .where((o) => o.createdAt >= cutoff));
      }
    } catch (_) {
      // A corrupt file must not stop the app from starting.
    } finally {
      _loaded = true;
    }
  }

  Future<void> _persistEvents() async {
    await LocalCache.instance.write(_eventsKey, _pendingEvents.map((e) => e.toJson()).toList());
  }

  Future<void> _persistOps() async {
    await LocalCache.instance.write(_opsKey, _ops.map((o) => o.toJson()).toList());
  }

  // ── Socket events ──────────────────────────────────────────────────────────

  void savePendingEvent(String eventName, Map<String, dynamic> payload) {
    _pendingEvents.add(OutboxEvent(
      id: _uuid.v4(),
      eventName: eventName,
      payload: payload,
    ));
    unawaited(_persistEvents());
  }

  Future<List<OutboxEvent>> getPendingEvents() async {
    await load();
    return List.unmodifiable(_pendingEvents);
  }

  Future<void> removeEvent(String id) async {
    _pendingEvents.removeWhere((event) => event.id == id);
    await _persistEvents();
  }

  // ── CRUD ops ───────────────────────────────────────────────────────────────

  Future<void> add(OutboxOp op) async {
    await load();
    _ops.add(op);
    await _persistOps();
  }

  Future<void> remove(String opId) async {
    _ops.removeWhere((o) => o.opId == opId);
    await _persistOps();
  }

  Future<List<OutboxOp>> opsForUser(String userId) async {
    await load();
    return _ops.where((o) => o.userId == userId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<int> countForUser(String userId) async {
    await load();
    return _ops.where((o) => o.userId == userId).length;
  }

  /// Clears everything — call on logout/account deletion so one account's
  /// queued writes can never replay under another's session.
  Future<void> clear() async {
    _pendingEvents.clear();
    _ops.clear();
    await Future.wait([_persistEvents(), _persistOps()]);
  }
}
