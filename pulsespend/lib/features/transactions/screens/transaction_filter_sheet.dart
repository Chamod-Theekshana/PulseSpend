import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/ds.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/transactions_provider.dart';
import '../../../providers/wallets_provider.dart';

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
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.radiusHero)),
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
  late int? _walletId = widget.current.walletId;
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
        walletId: _walletId,
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
    final t = context.tokens;
    final theme = Theme.of(context);
    final textPrimary = t.textPrimary;
    final categories = ref.watch(categoriesControllerProvider).items;
    final names = {for (final c in categories) c.name}.toList()..sort();

    return Padding(
      padding: EdgeInsets.only(
        left: AppTokens.screenPadding,
        right: AppTokens.screenPadding,
        top: AppTokens.space8,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppTokens.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The sheet's grab handle comes from bottomSheetTheme (showDragHandle),
          // so this no longer draws a second one of its own.
          Text('Filters', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppTokens.space20),

          _label('Category', textPrimary),
          const SizedBox(height: AppTokens.space8),
          DsCard(
            emphasis: DsCardEmphasis.nested,
            borderColor: t.border,
            radius: AppTokens.radiusButton,
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.space16),
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
          const SizedBox(height: AppTokens.space16),

          // Wallet filter — only offered once wallets exist.
          Consumer(builder: (context, ref, _) {
            final wallets = ref.watch(walletsControllerProvider).items;
            if (wallets.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Wallet', textPrimary),
                const SizedBox(height: AppTokens.space8),
                DsCard(
                  emphasis: DsCardEmphasis.nested,
                  borderColor: t.border,
                  radius: AppTokens.radiusButton,
                  padding: const EdgeInsets.symmetric(horizontal: AppTokens.space16),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _walletId == null || _walletId == 0 || wallets.any((w) => w.id == _walletId)
                          ? _walletId
                          : null,
                      isExpanded: true,
                      hint: const Text('All wallets'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('All wallets')),
                        const DropdownMenuItem<int?>(value: 0, child: Text('Default wallet')),
                        for (final w in wallets)
                          DropdownMenuItem<int?>(value: w.id, child: Text(w.name)),
                      ],
                      onChanged: (v) => setState(() => _walletId = v),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.space16),
              ],
            );
          }),

          _label('Date range', textPrimary),
          const SizedBox(height: AppTokens.space8),
          Row(
            children: [
              Expanded(child: _dateField(label: 'From', value: _from, onTap: () => _pickDate(isFrom: true))),
              const SizedBox(width: AppTokens.space12),
              Expanded(child: _dateField(label: 'To', value: _to, onTap: () => _pickDate(isFrom: false))),
            ],
          ),
          const SizedBox(height: AppTokens.space16),

          _label('Amount range', textPrimary),
          const SizedBox(height: AppTokens.space8),
          Row(
            children: [
              Expanded(child: _amountField(_minController, 'Min')),
              const SizedBox(width: AppTokens.space12),
              Expanded(child: _amountField(_maxController, 'Max')),
            ],
          ),
          const SizedBox(height: AppTokens.space8),
          Text(
            'Amounts are signed — use negative values for expenses (e.g. -1000).',
            style: theme.textTheme.bodySmall?.copyWith(color: t.textTertiary),
          ),
          const SizedBox(height: AppTokens.space24),

          Row(
            children: [
              Expanded(
                child: DsPrimaryButton(
                  label: 'Clear',
                  onPressed: _clear,
                  variant: DsButtonVariant.ghost,
                ),
              ),
              const SizedBox(width: AppTokens.space12),
              Expanded(
                child: DsPrimaryButton(
                  label: 'Apply',
                  onPressed: _apply,
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
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
      );

  // Both field builders below drop their local border / padding overrides: the
  // global inputDecorationTheme already fills, rounds and outlines every field,
  // so the date pickers and the amount inputs now match each other and the
  // search field on the list screen.
  Widget _dateField({required String label, required DateTime? value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusButton),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(
          value != null ? DateFormat('yyyy-MM-dd').format(value) : 'Any',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _amountField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
      decoration: InputDecoration(labelText: label),
    );
  }
}
