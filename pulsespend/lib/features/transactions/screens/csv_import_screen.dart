import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/repository_providers.dart';
import '../../../providers/transactions_provider.dart';
import '../../../shared/widgets/primary_button.dart';

/// Bank-statement CSV import: pick a file → map which columns hold the date /
/// title / amount (+ optional category) → preview → bulk import. Rows carry a
/// deterministic client_op_id, so importing the same file twice can't create
/// duplicates (see bulkImportTransactions on the backend).
class CsvImportScreen extends ConsumerStatefulWidget {
  const CsvImportScreen({super.key});

  @override
  ConsumerState<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends ConsumerState<CsvImportScreen> {
  List<List<String>> _rows = [];
  bool _hasHeader = true;
  int? _dateCol;
  int? _titleCol;
  int? _amountCol;
  int? _categoryCol; // optional
  bool _amountsAreExpenses = true;
  bool _importing = false;
  String? _fileName;

  int get _columnCount => _rows.isEmpty ? 0 : _rows.first.length;
  List<List<String>> get _dataRows => _hasHeader && _rows.length > 1 ? _rows.sublist(1) : _rows;

  /// Minimal RFC-4180-ish parser: handles quoted cells, escaped quotes and
  /// newlines inside quotes. Enough for real bank exports without a package.
  static List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;

    void endCell() {
      row.add(cell.toString());
      cell.clear();
    }

    void endRow() {
      endCell();
      if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        endCell();
      } else if (ch == '\n') {
        endRow();
      } else if (ch != '\r') {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  /// Tolerant date reader → yyyy-MM-dd, or null. ISO first; then d/m/y vs m/d/y
  /// by whichever part exceeds 12 (ambiguous dates read as day-first).
  static String? _parseDate(String raw) {
    final s = raw.trim();
    final iso = DateTime.tryParse(s);
    if (iso != null) return _fmt(iso);
    final parts = s.split(RegExp(r'[/\-.]'));
    if (parts.length != 3) return null;
    final nums = parts.map((p) => int.tryParse(p.trim())).toList();
    if (nums.any((n) => n == null)) return null;
    final a = nums[0]!, b = nums[1]!, c = nums[2]!;
    try {
      if (parts[0].trim().length == 4) return _fmt(DateTime(a, b, c)); // y-m-d
      final year = c < 100 ? 2000 + c : c;
      if (a > 12) return _fmt(DateTime(year, b, a)); // d/m/y
      if (b > 12) return _fmt(DateTime(year, a, b)); // m/d/y
      return _fmt(DateTime(year, b, a)); // ambiguous → day-first
    } catch (_) {
      return null;
    }
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static double? _parseAmount(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
      );
      if (result == null || result.files.single.path == null) return;
      final text = await File(result.files.single.path!).readAsString();
      final rows = _parseCsv(text);
      if (rows.isEmpty) {
        _snack('That file looks empty.', error: true);
        return;
      }
      setState(() {
        _fileName = result.files.single.name;
        _rows = rows;
        _dateCol = null;
        _titleCol = null;
        _amountCol = null;
        _categoryCol = null;
        _guessColumns();
      });
    } catch (e) {
      _snack('Failed to read file: $e', error: true);
    }
  }

  /// Best-effort auto-mapping from header names, so most bank exports need no
  /// manual mapping at all.
  void _guessColumns() {
    if (!_hasHeader || _rows.isEmpty) return;
    final header = _rows.first.map((h) => h.trim().toLowerCase()).toList();
    for (var i = 0; i < header.length; i++) {
      final h = header[i];
      if (_dateCol == null && h.contains('date')) _dateCol = i;
      if (_titleCol == null && (h.contains('desc') || h.contains('title') || h.contains('narrat') || h.contains('detail'))) {
        _titleCol = i;
      }
      if (_amountCol == null && h.contains('amount')) _amountCol = i;
      if (_categoryCol == null && h.contains('categor')) _categoryCol = i;
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? AppColors.expense : null),
    );
  }

  /// Stable per-row id so a re-import of the same file dedupes server-side.
  static String _opId(String date, double amount, String title, int occurrence) {
    var hash = 0;
    final key = '$date|$amount|$title|$occurrence';
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return 'csv-$hash-${title.length}-$occurrence';
  }

  List<Map<String, dynamic>> _buildRows() {
    final out = <Map<String, dynamic>>[];
    final seen = <String, int>{};
    for (final row in _dataRows) {
      String cell(int? i) => (i != null && i < row.length) ? row[i] : '';
      final date = _parseDate(cell(_dateCol));
      final amountRaw = _parseAmount(cell(_amountCol));
      final title = cell(_titleCol).trim();
      if (date == null || amountRaw == null || amountRaw == 0 || title.isEmpty) continue;

      // Sign convention: many statements list expenses as positive numbers.
      final amount = _amountsAreExpenses ? -amountRaw.abs() : amountRaw;
      final category = _categoryCol != null && cell(_categoryCol).trim().isNotEmpty
          ? cell(_categoryCol).trim()
          : 'Imported';

      final dupeKey = '$date|$amount|$title';
      final occurrence = (seen[dupeKey] = (seen[dupeKey] ?? 0) + 1);
      out.add({
        'title': title,
        'amount': amount,
        'category': category,
        'created_at': date,
        'client_op_id': _opId(date, amount, title, occurrence),
      });
    }
    return out;
  }

