import 'package:flutter/material.dart';

import '../../features/budgets/screens/budgets_screen.dart';
import '../../features/goals/screens/goals_screen.dart';
import '../../features/groups/screens/groups_screen.dart';
import '../../features/recurring/screens/recurring_screen.dart';
import '../../features/reminders/screens/reminders_screen.dart';

/// Global navigator key (attached to the app's MaterialApp) so notification
/// taps can navigate from outside the widget tree (FCM background/terminated
/// taps, local-notification taps).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Maps a notification `type` (the backend's `data.type` — see sendPushToUser
/// call sites) to the screen that gives it context. Null → just open the app.
Widget? screenForNotificationType(String? type) {
  final t = (type ?? '').toLowerCase();
  if (t.contains('budget')) return const BudgetsScreen();
  if (t.contains('goal')) return const GoalsScreen();
  if (t.contains('group')) return const GroupsScreen();
  if (t.contains('recurring')) return const RecurringScreen();
  if (t.contains('bill') || t.contains('reminder')) return const RemindersScreen();
  return null; // welcome / digest / security / reengagement → home is fine
}

/// Pushes the screen for [type] on the root navigator (no-op for unknown types
/// or when the navigator isn't mounted yet).
void handleNotificationTap(String? type) {
  final screen = screenForNotificationType(type);
  if (screen == null) return;
  appNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => screen),
  );
}
