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

  @override
  List<ChatMessage> build() {
    _initSocket();
    ref.onDispose(() {
      SocketService.instance.emitWithAck('leave_group', {'groupId': groupId.toString()}, (_) {});
      SocketService.instance.off('new_message', _handleIncomingMessage);
    });
    _loadHistory();
    return [];
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _chatRepository.getMessages(groupId);
      // The API returns newest-first (for pagination); the UI renders
      // chronologically, oldest first.
      final ordered = history.reversed.toList();

      // Merge rather than overwrite — a live message may have already
      // arrived over the socket while this REST call was in flight.
      final existingIds = state.map((m) => m.id).toSet();
      final merged = [
        ...ordered.where((m) => !existingIds.contains(m.id)),
        ...state,
      ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      state = merged;
    } catch (_) {
      // History failed to load (e.g. offline) — real-time chat still works
      // once connected, so don't surface a blocking error here.
    }
  }

  void _initSocket() {
    SocketService.instance.emitWithAck('join_group', {'groupId': groupId.toString()}, (response) {
      // Joined group successfully
    });

    SocketService.instance.on('new_message', _handleIncomingMessage);
  }

  void _handleIncomingMessage(dynamic data) {
    if (data is! Map) return;
    final incomingMsg = ChatMessage.fromJson(Map<String, dynamic>.from(data));

    if (incomingMsg.groupId != groupId.toString()) return;

    state = [
      for (final msg in state)
        if (msg.localId != null && msg.localId == incomingMsg.localId) incomingMsg else msg,
      if (!state.any((m) => m.localId == incomingMsg.localId && m.id == incomingMsg.id))
        incomingMsg,
    ];
  }

  Future<void> sendMessage(String content, {Map<String, dynamic>? expenseMetadata, required String myUserId}) async {
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

    SocketService.instance.emitWithAck('send_message', optimisticMsg.toJson(), (response) {
      if (response['status'] == 'success') {
        final serverId = response['messageId']?.toString();
        final updated = [
          for (final msg in state)
            if (msg.localId == localId)
              msg.copyWith(status: MessageStatus.sent, id: serverId ?? msg.id)
            else
              msg,
        ];
        final seenIds = <String>{};
        state = [
          for (final msg in updated)
            if (seenIds.add(msg.id)) msg,
        ];
      } else if (response['status'] != 'pending_offline') {
        _markMessageFailed(localId);
      }
    });
  }

  void _markMessageFailed(String localId) {
    state = [
      for (final msg in state)
        if (msg.localId == localId) msg.copyWith(status: MessageStatus.failed) else msg,
    ];
  }
}