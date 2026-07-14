class IncomeExpenseTrend {
  final List<double> incomeData;
  final List<double> expenseData;
  final List<String> labels;
  final double totalIncome;
  final double totalExpense;
  final double incomeTrend;
  final double expenseTrend;

  const IncomeExpenseTrend({
    required this.incomeData,
    required this.expenseData,
    required this.labels,
    required this.totalIncome,
    required this.totalExpense,
    required this.incomeTrend,
    required this.expenseTrend,
  });

  factory IncomeExpenseTrend.fromJson(Map<String, dynamic> json) {
    return IncomeExpenseTrend(
      incomeData: List<double>.from(json['incomeData'].map((x) => (x as num).toDouble())),
      expenseData: List<double>.from(json['expenseData'].map((x) => (x as num).toDouble())),
      labels: List<String>.from(json['labels']),
      totalIncome: (json['totalIncome'] as num).toDouble(),
      totalExpense: (json['totalExpense'] as num).toDouble(),
      incomeTrend: (json['incomeTrend'] as num).toDouble(),
      expenseTrend: (json['expenseTrend'] as num).toDouble(),
    );
  }
}

class CategorySpending {
  final String name;
  final double amount;
  final double percentage;

  const CategorySpending({
    required this.name,
    required this.amount,
    required this.percentage,
  });

  factory CategorySpending.fromJson(Map<String, dynamic> json) {
    return CategorySpending(
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      percentage: (json['percentage'] as num).toDouble(),
    );
  }
}

/// Compact recap over a completed period (backend AnalyticsModel.getDigest).
class DigestSummary {
  final String range; // 'week' | 'month'
  final double income;
  final double expense;
  final double net;
  final double savingsRate;
  final int transactionCount;
  final String? topCategoryName;
  final double topCategoryAmount;
  final String currency;

  const DigestSummary({
    required this.range,
    required this.income,
    required this.expense,
    required this.net,
    required this.savingsRate,
    required this.transactionCount,
    required this.topCategoryName,
    required this.topCategoryAmount,
    required this.currency,
  });

  factory DigestSummary.fromJson(Map<String, dynamic> json) {
    final top = json['topCategory'] as Map<String, dynamic>?;
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return DigestSummary(
      range: (json['range'] as String?) ?? 'week',
      income: d(json['income']),
      expense: d(json['expense']),
      net: d(json['net']),
      savingsRate: d(json['savingsRate']),
      transactionCount: (json['transactionCount'] as num?)?.toInt() ?? 0,
      topCategoryName: top?['name'] as String?,
      topCategoryAmount: d(top?['amount']),
      currency: (json['currency'] as String?) ?? 'LKR',
    );
  }
}

/// One day's totals for the spending heatmap (backend AnalyticsModel.getDaily).
class DailyTotal {
  final DateTime date;
  final double income;
  final double expense;

  const DailyTotal({required this.date, required this.income, required this.expense});

  factory DailyTotal.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return DailyTotal(
      date: DateTime.parse(json['date'].toString()),
      income: d(json['income']),
      expense: d(json['expense']),
    );
  }
}

/// A single templated spending insight (backend AnalyticsModel.getInsights).
class Insight {
  final String id;
  final String tone; // 'positive' | 'warning' | 'neutral'
  final String title;
  final String body;

  const Insight({required this.id, required this.tone, required this.title, required this.body});

  factory Insight.fromJson(Map<String, dynamic> json) {
    return Insight(
      id: (json['id'] as String?) ?? '',
      tone: (json['tone'] as String?) ?? 'neutral',
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
    );
  }
}

class AnalyticsSummary {
  final String period;
  final IncomeExpenseTrend trend;
  final double savingsRate;
  final List<CategorySpending> topCategories;
  final String currency;

  const AnalyticsSummary({
    required this.period,
    required this.trend,
    required this.savingsRate,
    required this.topCategories,
    required this.currency,
  });

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return AnalyticsSummary(
      period: json['period'] as String,
      trend: IncomeExpenseTrend.fromJson(json['trend']),
      savingsRate: (json['savingsRate'] as num).toDouble(),
      topCategories: (json['topCategories'] as List<dynamic>)
          .map((e) => CategorySpending.fromJson(e as Map<String, dynamic>))
          .toList(),
      currency: (json['currency'] as String?) ?? 'LKR',
    );
  }
}
