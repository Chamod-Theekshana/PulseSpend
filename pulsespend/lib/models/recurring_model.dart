/// A subscription-like series detected from real transaction history
/// (backend subscriptionDetector.ts) — NOT a recurring rule the user created.
class DetectedSubscription {
  final String name;
  final String seriesKey;
  final int occurrences;
  final int cadenceDays;
  final String cadenceLabel; // 'weekly' | 'monthly' | 'yearly'
  final double lastAmount;
  final double previousAmount;
  final double changePct;
  final String currency;

  const DetectedSubscription({
    required this.name,
    required this.seriesKey,
    required this.occurrences,
    required this.cadenceDays,
    required this.cadenceLabel,
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
      seriesKey: (json['seriesKey'] as String?) ?? '',
      occurrences: (json['occurrences'] as num?)?.toInt() ?? 0,
      cadenceDays: (json['cadenceDays'] as num?)?.toInt() ?? 30,
      cadenceLabel: (json['cadenceLabel'] as String?) ?? 'monthly',
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
  final String? currency;
  final int? walletId; // null = default wallet bucket
  /// Set = this rule is a TRANSFER of |amount| from walletId into this wallet
  /// (0 = default bucket) each run. Null = plain income/expense rule.
  final int? toWalletId;
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
    this.currency,
    this.walletId,
    this.toWalletId,
    this.createdAt,
  });

  bool get isExpense => amount < 0;

  /// The rule's amount normalized to a per-month figure (signed), so mixed
  /// frequencies can be summed into one monthly recurring-commitment total.
  double get monthlyEquivalent => switch (frequency) {
        'daily' => amount * 30.44, // avg days/month
        'weekly' => amount * 4.33, // 52 weeks / 12
        'yearly' => amount / 12,
        _ => amount, // monthly
      };

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
      currency: json['currency'] as String?,
      walletId: json['wallet_id'] != null ? int.tryParse(json['wallet_id'].toString()) : null,
      toWalletId: json['to_wallet_id'] != null ? int.tryParse(json['to_wallet_id'].toString()) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toCreateRequestJson() => {
        'title': title,
        'amount': amount,
        'category': category,
        'frequency': frequency,
        if (currency != null) 'currency': currency,
        if (walletId != null) 'wallet_id': walletId,
        if (toWalletId != null) 'to_wallet_id': toWalletId,
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
        if (currency != null) 'currency': currency,
        'wallet_id': walletId, // explicit null clears to default wallet
      };
}
