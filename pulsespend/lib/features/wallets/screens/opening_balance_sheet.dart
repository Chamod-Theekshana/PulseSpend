import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/wallet_model.dart';
import '../../../providers/wallets_provider.dart';

/// Corrects what a wallet held (or owed) when it was created.
///
/// The opening balance can only be answered once, at create time, and a wrong
/// answer skews the wallet forever — so it has to be fixable. This replaces the
/// original seed rather than posting an adjustment: someone fixing a number they
/// mistyped expects it changed, not a second entry explaining the difference.
///
/// It rewrites transactions, so the wallet's balance moves — hence a separate
/// flow from the plain name/type editor, with the effect spelled out first.
class OpeningBalanceSheet extends ConsumerStatefulWidget {
  final WalletModel wallet;
  final WalletBalance? balance;

  const OpeningBalanceSheet({super.key, required this.wallet, required this.balance});

  static Future<void> show(
    BuildContext context, {
    required WalletModel wallet,
    required WalletBalance? balance,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OpeningBalanceSheet(wallet: wallet, balance: balance),
    );
  }

  @override
  ConsumerState<OpeningBalanceSheet> createState() => _OpeningBalanceSheetState();
}

class _OpeningBalanceSheetState extends ConsumerState<OpeningBalanceSheet> {
  late final _controller = TextEditingController(
    text: (widget.balance?.borrowed ?? widget.wallet.openingBalance ?? 0) > 0
        ? (widget.balance?.borrowed ?? widget.wallet.openingBalance)!.toStringAsFixed(0)
        : '',
  );
  int? _drawdownWalletId;
  bool _saving = false;

  bool get _isLiability => widget.wallet.isLiability;
  bool get _canDrawDown => widget.wallet.type == 'loan' || widget.wallet.type == 'credit';

  /// Seeded before this was tracked, or never seeded: there's nothing to replace,
  /// so saving ADDS an opening the wallet never had and its balance jumps.
  bool get _isLegacy => widget.wallet.openingBalance == null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    final value = double.tryParse(text);
    if (text.isEmpty || value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount — 0 if there\'s nothing')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(walletsControllerProvider.notifier).correctOpeningBalance(
            widget.wallet.id,
            openingBalance: value,
            drawdownWalletId: _canDrawDown ? _drawdownWalletId : null,
          );
      if (!mounted) return;
      Navigator.pop(context);
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
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;
    final cur = widget.balance?.displayCurrency ?? widget.wallet.currency;

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
            _isLiability ? 'Correct amount owed' : 'Correct balance',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            _isLiability
                ? 'What ${widget.wallet.name} owed when you added it. Charges and repayments since then are kept.'
                : 'What was in ${widget.wallet.name} when you added it. Everything since then is kept.',
            style: TextStyle(fontSize: 12.5, color: textTertiary, height: 1.35),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _isLiability ? 'Amount owed at the start' : 'Balance at the start',
              prefixText: '$cur ',
            ),
          ),
          if (_isLegacy) ...[
            const SizedBox(height: 12),
            _Note(
              text: 'This wallet never had an opening balance recorded, so saving this will '
                  'change its balance by the full amount.',
              isDark: isDark,
            ),
          ],
          if (_canDrawDown && (double.tryParse(_controller.text.trim()) ?? 0) > 0) ...[
            const SizedBox(height: 16),
            Text('Where did the money go?',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
            const SizedBox(height: 8),
            _Destinations(
              selected: _drawdownWalletId,
              excludeId: widget.wallet.id,
              onChanged: (v) => setState(() => _drawdownWalletId = v),
            ),
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
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  final bool isDark;

  const _Note({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.warning.withValues(alpha: 0.12) : AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wallets the borrowed money could have landed in — assets only, since the cash
/// has to be somewhere it can be spent from, and never the debt itself.
class _Destinations extends ConsumerWidget {
  final int? selected;
  final int excludeId;
  final ValueChanged<int?> onChanged;

  const _Destinations({required this.selected, required this.excludeId, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final balances = ref.watch(walletBalancesProvider).asData?.value ?? const <WalletBalance>[];
    final destinations =
        balances.where((b) => !b.wallet.isLiability && b.wallet.id != excludeId).toList();

    Widget chip(String label, bool isSelected, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip('Already spent it', selected == null, () => onChanged(null)),
            for (final b in destinations)
              chip('Into ${b.wallet.name}', selected == b.wallet.id, () => onChanged(b.wallet.id)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          selected == null
              ? 'Debt you already owe — the money\'s gone. Your net worth drops by it.'
              : 'The cash lands there and the debt stays here, so your net worth doesn\'t change.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.35,
            color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
          ),
        ),
      ],
    );
  }
}
