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
