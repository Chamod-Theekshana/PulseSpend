class ChatMessage {
  final int id;
  final int groupId;
  final String userId;
  final String senderName;
  final String content;
  final DateTime createdAt;
  bool isMe;

  ChatMessage({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.senderName,
    required this.content,
    required this.createdAt,
    this.isMe = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      groupId: json['group_id'] as int,
      userId: json['user_id'].toString(),
      senderName: json['sender_name'] ?? 'Unknown',
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group_id': groupId,
      'user_id': userId,
      'sender_name': senderName,
      'content': content,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
