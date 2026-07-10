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

/// Fetches analytics summary for a given period.
/// Uses [keepAlive] so that switching tabs / rebuilding widgets does NOT
/// trigger a new network request — the cached result is reused until the
/// provider is explicitly invalidated (e.g. on pull-to-refresh or socket event).
final analyticsSummaryProvider = FutureProvider.family<AnalyticsSummary, String>((ref, period) async {
  // Keep this provider alive so navigating away and back doesn't re-fetch.
  ref.keepAlive();
  return ref.read(analyticsRepositoryProvider).getSummary(period);
});

