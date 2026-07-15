import 'package:flutter/material.dart';

/// Mirrors the backend `wallets` row (WalletModel.ts). Wallet id 0 is the
/// virtual "Default" bucket for transactions with no wallet assigned.
class WalletModel {
  final int id;
  final String name;
  final String type; // 'cash' | 'bank' | 'card'
  final String currency;

  const WalletModel({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
  });

  factory WalletModel.fromJson(Map<String, dynamic> json) {
    return WalletModel(
      id: int.parse(json['id'].toString()),
      name: (json['name'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'cash',
      currency: (json['currency'] as String?) ?? 'LKR',
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
  final String displayCurrency;

  const WalletBalance({
    required this.wallet,
    required this.income,
    required this.expense,
    required this.balance,
    required this.displayCurrency,
  });

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return WalletBalance(
      wallet: WalletModel.fromJson(json),
      income: d(json['income']),
      expense: d(json['expense']),
      balance: d(json['balance']),
      displayCurrency: (json['display_currency'] as String?) ?? 'LKR',
    );
  }
}
