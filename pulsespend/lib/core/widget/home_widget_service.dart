import 'dart:io';
import 'package:home_widget/home_widget.dart';
import '../../models/transaction_model.dart';

/// Pushes the latest balance/spend numbers to the Android home-screen widget
/// (see PulseWidgetProvider.kt). Android-only this cycle; every call is
/// best-effort — widget failures must never break app flows.
class HomeWidgetService {
  HomeWidgetService._();

  static const _providerName = 'PulseWidgetProvider';

  /// [monthIncome]/[monthExpense] are the CURRENT MONTH's figures — the widget
  /// layout is labelled "this month", and it used to be fed lifetime totals
  /// under that label. When the month figures aren't available the row is
  /// skipped rather than mislabelled.
  static Future<void> update(
    TransactionSummary summary, {
    double? monthIncome,
    double? monthExpense,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      String fmt(double n) => n.toStringAsFixed(0);
      await HomeWidget.saveWidgetData<String>(
        'balance',
        '${fmt(summary.balance)} ${summary.currency}',
      );
      if (monthIncome != null && monthExpense != null) {
        await HomeWidget.saveWidgetData<String>(
          'month_spend',
          '↑ ${fmt(monthIncome)}   ↓ ${fmt(monthExpense)}',
        );
      }
      await HomeWidget.updateWidget(name: _providerName, androidName: _providerName);
    } catch (_) {
      // Best-effort: missing plugin (tests) or no widget placed yet.
    }
  }
}
