import 'package:flutter/material.dart';
import '../../design_system/ds.dart';

/// App-wide empty state.
///
/// The public API is unchanged — every existing call site still passes an
/// [icon], a [title] and a [message]. What changed is the rendering: instead of
/// a grey glyph in a circle, the icon now picks a drawn scene from
/// [DsEmptyArt], so an empty screen looks composed rather than unfinished.
///
/// Pass [art] explicitly to override the mapping.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Overrides the icon → illustration mapping below.
  final DsEmptyArt? art;

  /// Tighter spacing, for use inside a card rather than a full screen.
  final bool compact;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.art,
    this.compact = false,
  });

  /// Maps the icon a screen already passes onto the closest drawn scene, so
  /// none of the existing call sites had to change.
  static DsEmptyArt _artFor(IconData icon) {
    if (icon == Icons.receipt_long_outlined ||
        icon == Icons.receipt_long_rounded ||
        icon == Icons.swap_horiz_rounded) {
      return DsEmptyArt.transactions;
    }
    if (icon == Icons.account_balance_wallet_outlined ||
        icon == Icons.account_balance_wallet_rounded ||
        icon == Icons.credit_card_rounded ||
        icon == Icons.handshake_outlined) {
      return DsEmptyArt.wallet;
    }
    if (icon == Icons.pie_chart_outline_rounded ||
        icon == Icons.flag_outlined ||
        icon == Icons.autorenew_rounded ||
        icon == Icons.category_outlined ||
        icon == Icons.groups_outlined) {
      return DsEmptyArt.progress;
    }
    if (icon == Icons.notifications_none_rounded ||
        icon == Icons.notifications_active_outlined) {
      return DsEmptyArt.bell;
    }
    if (icon == Icons.cloud_off_rounded || icon == Icons.wifi_off_rounded) {
      return DsEmptyArt.offline;
    }
    if (icon == Icons.search_off_rounded || icon == Icons.search_rounded) {
      return DsEmptyArt.search;
    }
    return DsEmptyArt.transactions;
  }

  @override
  Widget build(BuildContext context) {
    return DsEmptyState(
      art: art ?? _artFor(icon),
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      compact: compact,
    );
  }
}
