import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../models/user_model.dart';
import '../models/transaction_model.dart';
import '../models/budget_model.dart';
import '../models/goal_model.dart';
import '../models/category_model.dart';
import '../models/recurring_model.dart';
import '../models/reminder_model.dart';
import '../models/notification_model.dart';
import '../models/wallet_model.dart';
import '../models/group_model.dart';
import '../models/debt_model.dart';

import 'analytics_provider.dart';
import 'budgets_provider.dart';
import 'categories_provider.dart';
import 'currency_provider.dart';
import 'debts_provider.dart';
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

  /// Re-fetch all account-scoped data in a single optimized backend call. 
  /// Used after a socket reconnect (to pick up events missed while offline) 
  /// and on the initial authenticated load.
  Future<void> resync() async {
    try {
      final client = DioClient.instance.dio;
      final response = await client.get(ApiConfig.syncUrl);
      final data = response.data as Map<String, dynamic>;

      // Seed all controllers synchronously with the parsed data
      if (data['profile'] != null) {
        ref.read(profileControllerProvider.notifier).seed(UserModel.fromJson(data['profile']));
      }
      
      if (data['transactions'] != null) {
        final list = (data['transactions'] as List).map((e) => TransactionModel.fromJson(e)).toList();
        ref.read(transactionsControllerProvider.notifier).seed(list);
      }
      
      if (data['budgets'] != null) {
        final list = (data['budgets'] as List).map((e) => BudgetModel.fromJson(e)).toList();
        ref.read(budgetsControllerProvider.notifier).seed(list);
      }
      
      if (data['goals'] != null) {
        final list = (data['goals'] as List).map((e) => GoalModel.fromJson(e)).toList();
        ref.read(goalsControllerProvider.notifier).seed(list);
      }
      
      if (data['categories'] != null) {
        final list = (data['categories'] as List).map((e) => CategoryModel.fromJson(e)).toList();
        ref.read(categoriesControllerProvider.notifier).seed(list);
      }
      
      if (data['recurring'] != null) {
        final list = (data['recurring'] as List).map((e) => RecurringModel.fromJson(e)).toList();
        ref.read(recurringControllerProvider.notifier).seed(list);
      }
      
      if (data['reminders'] != null) {
        final list = (data['reminders'] as List).map((e) => ReminderModel.fromJson(e)).toList();
        ref.read(remindersControllerProvider.notifier).seed(list);
      }
      
      if (data['notifications'] != null) {
        final list = (data['notifications'] as List).map((e) => NotificationModel.fromJson(e)).toList();
        ref.read(notificationsControllerProvider.notifier).seed(list);
      }
      
      if (data['wallets'] != null) {
        final list = (data['wallets'] as List).map((e) => WalletModel.fromJson(e)).toList();
        ref.read(walletsControllerProvider.notifier).seed(list);
      }
      
      if (data['groups'] != null) {
        final list = (data['groups'] as List).map((e) => GroupModel.fromJson(e)).toList();
        ref.read(groupsControllerProvider.notifier).seed(list);
      }
      
      if (data['debts'] != null) {
        final list = (data['debts'] as List).map((e) => DebtModel.fromJson(e)).toList();
        ref.read(debtsControllerProvider.notifier).seed(list);
      }
    } catch (e) {
      // Fallback: If the sync endpoint fails, we let the providers try to
      // refresh themselves individually (which they do on boot anyway, but this
      // acts as a fallback for reconnects).
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
        ref.read(debtsControllerProvider.notifier).refresh(),
      ]);
    }

    // Family / future providers can't be refreshed by name → invalidate them.
    // Missing one here means it goes permanently stale after any socket
    // reconnect (missed events are never replayed) — list them ALL.
    ref.invalidate(analyticsSummaryProvider);
    ref.invalidate(dailyTotalsProvider);
    ref.invalidate(insightsProvider);
    ref.invalidate(weeklyDigestProvider);
    ref.invalidate(dashboardTransactionsProvider);
    ref.invalidate(walletBalancesProvider);
    ref.invalidate(netWorthProvider);
    ref.invalidate(balanceHistoryProvider);
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
    ref.invalidate(netWorthProvider);
    ref.invalidate(balanceHistoryProvider);
    ref.invalidate(walletsControllerProvider);
    ref.invalidate(groupsControllerProvider);
    ref.invalidate(debtsControllerProvider);
  }
}

final sessionSyncProvider =
    NotifierProvider<SessionSyncController, void>(SessionSyncController.new);
