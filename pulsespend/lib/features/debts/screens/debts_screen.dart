import 'package:flutter/material.dart';
import '../../../shared/widgets/app_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/debt_model.dart';
import '../../../providers/debts_provider.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/wallets_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../l10n/l10n_ext.dart';

/// 1:1 IOUs — "Alex owes me 2,000" without creating a full shared group.
/// Works offline: creates/settles queue in the outbox and sync on reconnect.
class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  Future<void> _settle(BuildContext context, WidgetRef ref, DebtModel debt) async {
    // The settlement is recorded server-side as a transfer-excluded wallet
    // movement — a repayment is a receivable/payable changing form, not
    // earnings or spending. (The old "Settle + log" flow here posted it as
    // plain income/expense, inflating lifetime Earnings with every repaid loan.)
    final result = await showModalBottomSheet<_SettleChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SettleSheet(debt: debt),
    );
    if (result == null) return;

    try {
      await ref
          .read(debtsControllerProvider.notifier)
          .settle(debt.id, walletId: result.walletId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settled ✓'), backgroundColor: AppColors.income),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, DebtModel debt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete IOU?'),
        content: Text('"${debt.counterpartyName} · ${CurrencyFormatter.format(debt.amount, debt.currency)}" will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.actionCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(debtsControllerProvider.notifier).delete(debt.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(debtsControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currency = ref.watch(profileControllerProvider).currency;
    // Net position with each IOU converted into the display currency — summing
    // raw amounts across currencies (300 USD + 5,000 LKR) produces nonsense.
    final money = ref.watch(moneyFormatterProvider);
    final net = state.owedToMe.fold<double>(
            0, (a, d) => a + money.convert(d.amount, d.currency)) -
        state.iOwe.fold<double>(0, (a, d) => a + money.convert(d.amount, d.currency));
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('IOUs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _AddDebtSheet(),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New IOU'),
      ),
      body: state.isLoading && state.items.isEmpty
          ? const Center(child: AppLoader(size: 40))
          : state.open.isEmpty && state.items.where((d) => !d.isOpen).isEmpty
              ? const EmptyState(
                  icon: Icons.handshake_outlined,
                  title: 'No IOUs yet',
                  message: 'Track money you\'ve lent or borrowed — "Alex owes me 2,000 for dinner" — and settle up later.',
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => ref.read(debtsControllerProvider.notifier).refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      // Net position header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Net position',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${net >= 0 ? '+' : ''}${CurrencyFormatter.format(net, currency)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (state.owedToMe.isNotEmpty) ...[
                        Text('Owed to me', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.income)),
                        const SizedBox(height: 8),
                        for (final d in state.owedToMe)
                          _DebtTile(debt: d, isDark: isDark, onSettle: () => _settle(context, ref, d), onDelete: () => _delete(context, ref, d)),
                        const SizedBox(height: 12),
                      ],
                      if (state.iOwe.isNotEmpty) ...[
                        Text('I owe', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.expense)),
                        const SizedBox(height: 8),
                        for (final d in state.iOwe)
                          _DebtTile(debt: d, isDark: isDark, onSettle: () => _settle(context, ref, d), onDelete: () => _delete(context, ref, d)),
                        const SizedBox(height: 12),
                      ],
                      if (state.items.any((d) => !d.isOpen)) ...[
                        Text('Settled', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textSecondary)),
                        const SizedBox(height: 8),
                        for (final d in state.items.where((d) => !d.isOpen).take(10))
                          _DebtTile(debt: d, isDark: isDark, onDelete: () => _delete(context, ref, d)),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  final DebtModel debt;
  final bool isDark;
  final VoidCallback? onSettle;
  final VoidCallback onDelete;

  const _DebtTile({required this.debt, required this.isDark, this.onSettle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final color = debt.owedToMe ? AppColors.income : AppColors.expense;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: color.withValues(alpha: 0.14),
            child: Text(
              debt.counterpartyName.isNotEmpty ? debt.counterpartyName[0].toUpperCase() : '?',
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  debt.counterpartyName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                    decoration: debt.isOpen ? null : TextDecoration.lineThrough,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (debt.note != null && debt.note!.isNotEmpty) debt.note!,
                    if (debt.createdAt != null) DateFormatter.relative(debt.createdAt!),
                    if (debt.id < 0) 'waiting to sync',
                  ].join(' · '),
                  style: TextStyle(fontSize: 11.5, color: textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            CurrencyFormatter.format(debt.amount, debt.currency),
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
          if (debt.isOpen && onSettle != null) ...[
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onSettle,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.income.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_rounded, size: 17, color: AppColors.income),
              ),
            ),
          ],
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onDelete,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.delete_outline_rounded, size: 18, color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Add-IOU form; owns its controllers (disposed after the sheet animates out).
class _AddDebtSheet extends ConsumerStatefulWidget {
  const _AddDebtSheet();

