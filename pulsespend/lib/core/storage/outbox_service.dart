import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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
}

/// Lightweight in-memory event + op queue.
///
/// Two independent queues live here:
/// 1. **Socket events** (`OutboxEvent`) — fire-and-forget socket emits buffered
///    while offline and flushed by [SocketService] on reconnect.
/// 2. **CRUD ops** (`OutboxOp`) — idempotent REST writes buffered by providers
///    (transactions, debts) and replayed by [TransactionsController.flushOutbox].
///
/// Both are in-memory for now; can be upgraded to Hive/SQLite for crash safety.
class OutboxService {
  OutboxService._();

  /// Global singleton used by providers and SocketService.
  static final OutboxService instance = OutboxService._();

  // ── Socket events ──────────────────────────────────────────────────
  final List<OutboxEvent> _pendingEvents = [];
  final _uuid = const Uuid();

  void savePendingEvent(String eventName, Map<String, dynamic> payload) {
    _pendingEvents.add(OutboxEvent(
      id: _uuid.v4(),
      eventName: eventName,
      payload: payload,
    ));
  }

  Future<List<OutboxEvent>> getPendingEvents() async {
    return List.unmodifiable(_pendingEvents);
  }

  Future<void> removeEvent(String id) async {
    _pendingEvents.removeWhere((event) => event.id == id);
  }

  // ── CRUD ops ───────────────────────────────────────────────────────
  final List<OutboxOp> _ops = [];

  Future<void> add(OutboxOp op) async {
    _ops.add(op);
  }

  Future<void> remove(String opId) async {
    _ops.removeWhere((o) => o.opId == opId);
  }

  Future<List<OutboxOp>> opsForUser(String userId) async {
    return _ops.where((o) => o.userId == userId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<int> countForUser(String userId) async {
    return _ops.where((o) => o.userId == userId).length;
  }
}

class OutboxEvent {
  final String id;
  final String eventName;
  final Map<String, dynamic> payload;

  OutboxEvent({required this.id, required this.eventName, required this.payload});
}