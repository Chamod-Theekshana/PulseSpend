/// Mirrors `ReminderRow` in ReminderModel.ts.
class ReminderModel {
  final int id;
  final String userId;
  final String title;
  final double amount;
  final String currency;
  final String category;
  final DateTime dueDate;
  final int remindDaysBefore;
  final bool isActive;
  final DateTime? lastNotifiedOn;
  final DateTime? createdAt;

  const ReminderModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.currency,
    required this.category,
    required this.dueDate,
    this.remindDaysBefore = 1,
    this.isActive = true,
    this.lastNotifiedOn,
    this.createdAt,
  });

  bool get isOverdue => dueDate.isBefore(DateTime.now()) &&
      !(DateTime.now().year == dueDate.year &&
          DateTime.now().month == dueDate.month &&
          DateTime.now().day == dueDate.day);

  int get daysUntilDue => dueDate.difference(DateTime.now()).inDays;

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    return ReminderModel(
      id: int.parse(json['id'].toString()),
      userId: json['user_id'].toString(),
      title: json['title'] as String,
      amount: double.parse(json['amount'].toString()),
      currency: (json['currency'] as String?) ?? 'LKR',
      category: json['category'] as String,
      dueDate: DateTime.parse(json['due_date'].toString()),
      remindDaysBefore: int.parse((json['remind_days_before'] ?? 1).toString()),
      isActive: json['is_active'] == true,
      lastNotifiedOn:
          json['last_notified_on'] != null ? DateTime.tryParse(json['last_notified_on'].toString()) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toRequestJson() => {
        'title': title,
        'amount': amount,
        'category': category,
        'due_date': '${dueDate.year.toString().padLeft(4, '0')}-'
            '${dueDate.month.toString().padLeft(2, '0')}-'
            '${dueDate.day.toString().padLeft(2, '0')}',
        'remind_days_before': remindDaysBefore,
        'currency': currency,
        'is_active': isActive,
      };
}
