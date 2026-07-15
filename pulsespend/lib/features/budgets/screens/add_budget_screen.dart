import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/budget_model.dart';
import '../../../providers/budgets_provider.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

/// Create a budget limit for a category. Mirrors POST /api/budgets
/// (category, amount, currency, period ∈ weekly | monthly | yearly).
class AddBudgetScreen extends ConsumerStatefulWidget {
  const AddBudgetScreen({super.key});

  @override
  ConsumerState<AddBudgetScreen> createState() => _AddBudgetScreenState();
}

class _AddBudgetScreenState extends ConsumerState<AddBudgetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  String? _selectedCategory;
  String _period = 'monthly';
  bool _isLoading = false;

  static const _periods = ['weekly', 'monthly', 'yearly'];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String _periodLabel(String p) => switch (p) {
        'weekly' => 'Weekly',
        'yearly' => 'Yearly',
        _ => 'Monthly',
      };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a category')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final currency = ref.read(profileControllerProvider).currency;
      final budget = BudgetModel(
        id: 0,
        userId: '',
        category: _selectedCategory!,
        amount: double.parse(_amountController.text.trim()),
        currency: currency,
        period: _period,
      );
      await ref.read(budgetsControllerProvider.notifier).create(budget);
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
    final categories = ref.watch(categoriesControllerProvider).expenseCategories;
    final currency = ref.watch(profileControllerProvider).currency;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceAlt = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Scaffold(
      appBar: AppBar(title: const Text('New Budget')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
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
              const SizedBox(height: 20),
              Text('Period', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _periods
                    .map((p) => ChoiceChip(
                          label: Text(_periodLabel(p)),
                          selected: _period == p,
                          onSelected: (_) => setState(() => _period = p),
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: _period == p ? Colors.white : textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 20),
              AppTextField(
                controller: _amountController,
                label: '${_periodLabel(_period)} limit ($currency)',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefixIcon: const Icon(Icons.attach_money_rounded),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 28),
              PrimaryButton(label: 'Create Budget', isLoading: _isLoading, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
