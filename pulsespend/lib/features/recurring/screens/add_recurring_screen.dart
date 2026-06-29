import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/recurring_model.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/recurring_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class AddRecurringScreen extends ConsumerStatefulWidget {
  const AddRecurringScreen({super.key});

  @override
  ConsumerState<AddRecurringScreen> createState() => _AddRecurringScreenState();
}

class _AddRecurringScreenState extends ConsumerState<AddRecurringScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isExpense = true;
  String? _selectedCategory;
  String _frequency = 'monthly';
  DateTime _startDate = DateTime.now();
  bool _isLoading = false;

  static const _frequencies = ['daily', 'weekly', 'monthly', 'yearly'];

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
        id: 0,
        userId: '',
        title: _titleController.text.trim(),
        amount: _isExpense ? -amountAbs : amountAbs,
        category: _selectedCategory!,
        frequency: _frequency,
        nextRun: _startDate,
      );
      await ref.read(recurringControllerProvider.notifier).create(rule);
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
    final categories = _isExpense ? categoriesState.expenseCategories : categoriesState.incomeCategories;

    return Scaffold(
      appBar: AppBar(title: const Text('New Recurring Rule')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppColors.lightSurfaceAlt, borderRadius: BorderRadius.circular(14)),
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
                              color: _selectedCategory == c.name ? AppColors.primary : AppColors.lightSurfaceAlt,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedCategory == c.name ? AppColors.primary : AppColors.lightBorder,
                              ),
                            ),
                            child: Text(
                              c.name,
                              style: TextStyle(
                                color: _selectedCategory == c.name ? Colors.white : AppColors.lightTextPrimary,
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
                            color: _frequency == f ? Colors.white : AppColors.lightTextPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickStartDate,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(color: AppColors.lightSurfaceAlt, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      const Icon(Icons.event_repeat_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text('Starts ${_startDate.day}/${_startDate.month}/${_startDate.year}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              PrimaryButton(label: 'Create Rule', isLoading: _isLoading, onPressed: _submit),
            ],
          ),
        ),
      ),
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
            style: TextStyle(color: selected ? Colors.white : AppColors.lightTextSecondary, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
