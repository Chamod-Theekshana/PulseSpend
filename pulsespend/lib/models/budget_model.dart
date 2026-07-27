/// Mirrors `BudgetStatus` (BudgetRow + computed spend fields) in BudgetModel.ts.
/// `GET /api/budgets` returns bare BudgetRow; `GET /api/budgets/status`
/// returns the enriched BudgetStatus — both parse fine here since the extra
/// fields are simply absent/defaulted for the bare list endpoint.
class BudgetModel {
  final int id;
  final String userId;
  final String category;
  final double amount;
  final String currency;
  final String period; // currently always 'monthly'
  final DateTime? createdAt;
  final double spent;
  final double percentage;
  final double remaining;
  final bool conversionError;

  const BudgetModel({
    required this.id,
    required this.userId,
    required this.category,
    required this.amount,
    required this.currency,
    required this.period,
    this.createdAt,
    this.spent = 0,
    this.percentage = 0,
    this.remaining = 0,
    this.conversionError = false,
  });

  bool get isExceeded => percentage >= 100;
  bool get isWarning => percentage >= 80 && percentage < 100;

  /// Human label for the budget's period ("Weekly" / "Monthly" / "Yearly").
  String get periodLabel => switch (period) {
        'weekly' => 'Weekly',
        'yearly' => 'Yearly',
        _ => 'Monthly',
      };

  /// Days remaining in the current period, inclusive of today (≥ 1).
  int get daysLeftInPeriod {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final DateTime periodEnd = switch (period) {
      'weekly' => today.add(Duration(days: 7 - now.weekday)), // ISO week ends Sunday
      'yearly' => DateTime(now.year, 12, 31),
      _ => DateTime(now.year, now.month + 1, 0), // last day of this month
    };
    return periodEnd.difference(today).inDays + 1;
  }

  /// Remaining budget spread evenly over the days left in the period. Zero once
  /// the budget is spent; used for the "Rs.X/day left" hint.
  double get dailyAllowance {
    if (remaining <= 0) return 0;
    final days = daysLeftInPeriod;
    return days <= 0 ? remaining : remaining / days;
  }

  int get _periodTotalDays {
    final now = DateTime.now();
    return switch (period) {
      'weekly' => 7,
      'yearly' => DateTime(now.year, 12, 31).difference(DateTime(now.year, 1, 1)).inDays + 1,
      _ => DateTime(now.year, now.month + 1, 0).day,
    };
  }

  /// True when the current spend pace projects to blow the limit before the
  /// period ends (mirrors the backend pacing alert). False once already over
  /// (the percentage badge already shows that).
  bool get isPacingOver {
    if (isExceeded || spent <= 0) return false;
    final total = _periodTotalDays;
    final elapsed = total - daysLeftInPeriod + 1;
    if (elapsed <= 0) return false;
    final frac = elapsed / total;
    if (frac < 0.25) return false; // too early to project
    return (spent / frac) > amount;
  }

  factory BudgetModel.fromJson(Map<String, dynamic> json) {
    final amount = double.parse(json['amount'].toString());
    final spent = json['spent'] != null ? double.parse(json['spent'].toString()) : 0.0;
    return BudgetModel(
      id: int.parse(json['id'].toString()),
      userId: json['user_id'].toString(),
      category: json['category'] as String,
      amount: amount,
      currency: (json['currency'] as String?) ?? 'LKR',
      period: (json['period'] as String?) ?? 'monthly',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      spent: spent,
      percentage: json['percentage'] != null
          ? double.parse(json['percentage'].toString())
          : (amount > 0 ? (spent / amount) * 100 : 0),
      remaining: json['remaining'] != null
          ? double.parse(json['remaining'].toString())
          : (amount - spent).clamp(0, double.infinity),
      conversionError: json['conversion_error'] == true,
    );
  }

  Map<String, dynamic> toCreateRequestJson() => {
        'category': category,
        'amount': amount,
        'currency': currency,
        'period': period,
      };

  Map<String, dynamic> toUpdateRequestJson() => {'amount': amount};
}

/// Overall monthly spending cap vs actual (backend BudgetModel.getTotalStatus).
/// [amount] is null when no total budget has been set.
class TotalBudgetStatus {
  final double? amount;
  final String currency;
  final double spent;
  final double percentage;
  final double remaining;
  final bool conversionError;

  const TotalBudgetStatus({
    required this.amount,
    required this.currency,
    required this.spent,
    required this.percentage,
    required this.remaining,
    required this.conversionError,
  });

  bool get isSet => amount != null && amount! > 0;
  bool get isExceeded => percentage >= 100;
  bool get isWarning => percentage >= 80 && percentage < 100;

  factory TotalBudgetStatus.fromJson(Map<String, dynamic> json) {
    double? amt() => json['amount'] == null ? null : double.tryParse(json['amount'].toString());
    double d(dynamic v) => v == null ? 0 : (double.tryParse(v.toString()) ?? 0);
    return TotalBudgetStatus(
      amount: amt(),
      currency: (json['currency'] as String?) ?? 'LKR',
      spent: d(json['spent']),
      percentage: d(json['percentage']),
      remaining: d(json['remaining']),
      conversionError: json['conversion_error'] == true,
    );
  }
}
