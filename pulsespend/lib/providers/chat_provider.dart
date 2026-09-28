import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message_model.dart';
import '../core/network/socket_service.dart';
import '../repositories/chat_repository.dart';

final chatProvider = NotifierProvider.family<ChatStateNotifier, List<ChatMessage>, int>(
  ChatStateNotifier.new,
);

class ChatStateNotifier extends Notifier<List<ChatMessage>> {
  final int groupId;
  final _uuid = const Uuid();
  final _chatRepository = ChatRepository();

  ChatStateNotifier(this.groupId);

  /// False once the server returns a short page — there is nothing older left.
  bool _hasMore = true;
  bool _isLoadingOlder = false;
  StreamSubscription<OutboxFlushResult>? _outboxSub;

  bool get hasMore => _hasMore;
  bool get isLoadingOlder => _isLoadingOlder;

  @override
  List<ChatMessage> build() {
    _initSocket();
    ref.onDispose(() {
      SocketService.instance.leaveGroup(groupId);
      SocketService.instance.off('new_message', _handleIncomingMessage);
      SocketService.instance.off('connection_ready', _handleReconnected);
      _outboxSub?.cancel();
    });
    _loadHistory();
    return const [];
  }

  void _initSocket() {
    // Joining goes through SocketService so the room is recorded and
    // automatically re-joined after every reconnect. The old code emitted
    // `join_group` directly, exactly once, which meant the chat silently
    // stopped receiving anything after the first dropped connection.
    SocketService.instance.joinGroup(groupId);
    SocketService.instance.on('new_message', _handleIncomingMessage);
    SocketService.instance.on('connection_ready', _handleReconnected);

    // A message sent while offline is queued to the outbox and immediately
    // acked as `pending_offline` — that's the last thing this notifier ever
    // heard about it. Without this, the bubble was stuck on "sending…"
    // forever once the queue actually flushed on reconnect: the backend
    // deliberately excludes the sender's own socket from the `new_message`
    // broadcast (so a live send doesn't double-render for the sender), so
    // there was no other path back to this state at all.
    _outboxSub = SocketService.instance.outboxFlushed.listen(_handleOutboxFlush);
  }

  void _handleOutboxFlush(OutboxFlushResult result) {
    if (result.eventName != 'send_message') return;
    if (result.payload['groupId'] != groupId.toString()) return;
    _applyAckResponse(result.payload['localId'] as String?, result.response);
  }

