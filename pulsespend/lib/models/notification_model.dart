/// Mirrors rows from the `notifications` table (see notificationsController.ts
/// getNotificationHistory: id, title, body, type, data, read, created_at).
class NotificationModel {
  final int id;
  final String title;
  final String body;
  final String? type;
  final Map<String, dynamic>? data;
  final bool read;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    this.type,
    this.data,
    this.read = false,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    dynamic rawData = json['data'];
    Map<String, dynamic>? parsedData;
    if (rawData is Map<String, dynamic>) {
      parsedData = rawData;
    }
    return NotificationModel(
      id: int.parse(json['id'].toString()),
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      type: json['type'] as String?,
      data: parsedData,
      read: json['read'] == true,
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }

  NotificationModel copyWith({bool? read}) {
    return NotificationModel(
      id: id,
      title: title,
      body: body,
      type: type,
      data: data,
      read: read ?? this.read,
      createdAt: createdAt,
    );
  }
}
