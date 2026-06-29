/// Mirrors `transaction_splits` rows from TransactionModel.ts.
class TransactionSplit {
  final int? id;
  final String category;
  final double amount; // negative for expense splits, per backend convention
  final double percentage;

  const TransactionSplit({
    this.id,
    required this.category,
    required this.amount,
    required this.percentage,
  });

  factory TransactionSplit.fromJson(Map<String, dynamic> json) {
    return TransactionSplit(
      id: json['id'] != null ? int.parse(json['id'].toString()) : null,
      category: json['category'] as String,
      amount: double.parse(json['amount'].toString()),
      percentage: double.parse((json['percentage'] ?? 0).toString()),
    );
  }

  /// Shape expected by the backend on create/update (category + amount only;
  /// percentage and sign are computed server-side in validateTransactionBody).
  Map<String, dynamic> toRequestJson() => {
        'category': category,
        'amount': amount.abs(),
      };
}

/// Mirrors `Transaction` interface in TransactionModel.ts exactly.
class TransactionModel {
  final int id;
  final String userId;
  final String title;
  final double amount; // negative = expense, positive = income
  final String currency;
  final String category;
  final DateTime createdAt;
  final String? notes;
  final String? receiptUrl;
  final List<String> tags;
  final List<TransactionSplit> splits;

  const TransactionModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.currency,
    required this.category,
    required this.createdAt,
    this.notes,
    this.receiptUrl,
    this.tags = const [],
    this.splits = const [],
  });

  bool get isExpense => amount < 0;
  bool get isIncome => amount > 0;
  bool get isSplit => splits.isNotEmpty;

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: int.parse(json['id'].toString()),
      userId: json['user_id'].toString(),
      title: json['title'] as String,
      amount: double.parse(json['amount'].toString()),
      currency: (json['currency'] as String?) ?? 'LKR',
      category: json['category'] as String,
      createdAt: DateTime.parse(json['created_at'].toString()),
      notes: json['notes'] as String?,
      receiptUrl: json['receipt_url'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      splits: (json['splits'] as List<dynamic>?)
              ?.map((e) => TransactionSplit.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  /// Body for POST /api/transaction and PUT /api/transaction/:id.
  Map<String, dynamic> toRequestJson() {
    return {
      'title': title,
      'amount': amount,
      'category': category,
      'created_at': '${createdAt.year.toString().padLeft(4, '0')}-'
          '${createdAt.month.toString().padLeft(2, '0')}-'
          '${createdAt.day.toString().padLeft(2, '0')}',
      'currency': currency,
      if (receiptUrl != null) 'receipt_url': receiptUrl,
      if (notes != null) 'notes': notes,
      if (tags.isNotEmpty) 'tags': tags,
      if (splits.isNotEmpty) 'splits': splits.map((s) => s.toRequestJson()).toList(),
    };
  }

  TransactionModel copyWith({
    String? title,
    double? amount,
    String? currency,
    String? category,
    DateTime? createdAt,
    String? notes,
    String? receiptUrl,
    List<String>? tags,
    List<TransactionSplit>? splits,
  }) {
    return TransactionModel(
      id: id,
      userId: userId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      tags: tags ?? this.tags,
      splits: splits ?? this.splits,
    );
  }
}

class TransactionSummary {
  final double balance;
  final double income;
  final double expense;
  final String currency;

  const TransactionSummary({
    required this.balance,
    required this.income,
    required this.expense,
    required this.currency,
  });

  factory TransactionSummary.fromJson(Map<String, dynamic> json) {
    return TransactionSummary(
      balance: double.parse(json['balance'].toString()),
      income: double.parse(json['income'].toString()),
      expense: double.parse(json['expense'].toString()),
      currency: (json['currency'] as String?) ?? 'LKR',
    );
  }

  static const empty = TransactionSummary(balance: 0, income: 0, expense: 0, currency: 'LKR');
}
