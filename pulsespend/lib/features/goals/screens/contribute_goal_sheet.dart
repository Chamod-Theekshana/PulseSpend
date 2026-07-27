import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/goal_model.dart';
import '../../../providers/goals_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/wallets_provider.dart';
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
  // Funding source: a wallet id (deducts real money), 0 = the Default bucket,
  // or null = just track (no money moved). Defaults to the first wallet.
  int? _walletId;
  bool _walletInit = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  /// Balance of the selected funding wallet in the profile currency, or null
  /// when "just track" (no wallet) is chosen.
  double? _selectedWalletBalance() {
    if (_walletId == null) return null;
    final balances = ref.read(walletBalancesProvider).asData?.value ?? const [];
    for (final b in balances) {
      if (b.wallet.id == _walletId) return b.balance;
    }
    return null;
  }

  Future<void> _submit(GoalModel goal) async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountController.text.trim());

    // Overdraft guard (client-side; the backend also enforces it): can't fund
    // from more than the wallet holds.
    final balance = _selectedWalletBalance();
    if (balance != null && amount > balance + 0.0001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Not enough — balance is ${CurrencyFormatter.format(balance, goal.currency)}')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final currency = ref.read(profileControllerProvider).currency;
      final warning = await ref.read(goalsControllerProvider.notifier).contribute(
            id: goal.id,
            amount: amount,
            currency: currency,
            walletId: _walletId,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (warning != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(warning)));
      }
    } catch (e) {
      if (!mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// A completed goal can't take more — offer to raise the target so saving
  /// can continue. New target must exceed what's already saved.
  Future<void> _raiseTarget(GoalModel goal) async {
    final controller = TextEditingController(text: goal.targetAmount.toStringAsFixed(0));
    String? error;
    final newTarget = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Raise the target'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'New target (${goal.currency})',
              helperText: 'Saved so far: ${CurrencyFormatter.format(goal.currentAmount, goal.currency)}',
              errorText: error,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final n = double.tryParse(controller.text.trim());
                if (n == null || n <= goal.currentAmount) {
                  setLocal(() => error =
                      'Must be more than ${CurrencyFormatter.format(goal.currentAmount, goal.currency)}');
                  return;
                }
                Navigator.pop(ctx, n);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (newTarget == null) return;

    try {
      final updated = GoalModel(
        id: goal.id,
        userId: goal.userId,
        name: goal.name,
        targetAmount: newTarget,
        currentAmount: goal.currentAmount,
        currency: goal.currency,
        deadline: goal.deadline,
        groupId: goal.groupId,
      );
      await ref.read(goalsControllerProvider.notifier).update(goal.id, updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live goal so the completed-state gate reflects the latest balance/target.
    final goal = ref.watch(goalsControllerProvider).items
        .firstWhere((g) => g.id == widget.goal.id, orElse: () => widget.goal);
    final textSecondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    // Watch balances so the "Balance: …" hint appears once they load.
    final balancesList = ref.watch(walletBalancesProvider).asData?.value ?? const [];
    double? balance;
    if (_walletId != null) {
      for (final b in balancesList) {
        if (b.wallet.id == _walletId) {
          balance = b.balance;
          break;
        }
      }
    }

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
            Text('Add to "${goal.name}"', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Currently ${CurrencyFormatter.format(goal.currentAmount, goal.currency)} of '
              '${CurrencyFormatter.format(goal.targetAmount, goal.currency)}',
              style: TextStyle(color: textSecondary),
            ),
            const SizedBox(height: 20),
            if (goal.isCompleted) ...[
              // Completed → can't contribute more; raise the target to continue.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.income.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded, color: AppColors.income),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Goal reached! 🎉 Raise the target to keep saving toward it.',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(label: 'Increase target', isLoading: false, onPressed: () => _raiseTarget(goal)),
            ] else ...[
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
              const SizedBox(height: 16),
              _WalletSourceField(
                label: 'Take from',
                selected: _walletId,
                onChanged: (v) => setState(() {
                  _walletId = v;
                  _walletInit = true;
                }),
                autoSelectFirst: !_walletInit,
                onAutoSelect: (v) => _walletId = v,
              ),
              if (balance != null) ...[
                const SizedBox(height: 6),
                Text('Balance: ${CurrencyFormatter.format(balance, goal.currency)}',
                    style: TextStyle(fontSize: 12, color: textSecondary)),
              ],
              const SizedBox(height: 20),
              PrimaryButton(label: 'Contribute', isLoading: _isLoading, onPressed: () => _submit(goal)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dropdown to choose which wallet funds a goal contribution / receives a
/// withdrawal. "Just track" (null) moves no real money — the old counter
/// behaviour. Shared by the contribute sheet and the withdraw dialog.
class _WalletSourceField extends ConsumerWidget {
  final String label;
  final int? selected;
  final ValueChanged<int?> onChanged;
  final bool autoSelectFirst;
  final ValueChanged<int?>? onAutoSelect;

  const _WalletSourceField({
    required this.label,
    required this.selected,
    required this.onChanged,
    this.autoSelectFirst = false,
    this.onAutoSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsControllerProvider).items;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surfaceAlt = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;

    // First build with wallets available → default to the first one.
    var value = selected;
    if (autoSelectFirst && selected == null && wallets.isNotEmpty) {
      value = wallets.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => onAutoSelect?.call(value));
    }
    // Guard against a stale id no longer in the list.
    final validIds = {null, 0, ...wallets.map((w) => w.id)};
    if (!validIds.contains(value)) value = null;

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
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: value,
              isExpanded: true,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Just track (no wallet)')),
                for (final w in wallets)
                  DropdownMenuItem<int?>(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
