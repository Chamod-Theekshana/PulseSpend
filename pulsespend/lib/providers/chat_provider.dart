import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message_model.dart';
import '../core/network/socket_service.dart';

final chatProvider = NotifierProvider.family<ChatStateNotifier, List<ChatMessage>, int>(
  ChatStateNotifier.new,
);

class ChatStateNotifier extends Notifier<List<ChatMessage>> {
  final int groupId;
  final _uuid = const Uuid();

  ChatStateNotifier(this.groupId);

  @override
  List<ChatMessage> build() {
    _initSocket();
    ref.onDispose(() {
      SocketService.instance.emitWithAck('leave_group', {'groupId': groupId.toString()}, (_) {});
      SocketService.instance.off('new_message', _handleIncomingMessage);
    });
    return [];
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
        state = [
          for (final msg in state)
            if (msg.localId == localId)
              msg.copyWith(status: MessageStatus.sent, id: response['messageId'])
            else
              msg,
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