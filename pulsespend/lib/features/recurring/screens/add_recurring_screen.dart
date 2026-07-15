import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/recurring_model.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/recurring_provider.dart';
import '../../../providers/wallets_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class AddRecurringScreen extends ConsumerStatefulWidget {
  /// Optional pre-fill (e.g. "Track as recurring" from a detected subscription).
  final String? initialTitle;
  final double? initialAmount;

  /// When set, the screen edits this rule instead of creating a new one.
  final RecurringModel? existing;

  const AddRecurringScreen({super.key, this.initialTitle, this.initialAmount, this.existing});

  @override
  ConsumerState<AddRecurringScreen> createState() => _AddRecurringScreenState();
}

class _AddRecurringScreenState extends ConsumerState<AddRecurringScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late bool _isExpense;
  String? _selectedCategory;
  late String _frequency;
  late DateTime _startDate;
  String? _currency;
  int? _walletId;
  bool _isLoading = false;

  static const _frequencies = ['daily', 'weekly', 'monthly', 'yearly'];
  static const _currencies = ['LKR', 'USD', 'EUR', 'GBP', 'INR', 'AUD', 'JPY', 'CAD'];

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleController = TextEditingController(text: e?.title ?? widget.initialTitle ?? '');
    _amountController = TextEditingController(
      text: e != null
          ? e.amount.abs().toStringAsFixed(2)
          : (widget.initialAmount != null ? widget.initialAmount!.toStringAsFixed(2) : ''),
    );
    _isExpense = e != null ? e.isExpense : true;
    _selectedCategory = e?.category;
    _frequency = e?.frequency ?? 'monthly';
    _startDate = e?.nextRun ?? DateTime.now();
    _currency = e?.currency;
    _walletId = e?.walletId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a category')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final amountAbs = double.parse(_amountController.text.trim());
      final rule = RecurringModel(
        id: widget.existing?.id ?? 0,
        userId: '',
        title: _titleController.text.trim(),
        amount: _isExpense ? -amountAbs : amountAbs,
        category: _selectedCategory!,
        frequency: _frequency,
        nextRun: _startDate,
        currency: _currency,
        walletId: _walletId,
      );
      final notifier = ref.read(recurringControllerProvider.notifier);
      if (_isEditing) {
        await notifier.update(widget.existing!.id, rule);
      } else {
        await notifier.create(rule);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesState = ref.watch(categoriesControllerProvider);
    final categories = _isExpense ? categoriesState.expenseCategories : categoriesState.incomeCategories;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceAlt = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final wallets = ref.watch(walletsControllerProvider).items;
    // Currency defaults to the user's preferred currency until they pick one.
    final currency = _currency ?? ref.watch(profileControllerProvider).currency;
    final currencyOptions = {..._currencies, currency}.toList();

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Recurring Rule' : 'New Recurring Rule')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: surfaceAlt, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Expanded(
                      child: _ToggleBtn(
                        label: 'Expense',
                        selected: _isExpense,
                        color: AppColors.expense,
                        onTap: () => setState(() {
                          _isExpense = true;
                          _selectedCategory = null;
                        }),
                      ),
                    ),
                    Expanded(
                      child: _ToggleBtn(
                        label: 'Income',
                        selected: !_isExpense,
                        color: AppColors.income,
                        onTap: () => setState(() {
                          _isExpense = false;
                          _selectedCategory = null;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AppTextField(
                controller: _titleController,
                label: 'Title',
                hint: 'e.g. Netflix, Rent, Salary',
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _amountController,
                label: 'Amount',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefixIcon: const Icon(Icons.attach_money_rounded),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text('Category', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories
                    .map((c) => GestureDetector(
                          onTap: () => setState(() => _selectedCategory = c.name),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedCategory == c.name ? AppColors.primary : surfaceAlt,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedCategory == c.name ? AppColors.primary : border,
                              ),
                            ),
                            child: Text(
                              c.name,
                              style: TextStyle(
                                color: _selectedCategory == c.name ? Colors.white : textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              Text('Frequency', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _frequencies
                    .map((f) => ChoiceChip(
                          label: Text(f[0].toUpperCase() + f.substring(1)),
                          selected: _frequency == f,
                          onSelected: (_) => setState(() => _frequency = f),
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: _frequency == f ? Colors.white : textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              // Currency + wallet the materialized transactions will use.
              Row(
                children: [
                  Expanded(
                    child: _PickerBox(
                      label: 'Currency',
                      surfaceAlt: surfaceAlt,
                      border: border,
                      child: DropdownButton<String>(
                        value: currency,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final c in currencyOptions) DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (v) => setState(() => _currency = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PickerBox(
                      label: 'Wallet',
                      surfaceAlt: surfaceAlt,
                      border: border,
                      child: DropdownButton<int?>(
                        value: wallets.any((w) => w.id == _walletId) ? _walletId : null,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Default')),
                          for (final w in wallets)
                            DropdownMenuItem<int?>(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => _walletId = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickStartDate,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(color: surfaceAlt, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      const Icon(Icons.event_repeat_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text('${_isEditing ? 'Next run' : 'Starts'} '
                          '${_startDate.day}/${_startDate.month}/${_startDate.year}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: _isEditing ? 'Save Changes' : 'Create Rule',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labelled bordered container hosting a dropdown (currency / wallet).
class _PickerBox extends StatelessWidget {
  final String label;
  final Color surfaceAlt;
  final Color border;
  final Widget child;

  const _PickerBox({
    required this.label,
    required this.surfaceAlt,
    required this.border,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: DropdownButtonHideUnderline(child: child),
        ),
      ],
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ToggleBtn({required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : (Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
