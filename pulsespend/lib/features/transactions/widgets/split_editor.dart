import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/transaction_model.dart';

/// Lets the user divide one expense across 2+ categories. Mirrors the
/// backend's rule in validators.ts: each split needs category + positive
/// amount, categories must be unique, and the sum must equal the total
/// (within 0.05 tolerance for rounding).
class SplitEditor extends StatefulWidget {
  final double totalAmount;
  final List<TransactionSplit> splits;
  final List<String> categories;
  final ValueChanged<List<TransactionSplit>> onChanged;

  const SplitEditor({
    super.key,
    required this.totalAmount,
    required this.splits,
    required this.categories,
    required this.onChanged,
  });

  @override
  State<SplitEditor> createState() => _SplitEditorState();
}

class _SplitEditorState extends State<SplitEditor> {
  late List<_SplitRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.splits.isEmpty
        ? [_SplitRow(), _SplitRow()]
        : widget.splits
            .map((s) => _SplitRow(category: s.category, amountController: TextEditingController(text: s.amount.abs().toStringAsFixed(2))))
            .toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.amountController.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final splits = _rows
        .where((r) => r.category != null && r.amountController.text.trim().isNotEmpty)
        .map((r) => TransactionSplit(
              category: r.category!,
              amount: -(double.tryParse(r.amountController.text.trim()) ?? 0).abs(),
              percentage: 0,
            ))
        .toList();
    widget.onChanged(splits);
  }

  double get _allocated => _rows.fold(0, (acc, r) => acc + (double.tryParse(r.amountController.text.trim()) ?? 0));

  @override
  Widget build(BuildContext context) {
    final remaining = widget.totalAmount - _allocated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _rows[i].category,
                    decoration: const InputDecoration(labelText: 'Category', isDense: true),
                    items: widget.categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _rows[i].category = v;
                      _emit();
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _rows[i].amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount', isDense: true),
                    onChanged: (_) => setState(_emit),
                  ),
                ),
                if (_rows.length > 2)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.expense),
                    onPressed: () => setState(() {
                      _rows[i].amountController.dispose();
                      _rows.removeAt(i);
                      _emit();
                    }),
                  ),
              ],
            ),
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _rows.add(_SplitRow())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add split'),
            ),
            const Spacer(),
            Text(
              remaining.abs() < 0.05
                  ? 'Fully allocated ✓'
                  : '${remaining > 0 ? "Remaining" : "Over by"}: ${CurrencyFormatter.format(remaining.abs(), '')}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: remaining.abs() < 0.05 ? AppColors.income : AppColors.warning,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SplitRow {
  String? category;
  final TextEditingController amountController;

  _SplitRow({this.category, TextEditingController? amountController})
      : amountController = amountController ?? TextEditingController();
}
