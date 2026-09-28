import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../design_system/ds.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/transactions_provider.dart';
import '../../../providers/wallets_provider.dart';
import '../../../shared/utils/image_utils.dart';
import '../../../shared/widgets/category_icon.dart';
import 'add_transaction_screen.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../providers/date_format_provider.dart';

class TransactionDetailScreen extends ConsumerWidget {
  final TransactionModel transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.actionCancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(transactionsControllerProvider.notifier).delete(transaction.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsControllerProvider).items;
    final tk = context.tokens;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AddTransactionScreen(existing: transaction)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.screenPadding),
          children: [
            // Hero: the one figure this screen exists for. It carries the
            // shadow, the padding and the weight — everything below it is
            // deliberately flatter and quieter.
            DsCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.space20,
                vertical: AppTokens.space24,
              ),
              child: Center(
                child: Column(
                  children: [
                    CategoryIcon(category: transaction.category, size: 64),
                    const SizedBox(height: AppTokens.space16),
                    Text(
                      transaction.title,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTokens.space12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: DsAmountText(
                        text: CurrencyFormatter.format(transaction.amount, transaction.currency, showSign: true),
                        amount: transaction.amount,
                        fontSize: 34,
                        showArrow: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTokens.space24),
            _DetailCard(
              children: [
                _DetailRow(icon: Icons.category_outlined, label: 'Category', value: transaction.category),
                _DetailRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date',
                  value: DateFormatter.display(transaction.createdAt, pattern: ref.watch(dateFormatProvider)),
                ),
                _DetailRow(
                  icon: Icons.payments_outlined,
                  label: 'Currency',
                  value: transaction.currency,
                ),
                // Which wallet this came out of — only once wallets exist, since
                // before that everything is implicitly the default bucket.
                if (wallets.isNotEmpty)
                  _DetailRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Wallet',
                    value: wallets
                            .where((w) => w.id == transaction.walletId)
                            .firstOrNull
                            ?.name ??
                        'Default',
                  ),
              ],
            ),
            if (transaction.isSplit) ...[
              const SizedBox(height: AppTokens.space24),
              const DsSectionHeader(title: 'Split breakdown', padding: EdgeInsets.zero),
              const SizedBox(height: AppTokens.space12),
              _DetailCard(
                children: transaction.splits
                    .map((s) => _DetailRow(
                          icon: Icons.call_split_rounded,
                          label: s.category,
                          value: CurrencyFormatter.format(s.amount.abs(), transaction.currency),
                        ))
                    .toList(),
              ),
            ],
            if (transaction.notes != null && transaction.notes!.isNotEmpty) ...[
              const SizedBox(height: AppTokens.space24),
              const DsSectionHeader(title: 'Notes', padding: EdgeInsets.zero),
              const SizedBox(height: AppTokens.space12),
              DsCard(
                width: double.infinity,
                emphasis: DsCardEmphasis.nested,
                radius: AppTokens.radiusCardSm,
                padding: const EdgeInsets.all(AppTokens.space16),
                child: Text(transaction.notes!, style: theme.textTheme.bodyMedium),
              ),
            ],
            if (transaction.tags.isNotEmpty) ...[
              const SizedBox(height: AppTokens.space24),
              const DsSectionHeader(title: 'Tags', padding: EdgeInsets.zero),
              const SizedBox(height: AppTokens.space12),
              Wrap(
                spacing: AppTokens.space8,
                runSpacing: AppTokens.space8,
                children: transaction.tags
                    .map((t) => DsBadge(label: '#$t', color: AppColors.primary))
                    .toList(),
              ),
            ],
            if (transaction.receiptUrl != null && transaction.receiptUrl!.isNotEmpty) ...[
              const SizedBox(height: AppTokens.space24),
              const DsSectionHeader(title: 'Receipt', padding: EdgeInsets.zero),
              const SizedBox(height: AppTokens.space12),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _ReceiptViewer(url: transaction.receiptUrl!),
                  ),
                ),
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                  child: Image(
                    image: getProfileImageProvider(transaction.receiptUrl!),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 80,
                      alignment: Alignment.center,
                      color: tk.surfaceAlt,
                      child: Text(
                        'Receipt unavailable',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-screen, zoomable receipt view.
class _ReceiptViewer extends StatelessWidget {
  final String url;
  const _ReceiptViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image(image: getProfileImageProvider(url)),
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final List<Widget> children;
  const _DetailCard({required this.children});

  @override
  Widget build(BuildContext context) {
    // Nested emphasis: flat, no shadow. The metadata is reference material, not
    // the point of the screen — the amount above it is.
    return DsCard(
      emphasis: DsCardEmphasis.nested,
      radius: AppTokens.radiusCardSm,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space16,
        vertical: AppTokens.space4,
      ),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space8),
      child: Row(
        children: [
          DsIconChip(icon: icon, color: AppColors.primary, size: 32, iconSize: 16),
          const SizedBox(width: AppTokens.space12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: tk.textSecondary),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
