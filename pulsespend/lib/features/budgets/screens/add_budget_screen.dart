import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../design_system/ds.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('New Budget')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.screenPadding,
              AppTokens.space8,
              AppTokens.screenPadding,
              AppTokens.space24,
            ),
            children: [
              const DsSectionHeader(title: 'Category', padding: EdgeInsets.zero),
              const SizedBox(height: AppTokens.space12),
              Wrap(
                spacing: AppTokens.space8,
                runSpacing: AppTokens.space8,
                children: categories
                    .map((c) => DsFilterChip(
                          label: c.name,
                          selected: _selectedCategory == c.name,
                          showChevron: false,
                          onTap: () => setState(() => _selectedCategory = c.name),
                        ))
                    .toList(),
              ),
              const SizedBox(height: AppTokens.space24),
              const DsSectionHeader(title: 'Period', padding: EdgeInsets.zero),
              const SizedBox(height: AppTokens.space12),
              Wrap(
                spacing: AppTokens.space8,
                runSpacing: AppTokens.space8,
                children: _periods
                    .map((p) => DsFilterChip(
                          label: _periodLabel(p),
                          selected: _period == p,
                          showChevron: false,
                          onTap: () => setState(() => _period = p),
                        ))
                    .toList(),
              ),
              const SizedBox(height: AppTokens.space24),
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
              const SizedBox(height: AppTokens.space32),
              PrimaryButton(label: 'Create Budget', isLoading: _isLoading, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