  Future<void> _import() async {
    final rows = _buildRows();
    if (rows.isEmpty) {
      _snack('No importable rows — check the column mapping.', error: true);
      return;
    }
    if (rows.length > 500) {
      _snack('Max 500 rows per import (found ${rows.length}). Split the file.', error: true);
      return;
    }
    setState(() => _importing = true);
    try {
      final result = await ref.read(transactionRepositoryProvider).bulkImport(rows);
      await ref.read(transactionsControllerProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      _snack(
        'Imported ${result.imported} transactions'
        '${result.duplicates > 0 ? ' · ${result.duplicates} duplicates skipped' : ''}'
        '${result.skipped > 0 ? ' · ${result.skipped} invalid rows' : ''}',
      );
    } catch (e) {
      _snack(DioClient.toApiException(e).message, error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final previewRows = _buildRows().take(5).toList();
    final ready = _dateCol != null && _titleCol != null && _amountCol != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Import CSV')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (_rows.isEmpty) ...[
              const SizedBox(height: 24),
              Icon(Icons.upload_file_rounded, size: 56, color: AppColors.primary.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              Text(
                'Import transactions from a bank-statement CSV. You\'ll choose which '
                'columns hold the date, description and amount.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondary, height: 1.4),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Choose CSV file', icon: Icons.folder_open_rounded, onPressed: _pickFile),
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.description_outlined, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_fileName · ${_dataRows.length} rows',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(onPressed: _pickFile, child: const Text('Change')),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('First row is a header', style: TextStyle(fontWeight: FontWeight.w600)),
                value: _hasHeader,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _hasHeader = v),
              ),
              const SizedBox(height: 8),
              _ColumnPicker(label: 'Date column', value: _dateCol, count: _columnCount, header: _headerNames(), onChanged: (v) => setState(() => _dateCol = v)),
              _ColumnPicker(label: 'Description column', value: _titleCol, count: _columnCount, header: _headerNames(), onChanged: (v) => setState(() => _titleCol = v)),
              _ColumnPicker(label: 'Amount column', value: _amountCol, count: _columnCount, header: _headerNames(), onChanged: (v) => setState(() => _amountCol = v)),
              _ColumnPicker(label: 'Category column (optional)', value: _categoryCol, count: _columnCount, header: _headerNames(), onChanged: (v) => setState(() => _categoryCol = v), allowNone: true),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Amounts are expenses', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('On: positive numbers import as spending', style: TextStyle(fontSize: 12, color: textSecondary)),
                value: _amountsAreExpenses,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _amountsAreExpenses = v),
              ),
              const SizedBox(height: 12),
              if (ready) ...[
                Text('Preview', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                if (previewRows.isEmpty)
                  Text('No rows parse with this mapping — adjust the columns above.', style: TextStyle(color: AppColors.expense.withValues(alpha: 0.9), fontSize: 13))
                else
                  ...previewRows.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Text(r['created_at'] as String, style: TextStyle(fontSize: 12, color: textSecondary)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(r['title'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                            Text(
                              (r['amount'] as double).toStringAsFixed(2),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: (r['amount'] as double) < 0 ? AppColors.expense : AppColors.income,
                              ),
                            ),
                          ],
                        ),
                      )),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Import ${_buildRows().length} transactions',
                  isLoading: _importing,
                  onPressed: _import,
                ),
              ] else
                Text('Map the date, description and amount columns to continue.', style: TextStyle(color: textSecondary, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _headerNames() {
    if (_rows.isEmpty) return const [];
    if (_hasHeader) return _rows.first.map((h) => h.trim()).toList();
    return List.generate(_columnCount, (i) => 'Column ${i + 1}');
  }
}

class _ColumnPicker extends StatelessWidget {
  final String label;
  final int? value;
  final int count;
  final List<String> header;
  final ValueChanged<int?> onChanged;
  final bool allowNone;

  const _ColumnPicker({
    required this.label,
    required this.value,
    required this.count,
    required this.header,
    required this.onChanged,
    this.allowNone = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: value != null && value! < count ? value : null,
                  isExpanded: true,
                  hint: Text(allowNone ? 'None' : 'Select…', style: const TextStyle(fontSize: 13)),
                  items: [
                    if (allowNone) const DropdownMenuItem<int?>(value: null, child: Text('None', style: TextStyle(fontSize: 13))),
                    for (var i = 0; i < count; i++)
                      DropdownMenuItem<int?>(
                        value: i,
                        child: Text(
                          header.length > i && header[i].isNotEmpty ? header[i] : 'Column ${i + 1}',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
