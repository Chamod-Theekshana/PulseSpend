/// Mirrors `Goal` interface in GoalModel.ts.
class GoalModel {
  final int id;
  final String userId;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final String currency;
  final DateTime? deadline;
  final bool isCompleted;
  final DateTime? createdAt;
  final double progressPercentage;

  const GoalModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.currency,
    this.deadline,
    this.isCompleted = false,
    this.createdAt,
    this.progressPercentage = 0,
  });

  double get remaining => (targetAmount - currentAmount).clamp(0, double.infinity);

  factory GoalModel.fromJson(Map<String, dynamic> json) {
    return GoalModel(
      id: int.parse(json['id'].toString()),
      userId: json['user_id'].toString(),
      name: json['name'] as String,
      targetAmount: double.parse(json['target_amount'].toString()),
      currentAmount: double.parse((json['current_amount'] ?? 0).toString()),
      currency: (json['currency'] as String?) ?? 'LKR',
      deadline: json['deadline'] != null ? DateTime.tryParse(json['deadline'].toString()) : null,
      isCompleted: json['is_completed'] == true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      progressPercentage: double.parse((json['progress_percentage'] ?? 0).toString()),
    );
  }

  Map<String, dynamic> toRequestJson() => {
        'name': name,
        'target_amount': targetAmount,
        'currency': currency,
        if (deadline != null)
          'deadline': '${deadline!.year.toString().padLeft(4, '0')}-'
              '${deadline!.month.toString().padLeft(2, '0')}-'
              '${deadline!.day.toString().padLeft(2, '0')}',
      };
}
