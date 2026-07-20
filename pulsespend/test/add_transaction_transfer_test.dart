import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pulsespend/features/transactions/screens/add_transaction_screen.dart';
import 'package:pulsespend/models/wallet_model.dart';
import 'package:pulsespend/providers/repository_providers.dart';
import 'package:pulsespend/repositories/wallet_repository.dart';
import 'package:pulsespend/shared/widgets/primary_button.dart';

const _bank = WalletModel(id: 1, name: 'Bank', type: 'bank', currency: 'LKR');
const _loan = WalletModel(id: 2, name: 'Car loan', type: 'loan', currency: 'LKR', openingBalance: 100000);

/// Bank holds 50,000; the loan still owes 90,000 of the original 100,000.
final _balances = [
  const WalletBalance(
      wallet: _bank, income: 50000, expense: 0, balance: 50000, displayCurrency: 'LKR'),
  const WalletBalance(
      wallet: _loan, income: 10000, expense: 100000, balance: -90000, displayCurrency: 'LKR'),
];

class _FakeWalletRepo extends WalletRepository {
  /// Records what a submitted transfer actually asked the backend to do.
  ({int from, int to, double amount})? lastTransfer;

  @override
  Future<List<WalletModel>> list() async => const [_bank, _loan];

  @override
  Future<List<WalletBalance>> balances() async => _balances;

  @override
  Future<void> transfer({
    required int fromWalletId,
    required int toWalletId,
    required double amount,
  }) async {
    lastTransfer = (from: fromWalletId, to: toWalletId, amount: amount);
  }
}

/// Balances that don't arrive on the first frame, like a real network fetch.
class _SlowWalletRepo extends _FakeWalletRepo {
  @override
  Future<List<WalletBalance>> balances() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return _balances;
  }
}

/// Opens the From (0) or To (1) dropdown and picks [walletName] from the menu.
/// Taps the DropdownButton itself rather than its hint text — the hint isn't
/// reliably in the hit path and tapping it warns.
Future<void> _choose(WidgetTester tester, int end, String walletName) async {
  await tester.tap(find.byType(DropdownButton<int>).at(end));
  await tester.pumpAndSettle();
  await tester.tap(find.text(walletName).last);
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(WidgetTester tester, _FakeWalletRepo repo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [walletRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: AddTransactionScreen()),
  ));
  // Let WalletsController.refresh() and the balances provider resolve.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('Transfer sits alongside Expense and Income once wallets exist', (tester) async {
    await _pumpScreen(tester, _FakeWalletRepo());
    expect(tester.takeException(), isNull);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
  });

  testWidgets('picking Transfer swaps the entry fields for the two wallet ends', (tester) async {
    await _pumpScreen(tester, _FakeWalletRepo());

    // Expense mode: a title and a category, no wallet ends.
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('From wallet'), findsNothing);

    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    // Transfer mode: title/category/date/tags don't describe money changing
    // pockets, so they give way to the two ends.
    expect(tester.takeException(), isNull);
    expect(find.text('From wallet'), findsOneWidget);
    expect(find.text('To wallet'), findsOneWidget);
    expect(find.text('Title'), findsNothing);
    expect(find.text('Category'), findsNothing);
    expect(find.text('Tags'), findsNothing);
  });

  testWidgets('says it is loading rather than showing empty wallet ends', (tester) async {
    // Two blank dropdowns while the balances fetch is in flight would read as
    // "you have no wallets". The screen now watches the balances from first
    // build (the wallet balance line pre-warms them), so to catch the in-flight
    // window the tap has to happen before the slow fetch resolves — no settling
    // pump first.
    final repo = _SlowWalletRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [walletRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: AddTransactionScreen()),
    ));
    await tester.pump(); // first frame + microtasks; the 30ms fetch is still out

    await tester.tap(find.text('Transfer'));
    await tester.pump();

    expect(find.text('Loading wallets…'), findsNWidgets(2));
    expect(find.byType(DropdownButton<int>), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Loading wallets…'), findsNothing);
    expect(find.byType(DropdownButton<int>), findsNWidgets(2));
  });

  testWidgets('a repayment submits as a transfer, not an income transaction', (tester) async {
    final repo = _FakeWalletRepo();
    await _pumpScreen(tester, repo);

    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '10000');
    await tester.pump();

    await _choose(tester, 0, 'Bank');
    await _choose(tester, 1, 'Car loan');

    await tester.tap(find.widgetWithText(PrimaryButton, 'Transfer'));
    await tester.pumpAndSettle();

    // Bank pays the loan: money leaves one wallet and lands on the debt.
    expect(repo.lastTransfer, isNotNull);
    expect(repo.lastTransfer!.from, _bank.id);
    expect(repo.lastTransfer!.to, _loan.id);
    expect(repo.lastTransfer!.amount, 10000);
  });

  testWidgets('a wallet chosen on one end is not offered on the other', (tester) async {
    await _pumpScreen(tester, _FakeWalletRepo());

    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    // Both ends offer everything until one is picked.
    List<DropdownButton<int>> dropdowns() =>
        tester.widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>)).toList();
    expect(dropdowns(), hasLength(2));
    expect(dropdowns()[1].items!.map((i) => i.value), containsAll([_bank.id, _loan.id]));

    await _choose(tester, 0, 'Bank');

    // Bank is taken, so the "to" end must not offer it — transferring a wallet
    // to itself is meaningless and the backend rejects it. The Default bucket
    // (id 0) is always offered: it's a legitimate destination even when empty.
    expect(dropdowns()[0].value, _bank.id);
    expect(dropdowns()[1].items!.map((i) => i.value), [0, _loan.id]);
  });
}