  @override
  ConsumerState<_AddDebtSheet> createState() => _AddDebtSheetState();
}

class _AddDebtSheetState extends ConsumerState<_AddDebtSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _direction = 'owed_to_me';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(debtsControllerProvider.notifier).create(
            counterpartyName: _nameController.text.trim(),
            amount: double.parse(_amountController.text.trim()),
            currency: ref.read(profileControllerProvider).currency,
            direction: _direction,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New IOU', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final d in const [('owed_to_me', 'Owed to me'), ('i_owe', 'I owe')]) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _direction = d.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _direction == d.$1
                              ? (d.$1 == 'owed_to_me' ? AppColors.income : AppColors.expense)
                              : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            d.$2,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _direction == d.$1
                                  ? Colors.white
                                  : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (d.$1 == 'owed_to_me') const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _nameController,
              label: 'Who?',
              hint: 'e.g. Alex',
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _amountController,
              label: 'Amount',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _noteController,
              label: 'Note (optional)',
              hint: 'e.g. dinner at Nihonbashi',
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Add IOU', isLoading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}


/// The settle sheet's answer: which wallet the money moved through, or null
/// for "not tracked in the app".
class _SettleChoice {
  final int? walletId;
  const _SettleChoice(this.walletId);
}

/// Asks where the settlement money physically went (owed-to-me) or came from
/// (i-owe). The chosen wallet's balance moves via a transfer-excluded leg;
/// "Not tracked" settles the IOU without touching any wallet.
class _SettleSheet extends ConsumerStatefulWidget {
  final DebtModel debt;
  const _SettleSheet({required this.debt});

  @override
  ConsumerState<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<_SettleSheet> {
  /// -1 = "not tracked"; 0 = Default bucket; >0 = wallet id.
  int _selection = -1;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final debt = widget.debt;
    // The cash has to sit somewhere spendable, so debt accounts are excluded.
    final wallets = ref
        .watch(walletsControllerProvider)
        .items
        .where((w) => !w.isLiability)
        .toList();

    Widget chip(String label, int value) {
      final selected = _selection == value;
      return GestureDetector(
        onTap: () => setState(() => _selection = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: selected ? Colors.white : textSecondary,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mark as settled?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            debt.owedToMe
                ? '${debt.counterpartyName} paid you back '
                    '${CurrencyFormatter.format(debt.amount, debt.currency)}.'
                : 'You paid ${debt.counterpartyName} '
                    '${CurrencyFormatter.format(debt.amount, debt.currency)}.',
            style: TextStyle(fontSize: 13, color: textSecondary),
          ),
          const SizedBox(height: 16),
          Text(
            debt.owedToMe ? 'Which wallet did it go into?' : 'Which wallet did it come from?',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('Not tracked', -1),
              chip('Default', 0),
              for (final w in wallets) chip(w.name, w.id),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _selection == -1
                ? 'Settles the IOU without touching any wallet.'
                : 'The wallet moves by the amount — without counting as '
                    '${debt.owedToMe ? 'income' : 'spending'}, because a repayment is neither.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                  context, _SettleChoice(_selection == -1 ? null : _selection)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Settle'),
            ),
          ),
        ],
      ),
    );
  }
}
