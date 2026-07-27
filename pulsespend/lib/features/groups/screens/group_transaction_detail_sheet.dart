import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../providers/groups_provider.dart';
import '../../../../shared/utils/image_utils.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/category_icon.dart';

class GroupTransactionDetailSheet extends ConsumerWidget {
  final int groupId;
  final int txId;

  const GroupTransactionDetailSheet({
    super.key,
    required this.groupId,
    required this.txId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(
      groupTransactionDetailProvider((groupId: groupId, txId: txId)),
    );

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: detailAsync.when(
          loading: () => const SizedBox(
            height: 300,
            child: Center(child: AppLoader(size: 40)),
          ),
          error: (err, stack) => SizedBox(
            height: 300,
            child: Center(
              child: Text(
                'Could not load details\n$err',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.expense),
              ),
            ),
          ),
          data: (detail) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
            final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
            final amountColor = detail.isExpense ? AppColors.expense : AppColors.income;

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: textSecondary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Header
                    Center(
                      child: Column(
                        children: [
                          CategoryIcon(category: detail.category, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            detail.title,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            CurrencyFormatter.format(detail.amount, detail.currency, showSign: true),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: amountColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Main Info Card
                    _DetailCard(
                      children: [
                        _DetailRow(
                          icon: Icons.person_outline,
                          label: detail.isExpense ? 'Paid by' : 'Received by',
                          value: detail.memberName,
                          valueWidget: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                                child: Text(
                                  detail.memberName.isNotEmpty ? detail.memberName[0].toUpperCase() : '?',
                                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 10),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(detail.memberName, style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary)),
                            ],
                          ),
                        ),
                        _DetailRow(icon: Icons.category_outlined, label: 'Category', value: detail.category),
                        _DetailRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Date',
                          value: DateFormatter.display(detail.createdAt),
                        ),
                        _DetailRow(
                          icon: Icons.payments_outlined,
                          label: 'Currency',
                          value: detail.currency,
                        ),
                        if (detail.walletName != null)
                          _DetailRow(
                            icon: Icons.account_balance_wallet_outlined,
                            label: 'Wallet',
                            value: detail.walletName!,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Viewer's Share Card
                    if (detail.viewerOwed != null && detail.viewerOwed! > 0) ...[
                      Text('Your share', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(detail.isExpense ? Icons.arrow_outward_rounded : Icons.south_west_rounded,
                                color: AppColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                detail.isExpense ? 'You owe' : 'You are owed',
                                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary),
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(detail.viewerOwed!, detail.currency),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Split Breakdown
                    if (detail.splits.isNotEmpty) ...[
                      Text('Split breakdown', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      _DetailCard(
                        children: detail.splits.map((s) {
                          return _DetailRow(
                            icon: Icons.call_split_rounded,
                            label: s.name,
                            value: CurrencyFormatter.format(s.owedAmount, detail.currency),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Notes
                    if (detail.notes != null && detail.notes!.isNotEmpty) ...[
                      Text('Notes', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(detail.notes!, style: TextStyle(color: textPrimary)),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Tags
                    if (detail.tags.isNotEmpty) ...[
                      Text('Tags', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: detail.tags.map((t) => Chip(label: Text('#$t'))).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Receipt
                    if (detail.receiptUrl != null && detail.receiptUrl!.isNotEmpty) ...[
                      Text('Receipt', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReceiptViewer(url: detail.receiptUrl!),
                          ),
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image(
                            image: getProfileImageProvider(detail.receiptUrl!),
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              height: 80,
                              alignment: Alignment.center,
                              color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
                              child: const Text('Receipt unavailable'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32), // bottom padding
                    ],
                  ],
                );
              },
            );
          },
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? valueWidget;

  const _DetailRow({required this.icon, required this.label, required this.value, this.valueWidget});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final primary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: secondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: secondary))),
          valueWidget ?? Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: primary)),
        ],
      ),
    );
  }
}

/// Full-screen, zoomable receipt view (reused from transactions).
class ReceiptViewer extends StatelessWidget {
  final String url;
  const ReceiptViewer({required this.url});

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
