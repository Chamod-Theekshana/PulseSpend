import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/group_model.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/groups_provider.dart';
import '../../../shared/widgets/category_icon.dart';

/// A single shared group: merged summary, invite code, members and a combined
/// (read-only) transaction feed from everyone in the group.
class GroupDetailScreen extends ConsumerWidget {
  final GroupModel group;
  const GroupDetailScreen({super.key, required this.group});

  Future<void> _confirmLeave(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(group.isOwner ? 'Disband group?' : 'Leave group?'),
        content: Text(
          group.isOwner
              ? 'As the owner, leaving disbands the group for everyone.'
              : 'You\'ll stop seeing this group\'s shared activity.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(group.isOwner ? 'Disband' : 'Leave', style: const TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(groupsControllerProvider.notifier).leave(group.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(groupFeedProvider(group.id));
    final membersAsync = ref.watch(groupMembersProvider(group.id));
    final money = ref.watch(moneyFormatterProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          IconButton(
            tooltip: group.isOwner ? 'Disband' : 'Leave',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _confirmLeave(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(groupFeedProvider(group.id));
          ref.invalidate(groupMembersProvider(group.id));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // ── Merged summary ──
            feedAsync.when(
              data: (feed) => _SummaryCard(summary: feed.summary, money: money),
              loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => _ErrorCard(message: DioClient.toApiException(e).message),
            ),
            const SizedBox(height: 20),

            // ── Invite code ──
            _InviteCard(code: group.inviteCode, groupName: group.name, isDark: isDark),
            const SizedBox(height: 20),

            // ── Members ──
            Text('Members', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
            const SizedBox(height: 10),
            membersAsync.when(
              data: (members) => Column(
                children: [
                  for (final m in members)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                            child: Text(
                              m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : '?',
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(m.displayName, style: TextStyle(fontSize: 14, color: textPrimary)),
                          ),
                          if (m.role == 'owner')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Owner', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              loading: () => const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
              error: (_, _) => Text('Couldn\'t load members', style: TextStyle(color: textSecondary)),
            ),
            const SizedBox(height: 20),

            // ── Combined activity ──
            Text('Combined activity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
            const SizedBox(height: 10),
            feedAsync.when(
              data: (feed) => feed.transactions.isEmpty
                  ? Text('No shared transactions yet.', style: TextStyle(color: textSecondary))
                  : Column(
                      children: [
                        for (final tx in feed.transactions)
                          _GroupTxRow(tx: tx, money: money, isDark: isDark),
                      ],
                    ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final GroupSummary summary;
  final MoneyFormatter money;
  const _SummaryCard({required this.summary, required this.money});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Group balance', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            money.formatCompact(summary.balance, summary.currency),
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _stat('Income', money.formatCompact(summary.income, summary.currency))),
              Expanded(child: _stat('Expense', money.formatCompact(summary.expense, summary.currency))),
              Expanded(child: _stat('Entries', '${summary.transactionCount}')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
        ],
      );
}

class _InviteCard extends StatelessWidget {
  final String code;
  final String groupName;
  final bool isDark;
  const _InviteCard({required this.code, required this.groupName, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFF1F1F1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invite code', style: TextStyle(fontSize: 12, color: textSecondary)),
                const SizedBox(height: 4),
                Text(
                  code,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 2, color: textPrimary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite code copied')),
              );
            },
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            onPressed: () => Share.share(
              'Join my "$groupName" group on PulseSpend with code: $code',
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTxRow extends StatelessWidget {
  final GroupTransaction tx;
  final MoneyFormatter money;
  final bool isDark;
  const _GroupTxRow({required this.tx, required this.money, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final amountColor = tx.isExpense ? AppColors.expense : AppColors.income;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CategoryIcon(category: tx.category, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.title, style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${tx.memberName} · ${DateFormatter.relative(tx.createdAt)}',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            money.format(tx.amount, tx.currency, showSign: true),
            style: TextStyle(fontWeight: FontWeight.w800, color: amountColor),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.expense.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.expense)),
    );
  }
}
