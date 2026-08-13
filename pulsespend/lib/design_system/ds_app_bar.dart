import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';

/// Header treatments. Two variants cover every screen in the app: the
/// dashboard's identity header, and the plain titled header everything else
/// uses. Neither is a Material [AppBar] — both are ordinary widgets, so they
/// can sit inside a scroll view and scroll away with the content.

// ══════════════════════════════════════════════════════════════════════
// IDENTITY HEADER  —  avatar + "Welcome back, {name}" + actions
// ══════════════════════════════════════════════════════════════════════

class DsIdentityAppBar extends StatelessWidget {
  const DsIdentityAppBar({
    super.key,
    required this.greeting,
    required this.name,
    this.avatar,
    this.onAvatarTap,
    this.onNotificationTap,
    this.onMenuTap,
    this.unreadCount = 0,
    this.leadingWidget,
    this.padding = const EdgeInsets.fromLTRB(
      AppTokens.screenPadding,
      AppTokens.space12,
      AppTokens.screenPadding,
      AppTokens.space20,
    ),
  });

  final String greeting;
  final String name;
  final ImageProvider? avatar;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onMenuTap;
  final int unreadCount;

  /// Replaces the avatar block entirely — e.g. a segmented toggle, as on the
  /// reference's "Manage / Invest" screen.
  final Widget? leadingWidget;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: leadingWidget ??
                  Row(
                    children: [
                      _Avatar(
                        image: avatar,
                        name: name,
                        onTap: onAvatarTap,
                      ),
                      const SizedBox(width: AppTokens.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              greeting,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: t.textSecondary),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
            ),
            if (onNotificationTap != null)
              DsHeaderIconButton(
                icon: Icons.notifications_none_rounded,
                onTap: onNotificationTap!,
                badgeCount: unreadCount,
              ),
            if (onMenuTap != null) ...[
              const SizedBox(width: AppTokens.space4),
              DsHeaderIconButton(
                icon: Icons.menu_rounded,
                onTap: onMenuTap!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.image, required this.name, this.onTap});

  final ImageProvider? image;
  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withValues(alpha: t.isDark ? 0.22 : 0.12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.22),
            width: 1.5,
          ),
          image: image == null
              ? null
              : DecorationImage(image: image!, fit: BoxFit.cover),
        ),
        alignment: Alignment.center,
        child: image != null
            ? null
            : Text(
                initial,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// HEADER ICON BUTTON
// ══════════════════════════════════════════════════════════════════════

/// Bell / menu / back. Optional unread dot with a count.
class DsHeaderIconButton extends StatelessWidget {
  const DsHeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.tooltip,
    this.filled = false,
    this.onHero = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;
  final String? tooltip;

  /// Sits the glyph on a surface chip — used when the header sits over content
  /// and a bare icon would lack contrast.
  final bool filled;

  /// Placed on the gradient hero: white glyph on a translucent white chip.
  final bool onHero;

  /// Overrides the glyph colour outright.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = color ?? (onHero ? Colors.white : t.textPrimary);

    final BoxDecoration? decoration;
    if (onHero) {
      decoration = BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      );
    } else if (filled) {
      decoration = BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
        border: Border.all(color: t.border),
      );
    } else {
      decoration = null;
    }

    final button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 42,
        height: 42,
        decoration: decoration,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 24, color: fg),
            if (badgeCount > 0)
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: BoxDecoration(
                    color: AppColors.expense,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

// ══════════════════════════════════════════════════════════════════════
// TITLED HEADER  —  every non-dashboard screen
// ══════════════════════════════════════════════════════════════════════

class DsTitleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DsTitleAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.showBack = true,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool showBack;

  /// A filter row, a segmented toggle — anything that belongs to the header
  /// rather than to the scrolling body.
  final Widget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(bottom == null ? 64 : 64 + 56);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.space12,
              AppTokens.space8,
              AppTokens.screenPadding,
              AppTokens.space8,
            ),
            child: Row(
              children: [
                if (showBack)
                  DsHeaderIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: onBack ?? () => Navigator.of(context).maybePop(),
                  )
                else
                  const SizedBox(width: AppTokens.space8),
                const SizedBox(width: AppTokens.space4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: t.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          if (bottom != null) bottom!,
        ],
      ),
    );
  }
}
