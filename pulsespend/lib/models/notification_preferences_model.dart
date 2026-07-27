/// Mirrors the backend `notification_preferences` row. A missing row means
/// everything is enabled, so every field defaults to `true`.
class NotificationPreferences {
  final bool pushEnabled;
  final bool billReminders;
  final bool goalReminders;
  final bool budgetAlerts;
  final bool recurringAlerts;
  final bool summaryDigest;
  final bool groupActivity;

  const NotificationPreferences({
    this.pushEnabled = true,
    this.billReminders = true,
    this.goalReminders = true,
    this.budgetAlerts = true,
    this.recurringAlerts = true,
    this.summaryDigest = true,
    this.groupActivity = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    bool b(dynamic v) => v == null ? true : v == true || v == 'true' || v == 1;
    return NotificationPreferences(
      pushEnabled: b(json['push_enabled']),
      billReminders: b(json['bill_reminders']),
      goalReminders: b(json['goal_reminders']),
      budgetAlerts: b(json['budget_alerts']),
      recurringAlerts: b(json['recurring_alerts']),
      summaryDigest: b(json['summary_digest']),
      groupActivity: b(json['group_activity']),
    );
  }

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? billReminders,
    bool? goalReminders,
    bool? budgetAlerts,
    bool? recurringAlerts,
    bool? summaryDigest,
    bool? groupActivity,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      billReminders: billReminders ?? this.billReminders,
      goalReminders: goalReminders ?? this.goalReminders,
      budgetAlerts: budgetAlerts ?? this.budgetAlerts,
      recurringAlerts: recurringAlerts ?? this.recurringAlerts,
      summaryDigest: summaryDigest ?? this.summaryDigest,
      groupActivity: groupActivity ?? this.groupActivity,
    );
  }
}
