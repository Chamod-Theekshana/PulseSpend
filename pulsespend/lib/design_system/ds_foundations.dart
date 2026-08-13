import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';

/// Foundational surfaces and primitives. Everything else in the design system
/// is assembled from these, so a change here propagates to every screen.

// ══════════════════════════════════════════════════════════════════════
// SURFACES
// ══════════════════════════════════════════════════════════════════════

/// Emphasis level for a [DsCard]. The reference design does not give every
/// card the same weight — a hero sits forward, a nested stat card recedes —
/// and this enum is how that hierarchy stays consistent instead of being
/// re-invented per screen.
enum DsCardEmphasis {
  /// Primary content card: full surface, standard radius, soft shadow.
  standard,

  /// Nested or secondary card sitting *inside* another surface. Flat, alt
  /// background, no shadow — it must not compete with its parent.
  nested,

  /// Quiet grouping container: no fill, hairline border only.
  outlined,
}

class DsCard extends StatelessWidget {
  const DsCard({
    super.key,
    required this.child,
    this.emphasis = DsCardEmphasis.standard,
    this.padding = const EdgeInsets.all(AppTokens.space16),
    this.radius = AppTokens.radiusCard,
    this.onTap,
    this.borderColor,
    this.color,
    this.width,
    this.margin,
  });

  final Widget child;
  final DsCardEmphasis emphasis;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;
  final double? width;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);

    late final Color fill;
    late final List<BoxShadow> shadow;
    late final Color line;

    switch (emphasis) {
      case DsCardEmphasis.standard:
        fill = color ?? theme.colorScheme.surface;
        shadow = t.cardShadow;
        line = borderColor ?? (t.isDark ? t.border : t.border.withValues(alpha: 0.7));
        break;
      case DsCardEmphasis.nested:
        fill = color ?? t.surfaceAlt;
        shadow = const [];
        line = borderColor ?? Colors.transparent;
        break;
      case DsCardEmphasis.outlined:
        fill = color ?? Colors.transparent;
        shadow = const [];
        line = borderColor ?? t.border;
        break;
    }

    final content = Container(
      width: width,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: line == Colors.transparent ? null : Border.all(color: line, width: 1),
        boxShadow: shadow,
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: AppColors.primary.withValues(alpha: 0.06),
        highlightColor: AppColors.primary.withValues(alpha: 0.04),
        child: content,
      ),
    );
  }
}

/// The gradient surface the balance / portfolio hero sits on. Separated from
/// [DsHeroBalanceCard] so other screens (wallet totals, goal detail) can borrow
/// the same treatment without inheriting a chart.
class DsHeroSurface extends StatelessWidget {
  const DsHeroSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTokens.space20),
    this.margin,
    this.radius = AppTokens.radiusHero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: t.heroGradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: t.heroShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            // Faint topographic swirl, as in the reference cards. Painted rather
            // than shipped as an asset so it tints with the gradient.
            Positioned.fill(
              child: CustomPaint(painter: _HeroContourPainter()),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class _HeroContourPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.055);

    // Three nested arcs sweeping out of the bottom-right corner.
    for (var i = 0; i < 3; i++) {
      final r = size.width * (0.55 + i * 0.22);
      canvas.drawCircle(Offset(size.width * 0.92, size.height * 1.05), r, paint);
    }
    for (var i = 0; i < 2; i++) {
      final r = size.width * (0.30 + i * 0.18);
      canvas.drawCircle(Offset(size.width * 0.06, -size.height * 0.15), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════════
// SECTION HEADER
// ══════════════════════════════════════════════════════════════════════

/// "Transactions            View all →". One header treatment, every screen.
class DsSectionHeader extends StatelessWidget {
  const DsSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: AppTokens.screenPadding),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Overrides [actionLabel] when a screen needs something richer than a link
  /// (a date chip, a dropdown).
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null)
            trailing!
          else if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_forward_rounded, size: 15),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// ICON CHIP
// ══════════════════════════════════════════════════════════════════════

