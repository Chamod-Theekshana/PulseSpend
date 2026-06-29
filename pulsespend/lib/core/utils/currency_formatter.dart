import 'package:intl/intl.dart';

/// Formats amounts using the user's preferred currency (stored on the
/// profile — see `users.currency`, default 'LKR' per db.ts).
class CurrencyFormatter {
  CurrencyFormatter._();

  static const Map<String, String> _symbols = {
    'LKR': 'Rs.',
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'INR': '₹',
    'AUD': r'A$',
    'JPY': '¥',
    'CAD': r'C$',
  };

  static String symbolFor(String currencyCode) =>
      _symbols[currencyCode.toUpperCase()] ?? '${currencyCode.toUpperCase()} ';

  static String format(num amount, String currencyCode, {bool showSign = false}) {
    final symbol = symbolFor(currencyCode);
    final formatter = NumberFormat('#,##0.00');
    final abs = formatter.format(amount.abs());
    final sign = amount < 0 ? '-' : (showSign ? '+' : '');
    return '$sign$symbol$abs';
  }

  /// Compact form for tight spaces, e.g. "Rs.12.4K"
  static String formatCompact(num amount, String currencyCode) {
    final symbol = symbolFor(currencyCode);
    final formatter = NumberFormat.compact();
    final sign = amount < 0 ? '-' : '';
    return '$sign$symbol${formatter.format(amount.abs())}';
  }
}
