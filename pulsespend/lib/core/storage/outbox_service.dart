import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A single queued write that failed while offline and must be replayed once
/// connectivity returns. [opId] is a stable client-generated id used as the
/// backend idempotency key, so replaying (or a lost response) never duplicates.
class OutboxOp {
  final String opId;
  final String userId;

  /// What kind of record this op targets. 'transaction' is the default so ops
  /// persisted before this field existed keep replaying correctly.
  final String entity; // 'transaction' | 'debt' | 'goal_contribution'

  final String type; // 'create' | 'update' | 'delete'

  /// create/update → request body (update also carries {'id': int});
  /// delete → {'id': int}.
  final Map<String, dynamic> body;
  final int createdAt;

  const OutboxOp({
    required this.opId,
    required this.userId,
    required this.type,
    required this.body,
    required this.createdAt,
    this.entity = 'transaction',
  });

  Map<String, dynamic> toJson() => {
        'opId': opId,
        'userId': userId,
        'entity': entity,
        'type': type,
        'body': body,
        'createdAt': createdAt,
      };

  factory OutboxOp.fromJson(Map<String, dynamic> json) => OutboxOp(
        opId: json['opId'].toString(),
        userId: json['userId'].toString(),
        entity: (json['entity'] as String?) ?? 'transaction',
        type: json['type'].toString(),
        body: (json['body'] as Map).cast<String, dynamic>(),
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// Persists the offline write queue in secure storage (the app has no local DB;
/// the queue is small — a handful of transactions typed while offline). The
/// whole list is stored as one JSON blob under a single key.
class OutboxService {
  OutboxService._internal();
  static final OutboxService instance = OutboxService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kOutbox = 'pulsespend_outbox';

  Future<List<OutboxOp>> _all() async {
    final raw = await _storage.read(key: _kOutbox);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => OutboxOp.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<OutboxOp> ops) async {
    await _storage.write(key: _kOutbox, value: jsonEncode(ops.map((o) => o.toJson()).toList()));
  }

  /// Ops queued for [userId], oldest first (FIFO replay order).
  Future<List<OutboxOp>> opsForUser(String userId) async {
    final all = await _all();
    return (all.where((o) => o.userId == userId).toList())
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<int> countForUser(String userId) async {
    final all = await _all();
    return all.where((o) => o.userId == userId).length;
  }

  Future<void> add(OutboxOp op) async {
    final all = await _all();
    all.add(op);
    await _save(all);
  }

  Future<void> remove(String opId) async {
    final all = await _all();
    all.removeWhere((o) => o.opId == opId);
    await _save(all);
  }
}
