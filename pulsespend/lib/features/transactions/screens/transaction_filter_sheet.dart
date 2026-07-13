import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/transactions_provider.dart';

/// Bottom sheet for the advanced (server-side) transaction filters: category,
/// date range and amount range. Returns the merged [TransactionFilters]
/// (preserving the caller's current query + type) via Navigator.pop, or null if
/// dismissed. The list controller applies them server-side across full history.
Future<TransactionFilters?> showTransactionFilterSheet(
  BuildContext context,
  TransactionFilters current,
) {
  return showModalBottomSheet<TransactionFilters>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _TransactionFilterSheet(current: current),
  );
}

class _TransactionFilterSheet extends ConsumerStatefulWidget {
  final TransactionFilters current;
  const _TransactionFilterSheet({required this.current});

  @override
  ConsumerState<_TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends ConsumerState<_TransactionFilterSheet> {
  late String? _category = widget.current.category;
  late DateTime? _from = widget.current.from;
  late DateTime? _to = widget.current.to;
  late final _minController =
      TextEditingController(text: widget.current.minAmount?.toString() ?? '');
  late final _maxController =
      TextEditingController(text: widget.current.maxAmount?.toString() ?? '');

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = (isFrom ? _from : _to) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _from = picked;
        } else {
          _to = picked;
        }
      });
    }
  }

  void _apply() {
    final min = double.tryParse(_minController.text.trim());
    final max = double.tryParse(_maxController.text.trim());
    Navigator.pop(
      context,
      TransactionFilters(
        query: widget.current.query,
        type: widget.current.type,
        category: (_category != null && _category!.isNotEmpty) ? _category : null,
        from: _from,
        to: _to,
        minAmount: min,
        maxAmount: max,
      ),
    );
  }

  void _clear() {
    // Keep the free-text query and type chips; only reset the advanced filters.
    Navigator.pop(
      context,
      TransactionFilters(query: widget.current.query, type: widget.current.type),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final categories = ref.watch(categoriesControllerProvider).items;
    final names = {for (final c in categories) c.name}.toList()..sort();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Filters',
            style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),

          _label('Category', textPrimary),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: (_category != null && names.contains(_category)) ? _category : null,
                isExpanded: true,
                hint: const Text('All categories'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
                  for (final n in names) DropdownMenuItem<String?>(value: n, child: Text(n)),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
            ),
          ),
          const SizedBox(height: 18),

          _label('Date range', textPrimary),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _dateField(label: 'From', value: _from, onTap: () => _pickDate(isFrom: true))),
              const SizedBox(width: 12),
              Expanded(child: _dateField(label: 'To', value: _to, onTap: () => _pickDate(isFrom: false))),
            ],
          ),
          const SizedBox(height: 18),

          _label('Amount range', textPrimary),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _amountField(_minController, 'Min')),
              const SizedBox(width: 12),
              Expanded(child: _amountField(_maxController, 'Max')),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Amounts are signed — use negative values for expenses (e.g. -1000).',
            style: TextStyle(
              color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clear,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _apply,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text, Color color) => Text(
        text,
        style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w700),
      );

  Widget _dateField({required String label, required DateTime? value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Text(
          value != null ? DateFormat('yyyy-MM-dd').format(value) : 'Any',
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }

  Widget _amountField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}
