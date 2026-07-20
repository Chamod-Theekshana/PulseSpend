import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/wallet_model.dart';
import '../../../providers/repository_providers.dart';
import '../../../providers/wallets_provider.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/wallet_dropdown.dart';
import 'wallet_detail_screen.dart';

/// Manage cash/bank/card wallets. Transactions can be assigned to a wallet in
/// Add/Edit Transaction; deleting a wallet moves its transactions back to the
/// default bucket (server-side).
class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

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
    final balances = ref.watch(walletBalancesProvider).asData?.value ?? const <WalletBalance>[];

    WalletBalance? balanceFor(int id) {
      for (final b in balances) {
        if (b.wallet.id == id) return b;
      }
      return null;
    }

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
        onPressed: () => WalletEditorSheet.show(context),
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
                      return _WalletCard(
                        wallet: w,
                        balance: balanceFor(w.id),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => WalletDetailScreen(walletId: w.id)),
                        ),
                        onDelete: () => _confirmDelete(context, ref, w),
                      );
                    },
                  ),
                ),
    );
  }
}

/// One wallet row. Liability wallets (credit/card/loan) read as debt: the
/// headline is what's owed, and the breakdown spells out charged vs repaid so
/// "owe 8,000" is traceable back to the transactions behind it.
class _WalletCard extends StatelessWidget {
  final WalletModel wallet;
  final WalletBalance? balance;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _WalletCard({
    required this.wallet,
    required this.balance,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final b = balance;
    final isLiability = wallet.isLiability;
    final owed = b?.amountOwed ?? 0;
    final progress = b?.payoffProgress;
    final cur = b?.displayCurrency ?? wallet.currency;

    String money(double v) => v.toStringAsFixed(0);

    return Material(
      color: isDark ? AppColors.darkSurface : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (isLiability ? AppColors.expense : AppColors.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(wallet.icon,
                        color: isLiability ? AppColors.expense : AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(wallet.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          '${wallet.type[0].toUpperCase()}${wallet.type.substring(1)} · ${wallet.currency}',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (b != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          // An overpaid debt reads as credit; a cleared one as
                          // finished (loan) or settled (card) — never "owe 0".
                          b.isOverpaid
                              ? 'credit ${money(b.creditBalance)}'
                              : b.isPaidOff
                                  ? (wallet.type == 'loan' ? 'PAID OFF 🎉' : 'All clear ✓')
                                  : (isLiability ? 'owe ${money(owed)}' : money(b.balance)),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: b.isOverpaid || b.isPaidOff
                                ? AppColors.income
                                : (isLiability
                                    ? AppColors.expense
                                    : (b.balance < 0 ? AppColors.expense : null)),
                          ),
                        ),
                        Text(cur, style: TextStyle(fontSize: 10.5, color: textSecondary)),
                      ],
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 20, color: AppColors.expense),
                    onPressed: onDelete,
                  ),
                ],
              ),
              // Debt is the net of opposite flows; naming them makes the number
              // self-explanatory. What was borrowed is kept apart from what was
              // charged since — lumping them reads as "you spent 105,000" when
              // 100,000 of it was the loan itself.
              if (isLiability && b != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    if (b.borrowed > 0)
                      _Flow(label: 'borrowed', value: money(b.borrowed), color: textSecondary),
                    if (b.charged > 0)
                      _Flow(label: 'charged', value: money(b.charged), color: textSecondary),
                    if (b.repaid > 0)
                      _Flow(label: 'repaid', value: money(b.repaid), color: textSecondary),
                    if (b.availableCredit != null)
                      _Flow(
                        label: 'available',
                        value: '${money(b.availableCredit!)} of ${money(b.wallet.creditLimit ?? 0)}',
                        color: textSecondary,
                      ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: AppColors.expense.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation(AppColors.income),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${(progress * 100).toStringAsFixed(0)}% paid off · '
                      '${money(b.borrowed)} $cur borrowed'
                      '${b.charged > 0 ? ' · ${money(b.charged)} in charges' : ''}',
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One "borrowed 100,000"-style figure in a wallet card's debt breakdown.
class _Flow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Flow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text('$label $value', style: TextStyle(fontSize: 11.5, color: color));
  }
}

/// "Where did the money go?" for a loan being created.
///
/// Borrowing produces two real things at once — cash you can spend and a debt
/// you owe — and they have to be recorded together or the books are wrong in one
/// direction or the other. Naming the wallet the cash landed in keeps net worth
/// unchanged (you're no richer for borrowing) and means spending comes out of
/// *that* wallet, leaving the loan to track only what's outstanding. Choosing
/// "already spent" is the honest answer for a debt you're just now writing down.
class _DrawdownChoice extends ConsumerWidget {
  final int? selected;
  final String currency;
  final ValueChanged<int?> onChanged;

