enum MessageStatus { pending, sent, failed }

class ChatMessage {
  final String id;
  final String? localId;
  final String groupId;
  final String senderId;
  final String content;
  final MessageStatus status;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  ChatMessage({
    required this.id,
    this.localId,
    required this.groupId,
    this.senderId = '',
    required this.content,
    this.status = MessageStatus.sent,
    required this.timestamp,
    this.metadata,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? json['messageId'] ?? '',
      localId: json['localId'],
      groupId: json['groupId'] ?? '',
      senderId: json['senderId'] ?? '',
      content: json['content'] ?? '',
      status: _statusFromString(json['status']),
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp']) 
          : DateTime.now(),
      metadata: json['metadata'] != null 
          ? Map<String, dynamic>.from(json['metadata']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'localId': localId,
      'groupId': groupId,
      'senderId': senderId,
      'content': content,
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  ChatMessage copyWith({
    String? id,
    String? localId,
    String? groupId,
    String? senderId,
    String? content,
    MessageStatus? status,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      localId: localId ?? this.localId,
      groupId: groupId ?? this.groupId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }

  static MessageStatus _statusFromString(String? status) {
    switch (status) {
      case 'pending':
        return MessageStatus.pending;
      case 'failed':
        return MessageStatus.failed;
      default:
        return MessageStatus.sent;
    }
  }
}