/// A rounded pastel square holding an outline icon — the reference's signature
/// list-row leading element. The background is the accent colour at a low tint;
/// the icon is the same accent at full saturation.
class DsIconChip extends StatelessWidget {
  const DsIconChip({
    super.key,
    required this.icon,
    required this.color,
    this.size = AppTokens.iconChipSize,
    this.iconSize,
    this.shape = BoxShape.rectangle,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.13),
        shape: shape,
        borderRadius: shape == BoxShape.rectangle
            ? BorderRadius.circular(AppTokens.radiusChip)
            : null,
      ),
      child: Icon(icon, color: color, size: iconSize ?? size * 0.5),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// PROGRESS BAR
// ══════════════════════════════════════════════════════════════════════

/// Thin, fully-rounded track. Colour follows [AppTokens.progressColor] unless
/// overridden, so a bar at 80% looks the same whether it is a budget or a goal.
class DsProgressBar extends StatelessWidget {
  const DsProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = AppTokens.progressBarHeight,
    this.trackColor,
    this.animate = true,
  });

  /// 0.0 – 1.0. Values above 1 are clamped for drawing but still colour as
  /// "over limit".
  final double value;
  final Color? color;
  final double height;
  final Color? trackColor;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final clamped = value.clamp(0.0, 1.0);
    final fill = color ?? t.progressColor(value);

    // Sized with Align + FractionallySizedBox rather than a Stack over a
    // LayoutBuilder. A Stack takes its size from its largest *non-positioned*
    // child, so the earlier version measured the fill and collapsed the whole
    // bar to the filled fraction whenever the parent handed down loose
    // constraints — a bar at 20% rendered as a 20%-wide bar with no track.
    final bar = Container(
      height: height,
      decoration: BoxDecoration(
        color: trackColor ?? t.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: clamped,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
          ),
        ),
      ),
    );

    if (!animate) return bar;

    // Animating the *factor* rather than a pixel width keeps the tween correct
    // when the bar is resized mid-flight (rotation, split-screen).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: clamped),
      duration: AppTokens.motionSlow,
      curve: AppTokens.motionCurve,
      builder: (context, v, _) => Container(
        height: height,
        decoration: BoxDecoration(
          color: trackColor ?? t.surfaceAlt,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// BADGE / PILL
// ══════════════════════════════════════════════════════════════════════

/// The small tinted percentage or delta pill — "+3.75%", "35%", "Listed in BSE".
class DsBadge extends StatelessWidget {
  const DsBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
    this.dense = false,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Solid fill with white text, for the strongest emphasis.
  final bool filled;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final fg = filled ? Colors.white : color;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: isDark ? 0.22 : 0.13),
        borderRadius: BorderRadius.circular(AppTokens.radiusBadge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: dense ? 10.5 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// AMOUNT TEXT
// ══════════════════════════════════════════════════════════════════════

/// Renders a money figure in the semantic colour for its sign, with the small
/// trend arrow the reference puts beside trailing amounts. Centralised so no
/// screen ever has to decide "is this green or red" on its own.
class DsAmountText extends StatelessWidget {
  const DsAmountText({
    super.key,
    required this.text,
    required this.amount,
    this.showArrow = true,
    this.fontSize = 15,
    this.neutral = false,
  });

  final String text;
  final num amount;
  final bool showArrow;
  final double fontSize;

  /// Transfers and internal movements are neither income nor expense — they
  /// render in the neutral tone so the eye does not read them as spending.
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = neutral ? t.neutralShift : t.amountColor(amount);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        if (showArrow) ...[
          const SizedBox(width: 3),
          Icon(
            neutral
                ? Icons.swap_vert_rounded
                : (amount < 0
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded),
            size: fontSize * 0.85,
            color: color,
          ),
        ],
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// DIVIDER
// ══════════════════════════════════════════════════════════════════════

/// Inset hairline. Replaces bare `Divider()` so the indent is never guessed.
class DsDivider extends StatelessWidget {
  const DsDivider({super.key, this.indent = 0, this.height = 1});

  final double indent;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: EdgeInsets.only(left: indent),
      color: context.tokens.border,
    );
  }
}
