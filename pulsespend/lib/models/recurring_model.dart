/// A subscription-like series detected from real transaction history
/// (backend subscriptionDetector.ts) — NOT a recurring rule the user created.
class DetectedSubscription {
  final String name;
  final int occurrences;
  final int cadenceDays;
  final double lastAmount;
  final double previousAmount;
  final double changePct;
  final String currency;

  const DetectedSubscription({
    required this.name,
    required this.occurrences,
    required this.cadenceDays,
    required this.lastAmount,
    required this.previousAmount,
    required this.changePct,
    required this.currency,
  });

  bool get priceIncreased => changePct > 10;

  factory DetectedSubscription.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return DetectedSubscription(
      name: (json['name'] as String?) ?? '',
      occurrences: (json['occurrences'] as num?)?.toInt() ?? 0,
      cadenceDays: (json['cadenceDays'] as num?)?.toInt() ?? 30,
      lastAmount: d(json['lastAmount']),
      previousAmount: d(json['previousAmount']),
      changePct: d(json['changePct']),
      currency: (json['currency'] as String?) ?? 'LKR',
    );
  }
}

/// Mirrors `RecurringRow` in RecurringModel.ts.
class RecurringModel {
  final int id;
  final String userId;
  final String title;
  final double amount;
  final String category;
  final String frequency; // 'daily' | 'weekly' | 'monthly' | 'yearly'
  final DateTime nextRun;
  final bool isActive;
  final DateTime? createdAt;

  const RecurringModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.category,
    required this.frequency,
    required this.nextRun,
    this.isActive = true,
    this.createdAt,
  });

  bool get isExpense => amount < 0;

  factory RecurringModel.fromJson(Map<String, dynamic> json) {
    return RecurringModel(
      id: int.parse(json['id'].toString()),
      userId: json['user_id'].toString(),
      title: json['title'] as String,
      amount: double.parse(json['amount'].toString()),
      category: json['category'] as String,
      frequency: json['frequency'] as String,
      nextRun: DateTime.parse(json['next_run'].toString()),
      isActive: json['is_active'] == true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toCreateRequestJson() => {
        'title': title,
        'amount': amount,
        'category': category,
        'frequency': frequency,
        'startDate': '${nextRun.year.toString().padLeft(4, '0')}-'
            '${nextRun.month.toString().padLeft(2, '0')}-'
            '${nextRun.day.toString().padLeft(2, '0')}',
      };

  Map<String, dynamic> toUpdateRequestJson() => {
        'title': title,
        'amount': amount,
        'category': category,
        'frequency': frequency,
        'is_active': isActive,
      };
}
