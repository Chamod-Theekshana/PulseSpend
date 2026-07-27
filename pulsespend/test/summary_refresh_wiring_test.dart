import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pulsespend/core/network/socket_service.dart';
import 'package:pulsespend/models/transaction_model.dart';
import 'package:pulsespend/providers/auth_provider.dart';
import 'package:pulsespend/providers/repository_providers.dart';
import 'package:pulsespend/providers/transactions_provider.dart';
import 'package:pulsespend/models/analytics_model.dart';
import 'package:pulsespend/repositories/analytics_repository.dart';
import 'package:pulsespend/repositories/transaction_repository.dart';

/// The refresh WIRING for the dashboard headline.
///
/// The regression this guards: the backend announced money moves that create no
/// transaction event (IOU settlements, goal funding, opening balances,
/// auto-contributions) with 'tx:summary:invalidate' — emitted from nine server
/// sites and, for a while, heard by nothing. The headline sat stale next to
/// wallet cards that had already updated. These tests pin the two listeners
/// that close that gap.
class _CountingRepo extends TransactionRepository {
  int summaryCalls = 0;

  @override
  Future<TransactionSummary> summary(String userId) async {
    summaryCalls++;
    return TransactionSummary(
      balance: 1000.0 * summaryCalls,
      income: 0,
      expense: 0,
      currency: 'LKR',
    );
  }
}

/// The summary provider also fetches month figures for the home widget; the
/// real repo would hit the network. Throwing is fine — the provider treats a
/// failed month fetch as "skip the widget row".
class _ThrowingAnalyticsRepo extends AnalyticsRepository {
  @override
  Future<AnalyticsSummary> getSummary(String period) async => throw Exception('offline');
}

/// The summary provider watches the transactions controller; the real one
/// hydrates caches and talks to the network, none of which matters here.
class _StubTransactionsController extends TransactionsController {
  @override
  TransactionsState build() => const TransactionsState();
}

void main() {
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  ProviderContainer makeContainer(_CountingRepo repo) {
    final container = ProviderContainer(overrides: [
      transactionRepositoryProvider.overrideWithValue(repo),
      analyticsRepositoryProvider.overrideWithValue(_ThrowingAnalyticsRepo()),
      transactionsControllerProvider.overrideWith(_StubTransactionsController.new),
      currentUserIdProvider.overrideWithValue('1'),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('tx:summary:invalidate refetches the headline', () async {
    final repo = _CountingRepo();
    final container = makeContainer(repo);

    // Keep the autoDispose provider alive like the dashboard does.
    final sub = container.listen(transactionSummaryProvider, (_, __) {});
    addTearDown(sub.close);
    await settle();
    expect(repo.summaryCalls, 1);

    SocketService.instance.simulateEvent('tx:summary:invalidate');
    await settle();
    expect(repo.summaryCalls, 2, reason: 'the server-side invalidate signal must refetch');
    expect(sub.read().asData?.value.balance, 2000);
  });

  test('wallet:changed refetches the headline (money on hand lives in wallets)', () async {
    final repo = _CountingRepo();
    final container = makeContainer(repo);

    final sub = container.listen(transactionSummaryProvider, (_, __) {});
    addTearDown(sub.close);
    await settle();
    expect(repo.summaryCalls, 1);

    SocketService.instance.simulateEvent('wallet:changed');
    await settle();
    expect(repo.summaryCalls, 2);
  });

  test('unrelated events do not refetch', () async {
    final repo = _CountingRepo();
    final container = makeContainer(repo);

    final sub = container.listen(transactionSummaryProvider, (_, __) {});
    addTearDown(sub.close);
    await settle();

    SocketService.instance.simulateEvent('goal:updated');
    await settle();
    expect(repo.summaryCalls, 1, reason: 'goal:updated alone moves no wallet money');
  });
}
