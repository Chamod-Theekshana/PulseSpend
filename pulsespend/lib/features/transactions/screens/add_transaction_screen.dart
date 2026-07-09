import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/transactions_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../widgets/split_editor.dart';

/// Add or edit a transaction. Mirrors validateTransactionBody exactly:
/// - amount must be non-zero, sign determines income/expense
/// - splits only allowed for expenses, need >= 2 entries, must sum to total
/// - tags: lowercase, letters/numbers/_/- , max 30 chars each, max 20 tags
class AddTransactionScreen extends ConsumerStatefulWidget {
  final TransactionModel? existing;

  const AddTransactionScreen({super.key, this.existing});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _tagController = TextEditingController();

  bool _isExpense = true;
  String? _selectedCategory;
  DateTime _date = DateTime.now();
  List<String> _tags = [];
  List<TransactionSplit> _splits = [];
  bool _isSplitMode = false;
  bool _isLoading = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.existing;
    if (tx != null) {
      _titleController.text = tx.title;
      _amountController.text = tx.amount.abs().toStringAsFixed(2);
      _notesController.text = tx.notes ?? '';
      _isExpense = tx.isExpense;
      _selectedCategory = tx.category;
      _date = tx.createdAt;
      _tags = List.of(tx.tags);
      _splits = List.of(tx.splits);
      _isSplitMode = tx.isSplit;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTag() {
    final raw = _tagController.text.trim().replaceFirst(RegExp(r'^#+'), '').toLowerCase();
    if (raw.isEmpty) return;
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,29}$').hasMatch(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tags: letters, numbers, _ or - only (max 30 chars)')),
      );
      return;
    }
    if (_tags.contains(raw)) {
      _tagController.clear();
      return;
    }
    if (_tags.length >= 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 20 tags allowed')),
      );
      return;
    }
    setState(() {
      _tags.add(raw);
      _tagController.clear();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null && !_isSplitMode) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a category')));
      return;
    }

    final amountAbs = double.parse(_amountController.text.trim());
    final signedAmount = _isExpense ? -amountAbs : amountAbs;

    if (_isSplitMode) {
      if (_splits.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Split transactions need at least 2 categories')),
        );
        return;
      }
      final sum = _splits.fold<double>(0, (acc, s) => acc + s.amount.abs());
      if ((sum - amountAbs).abs() > 0.05) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Splits must add up to the total (currently ${sum.toStringAsFixed(2)})')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final currency = ref.read(profileControllerProvider).currency;
      final transaction = TransactionModel(
        id: widget.existing?.id ?? 0,
        userId: widget.existing?.userId ?? '',
        title: _titleController.text.trim(),
        amount: signedAmount,
        currency: currency,
        category: _isSplitMode ? (_splits.first.category) : _selectedCategory!,
        createdAt: _date,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        tags: _tags,
        splits: _isSplitMode ? _splits : const [],
      );

      if (_isEditing) {
        await ref.read(transactionsControllerProvider.notifier).update(widget.existing!.id, transaction);
      } else {
        await ref.read(transactionsControllerProvider.notifier).create(transaction);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesState = ref.watch(categoriesControllerProvider);
    final relevantCategories =
        _isExpense ? categoriesState.expenseCategories : categoriesState.incomeCategories;
    final currency = ref.watch(profileControllerProvider).currency;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceAlt = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Transaction' : 'Add Transaction')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              // Income / Expense toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _TypeToggleButton(
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
                      child: _TypeToggleButton(
                        label: 'Income',
                        selected: !_isExpense,
                        color: AppColors.income,
                        onTap: () => setState(() {
                          _isExpense = false;
                          _selectedCategory = null;
                          _isSplitMode = false;
                          _splits = [];
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
                textCapitalization: TextCapitalization.sentences,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Title is required';
                  if (v.trim().length > 200) return 'Max 200 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _amountController,
                label: 'Amount ($currency)',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefixIcon: const Icon(Icons.attach_money_rounded),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text('${_date.day}/${_date.month}/${_date.year}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (!_isSplitMode) ...[
                Text('Category', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: relevantCategories
                      .map((c) => _CategoryChip(
                            label: c.name,
                            selected: _selectedCategory == c.name,
                            onTap: () => setState(() => _selectedCategory = c.name),
                          ))
                      .toList(),
                ),
              ],
              if (_isExpense) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Split across categories', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Divide this expense between 2+ categories', style: TextStyle(fontSize: 12)),
                  value: _isSplitMode,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() {
                    _isSplitMode = v;
                    if (v) _selectedCategory = null;
                  }),
                ),
                if (_isSplitMode)
                  SplitEditor(
                    totalAmount: double.tryParse(_amountController.text.trim()) ?? 0,
                    splits: _splits,
                    categories: relevantCategories.map((c) => c.name).toList(),
                    onChanged: (splits) => setState(() => _splits = splits),
                  ),
              ],
              const SizedBox(height: 16),
              AppTextField(
                controller: _notesController,
                label: 'Notes (optional)',
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Text('Tags', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _tagController,
                      label: 'Add a tag',
                      hint: 'e.g. work, vacation',
                      onChanged: (_) {},
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addTag,
                    icon: const Icon(Icons.add_rounded),
                    style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ],
              ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags
                      .map((tag) => Chip(
                            label: Text('#$tag'),
                            onDeleted: () => setState(() => _tags.remove(tag)),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 28),
              PrimaryButton(
                label: _isEditing ? 'Save Changes' : 'Add Transaction',
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

class _TypeToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeToggleButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

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

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
