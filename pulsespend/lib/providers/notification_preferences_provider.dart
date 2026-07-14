import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_preferences_model.dart';
import 'repository_providers.dart';

class NotificationPrefsState {
  final NotificationPreferences prefs;
  final bool isLoading;
  final String? error;

  const NotificationPrefsState({
    this.prefs = const NotificationPreferences(),
    this.isLoading = false,
    this.error,
  });

  NotificationPrefsState copyWith({
    NotificationPreferences? prefs,
    bool? isLoading,
    String? error,
  }) {
    return NotificationPrefsState(
      prefs: prefs ?? this.prefs,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class NotificationPrefsController extends Notifier<NotificationPrefsState> {
  @override
  NotificationPrefsState build() {
    Future.microtask(refresh);
    return const NotificationPrefsState(isLoading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final prefs = await ref.read(notificationRepositoryProvider).getPreferences();
      state = state.copyWith(prefs: prefs, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Optimistically flips a single toggle and persists it, rolling back on error.
  Future<void> setPreference(String key, bool value) async {
    final previous = state.prefs;
    final optimistic = switch (key) {
      'push_enabled' => previous.copyWith(pushEnabled: value),
      'bill_reminders' => previous.copyWith(billReminders: value),
      'goal_reminders' => previous.copyWith(goalReminders: value),
      'budget_alerts' => previous.copyWith(budgetAlerts: value),
      'recurring_alerts' => previous.copyWith(recurringAlerts: value),
      'summary_digest' => previous.copyWith(summaryDigest: value),
      'group_activity' => previous.copyWith(groupActivity: value),
      _ => previous,
    };
    state = state.copyWith(prefs: optimistic);
    try {
      final updated =
          await ref.read(notificationRepositoryProvider).updatePreferences({key: value});
      state = state.copyWith(prefs: updated);
    } catch (e) {
      state = state.copyWith(prefs: previous, error: e.toString());
      rethrow;
    }
  }
}

final notificationPrefsControllerProvider =
    NotifierProvider<NotificationPrefsController, NotificationPrefsState>(
        NotificationPrefsController.new);
