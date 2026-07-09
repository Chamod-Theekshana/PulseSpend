import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/goal_model.dart';
import '../../../providers/goals_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

/// Bottom sheet for POST /api/goals/:id/contribute. Currency defaults to the
/// user's profile currency but can differ from the goal's — the backend
/// converts via exchangeRateService and may return a `conversion_warning`.
class ContributeGoalSheet extends ConsumerStatefulWidget {
  final GoalModel goal;

  const ContributeGoalSheet({super.key, required this.goal});

  @override
  ConsumerState<ContributeGoalSheet> createState() => _ContributeGoalSheetState();
}

class _ContributeGoalSheetState extends ConsumerState<ContributeGoalSheet> {
  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final currency = ref.read(profileControllerProvider).currency;
      final warning = await ref.read(goalsControllerProvider.notifier).contribute(
            id: widget.goal.id,
            amount: double.parse(_amountController.text.trim()),
            currency: currency,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (warning != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(warning)));
      }
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
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Add to "${widget.goal.name}"', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Currently ${CurrencyFormatter.format(widget.goal.currentAmount, widget.goal.currency)} of '
              '${CurrencyFormatter.format(widget.goal.targetAmount, widget.goal.currency)}',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _amountController,
              label: 'Amount to add',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              prefixIcon: const Icon(Icons.savings_outlined),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Contribute', isLoading: _isLoading, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
