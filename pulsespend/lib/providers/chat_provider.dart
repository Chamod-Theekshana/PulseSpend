import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/socket_service.dart';
import '../models/chat_message_model.dart';
import 'repository_providers.dart';

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isSending;
  final String? error;
  final bool hasMore;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.hasMore = true,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
    bool? hasMore,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: error,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class ChatController extends Notifier<ChatState> {
  ChatController(this.arg);
  final int arg;

  late SocketSubscription _socketSub;

  @override
  ChatState build() {
    _socketSub = SocketService.instance.on('group:message', _onNewMessage);
    ref.onDispose(() {
      _socketSub.cancel();
    });
    
    Future.microtask(loadInitial);
    return const ChatState(isLoading: true);
  }

  void _onNewMessage(dynamic data) {
    if (data == null) return;
    try {
      final payloadGroupId = data['groupId'] as int?;
      if (payloadGroupId != arg) return;

      final msgData = data['message'];
      if (msgData != null) {
        final newMsg = ChatMessage.fromJson(msgData);
        // Prepend because our list is newest-first (reversed listview)
        state = state.copyWith(messages: [newMsg, ...state.messages]);
      }
    } catch (e) {
      // ignore parsing errors on socket events
    }
  }

  Future<void> loadInitial() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final msgs = await ref.read(chatRepositoryProvider).getMessages(arg);
      state = state.copyWith(messages: msgs, isLoading: false, hasMore: msgs.length == 30);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.messages.isEmpty) return;
    
    // The messages list is newest-first, so the last element is the oldest message
    final oldestId = state.messages.last.id;
    
    state = state.copyWith(isLoading: true, error: null);
    try {
      final olderMsgs = await ref.read(chatRepositoryProvider).getMessages(arg, before: oldestId);
      state = state.copyWith(
        messages: [...state.messages, ...olderMsgs],
        isLoading: false,
        hasMore: olderMsgs.length == 30,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;
    state = state.copyWith(isSending: true, error: null);
    try {
      // The socket event will also fire for our own message, but we can optimistically 
      // add it, or just let the socket handle it. The backend emits to all members, 
      // including the sender. So we can just let the socket event populate it to avoid dupes,
      // or we can add it here and filter dupes in _onNewMessage. 
      // Let's rely on the REST response for our own message, and filter socket dupes.
      final newMsg = await ref.read(chatRepositoryProvider).sendMessage(arg, content.trim());
      
      // Check if we already have it from socket
      if (!state.messages.any((m) => m.id == newMsg.id)) {
        state = state.copyWith(messages: [newMsg, ...state.messages], isSending: false);
      } else {
        state = state.copyWith(isSending: false);
      }
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }
}

final chatControllerProvider = NotifierProvider.autoDispose.family<ChatController, ChatState, int>(
  (int arg) => ChatController(arg),
);