  const _DrawdownChoice({required this.selected, required this.currency, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;
    final balances = ref.watch(walletBalancesProvider).asData?.value ?? const <WalletBalance>[];
    // The money can only land somewhere it can be spent from.
    final destinations = balances.where((b) => !b.wallet.isLiability).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _DrawdownOption(
              label: 'Already spent it',
              selected: selected == null,
              onTap: () => onChanged(null),
            ),
            for (final b in destinations)
              _DrawdownOption(
                label: 'Into ${b.wallet.name}',
                selected: selected == b.wallet.id,
                onTap: () => onChanged(b.wallet.id),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          selected == null
              ? 'This is debt you already owe — the money\'s gone. Your net worth drops by it.'
              : 'The cash lands there and the debt is recorded here. Your net worth doesn\'t '
                  'change — spend it from that wallet, and this one tracks what\'s left to repay.',
          style: TextStyle(fontSize: 11.5, height: 1.35, color: textTertiary),
        ),
        if (destinations.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Create a cash or bank wallet first if the money landed somewhere.',
            style: TextStyle(fontSize: 11.5, color: textTertiary),
          ),
        ],
      ],
    );
  }
}

class _DrawdownOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawdownOption({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
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
            color: selected
                ? Colors.white
                : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
          ),
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
          WalletDropdown(
            label: 'From wallet',
            value: _fromId,
            excludeId: _toId,
            onChanged: (v) => setState(() => _fromId = v),
          ),
          const SizedBox(height: 12),
          WalletDropdown(
            label: 'To wallet',
            value: _toId,
            excludeId: _fromId,
            onChanged: (v) => setState(() => _toId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          // Warn-only overdraft check on the source asset wallet — moving more
          // than it holds is allowed, but shouldn't be a surprise.
          Builder(builder: (context) {
            final balances =
                ref.watch(walletBalancesProvider).asData?.value ?? const <WalletBalance>[];
            final from = balances.where((b) => b.wallet.id == _fromId).firstOrNull;
            final amount = double.tryParse(_amountController.text.trim()) ?? 0;
            if (from == null ||
                from.wallet.isLiability ||
                amount <= 0 ||
                amount <= from.balance + 0.01) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.warning),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${from.wallet.name} only has ${from.balance.toStringAsFixed(0)} '
                      '${from.displayCurrency} — this transfer will overdraw it.',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.warning, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            );
          }),
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
class WalletEditorSheet extends ConsumerStatefulWidget {
  final WalletModel? existing;
  const WalletEditorSheet({super.key, this.existing});

  static Future<void> show(BuildContext context, {WalletModel? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => WalletEditorSheet(existing: existing),
    );
  }

  @override
  ConsumerState<WalletEditorSheet> createState() => _WalletEditorSheetState();
}

class _WalletEditorSheetState extends ConsumerState<WalletEditorSheet> {
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  final _openingController = TextEditingController();
  late final _limitController = TextEditingController(
    text: (widget.existing?.creditLimit ?? 0) > 0
        ? widget.existing!.creditLimit!.toStringAsFixed(0)
        : '',
  );
  late String _type = widget.existing?.type ?? 'cash';
  late String _currency = widget.existing?.currency ?? 'LKR';
  bool _saving = false;

  static const _currencies = ['LKR', 'USD', 'EUR', 'GBP', 'INR', 'AUD', 'JPY', 'CAD'];

  /// Where a new loan's money landed. Null = "already spent / existing debt".
  int? _drawdownWalletId;

  bool get _isLiability => _type == 'credit' || _type == 'card' || _type == 'loan';

  /// A card is already-charged by the time you seed it — there's no cash to
  /// place — so the question only fits money you actually receive.
  bool get _canDrawDown => _type == 'loan' || _type == 'credit';

  /// Credit/card carry a classic credit limit; a loan can OPTIONALLY cap how
  /// far interest/fees may grow the debt. No cap = warn-only (the default).
  bool get _takesLimit => _type == 'credit' || _type == 'card' || _type == 'loan';

  @override
  void dispose() {
    _nameController.dispose();
    _openingController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final openingText = _openingController.text.trim();
    final opening = double.tryParse(openingText);
    // Required on create: the seed can only be written once here, and a wallet
    // silently starting at zero is wrong in a way the user won't notice until
    // their balances have drifted. "0" is a fine answer — but it has to be said.
    if (widget.existing == null && (openingText.isEmpty || opening == null || opening < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isLiability
              ? 'Enter how much you owe on this — 0 if nothing yet'
              : 'Enter what\'s in this wallet right now — 0 if it\'s empty'),
        ),
      );
      return;
    }
    final limitText = _limitController.text.trim();
    final limit = double.tryParse(limitText);
    if (_takesLimit && limitText.isNotEmpty && (limit == null || limit <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid credit limit, or leave it empty')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final controller = ref.read(walletsControllerProvider.notifier);
      if (widget.existing == null) {
        await controller.create(
          name: name,
          type: _type,
          currency: _currency,
          openingBalance: opening,
          drawdownWalletId: _canDrawDown ? _drawdownWalletId : null,
          creditLimit: _takesLimit ? limit : null,
        );
      } else {
        await controller.update(
          widget.existing!.id,
          name: name,
          type: _type,
          currency: _currency,
          // Always restate the limit on edit: an emptied field clears it.
          setCreditLimit: _takesLimit,
          creditLimit: _takesLimit && limitText.isNotEmpty ? limit : null,
        );
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
          // Credit/card wallets can carry a spending ceiling; the backend
          // refuses a charge that would push the amount owed past it.
          if (_takesLimit) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _limitController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _type == 'loan' ? 'Maximum owed (optional)' : 'Credit limit (optional)',
                hintText: _type == 'loan'
                    ? 'expenses pushing the debt past this are blocked'
                    : 'e.g. 50000 — charges beyond this are blocked',
                prefixText: '$_currency ',
              ),
            ),
          ],
          // Seed what's already there, so a new wallet doesn't have to start at
          // zero. Create-only — re-seeding on edit would double-count; the
          // wallet detail screen corrects it afterwards instead.
          if (widget.existing == null) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _openingController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}), // the drawdown question depends on it
              decoration: InputDecoration(
                labelText: _isLiability ? 'How much do you owe on this?' : 'What\'s in it right now?',
                hintText: _isLiability ? 'e.g. 100000 — enter 0 if nothing yet' : 'e.g. 50000 — enter 0 if empty',
                prefixText: '$_currency ',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isLiability
                  ? "Starts this wallet as a debt you owe. It lowers your net worth without counting as spending."
                  : "Money already in this wallet. It raises your net worth without counting as income.",
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              ),
            ),
            // Borrowing puts real cash somewhere. Saying where records the debt
            // and the money together, so net worth doesn't move and the user
            // spends from the wallet it landed in — the loan just tracks what's
            // owed. Without this the debt exists and the cash never does.
            if (_canDrawDown && (double.tryParse(_openingController.text.trim()) ?? 0) > 0) ...[
              const SizedBox(height: 16),
              Text('Where did the money go?',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
              const SizedBox(height: 8),
              _DrawdownChoice(
                selected: _drawdownWalletId,
                currency: _currency,
                onChanged: (v) => setState(() => _drawdownWalletId = v),
              ),
            ],
          ],
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
