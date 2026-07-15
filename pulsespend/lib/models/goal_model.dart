/// One row of a goal's deposit/withdrawal timeline (goal_contributions).
class GoalContribution {
  final int id;
  final double amount; // negative = withdrawal
  final String source; // 'manual' | 'auto' | 'roundup'
  final String? contributorName; // set for group goals (who contributed)
  final DateTime? createdAt;

  const GoalContribution({
    required this.id,
    required this.amount,
    required this.source,
    this.contributorName,
    this.createdAt,
  });

  factory GoalContribution.fromJson(Map<String, dynamic> json) {
    return GoalContribution(
      id: int.parse(json['id'].toString()),
      amount: double.parse(json['amount'].toString()),
      source: (json['source'] as String?) ?? 'manual',
      contributorName: json['contributor_name'] as String?,
      createdAt:
          json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }
}

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

  /// Monthly auto-contribution rule (null = off).
  final double? autoAmount;
  final int? autoDay;

  /// Set when the goal is shared with a group (all members can contribute).
  final int? groupId;

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
    this.autoAmount,
    this.autoDay,
    this.groupId,
  });

  double get remaining => (targetAmount - currentAmount).clamp(0, double.infinity);

  /// Amount to save per week to hit the deadline (null without a future deadline).
  double? get requiredPerWeek {
    if (deadline == null || isCompleted || remaining <= 0) return null;
    final days = deadline!.difference(DateTime.now()).inDays;
    if (days <= 0) return null;
    return remaining / (days / 7);
  }

  /// On track = saved at least the linear expectation between creation and
  /// deadline. Null when there's no deadline to pace against.
  bool? get onTrack {
    if (deadline == null || createdAt == null || isCompleted) return null;
    final total = deadline!.difference(createdAt!).inDays;
    if (total <= 0) return null;
    final elapsed = DateTime.now().difference(createdAt!).inDays.clamp(0, total);
    final expected = targetAmount * (elapsed / total);
    return currentAmount >= expected;
  }

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
      autoAmount:
          json['auto_amount'] != null ? double.tryParse(json['auto_amount'].toString()) : null,
      autoDay: json['auto_day'] != null ? int.tryParse(json['auto_day'].toString()) : null,
      groupId: json['group_id'] != null ? int.tryParse(json['group_id'].toString()) : null,
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
        if (groupId != null) 'group_id': groupId,
      };
}
