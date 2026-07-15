import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/goal_model.dart';
import '../../../models/group_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../goals/screens/contribute_goal_sheet.dart';

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
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
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
              error: (e, _) => _ErrorCard(message: DioClient.toApiException(e).localizedMessage(context)),
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

            // ── Balances (Splitwise-lite) ──
            _BalancesSection(group: group, money: money, isDark: isDark),
            const SizedBox(height: 20),

            // ── Shared goals ──
            _GroupGoalsSection(group: group, money: money, isDark: isDark),
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

/// Who-owes-whom over the group's shared expenses, with one-tap settle-up.
class _BalancesSection extends ConsumerWidget {
  final GroupModel group;
  final MoneyFormatter money;
  final bool isDark;

  const _BalancesSection({required this.group, required this.money, required this.isDark});

  Future<void> _settle(BuildContext context, WidgetRef ref, SettleSuggestion s, String currency) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record payment?'),
        content: Text(
          'This records that you paid ${s.toName} '
          '${s.amount.toStringAsFixed(2)} $currency. They\'ll be notified.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Record')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(groupRepositoryProvider).settle(
            group.id,
            toUser: s.toUserId,
            amount: s.amount,
            currency: currency,
          );
      ref.invalidate(groupBalancesProvider(group.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded ✓'), backgroundColor: AppColors.income),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(groupBalancesProvider(group.id));
    final myId = ref.watch(authControllerProvider).userId;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return balancesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (balances) {
        if (balances.total <= 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Balances',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
              const SizedBox(height: 8),
              Text(
                'No shared expenses yet. Use "Share to group" when adding an expense '
                'to split it with members.',
                style: TextStyle(fontSize: 12.5, color: textSecondary, height: 1.4),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Balances',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
            const SizedBox(height: 4),
            Text(
              'Shared spend: ${money.formatCompact(balances.total, balances.currency)} · split equally',
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
            const SizedBox(height: 10),
            for (final m in balances.members)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.userId == myId ? '${m.name} (you)' : m.name,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      m.net.abs() < 0.01
                          ? 'settled'
                          : m.net > 0
                              ? 'gets back ${money.formatCompact(m.net, balances.currency)}'
                              : 'owes ${money.formatCompact(m.net.abs(), balances.currency)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: m.net.abs() < 0.01
                            ? textSecondary
                            : m.net > 0
                                ? AppColors.income
                                : AppColors.expense,
                      ),
                    ),
                  ],
                ),
              ),
            // Settle-up: only the suggestions where *I* am the payer.
            for (final s in balances.suggestions.where((s) => s.fromUserId == myId)) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _settle(context, ref, s, balances.currency),
                  icon: const Icon(Icons.handshake_outlined, size: 18),
                  label: Text(
                    'Settle up: pay ${s.toName} ${money.formatCompact(s.amount, balances.currency)}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _GroupGoalsSection extends ConsumerWidget {
  final GroupModel group;
  final MoneyFormatter money;
  final bool isDark;

  const _GroupGoalsSection({required this.group, required this.money, required this.isDark});

  Future<void> _contribute(BuildContext context, WidgetRef ref, GoalModel goal) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ContributeGoalSheet(goal: goal),
    );
    ref.invalidate(groupGoalsProvider(group.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(groupGoalsProvider(group.id));
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return goalsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (goals) {
        if (goals.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shared goals',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
            const SizedBox(height: 10),
            for (final g in goals)
              _goalCard(context, ref, g, textPrimary, textSecondary),
          ],
        );
      },
    );
  }

  Widget _goalCard(BuildContext context, WidgetRef ref, GoalModel g,
      Color textPrimary, Color textSecondary) {
    final progress =
        g.targetAmount > 0 ? (g.currentAmount / g.targetAmount).clamp(0.0, 1.0) : 0.0;
    return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFF1F1F1)),
                ),
                child: Row(
                  children: [
                    // Progress ring
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 4,
                            backgroundColor:
                                (isDark ? AppColors.darkBorder : const Color(0xFFEDEDED)),
                            valueColor: AlwaysStoppedAnimation(
                              g.isCompleted ? AppColors.income : AppColors.primary,
                            ),
                          ),
                          Text(
                            '${(progress * 100).round()}%',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w800, color: textPrimary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.name,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${money.formatCompact(g.currentAmount, g.currency)} of '
                            '${money.formatCompact(g.targetAmount, g.currency)}',
                            style: TextStyle(fontSize: 12, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (!g.isCompleted)
                      TextButton(
                        onPressed: () => _contribute(context, ref, g),
                        child: const Text('Add',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      )
                    else
                      const Icon(Icons.emoji_events_rounded, color: AppColors.income, size: 22),
                  ],
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
