import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/analytics_model.dart';
import '../core/network/socket_service.dart';
import 'repository_providers.dart';

class AnalyticsPeriodNotifier extends Notifier<String> {
  @override
  String build() {
    final sub = SocketService.instance.on('analytics:invalidate', (_) {
      ref.invalidate(analyticsSummaryProvider);
    });
    ref.onDispose(sub.cancel);
    return 'week';
  }

  void setPeriod(String period) => state = period;
}

final analyticsPeriodProvider = NotifierProvider<AnalyticsPeriodNotifier, String>(AnalyticsPeriodNotifier.new);

/// How the Income-vs-Expenses chart is drawn. Toggled from the card's ⋮ menu.
enum AnalyticsChartType { line, bar }

class AnalyticsChartTypeNotifier extends Notifier<AnalyticsChartType> {
  @override
  AnalyticsChartType build() => AnalyticsChartType.line;

  void set(AnalyticsChartType type) => state = type;
}

final analyticsChartTypeProvider =
    NotifierProvider<AnalyticsChartTypeNotifier, AnalyticsChartType>(AnalyticsChartTypeNotifier.new);

/// Fetches analytics summary for a given period.
/// Uses [keepAlive] so that switching tabs / rebuilding widgets does NOT
/// trigger a new network request — the cached result is reused until the
/// provider is explicitly invalidated (e.g. on pull-to-refresh or socket event).
final analyticsSummaryProvider = FutureProvider.family<AnalyticsSummary, String>((ref, period) async {
  // Keep this provider alive so navigating away and back doesn't re-fetch.
  ref.keepAlive();
  return ref.read(analyticsRepositoryProvider).getSummary(period);
});

/// Per-day totals for the spending heatmap, keyed by (year, month). Listens to
/// the tx events as well as analytics:invalidate so a single missed event
/// can't leave the grid stale; sessionSync also invalidates this on reconnect.
final dailyTotalsProvider =
    FutureProvider.autoDispose.family<List<DailyTotal>, (int, int)>((ref, ym) async {
  final subs = [
    SocketService.instance.on('analytics:invalidate', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:new', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:updated', (_) => ref.invalidateSelf()),
    SocketService.instance.on('tx:deleted', (_) => ref.invalidateSelf()),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });
  return ref.read(analyticsRepositoryProvider).getDaily(ym.$1, ym.$2);
});

/// Templated spending insights for the dashboard card. Invalidated live when
/// the backend signals analytics changed.
final insightsProvider = FutureProvider.autoDispose<List<Insight>>((ref) async {
  final sub = SocketService.instance.on('analytics:invalidate', (_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return ref.read(analyticsRepositoryProvider).getInsights();
});

/// Weekly recap shown as an in-app card (mirrors the scheduled push digest).
final weeklyDigestProvider = FutureProvider.autoDispose<DigestSummary>((ref) async {
  final sub = SocketService.instance.on('digest:new', (_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return ref.read(analyticsRepositoryProvider).getDigest('week');
});

