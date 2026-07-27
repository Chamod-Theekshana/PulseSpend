import 'package:flutter_test/flutter_test.dart';
import 'package:pulsespend/models/wallet_model.dart';

/// Liability wallets invert the usual reading of a balance: charges drive it
/// negative and that negative IS the debt, while repayments pull it back toward
/// zero. These lock in that mapping and the payoff maths built on it.
void main() {
  /// Mirrors what the balances endpoint sends: `borrowed`/`charged`/`repaid`
  /// are split server-side (see financeMath.liabilityBreakdown) and arrive
  /// already converted, alongside the raw totals.
  WalletBalance build({
    required String type,
    double? openingBalance,
    double income = 0,
    double expense = 0,
  }) {
    final borrowed = (openingBalance ?? 0) > 0 ? openingBalance! : 0.0;
    return WalletBalance(
      wallet: WalletModel(
        id: 1,
        name: 'Test',
        type: type,
        currency: 'LKR',
        openingBalance: openingBalance,
      ),
      income: income,
      expense: expense,
      balance: income - expense,
      borrowed: borrowed,
      charged: (expense - borrowed) < 0 ? 0 : expense - borrowed,
      repaid: income,
      displayCurrency: 'LKR',
    );
  }

  group('amountOwed', () {
    test('is the magnitude of a liability wallet\'s negative balance', () {
      // Charged 12,000, repaid 4,000 → owes 8,000.
      final card = build(type: 'credit', income: 4000, expense: 12000);
      expect(card.balance, -8000);
      expect(card.amountOwed, 8000);
    });

    test('is zero once a liability is overpaid (never negative debt)', () {
      final card = build(type: 'card', income: 5000, expense: 3000);
      expect(card.balance, 2000);
      expect(card.amountOwed, 0);
    });

    test('is always zero for asset wallets, even when overdrawn', () {
      final bank = build(type: 'bank', income: 1000, expense: 3000);
      expect(bank.balance, -2000);
      expect(bank.amountOwed, 0);
    });
  });

  group('creditBalance / isOverpaid', () {
    test('surfaces the credit when a debt account is overpaid', () {
      // Charged 12,000, repaid 15,000 → 3,000 sitting in your favour.
      final card = build(type: 'credit', income: 15000, expense: 12000);
      expect(card.amountOwed, 0);
      expect(card.creditBalance, 3000);
      expect(card.isOverpaid, isTrue);
    });

    test('is zero while a debt is still outstanding', () {
      final card = build(type: 'credit', income: 4000, expense: 12000);
      expect(card.creditBalance, 0);
      expect(card.isOverpaid, isFalse);
    });

    test('is zero for asset wallets, which are never "overpaid"', () {
      final bank = build(type: 'bank', income: 50000);
      expect(bank.creditBalance, 0);
      expect(bank.isOverpaid, isFalse);
    });
  });

  group('isPaidOff', () {
    test('true only when a debt existed and is now exactly cleared', () {
      final cleared = build(type: 'loan', openingBalance: 100000, expense: 100000, income: 100000);
      expect(cleared.isPaidOff, isTrue);

      final outstanding = build(type: 'loan', openingBalance: 100000, expense: 100000, income: 40000);
      expect(outstanding.isPaidOff, isFalse);
    });

    test('overpaid is its own state, not paid off', () {
      final overpaid = build(type: 'credit', income: 15000, expense: 12000);
      expect(overpaid.isOverpaid, isTrue);
      expect(overpaid.isPaidOff, isFalse);
    });

    test('never true for a wallet that never had debt, or for assets', () {
      expect(build(type: 'loan').isPaidOff, isFalse);
      expect(build(type: 'bank', income: 5000, expense: 5000).isPaidOff, isFalse);
    });

    test('a settled revolving card counts (settled-for-now, "All clear")', () {
      final card = build(type: 'card', income: 12000, expense: 12000);
      expect(card.isPaidOff, isTrue);
    });
  });

  group('payoffProgress', () {
    test('tracks repayment against the original debt', () {
      // Borrowed 100,000; repaid 10,000 → 10% paid off.
      final loan = build(
        type: 'loan',
        openingBalance: 100000,
        expense: 100000,
        income: 10000,
      );
      expect(loan.amountOwed, 90000);
      expect(loan.payoffProgress, closeTo(0.1, 1e-9));
    });

    test('reaches 1.0 when the debt is fully cleared', () {
      final loan = build(
        type: 'loan',
        openingBalance: 100000,
        expense: 100000,
        income: 100000,
      );
      expect(loan.amountOwed, 0);
      expect(loan.payoffProgress, 1.0);
    });

    test('clamps to 1.0 when overpaid rather than exceeding it', () {
      final loan = build(
        type: 'loan',
        openingBalance: 100000,
        expense: 100000,
        income: 120000,
      );
      expect(loan.payoffProgress, 1.0);
    });

    test('starts at 0.0 when the debt grew past the original and nothing is repaid', () {
      final card = build(
        type: 'credit',
        openingBalance: 10000,
        expense: 25000,
      );
      expect(card.amountOwed, 25000);
      expect(card.payoffProgress, 0.0);
    });

    test('keeps moving when interest grew the debt past the principal', () {
      // The user's own scenario: loan 1,000, then 2,000 of interest/charges.
      // The old (borrowed − owed)/borrowed formula pinned this at 0% forever —
      // owed exceeded borrowed, so no repayment could ever move the bar.
      final loan = build(
        type: 'loan',
        openingBalance: 1000,
        expense: 3000, // 1,000 seed + 2,000 charges
        income: 500, // repaid so far
      );
      expect(loan.amountOwed, 2500);
      // repaid / (borrowed + charged) = 500 / 3,000
      expect(loan.payoffProgress, closeTo(500 / 3000, 1e-9));

      // Repaying the rest completes it.
      final done = build(type: 'loan', openingBalance: 1000, expense: 3000, income: 3000);
      expect(done.payoffProgress, 1.0);
      expect(done.isPaidOff, isTrue);
    });

    test('is null without a starting debt to measure against', () {
      expect(build(type: 'loan', expense: 5000).payoffProgress, isNull);
      expect(build(type: 'loan', openingBalance: 0, expense: 5000).payoffProgress, isNull);
    });

    test('is null for asset wallets even when seeded', () {
      expect(build(type: 'bank', openingBalance: 50000, income: 50000).payoffProgress, isNull);
    });

    test('measures against the converted figure, not the wallet-currency column', () {
      // A USD loan displayed in LKR. `openingBalance` is the raw column — 1,000
      // USD — while every total here is LKR. Dividing one by the other scaled
      // the answer by the exchange rate, so the server sends `borrowed` already
      // converted and that's what progress must use.
      const loan = WalletBalance(
        wallet: WalletModel(
          id: 1,
          name: 'US loan',
          type: 'loan',
          currency: 'USD',
          openingBalance: 1000,
        ),
        income: 30000,
        expense: 300000,
        balance: -270000,
        borrowed: 300000, // 1,000 USD in LKR
        charged: 0,
        repaid: 30000,
        displayCurrency: 'LKR',
      );
      expect(loan.amountOwed, 270000);
      expect(loan.payoffProgress, closeTo(0.1, 1e-9));
    });
  });

  test('opening balance parses from the JSON string Postgres sends for DECIMAL', () {
    final w = WalletModel.fromJson({
      'id': 3,
      'name': 'Car loan',
      'type': 'loan',
      'currency': 'LKR',
      'opening_balance': '100000.00',
    });
    expect(w.openingBalance, 100000);
    expect(w.isLiability, isTrue);
  });

  test('opening balance is null when the wallet started empty', () {
    final w = WalletModel.fromJson({
      'id': 4,
      'name': 'Wallet',
      'type': 'cash',
      'currency': 'LKR',
      'opening_balance': null,
    });
    expect(w.openingBalance, isNull);
    expect(w.isLiability, isFalse);
  });
}
