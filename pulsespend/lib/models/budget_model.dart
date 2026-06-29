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
