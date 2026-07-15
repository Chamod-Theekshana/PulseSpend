import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/wallet_model.dart';
import '../../../providers/repository_providers.dart';
import '../../../providers/wallets_provider.dart';
import '../../../shared/widgets/empty_state.dart';

/// Manage cash/bank/card wallets. Transactions can be assigned to a wallet in
/// Add/Edit Transaction; deleting a wallet moves its transactions back to the
/// default bucket (server-side).
class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

  Future<void> _openEditor(BuildContext context, WidgetRef ref, {WalletModel? existing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WalletEditorSheet(existing: existing),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, WalletModel wallet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete wallet?'),
        content: Text(
          '"${wallet.name}" will be removed. Its transactions are kept and move '
          'to the default wallet.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(walletsControllerProvider.notifier).delete(wallet.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(walletsControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallets'),
        actions: [
          // Move money between wallets (recorded as a −/+ transfer pair that
          // stays out of income/expense analytics).
          if (state.items.isNotEmpty)
            IconButton(
              tooltip: 'Transfer between wallets',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const _TransferSheet(),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New wallet'),
      ),
      body: state.isLoading && state.items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.items.isEmpty
              ? const EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No wallets yet',
                  message:
                      'Create wallets for cash, bank accounts and cards, then assign '
                      'transactions to see per-wallet balances.',
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => ref.read(walletsControllerProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: state.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final w = state.items[i];
                      return Material(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _openEditor(context, ref, existing: w),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(w.icon, color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(w.name,
                                          style: const TextStyle(fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${w.type[0].toUpperCase()}${w.type.substring(1)} · ${w.currency}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      size: 20, color: AppColors.expense),
                                  onPressed: () => _confirmDelete(context, ref, w),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

/// Move money between two wallets (or the Default bucket). Owns its
/// controller — disposed after the sheet's dismiss animation.
class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet();

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  final _amountController = TextEditingController();
  int? _fromId;
  int? _toId;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (_fromId == null || _toId == null || _fromId == _toId || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick two different wallets and a valid amount')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(walletRepositoryProvider)
          .transfer(fromWalletId: _fromId!, toWalletId: _toId!, amount: amount);
      ref.invalidate(walletBalancesProvider);
      ref.invalidate(netWorthProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer complete ✓'), backgroundColor: AppColors.income),
        );
      }
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
    final balances = ref.watch(walletBalancesProvider).asData?.value ?? const <WalletBalance>[];

    Widget walletDropdown({
      required String label,
      required int? value,
      required ValueChanged<int?> onChanged,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            hint: Text(label),
            isExpanded: true,
            items: [
              for (final b in balances)
                DropdownMenuItem(
                  value: b.wallet.id,
                  child: Text(
                    '${b.wallet.name} · ${b.balance.toStringAsFixed(0)} ${b.displayCurrency}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged,
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
          const Row(
            children: [
              Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Transfer between wallets',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Moves money without counting as income or spending.',
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          walletDropdown(
            label: 'From wallet',
            value: _fromId,
            onChanged: (v) => setState(() => _fromId = v),
          ),
          const SizedBox(height: 12),
          walletDropdown(
            label: 'To wallet',
            value: _toId,
            onChanged: (v) => setState(() => _toId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_saving ? 'Transferring…' : 'Transfer'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Create/edit form. Owns its controller (disposed after the sheet's dismiss
/// animation — see the TextEditingController-after-dispose pitfall).
class _WalletEditorSheet extends ConsumerStatefulWidget {
  final WalletModel? existing;
  const _WalletEditorSheet({this.existing});

  @override
  ConsumerState<_WalletEditorSheet> createState() => _WalletEditorSheetState();
}

class _WalletEditorSheetState extends ConsumerState<_WalletEditorSheet> {
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late String _type = widget.existing?.type ?? 'cash';
  late String _currency = widget.existing?.currency ?? 'LKR';
  bool _saving = false;

  static const _currencies = ['LKR', 'USD', 'EUR', 'GBP', 'INR', 'AUD', 'JPY', 'CAD'];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final controller = ref.read(walletsControllerProvider.notifier);
      if (widget.existing == null) {
        await controller.create(name: name, type: _type, currency: _currency);
      } else {
        await controller.update(widget.existing!.id, name: name, type: _type, currency: _currency);
      }
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? 'New wallet' : 'Edit wallet',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. BOC Savings'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in const [
                ('cash', 'Cash'),
                ('bank', 'Bank'),
                ('card', 'Card'),
                ('credit', 'Credit'),
                ('investment', 'Investment'),
                ('loan', 'Loan'),
              ])
                GestureDetector(
                  onTap: () => setState(() => _type = t.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _type == t.$1
                          ? AppColors.primary
                          : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      t.$2,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _type == t.$1
                            ? Colors.white
                            : (isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Credit, card & loan wallets count as liabilities in your net worth.',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _currencies.contains(_currency) ? _currency : _currencies.first,
                isExpanded: true,
                items: [
                  for (final c in _currencies) DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _currency = v ?? 'LKR'),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_saving ? 'Saving…' : (widget.existing == null ? 'Create' : 'Save')),
            ),
          ),
        ],
      ),
    );
  }
}