  /// After a reconnect, pull history again: anything sent while this device was
  /// away was broadcast to a socket that no longer existed, so the only way to
  /// see it is to refetch. The merge in [_loadHistory] keeps it idempotent.
  void _handleReconnected(dynamic _) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _chatRepository.getMessages(groupId);
      // The API returns newest-first (for pagination); the UI renders
      // chronologically, oldest first.
      final ordered = history.reversed.toList();
      _hasMore = history.length >= 30;
      state = _merge(state, ordered);
    } catch (_) {
      // History failed to load (e.g. offline) — real-time chat still works
      // once connected, so don't surface a blocking error here.
    }
  }

  /// Fetches the page of messages older than the oldest one currently held.
  Future<void> loadOlder() async {
    if (_isLoadingOlder || !_hasMore) return;

    // Only server-persisted messages have a usable numeric cursor; optimistic
    // local ones carry a UUID.
    final oldestServerId = state
        .map((m) => int.tryParse(m.id))
        .whereType<int>()
        .fold<int?>(null, (min, id) => min == null || id < min ? id : min);
    if (oldestServerId == null) return;

    _isLoadingOlder = true;
    try {
      final older = await _chatRepository.getMessages(groupId, before: oldestServerId);
      if (older.length < 30) _hasMore = false;
      if (older.isNotEmpty) {
        state = _merge(state, older.reversed.toList());
      }
    } catch (_) {
      // Leave _hasMore alone so the user can pull again.
    } finally {
      _isLoadingOlder = false;
    }
  }

  /// Merges [incoming] into [current], de-duplicating on server id and keeping
  /// chronological order. Pending local messages (UUID ids) are preserved.
  List<ChatMessage> _merge(List<ChatMessage> current, List<ChatMessage> incoming) {
    final byId = <String, ChatMessage>{};
    for (final m in current) {
      byId[m.id] = m;
    }
    for (final m in incoming) {
      // A server copy always wins over an optimistic one with the same id.
      byId[m.id] = m;
    }
    final merged = byId.values.toList()
      ..sort((a, b) {
        final byTime = a.timestamp.compareTo(b.timestamp);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
    return merged;
  }

  void _handleIncomingMessage(dynamic data) {
    final raw = data is List ? data.first : data;
    if (raw is! Map) return;
    final incoming = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
    if (incoming.groupId != groupId.toString()) return;

    final localId = incoming.localId;

    // Case 1: this is the server's echo of a message THIS device sent
    // optimistically — swap the placeholder for the authoritative copy.
    if (localId != null && state.any((m) => m.localId == localId && m.id != incoming.id)) {
      state = [
        for (final m in state)
          if (m.localId == localId) incoming else m,
      ];
      return;
    }

    // Case 2: already have it (a replayed packet after connection-state
    // recovery, or a duplicate broadcast). The previous implementation compared
    // localId AND id together, so a re-delivered message whose localId was null
    // on our side slipped through and appeared twice.
    if (state.any((m) => m.id == incoming.id)) return;

    state = _merge(state, [incoming]);
  }

  Future<void> sendMessage(
    String content, {
    Map<String, dynamic>? expenseMetadata,
    required String myUserId,
  }) async {
    final localId = _uuid.v4();

    final optimisticMsg = ChatMessage(
      id: localId,
      localId: localId,
      groupId: groupId.toString(),
      senderId: myUserId,
      content: content,
      status: MessageStatus.pending,
      timestamp: DateTime.now(),
      metadata: expenseMetadata,
    );

    state = [...state, optimisticMsg];
    _emit(optimisticMsg);
  }

  /// Re-sends a message that previously failed, without creating a duplicate
  /// bubble. Reuses the original localId so the server ack still matches.
  void retry(String localId) {
    final idx = state.indexWhere((m) => m.localId == localId);
    if (idx < 0) return;
    final msg = state[idx];
    if (msg.status == MessageStatus.sent) return;
    state = [
      for (final m in state)
        if (m.localId == localId) m.copyWith(status: MessageStatus.pending) else m,
    ];
    _emit(msg);
  }

  void _emit(ChatMessage msg) {
    SocketService.instance.emitWithAck(
      'send_message',
      msg.toJson(),
      (response) => _applyAckResponse(msg.localId, response),
    );
  }

  /// Reconciles an optimistic bubble against a `send_message` ack, whether
  /// that ack arrived immediately (device online) or later, out-of-band, via
  /// [SocketService.outboxFlushed] (device was offline when it was sent).
  void _applyAckResponse(String? localId, Map<String, dynamic> response) {
    final status = response['status'];
    if (status == 'success') {
      final serverId = response['messageId']?.toString();
      final serverTs = response['timestamp']?.toString();
      state = [
        for (final m in state)
          if (m.localId == localId)
            m.copyWith(
              status: MessageStatus.sent,
              id: serverId ?? m.id,
              timestamp: serverTs != null
                  ? (DateTime.tryParse(serverTs) ?? m.timestamp)
                  : m.timestamp,
            )
          else
            m,
      ];
      // Collapse any duplicate that arrived over the broadcast (or a history
      // refetch) in the gap between our optimistic insert and this ack.
      final seen = <String>{};
      state = [
        for (final m in state)
          if (seen.add(m.id)) m,
      ];
    } else if (status == 'pending_offline') {
      // Queued in the outbox; it stays visually pending until it flushes.
    } else {
      _markMessageFailed(localId);
    }
  }

  void _markMessageFailed(String? localId) {
    if (localId == null) return;
    state = [
      for (final msg in state)
        if (msg.localId == localId) msg.copyWith(status: MessageStatus.failed) else msg,
    ];
  }
}
