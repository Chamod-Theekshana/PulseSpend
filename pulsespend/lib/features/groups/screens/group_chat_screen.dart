import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/chat_message_model.dart';
import '../../../models/group_model.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../providers/transactions_provider.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../widgets/expense_bubble_widget.dart';
import '../widgets/group_settle_sheet.dart';

class GroupChatScreen extends ConsumerStatefulWidget {
  final GroupModel group;

  const GroupChatScreen({
    super.key,
    required this.group,
  });

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// Message count at the last build, so we only auto-scroll when the list
  /// actually grew. The old code called `_scrollToBottom()` on EVERY build,
  /// which fired an animation on unrelated rebuilds (typing, theme changes,
  /// provider ticks) and fought the user whenever they scrolled up to read.
  int _lastMessageCount = 0;

  /// Server ids of expense bubbles whose settle request is in flight.
  final Set<String> _settling = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // Near the top of a chronological list = the oldest messages = fetch more.
    if (_scrollController.position.pixels <= 120) {
      ref.read(chatProvider(widget.group.id).notifier).loadOlder();
    }
  }

  /// True when the viewport is close enough to the bottom that auto-scrolling
  /// is welcome rather than intrusive.
  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels < 220;
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final myUserId = ref.read(authControllerProvider).userId ?? '';
    ref.read(chatProvider(widget.group.id).notifier).sendMessage(
          text,
          myUserId: myUserId,
        );
    _messageController.clear();
    _scrollToBottom();
  }

  // ── Shared expense ─────────────────────────────────────────────────────────

  /// Creates a REAL group transaction, then announces it in the chat.
  ///
  /// The previous implementation only posted a chat message carrying some
  /// metadata. Nothing was ever written to `transactions` or
  /// `group_expense_splits`, so a "shared expense" never moved anyone's group
  /// balance — which in turn meant the settle button on the bubble had nothing
  /// real to settle. The bubble is now a *view* of an actual shared expense.
  Future<void> _shareExpense(String title, double amount) async {
    final myUserId = ref.read(authControllerProvider).userId ?? '';
    final myName = ref.read(profileControllerProvider).user?.name ?? 'They';
    final currency = ref.read(displayCurrencyProvider);
    final memberCount = math.max(widget.group.memberCount, 1);

    try {
      final created = await ref.read(transactionRepositoryProvider).create(
            TransactionModel(
              id: 0,
              userId: myUserId,
              title: title,
              // Negative: this is money spent. The backend splits on the
              // absolute value and keeps the sign on the transaction.
              amount: -amount,
              currency: currency,
              category: 'Group',
              createdAt: DateTime.now(),
              groupId: widget.group.id,
              // No explicit participants → the server splits equally across
              // all current members, which is what "split with everyone" means.
              groupSplit: const {'mode': 'equal'},
            ),
          );

      if (!mounted) return;

      await ref.read(chatProvider(widget.group.id).notifier).sendMessage(
        'Shared an expense: $title',
        myUserId: myUserId,
        expenseMetadata: {
          'type': 'expense',
          'transactionId': created.id,
          'title': title,
          'amount': amount,
          'currency': currency,
          'payerId': myUserId,
          'payerName': myName,
          'participantCount': memberCount,
          'shareAmount': amount / memberCount,
          'splitWith': memberCount > 1 ? '$memberCount members' : 'the group',
        },
      );

      // The group's own screens key off these.
      ref.invalidate(groupBalancesProvider(widget.group.id));
      ref.invalidate(groupFeedProvider(widget.group.id));
      _refreshTransactions();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
      );
    }
  }

  /// Keeps the personal transaction list in step without blocking the UI.
  void _refreshTransactions() {
    unawaited(ref.read(transactionsControllerProvider.notifier).refresh());
  }

  // ── Settlement ─────────────────────────────────────────────────────────────

  /// How much the viewer currently owes [payerId], per the group's authoritative
  /// balance netting (in the balances' currency).
  double _netOwedTo(GroupBalances? balances, String myId, String payerId) {
    if (balances == null) return 0;
    for (final s in balances.suggestions) {
      if (s.fromUserId == myId && s.toUserId == payerId) return s.amount;
    }
    return 0;
  }

  /// Settles the viewer's share of a shared expense with the person who paid.
  ///
  /// The amount is the smaller of (a) this expense's per-person share and
  /// (b) what the viewer actually still owes that person across the whole
  /// group. Capping at (b) matters: settling the raw share when earlier
  /// expenses have already been netted off would overpay and flip the balance
  /// the other way.
  Future<void> _settleShare(ChatMessage message, GroupBalances balances) async {
    final meta = message.metadata ?? const <String, dynamic>{};
    final payerId = (meta['payerId'] ?? message.senderId).toString();
    final payerName = (meta['payerName'] as String?) ?? 'them';
    final title = (meta['title'] as String?) ?? 'shared expense';

    final money = ref.read(moneyFormatterProvider);
    final expenseCurrency = (meta['currency'] as String?) ?? balances.currency;
    final share = (meta['shareAmount'] as num?)?.toDouble() ?? 0;
    // Compare like with like: balances are already in the display currency.
    final shareInBalanceCurrency = money.convert(share, expenseCurrency);
    final owed = _netOwedTo(balances, ref.read(authControllerProvider).userId ?? '', payerId);
    final amount = math.min(shareInBalanceCurrency, owed);

    if (amount <= 0.005) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are already settled up with them')),
      );
      return;
    }

    final choice = await showModalBottomSheet<GroupSettleResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GroupSettleSheet(
        toName: payerName,
        amount: amount,
        currency: balances.currency,
        subtitle: 'Your share of "$title"',
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _settling.add(message.id));
    try {
      await ref.read(groupRepositoryProvider).settle(
            widget.group.id,
            toUser: payerId,
            amount: amount,
            currency: balances.currency,
            walletId: choice.walletId,
          );

      ref.invalidate(groupBalancesProvider(widget.group.id));
      ref.invalidate(groupSettlementsProvider(widget.group.id));
      ref.invalidate(groupFeedProvider(widget.group.id));
      _refreshTransactions();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settled up ✓'), backgroundColor: AppColors.income),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
      );
    } finally {
      if (mounted) setState(() => _settling.remove(message.id));
    }
  }

  void _showExpenseDialog() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Share an Expense',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'This records a real group expense and splits it equally.',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              style: TextStyle(
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'What was it for?',
                hintText: 'e.g. Dinner, Groceries',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              style: TextStyle(
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                hintText: '0.00',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () {
                  final title = titleCtrl.text.trim();
                  final amount = double.tryParse(amountCtrl.text.trim());
                  if (title.isEmpty || amount == null || amount <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid title and amount')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  _shareExpense(title, amount);
                },
                icon: const Icon(Icons.send),
                label: const Text('Share with Group'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider(widget.group.id));
    final myUserId = ref.watch(authControllerProvider).userId ?? '';
    final balancesAsync = ref.watch(groupBalancesProvider(widget.group.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final inputBg = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    // Only follow the conversation when it actually advanced AND the reader is
    // already at the bottom — never yank them away from older messages.
    if (messages.length > _lastMessageCount) {
      final grewByOne = messages.length - _lastMessageCount == 1;
      if (_isNearBottom || grewByOne) _scrollToBottom();
    }
    _lastMessageCount = messages.length;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            if (widget.group.membersPreview.isNotEmpty) ...[
              AvatarStack(
                backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? surfaceColor,
                radius: 13,
                max: 3,
                people: [
                  for (final m in widget.group.membersPreview)
                    (name: m.name, photoUrl: m.profilePhoto, userId: m.userId),
                ],
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.group.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${widget.group.memberCount} members',
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _EmptyChat(textSecondary: textSecondary)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message.senderId == myUserId;

                      // WhatsApp-style run grouping: consecutive messages from
                      // the same person within a few minutes read as one block.
                      // The name goes on the FIRST of a run and the avatar on
                      // the LAST, so the block reads as a single utterance
                      // instead of repeating the sender on every line.
                      final prev = index > 0 ? messages[index - 1] : null;
                      final next = index < messages.length - 1 ? messages[index + 1] : null;
                      bool sameRun(ChatMessage? other) =>
                          other != null &&
                          other.senderId == message.senderId &&
                          (message.timestamp.difference(other.timestamp).inMinutes).abs() < 5;
                      final isFirstOfRun = !sameRun(prev);
                      final isLastOfRun = !sameRun(next);

                      final meta = message.metadata;
                      if (meta != null && meta['type'] == 'expense') {
                        return _AvatarRow(
                          isMe: isMe,
                          showAvatar: isLastOfRun,
                          name: message.senderName ?? 'Member',
                          photoUrl: message.senderPhoto,
                          userId: message.senderId,
                          child: _buildExpenseBubble(
                            message: message,
                            isMe: isMe,
                            myUserId: myUserId,
                            balancesAsync: balancesAsync,
                          ),
                        );
                      }

                      return _AvatarRow(
                        isMe: isMe,
                        showAvatar: isLastOfRun,
                        name: message.senderName ?? 'Member',
                        photoUrl: message.senderPhoto,
                        userId: message.senderId,
                        child: _TextBubble(
                          message: message,
                          isMe: isMe,
                          isDark: isDark,
                          showSenderName: !isMe && isFirstOfRun,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onRetry: message.status == MessageStatus.failed
                              ? () => ref
                                  .read(chatProvider(widget.group.id).notifier)
                                  .retry(message.localId ?? '')
                              : null,
                        ),
                      );
                    },
                  ),
          ),
          _buildComposer(
            surfaceColor: surfaceColor,
            borderColor: borderColor,
            inputBg: inputBg,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseBubble({
    required ChatMessage message,
    required bool isMe,
    required String myUserId,
    required AsyncValue<GroupBalances> balancesAsync,
  }) {
    final meta = message.metadata ?? const <String, dynamic>{};
    final payerId = (meta['payerId'] ?? message.senderId).toString();
    final balances = balancesAsync.asData?.value;

    SettleState settleState;
    double settleAmount = 0;

    if (isMe) {
      settleState = SettleState.mine;
    } else if (balances == null) {
      settleState = SettleState.loading;
    } else {
      final money = ref.read(moneyFormatterProvider);
      final expenseCurrency = (meta['currency'] as String?) ?? balances.currency;
      final share = (meta['shareAmount'] as num?)?.toDouble() ?? 0;
      final owed = _netOwedTo(balances, myUserId, payerId);
      settleAmount = math.min(money.convert(share, expenseCurrency), owed);
      settleState = settleAmount > 0.005 ? SettleState.owed : SettleState.settled;
    }

    return ExpenseBubbleWidget(
      message: message,
      isMe: isMe,
      settleState: settleState,
      settleAmount: settleAmount,
      isSettling: _settling.contains(message.id),
      onSettlePressed: (settleState == SettleState.owed && balances != null)
          ? () => _settleShare(message, balances)
          : null,
    );
  }

  Widget _buildComposer({
    required Color surfaceColor,
    required Color borderColor,
    required Color inputBg,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(top: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _showExpenseDialog,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long_outlined,
                        color: AppColors.primary, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: TextStyle(color: textPrimary, fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: textSecondary, fontSize: 14.5),
                    filled: true,
                    fillColor: inputBg,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          BorderSide(color: AppColors.primary.withValues(alpha: 0.4), width: 1),
                    ),
                    isDense: true,
                  ),
                  maxLines: 4,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _sendMessage,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 19),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final Color textSecondary;
  const _EmptyChat({required this.textSecondary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 64, color: textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            'No messages yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Start the conversation!',
            style: TextStyle(fontSize: 13, color: textSecondary.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

/// Lays a bubble out with an avatar gutter on the incoming side.
///
/// The gutter is reserved even when no avatar is drawn, so every bubble in a
/// run lines up rather than jittering left and right as avatars appear and
/// disappear. Outgoing messages get no avatar at all — you know who you are.
class _AvatarRow extends StatelessWidget {
  final bool isMe;
  final bool showAvatar;
  final String name;
  final String? photoUrl;
  final String userId;
  final Widget child;

  const _AvatarRow({
    required this.isMe,
    required this.showAvatar,
    required this.name,
    required this.photoUrl,
    required this.userId,
    required this.child,
  });

  static const double _gutter = 40;

  @override
  Widget build(BuildContext context) {
    if (isMe) return child;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(
          width: _gutter,
          child: showAvatar
              ? Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: UserAvatar(
                    name: name,
                    photoUrl: photoUrl,
                    userId: userId,
                    radius: 14,
                  ),
                )
              : null,
        ),
        Flexible(child: child),
      ],
    );
  }
}

class _TextBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool isDark;
  final bool showSenderName;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback? onRetry;

  const _TextBubble({
    required this.message,
    required this.isMe,
    required this.isDark,
    required this.showSenderName,
    required this.textPrimary,
    required this.textSecondary,
    this.onRetry,
  });

  String _formatTime(DateTime time) {
    final h = time.hour;
    final m = time.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$hour12:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final failed = message.status == MessageStatus.failed;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        // A failed message used to be a dead end — the only way to recover was
        // to retype it. Tapping now re-sends the same message.
        onTap: onRetry,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: EdgeInsets.only(
            top: 3,
            bottom: 3,
            left: isMe ? 12 : 0,
            right: 12,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMe
                ? AppColors.primary
                : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            border: failed
                ? Border.all(color: AppColors.expense.withValues(alpha: 0.8), width: 1)
                : null,
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSenderName) ...[
                Text(
                  message.senderName ?? 'Member',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    // Same colour the avatar uses, so name and face are
                    // visually tied together.
                    color: UserAvatar.colorFor(message.senderId),
                  ),
                ),
                const SizedBox(height: 3),
              ],
              Text(
                message.content,
                style: TextStyle(
                  fontSize: 14.5,
                  color: isMe ? Colors.white : textPrimary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    failed ? 'Tap to retry' : _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: failed
                          ? AppColors.expense
                          : (isMe ? Colors.white70 : textSecondary),
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 3),
                    Icon(
                      message.status == MessageStatus.sent
                          ? Icons.done_all
                          : message.status == MessageStatus.pending
                              ? Icons.access_time_rounded
                              : Icons.error_outline,
                      size: 13,
                      color: failed ? AppColors.expense : Colors.white70,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
