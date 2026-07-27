import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../shared/widgets/app_loader.dart';
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
import '../../../providers/wallets_provider.dart';
import '../../../shared/utils/image_utils.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../goals/screens/contribute_goal_sheet.dart';
import 'group_transaction_detail_sheet.dart';
import 'group_analytics_section.dart';
import 'group_chat_screen.dart';

class _IsExportingNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final _isExportingProvider = NotifierProvider.autoDispose<_IsExportingNotifier, bool>(_IsExportingNotifier.new);

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

  Future<void> _act(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
      );
    }
  }

  Future<void> _kick(BuildContext context, WidgetRef ref, GroupMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.displayName}?'),
        content: const Text('They\'ll lose access to the group. Their share of past '
            'expenses stays on the books so balances don\'t change.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _act(context, () => ref.read(groupsControllerProvider.notifier).removeMember(group.id, m.userId));
    }
  }

  Future<void> _makeOwner(BuildContext context, WidgetRef ref, GroupMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Make ${m.displayName} the owner?'),
        content: const Text('They\'ll be able to manage members and the group. You\'ll become a regular member.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Transfer')),
        ],
      ),
    );
    if (ok == true) {
      await _act(context, () => ref.read(groupsControllerProvider.notifier).transferOwnership(group.id, m.userId));
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (name != null && name.isNotEmpty && name != group.name) {
      await _act(context, () => ref.read(groupsControllerProvider.notifier).rename(group.id, name));
    }
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    ref.read(_isExportingProvider.notifier).set(true);
    try {
      final csv = await ref.read(groupsControllerProvider.notifier).exportCsv(group.id);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File('${dir.path}/pulsespend_group_${group.id}_$stamp.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)], text: '${group.name} transactions');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(DioClient.toApiException(e).localizedMessage(context)),
          backgroundColor: AppColors.expense,
        ),
      );
    } finally {
      ref.read(_isExportingProvider.notifier).set(false);
    }
  }

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    ref.read(_isExportingProvider.notifier).set(true);
    try {
      final bytes = await ref.read(groupsControllerProvider.notifier).exportPdf(group.id);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File('${dir.path}/pulsespend_group_${group.id}_$stamp.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: '${group.name} report');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(DioClient.toApiException(e).localizedMessage(context)),
          backgroundColor: AppColors.expense,
        ),
      );
    } finally {
      ref.read(_isExportingProvider.notifier).set(false);
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
    final isExporting = ref.watch(_isExportingProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          IconButton(
            tooltip: 'Group Chat',
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => GroupChatScreen(group: group),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Export',
            enabled: !isExporting,
            icon: isExporting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
            onSelected: (v) => v == 'pdf' ? _exportPdf(context, ref) : _exportCsv(context, ref),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: Icon(Icons.table_view_rounded),
                  title: Text('Export CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_rounded),
                  title: Text('Export PDF'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          if (group.isOwner)
            IconButton(
              tooltip: 'Rename group',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _rename(context, ref),
            ),
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
              loading: () => const SizedBox(height: 120, child: Center(child: AppLoader(size: 40))),
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
                            )
                          // The owner can hand over ownership or remove a member.
                          else if (group.isOwner)
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_horiz_rounded, size: 20, color: textSecondary),
                              onSelected: (v) => v == 'owner'
                                  ? _makeOwner(context, ref, m)
                                  : _kick(context, ref, m),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'owner', child: Text('Make owner')),
                                PopupMenuItem(value: 'remove', child: Text('Remove from group')),
                              ],
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

            // ── Analytics ──
            GroupAnalyticsSection(groupId: group.id),
            const SizedBox(height: 20),

            // ── Balances (Splitwise-lite) ──
            _BalancesSection(group: group, money: money, isDark: isDark),
            const SizedBox(height: 20),

            // ── Settle-up history ──
            _SettlementsSection(group: group, money: money, isDark: isDark),

            // ── Shared goals ──
            _GroupGoalsSection(group: group, money: money, isDark: isDark),
            const SizedBox(height: 20),

            // ── Receipts Gallery ──
            _ReceiptsGallerySection(group: group, isDark: isDark),
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
                          _GroupTxRow(tx: tx, money: money, isDark: isDark, groupId: group.id),
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
/// Settle-up history. Every settle-up is immediate and moves real cash; either
/// party can undo one, which reverses both wallets and the group balance.
class _SettlementsSection extends ConsumerWidget {
  final GroupModel group;
  final MoneyFormatter money;
  final bool isDark;

  const _SettlementsSection({required this.group, required this.money, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupSettlementsProvider(group.id));
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        // Read lazily so an error/loading state short-circuits before this
        // (currentUserIdProvider throws when unauthenticated, e.g. in tests).
        final myId = ref.watch(currentUserIdProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settle-up history',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
            const SizedBox(height: 10),
            for (final s in items.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      s.status == 'disputed' ? Icons.cancel_rounded : Icons.check_circle_rounded,
                      size: 18,
                      color: s.status == 'disputed' ? AppColors.expense : AppColors.income,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${s.fromName} → ${s.toName}',
                          style: TextStyle(fontSize: 13, color: textPrimary),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(money.format(s.amount, s.currency),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textSecondary)),
                    // Either the payer or the payee can undo their settle-up.
                    if (s.fromUserId == myId || s.toUserId == myId) ...[
                      const SizedBox(width: 8),
                      _MiniBtn(label: 'Undo', color: AppColors.expense, onTap: () => _undo(context, ref, s)),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Future<void> _undo(BuildContext context, WidgetRef ref, GroupSettlement s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo settle-up?'),
        content: Text(
          'Reverses ${s.fromName} → ${s.toName} ${money.format(s.amount, s.currency)}. '
          'Both wallets and the group balance snap back.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Undo')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(groupsControllerProvider.notifier).undoSettlement(group.id, s.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
      );
    }
  }
}

class _MiniBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MiniBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }
}

class _BalancesSection extends ConsumerWidget {
  final GroupModel group;
  final MoneyFormatter money;
  final bool isDark;

  const _BalancesSection({required this.group, required this.money, required this.isDark});

  Future<void> _settle(BuildContext context, WidgetRef ref, SettleSuggestion s, String currency) async {
    // Ask which wallet the cash left from, then settle immediately: the balance
    // moves now and real money changes hands (payer's wallet out, payee's default
    // bucket in). Net worth stays flat — the open group position moves the other way.
    final choice = await showModalBottomSheet<_GroupSettleResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GroupSettleSheet(toName: s.toName, amount: s.amount, currency: currency),
    );
    if (choice == null) return;
    try {
      await ref.read(groupRepositoryProvider).settle(
            group.id,
            toUser: s.toUserId,
            amount: s.amount,
            currency: currency,
            walletId: choice.walletId,
          );
      ref.invalidate(groupBalancesProvider(group.id));
      ref.invalidate(groupSettlementsProvider(group.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settled up ✓'), backgroundColor: AppColors.income),
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
                'Nothing shared yet. Use "Share to group" when adding an expense or '
                'income to split it with members.',
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
              'Shared total: ${money.formatCompact(balances.total, balances.currency)}',
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

class _ReceiptsGallerySection extends ConsumerWidget {
  final GroupModel group;
  final bool isDark;
  const _ReceiptsGallerySection({required this.group, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final feedAsync = ref.watch(groupFeedProvider(group.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Receipts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary)),
        const SizedBox(height: 10),
        feedAsync.when(
          data: (feed) {
            final txsWithReceipts = feed.transactions.where((t) => t.receiptUrl != null && t.receiptUrl!.isNotEmpty).toList();
            if (txsWithReceipts.isEmpty) {
              return Text('No receipts added yet.', style: TextStyle(color: textSecondary));
            }
            return SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: txsWithReceipts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final tx = txsWithReceipts[i];
                  return InkWell(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => GroupTransactionDetailSheet(
                          groupId: group.id,
                          txId: tx.id,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image(
                        image: getProfileImageProvider(tx.receiptUrl!),
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 100,
                          height: 100,
                          color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
                          alignment: Alignment.center,
                          child: const Icon(Icons.receipt_long_outlined, color: Colors.grey),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
      ],
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
  final int groupId;
  const _GroupTxRow({required this.tx, required this.money, required this.isDark, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final amountColor = tx.isExpense ? AppColors.expense : AppColors.income;

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => GroupTransactionDetailSheet(
            groupId: groupId,
            txId: tx.id,
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            CategoryIcon(category: tx.category, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(tx.title,
                            style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (tx.receiptUrl != null) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.receipt_long_outlined, size: 14, color: textSecondary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Expense → "paid by X · you owe Y"; income → "received by X ·
                    // you're owed Y" (income splits in reverse — the receiver owes
                    // the others their share).
                    '${tx.isExpense ? 'paid by' : 'received by'} ${tx.memberName}'
                    '${tx.viewerOwed != null && tx.viewerOwed! > 0 ? ' · ${tx.isExpense ? 'you owe' : 'you\'re owed'} ${money.format(tx.viewerOwed!, tx.currency)}' : ''}'
                    ' · ${DateFormatter.relative(tx.createdAt)}',
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                  if (tx.notes != null && tx.notes!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(tx.notes!,
                        style: TextStyle(fontSize: 11.5, color: textSecondary, fontStyle: FontStyle.italic),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
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

class _GroupSettleResult {
  /// null = the default cash bucket; >0 = a specific wallet the cash left from.
  final int? walletId;
  const _GroupSettleResult(this.walletId);
}

/// Asks which wallet the payer's settle-up cash came from, then settles. The
/// chosen wallet moves by the amount via a transfer-excluded leg (not counted as
/// spending); "Default" uses the untracked cash bucket. The payee's side always
/// lands in their own default bucket, since we can't know their wallets.
class _GroupSettleSheet extends ConsumerStatefulWidget {
  final String toName;
  final double amount;
  final String currency;
  const _GroupSettleSheet({required this.toName, required this.amount, required this.currency});

  @override
  ConsumerState<_GroupSettleSheet> createState() => _GroupSettleSheetState();
}

class _GroupSettleSheetState extends ConsumerState<_GroupSettleSheet> {
  /// 0 = the default bucket; >0 = a specific wallet id.
  int _selection = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final money = ref.watch(moneyFormatterProvider);
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
          const Text('Settle up?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'You paid ${widget.toName} ${money.format(widget.amount, widget.currency)}. '
            'This settles the balance right away.',
            style: TextStyle(fontSize: 13, color: textSecondary),
          ),
          const SizedBox(height: 16),
          const Text('Which wallet did it come from?',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('Default', 0),
              for (final w in wallets) chip(w.name, w.id),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'The wallet drops by the amount — without counting as spending, because '
            'settling a shared debt is money changing hands, not an expense.',
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
              onPressed: () =>
                  Navigator.pop(context, _GroupSettleResult(_selection == 0 ? null : _selection)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Settle up'),
            ),
          ),
        ],
      ),
    );
  }
}
