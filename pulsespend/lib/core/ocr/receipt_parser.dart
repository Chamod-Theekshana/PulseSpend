import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Best-effort fields parsed from a receipt photo. Null = not confident —
/// callers must leave the corresponding form field untouched rather than guess.
class ReceiptScanResult {
  final double? amount;
  final DateTime? date;
  final String? merchant;
  final String rawText;

  const ReceiptScanResult({this.amount, this.date, this.merchant, this.rawText = ''});

  bool get isEmpty => amount == null && date == null && merchant == null;
}

/// On-device OCR (ML Kit) + conservative regex parsing for receipts.
/// Free, offline, no API keys — preferred over a server-side Vision call.
class ReceiptParser {
  ReceiptParser._();

  /// Money value like 1,234.56 / 1234.56 — two decimals required, so random
  /// integers (phone numbers, item counts) never match.
  static final _money = RegExp(r'(\d{1,3}(?:[,\s]\d{3})+|\d+)\.(\d{2})\b');

  /// Lines that most likely carry the receipt total.
  static final _totalHint =
      RegExp(r'total|amount|net|grand|balance due|to pay', caseSensitive: false);

  /// Rejects the "change/cash given" style lines that also carry money values.
  static final _antiHint = RegExp(r'change|cash|tender|vat|tax\b', caseSensitive: false);

  static Future<ReceiptScanResult> scan(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return parseText(result.text);
    } catch (_) {
      return const ReceiptScanResult();
    } finally {
      await recognizer.close();
    }
  }

  /// Pure text → fields (separated from OCR so it's unit-testable).
  static ReceiptScanResult parseText(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return ReceiptScanResult(
      amount: _parseAmount(lines),
      date: _parseDate(lines),
      merchant: _parseMerchant(lines),
      rawText: text,
    );
  }

  static double? _parseAmount(List<String> lines) {
    double toValue(RegExpMatch m) =>
        double.parse('${m.group(1)!.replaceAll(RegExp(r'[,\s]'), '')}.${m.group(2)}');

    // 1st choice: money on a "total"-ish line (largest wins if several).
    final totals = <double>[];
    for (final line in lines) {
      if (_totalHint.hasMatch(line) && !_antiHint.hasMatch(line)) {
        totals.addAll(_money.allMatches(line).map(toValue));
      }
    }
    if (totals.isNotEmpty) {
      return totals.reduce((a, b) => a > b ? a : b);
    }

    // Fallback: the largest money value anywhere (usually the total).
    final all = <double>[];
    for (final line in lines) {
      if (_antiHint.hasMatch(line)) continue;
      all.addAll(_money.allMatches(line).map(toValue));
    }
    if (all.isEmpty) return null;
    final max = all.reduce((a, b) => a > b ? a : b);
    return max > 0 ? max : null;
  }

  static DateTime? _parseDate(List<String> lines) {
    final iso = RegExp(r'\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b');
    final dmy = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2}|\d{2})\b');

    for (final line in lines) {
      final mIso = iso.firstMatch(line);
      if (mIso != null) {
        final d = _tryDate(int.parse(mIso.group(1)!), int.parse(mIso.group(2)!), int.parse(mIso.group(3)!));
        if (d != null) return d;
      }
      final mDmy = dmy.firstMatch(line);
      if (mDmy != null) {
        final a = int.parse(mDmy.group(1)!);
        final b = int.parse(mDmy.group(2)!);
        var y = int.parse(mDmy.group(3)!);
        if (y < 100) y += 2000;
        // day-first unless impossible (matches the CSV importer's convention).
        final d = a > 12 ? _tryDate(y, b, a) : (b > 12 ? _tryDate(y, a, b) : _tryDate(y, b, a));
        if (d != null) return d;
      }
    }
    return null;
  }

  static DateTime? _tryDate(int y, int m, int d) {
    if (y < 2000 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, m, d);
    // Receipts are from the past (small tolerance for timezone edges).
    if (date.isAfter(DateTime.now().add(const Duration(days: 1)))) return null;
    return date;
  }

  static String? _parseMerchant(List<String> lines) {
    for (final line in lines.take(4)) {
      final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
      // A merchant line is mostly letters and not a hint/date/amount row.
      if (letters.length >= 3 &&
          letters.length >= line.length * 0.5 &&
          !_totalHint.hasMatch(line) &&
          !_money.hasMatch(line)) {
        final cleaned = line.replaceAll(RegExp(r'\s+'), ' ').trim();
        return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
      }
    }
    return null;
  }
}
