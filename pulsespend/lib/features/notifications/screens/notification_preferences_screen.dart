import 'package:flutter/material.dart';
import '../../../shared/widgets/app_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/notification_preferences_provider.dart';
import '../../profile/widgets/settings_widgets.dart';

class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, String key, bool value) async {
    try {
      await ref.read(notificationPrefsControllerProvider.notifier).setPreference(key, value);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationPrefsControllerProvider);
    final prefs = state.prefs;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final pushOn = prefs.pushEnabled;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Notifications')),
      body: state.isLoading
          ? const Center(child: AppLoader(size: 40))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                SettingsCard(
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.notifications_active_outlined,
                      title: 'Push notifications',
                      subtitle: 'Master switch for all alerts on this account',
                      value: prefs.pushEnabled,
                      onChanged: (v) => _set(context, ref, 'push_enabled', v),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SettingsSectionTitle('Alert types'),
                Opacity(
                  opacity: pushOn ? 1 : 0.5,
                  child: IgnorePointer(
                    ignoring: !pushOn,
                    child: SettingsCard(
                      children: [
                        SettingsSwitchTile(
                          icon: Icons.receipt_long_outlined,
                          title: 'Bill reminders',
                          subtitle: 'Upcoming bills and due-date reminders',
                          value: prefs.billReminders,
                          onChanged: (v) => _set(context, ref, 'bill_reminders', v),
                        ),
                        SettingsSwitchTile(
                          icon: Icons.savings_outlined,
                          title: 'Goal reminders',
                          subtitle: 'Progress nudges and deadline alerts',
                          value: prefs.goalReminders,
                          onChanged: (v) => _set(context, ref, 'goal_reminders', v),
                        ),
                        SettingsSwitchTile(
                          icon: Icons.pie_chart_outline,
                          title: 'Budget alerts',
                          subtitle: 'When a category nears or exceeds its budget',
                          value: prefs.budgetAlerts,
                          onChanged: (v) => _set(context, ref, 'budget_alerts', v),
                        ),
                        SettingsSwitchTile(
                          icon: Icons.autorenew_rounded,
                          title: 'Recurring transactions',
                          subtitle: 'When a scheduled transaction is added',
                          value: prefs.recurringAlerts,
                          onChanged: (v) => _set(context, ref, 'recurring_alerts', v),
                        ),
                        SettingsSwitchTile(
                          icon: Icons.insights_outlined,
                          title: 'Weekly & monthly recap',
                          subtitle: 'A spending summary every Monday and month start',
                          value: prefs.summaryDigest,
                          onChanged: (v) => _set(context, ref, 'summary_digest', v),
                        ),
                        SettingsSwitchTile(
                          icon: Icons.groups_outlined,
                          title: 'Shared group activity',
                          subtitle: 'When a member adds a big expense or joins your group',
                          value: prefs.groupActivity,
                          onChanged: (v) => _set(context, ref, 'group_activity', v),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    pushOn
                        ? 'Muted types are dropped entirely — they won\'t appear in your inbox or as a push.'
                        : 'All notifications are off. Turn on push notifications to choose alert types.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
