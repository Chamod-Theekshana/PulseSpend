import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/wallet_model.dart';

/// Breaks the net-worth headline into where it actually comes from: each wallet
/// type's contribution on the asset side (plus goal savings), each debt on the
/// liability side. Renders `NetWorth.byType` straight from the API.
class NetWorthBreakdownSheet extends StatelessWidget {
  final NetWorth netWorth;

  const NetWorthBreakdownSheet({super.key, required this.netWorth});

  static Future<void> show(BuildContext context, NetWorth netWorth) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NetWorthBreakdownSheet(netWorth: netWorth),
    );
  }

  static String _label(String type) => switch (type) {
        'cash' => 'Cash',
        'bank' => 'Bank accounts',
        'card' => 'Cards',
        'credit' => 'Credit',
        'investment' => 'Investments',
        'loan' => 'Loans',
        'goals' => 'Saving goals',
        'iou_receivable' => 'Owed to you',
        'iou_payable' => 'You owe others',
        _ => '${type[0].toUpperCase()}${type.substring(1)}',
      };

  static IconData _icon(String type) => switch (type) {
        'bank' => Icons.account_balance_rounded,
        'card' || 'credit' => Icons.credit_card_rounded,
        'investment' => Icons.trending_up_rounded,
        'loan' => Icons.request_quote_outlined,
        'goals' => Icons.savings_outlined,
        'iou_receivable' || 'iou_payable' => Icons.handshake_outlined,
        _ => Icons.payments_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final cur = netWorth.currency;

    final assets = netWorth.byType.where((t) => !t.isLiability && t.total != 0).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final liabilities = netWorth.byType.where((t) => t.isLiability && t.total != 0).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Text('Net worth breakdown',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Everything you own, minus everything you owe.',
            style: TextStyle(fontSize: 12.5, color: textSecondary),
          ),
          const SizedBox(height: 18),
          _Section(
            title: 'Assets',
            total: netWorth.assets,
            currency: cur,
            color: AppColors.income,
            rows: assets,
          ),
          if (liabilities.isNotEmpty) ...[
            const SizedBox(height: 18),
            _Section(
              title: 'Liabilities',
              total: netWorth.liabilities,
              currency: cur,
              color: AppColors.expense,
              rows: liabilities,
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Net worth',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14, color: textPrimary)),
                ),
                Text(
                  CurrencyFormatter.format(netWorth.netWorth, cur),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: netWorth.netWorth < 0 ? AppColors.expense : AppColors.income,
                  ),
                ),
              ],
            ),
          ),
          if (liabilities.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'No liabilities yet. Credit, card and loan wallets show up here as debt — '
              'create one with what you already owe to see it counted.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final double total;
  final String currency;
  final Color color;
  final List<NetWorthType> rows;

  const _Section({
    required this.title,
    required this.total,
    required this.currency,
    required this.color,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: textPrimary)),
            ),
            Text(
              CurrencyFormatter.format(total, currency),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: color),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Text('Nothing here yet.', style: TextStyle(fontSize: 12, color: textSecondary)),
          ),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(NetWorthBreakdownSheet._icon(r.type), size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    NetWorthBreakdownSheet._label(r.type),
                    style: TextStyle(fontSize: 13, color: textPrimary),
                  ),
                ),
                Text(
                  CurrencyFormatter.format(r.total, currency),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
