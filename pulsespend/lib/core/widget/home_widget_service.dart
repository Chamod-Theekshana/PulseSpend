import 'dart:io';
import 'package:home_widget/home_widget.dart';
import '../../models/transaction_model.dart';

/// Pushes the latest balance/spend numbers to the Android home-screen widget
/// (see PulseWidgetProvider.kt). Android-only this cycle; every call is
/// best-effort — widget failures must never break app flows.
class HomeWidgetService {
  HomeWidgetService._();

  static const _providerName = 'PulseWidgetProvider';

  static Future<void> update(TransactionSummary summary) async {
    if (!Platform.isAndroid) return;
    try {
      String fmt(double n) => n.toStringAsFixed(0);
      await HomeWidget.saveWidgetData<String>(
        'balance',
        '${fmt(summary.balance)} ${summary.currency}',
      );
      await HomeWidget.saveWidgetData<String>(
        'month_spend',
        '↑ ${fmt(summary.income)}   ↓ ${fmt(summary.expense)}',
      );
      await HomeWidget.updateWidget(name: _providerName, androidName: _providerName);
    } catch (_) {
      // Best-effort: missing plugin (tests) or no widget placed yet.
    }
  }
}
