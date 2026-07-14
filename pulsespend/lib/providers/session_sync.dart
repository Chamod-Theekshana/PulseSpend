import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_provider.dart';
import 'budgets_provider.dart';
import 'categories_provider.dart';
import 'currency_provider.dart';
import 'goals_provider.dart';
import 'groups_provider.dart';
import 'notification_preferences_provider.dart';
import 'notifications_provider.dart';
import 'profile_provider.dart';
import 'recurring_provider.dart';
import 'reminders_provider.dart';
import 'transactions_provider.dart';
import 'wallets_provider.dart';

/// Central coordinator that knows every account-scoped provider, so real-time
/// recovery and account switching stay correct and leak-free. Exposed as a
/// Notifier so both widgets (`ref.read(sessionSyncProvider.notifier)`) and
/// other providers can drive it with a single source of truth.
class SessionSyncController extends Notifier<void> {
  @override
  void build() {}

  /// Re-fetch all account-scoped data. Used after a socket reconnect (to pick
  /// up events missed while offline) and on the initial authenticated load.
  Future<void> resync() async {
    await Future.wait([
      ref.read(profileControllerProvider.notifier).refresh(),
      ref.read(transactionsControllerProvider.notifier).refresh(),
      ref.read(budgetsControllerProvider.notifier).refresh(),
      ref.read(goalsControllerProvider.notifier).refresh(),
      ref.read(categoriesControllerProvider.notifier).refresh(),
      ref.read(recurringControllerProvider.notifier).refresh(),
      ref.read(remindersControllerProvider.notifier).refresh(),
      ref.read(notificationsControllerProvider.notifier).refresh(),
      ref.read(walletsControllerProvider.notifier).refresh(),
      ref.read(groupsControllerProvider.notifier).refresh(),
    ]);
    // Family / future providers can't be refreshed by name → invalidate them.
    // Missing one here means it goes permanently stale after any socket
    // reconnect (missed events are never replayed) — list them ALL.
    ref.invalidate(analyticsSummaryProvider);
    ref.invalidate(dailyTotalsProvider);
    ref.invalidate(insightsProvider);
    ref.invalidate(weeklyDigestProvider);
    ref.invalidate(dashboardTransactionsProvider);
    ref.invalidate(walletBalancesProvider);
    ref.invalidate(notificationPrefsControllerProvider);
    ref.invalidate(exchangeRatesProvider);
  }

  /// Invalidate every account-scoped provider so a freshly switched account
  /// starts from a clean slate with no cached data leaking across accounts.
  void reset() {
    ref.invalidate(transactionsControllerProvider);
    ref.invalidate(budgetsControllerProvider);
    ref.invalidate(goalsControllerProvider);
    ref.invalidate(categoriesControllerProvider);
    ref.invalidate(recurringControllerProvider);
    ref.invalidate(remindersControllerProvider);
    ref.invalidate(notificationsControllerProvider);
    ref.invalidate(notificationPrefsControllerProvider);
    ref.invalidate(analyticsSummaryProvider);
    ref.invalidate(dailyTotalsProvider);
    ref.invalidate(insightsProvider);
    ref.invalidate(weeklyDigestProvider);
    ref.invalidate(dashboardTransactionsProvider);
    ref.invalidate(walletBalancesProvider);
    ref.invalidate(walletsControllerProvider);
    ref.invalidate(groupsControllerProvider);
  }
}

final sessionSyncProvider =
    NotifierProvider<SessionSyncController, void>(SessionSyncController.new);
