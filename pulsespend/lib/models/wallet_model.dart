import 'package:flutter/material.dart';

/// Mirrors the backend `wallets` row (WalletModel.ts). Wallet id 0 is the
/// virtual "Default" bucket for transactions with no wallet assigned.
class WalletModel {
  final int id;
  final String name;
  final String type; // 'cash' | 'bank' | 'card'
  final String currency;

  /// What the wallet was seeded with on create; for liabilities, the original
  /// amount owed (positive). Null = it started empty.
  final double? openingBalance;

  /// Spending ceiling for credit/card wallets; a charge past it is refused
  /// server-side. Null = no limit.
  final double? creditLimit;

  const WalletModel({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    this.openingBalance,
    this.creditLimit,
  });

  factory WalletModel.fromJson(Map<String, dynamic> json) {
    final opening = json['opening_balance'];
    final limit = json['credit_limit'];
    return WalletModel(
      id: int.parse(json['id'].toString()),
      name: (json['name'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'cash',
      currency: (json['currency'] as String?) ?? 'LKR',
      // Postgres DECIMAL arrives as a string over JSON.
      openingBalance: opening == null ? null : double.tryParse(opening.toString()),
      creditLimit: limit == null ? null : double.tryParse(limit.toString()),
    );
  }

  IconData get icon => switch (type) {
        'bank' => Icons.account_balance_rounded,
        'card' || 'credit' => Icons.credit_card_rounded,
        'investment' => Icons.trending_up_rounded,
        'loan' => Icons.request_quote_outlined,
        _ => Icons.payments_rounded,
      };

  bool get isLiability => type == 'credit' || type == 'card' || type == 'loan';
}

/// Money on hand at the end of one month (backend `moneyOnHandHistory`).
/// Computed server-side: the client holds only the latest page of transactions
/// and can't tell a transfer leg from a real expense, so it can't derive this.
class BalanceHistoryPoint {
  /// First day of the month this point ends.
  final DateTime month;
  final double balance;

  const BalanceHistoryPoint({required this.month, required this.balance});

  factory BalanceHistoryPoint.fromJson(Map<String, dynamic> json) {
    // Sent as "YYYY-MM".
    final parts = (json['month'] as String? ?? '').split('-');
    return BalanceHistoryPoint(
      month: parts.length == 2
          ? DateTime(int.parse(parts[0]), int.parse(parts[1]))
          : DateTime.now(),
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Aggregated net-worth snapshot (backend WalletModel.netWorth).
class NetWorth {
  final double assets;
  final double liabilities;
  final double netWorth;
  final String currency;
  final List<NetWorthType> byType;

  const NetWorth({
    required this.assets,
    required this.liabilities,
    required this.netWorth,
    required this.currency,
    required this.byType,
  });

  factory NetWorth.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return NetWorth(
      assets: d(json['assets']),
      liabilities: d(json['liabilities']),
      netWorth: d(json['netWorth']),
      currency: (json['currency'] as String?) ?? 'LKR',
      byType: (json['byType'] as List<dynamic>? ?? const [])
          .map((e) => NetWorthType.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class NetWorthType {
  final String type;
  final double total;
  final bool isLiability;

  const NetWorthType({required this.type, required this.total, required this.isLiability});

  factory NetWorthType.fromJson(Map<String, dynamic> json) {
    return NetWorthType(
      type: (json['type'] as String?) ?? 'cash',
      total: (json['total'] as num?)?.toDouble() ?? 0,
      isLiability: json['isLiability'] == true,
    );
  }
}

/// Wallet + its totals, converted to the user's display currency server-side.
class WalletBalance {
  final WalletModel wallet;
  final double income;
  final double expense;
  final double balance;

  /// The three flows behind a debt, split server-side so both screens read one
  /// definition on one currency basis: `borrowed + charged - repaid = owed`.
  /// `expense` alone can't be shown as "charged" — it includes the opening seed.
  final double borrowed;
  final double charged;
  final double repaid;

  final String displayCurrency;

  const WalletBalance({
    required this.wallet,
    required this.income,
    required this.expense,
    required this.balance,
    this.borrowed = 0,
    this.charged = 0,
    this.repaid = 0,
    required this.displayCurrency,
  });

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return WalletBalance(
      // NOTE: the wallet nested here carries `opening_balance` already converted
      // into the display currency (the balances endpoint converts it), unlike
      // the raw value the wallet list returns.
      wallet: WalletModel.fromJson(json),
      income: d(json['income']),
      expense: d(json['expense']),
      balance: d(json['balance']),
      borrowed: d(json['borrowed']),
      charged: d(json['charged']),
      repaid: d(json['repaid']),
      displayCurrency: (json['display_currency'] as String?) ?? 'LKR',
    );
  }

  /// What's still owed on a liability wallet (debt drives the balance negative).
  /// Always 0 for asset wallets.
  double get amountOwed =>
      wallet.isLiability ? (balance < 0 ? -balance : 0) : 0;

  /// Credit sitting on a liability wallet — more has been paid in than charged
  /// (overpaid card, extra loan payment, a refund bigger than the charges).
  /// That's money in your favour, so it counts as an asset rather than a zero.
  double get creditBalance =>
      wallet.isLiability && balance > 0 ? balance : 0;

  /// True when a debt account has tipped into credit — the headline should read
  /// as money you have, not money you owe.
  bool get isOverpaid => creditBalance > 0;

  /// Credit still available on a limited credit/card wallet, or null when no
  /// limit is set. Both sides arrive converted to the display currency.
  double? get availableCredit {
    final limit = wallet.creditLimit;
    if (limit == null || limit <= 0) return null;
    return (limit - amountOwed).clamp(0.0, limit);
  }

  /// How much of the total debt has been repaid, 0–1: `repaid / (borrowed +
  /// charged)`. Null when there's no starting debt to measure against.
  ///
  /// The denominator includes [charged] so interest/fees growing the debt grow
  /// the target instead of breaking the bar: the old `(borrowed − owed)/borrowed`
  /// pinned at 0% forever once owed exceeded the principal, and no repayment
  /// could ever move it again.
  ///
  /// Still gated on `borrowed > 0`: a card seeded with an opening debt is
  /// loan-like and gets the bar, but a pure revolving card must not — "lifetime
  /// repaid ÷ lifetime charged" trends toward a number that never finishes.
  ///
  /// All three figures arrive in the display currency (server-converted), so
  /// the ratio is currency-safe.
  double? get payoffProgress {
    if (!wallet.isLiability || borrowed <= 0) return null;
    final totalDebt = borrowed + charged;
    if (totalDebt <= 0) return null;
    return (repaid / totalDebt).clamp(0.0, 1.0);
  }

  /// A debt account that had debt and now owes nothing. For a loan that means
  /// FINISHED; for a card it means settled-for-now. Overpaid is its own state
  /// (checked first by the UI) — credit in your favour, not merely zero.
  bool get isPaidOff =>
      wallet.isLiability && (borrowed + charged) > 0 && amountOwed == 0 && !isOverpaid;
}
