import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/currency_formatter.dart';
import 'profile_provider.dart';
import 'repository_providers.dart';

/// The user's display currency (from the profile). Watching only this field
/// keeps rebuilds tight when unrelated profile data changes.
final displayCurrencyProvider = Provider<String>((ref) {
  return ref.watch(profileControllerProvider.select((s) => s.currency));
});

/// Live FX rates with [base] as the base currency, i.e. `rates[X]` = how many
/// units of X equal 1 [base]. Cached (keepAlive) and re-fetched only when the
/// display currency changes. Refreshed on reconnect via [ref.invalidate].
final exchangeRatesProvider =
    FutureProvider.family<Map<String, double>, String>((ref, base) async {
  ref.keepAlive();
  return ref.read(exchangeRateRepositoryProvider).getAllRates(base);
});

/// Converts and formats amounts from their stored currency into the user's
/// display currency at display time (non-destructive — see Section 3).
/// Falls back to the raw amount when a rate is unavailable, so money is never
/// hidden if FX data fails to load.
class MoneyFormatter {
  final String displayCurrency;
  final Map<String, double>? _rates; // base == displayCurrency, null while loading

  const MoneyFormatter(this.displayCurrency, this._rates);

  /// True once live rates are available (otherwise amounts show unconverted).
  bool get hasRates => _rates != null;

  double convert(num amount, String fromCurrency) {
    final from = fromCurrency.toUpperCase();
    if (from == displayCurrency.toUpperCase()) return amount.toDouble();
    final rate = _rates?[from];
    if (rate == null || rate == 0) return amount.toDouble();
    // rates[from] = units of `from` per 1 display currency ⇒ divide to convert.
    return amount / rate;
  }

  String format(num amount, String fromCurrency, {bool showSign = false}) {
    return CurrencyFormatter.format(
      convert(amount, fromCurrency),
      displayCurrency,
      showSign: showSign,
    );
  }

  String formatCompact(num amount, String fromCurrency) {
    return CurrencyFormatter.formatCompact(convert(amount, fromCurrency), displayCurrency);
  }
}

/// One-stop money formatter for widgets: `ref.watch(moneyFormatterProvider)`
/// then `money.format(tx.amount, tx.currency)`.
final moneyFormatterProvider = Provider<MoneyFormatter>((ref) {
  final display = ref.watch(displayCurrencyProvider);
  final ratesAsync = ref.watch(exchangeRatesProvider(display));
  return MoneyFormatter(display, ratesAsync.asData?.value);
});
