// Grapheme-cluster aware initials: `name[0]` splits Sinhala and Tamil
// combining sequences into broken glyphs, and this app ships both locales.
import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';
import 'ds_foundations.dart';

/// Rows and cards that present data. These are the workhorses — a transaction
/// list, a budget list and a watchlist all share one visual grammar so moving
/// between screens never feels like moving between apps.

// ══════════════════════════════════════════════════════════════════════
// TRANSACTION LIST ITEM
// ══════════════════════════════════════════════════════════════════════

class DsTransactionTile extends StatelessWidget {
  const DsTransactionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amountText,
    required this.amount,
    required this.icon,
    required this.iconColor,
    this.onTap,
    this.onLongPress,
    this.neutral = false,
    this.trailingBelow,
    this.leading,
    this.dense = false,
  });

  final String title;
  final String subtitle;
  final String amountText;
  final num amount;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Transfers: rendered in the neutral tone rather than green/red.
  final bool neutral;

  /// Optional second line under the amount (a wallet name, a status).
  final Widget? trailingBelow;

  /// Replaces the generated icon chip — for an avatar, a merchant logo.
  final Widget? leading;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppTokens.radiusCardSm),
        splashColor: AppColors.primary.withValues(alpha: 0.05),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppTokens.space12,
            vertical: dense ? 8 : AppTokens.space12,
          ),
          child: Row(
            children: [
              leading ??
                  DsIconChip(
                    icon: icon,
                    color: iconColor,
                    size: dense ? 38 : AppTokens.iconChipSize,
                  ),
              const SizedBox(width: AppTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: t.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.space8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DsAmountText(
                    text: amountText,
                    amount: amount,
                    neutral: neutral,
                    fontSize: dense ? 14 : 15,
                  ),
                  if (trailingBelow != null) ...[
                    const SizedBox(height: 2),
                    trailingBelow!,
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

// ══════════════════════════════════════════════════════════════════════
// CATEGORY / BUDGET PROGRESS CARD
// ══════════════════════════════════════════════════════════════════════

class DsBudgetProgressCard extends StatelessWidget {
  const DsBudgetProgressCard({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.spentText,
    required this.limitText,
    required this.fraction,
    this.caption,
    this.footnoteStart,
    this.footnoteEnd,
    this.onTap,
    this.showChevron = true,
    this.remainingText,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final String spentText;
  final String limitText;

  /// 0.0 – 1.0+. Drives both the bar width and its colour.
  final double fraction;

  /// e.g. "32 transactions".
  final String? caption;

  /// Period bounds shown small under the bar, as in the reference.
  final String? footnoteStart;
  final String? footnoteEnd;

  final VoidCallback? onTap;
  final bool showChevron;

  /// e.g. "$900 left out of $1500".
  final String? remainingText;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final pct = (fraction * 100).round();
    final barColor = t.progressColor(fraction);

    return DsCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DsIconChip(icon: icon, color: iconColor),
              const SizedBox(width: AppTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: t.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.space8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    spentText,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    limitText,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: t.textSecondary),
                  ),
                ],
              ),
              if (showChevron && onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: t.textTertiary,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppTokens.space12),
          Row(
            children: [
              Expanded(child: DsProgressBar(value: fraction)),
              const SizedBox(width: AppTokens.space8),
              DsBadge(label: '$pct%', color: barColor, dense: true),
            ],
          ),
          if (remainingText != null) ...[
            const SizedBox(height: AppTokens.space8),
            Text(
              remainingText!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: t.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (footnoteStart != null || footnoteEnd != null) ...[
            const SizedBox(height: AppTokens.space8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  footnoteStart ?? '',
                  style: TextStyle(fontSize: 10.5, color: t.textTertiary),
                ),
                Text(
                  footnoteEnd ?? '',
                  style: TextStyle(fontSize: 10.5, color: t.textTertiary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// STAT TILE  —  the small paired cards ("Mutual Funds", "Interest")
// ══════════════════════════════════════════════════════════════════════

class DsStatTile extends StatelessWidget {
  const DsStatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.sublabel,
    this.badge,
    this.valueColor,
    this.onTap,
    this.emphasis = DsCardEmphasis.standard,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final String? sublabel;
  final Widget? badge;
  final Color? valueColor;
  final VoidCallback? onTap;
  final DsCardEmphasis emphasis;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final accent = iconColor ?? AppColors.primary;

    return DsCard(
      onTap: onTap,
      emphasis: emphasis,
      padding: const EdgeInsets.all(AppTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            DsIconChip(icon: icon!, color: accent, size: 38, iconSize: 19),
            const SizedBox(height: AppTokens.space12),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 1),
            Text(
              sublabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: t.textSecondary),
            ),
          ],
          const SizedBox(height: AppTokens.space8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: valueColor,
                fontSize: 20,
              ),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(height: AppTokens.space8),
            badge!,
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// WATCHLIST / MARKET ROW
// ══════════════════════════════════════════════════════════════════════

/// Leading logo or flag, name + exchange subtitle, trailing price and a signed
/// change badge. Also serves non-market lists that share the shape — a
/// recurring-payments list, an account list.
class DsWatchlistRow extends StatelessWidget {
  const DsWatchlistRow({
    super.key,
    required this.name,
    required this.subtitle,
    required this.value,
    this.change,
    this.changeIsPositive = true,
    this.leading,
    this.onTap,
    this.sparkline,
  });

  final String name;
  final String subtitle;
  final String value;
  final String? change;
  final bool changeIsPositive;
  final Widget? leading;
  final VoidCallback? onTap;

  /// Optional inline mini-chart between the label and the price.
  final Widget? sparkline;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final changeColor = changeIsPositive ? t.success : t.danger;

    return DsCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space16,
        vertical: AppTokens.space12,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppTokens.space12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: t.textSecondary),
                ),
              ],
            ),
          ),
          if (sparkline != null) ...[
            SizedBox(width: 56, height: 28, child: sparkline),
            const SizedBox(width: AppTokens.space12),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (change != null) ...[
                const SizedBox(height: 3),
                Text(
                  change!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: changeColor,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// AVATAR ROW
// ══════════════════════════════════════════════════════════════════════

class DsAvatarEntry {
  const DsAvatarEntry({
    required this.name,
    this.imageProvider,
    this.onTap,
    this.color,
  });

  final String name;
  final ImageProvider? imageProvider;
  final VoidCallback? onTap;
  final Color? color;
}

/// Horizontally scrollable circular avatars with name captions. An optional
/// leading "add" affordance keeps the row useful when it is empty.
class DsAvatarRow extends StatelessWidget {
  const DsAvatarRow({
    super.key,
    required this.entries,
    this.onAdd,
    this.addLabel = 'Add',
    this.size = 54,
    this.padding =
        const EdgeInsets.symmetric(horizontal: AppTokens.screenPadding),
  });

  final List<DsAvatarEntry> entries;
  final VoidCallback? onAdd;
  final String addLabel;
  final double size;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final tiles = <Widget>[];
    if (onAdd != null) {
      tiles.add(
        _AvatarTile(
          size: size,
          label: addLabel,
          onTap: onAdd,
          child: DottedCircle(
            size: size,
            color: t.border,
            child: Icon(Icons.add_rounded, color: AppColors.primary, size: 22),
          ),
        ),
      );
    }

    for (final e in entries) {
      final initial = e.name.characters.isEmpty
          ? '?'
          : e.name.characters.first.toUpperCase();
      final color = e.color ?? AppColors.categoryColor(e.name);
      tiles.add(
        _AvatarTile(
          size: size,
          label: e.name,
          onTap: e.onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: t.isDark ? 0.24 : 0.14),
              image: e.imageProvider == null
                  ? null
                  : DecorationImage(image: e.imageProvider!, fit: BoxFit.cover),
            ),
            alignment: Alignment.center,
            child: e.imageProvider != null
                ? null
                : Text(
                    initial,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: size * 0.36,
                    ),
                  ),
          ),
        ),
      );
    }

    return SizedBox(
      height: size + 26,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppTokens.space16),
        itemBuilder: (_, i) => tiles[i],
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({
    required this.child,
    required this.label,
    required this.size,
    this.onTap,
  });

  final Widget child;
  final String label;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 6),
          SizedBox(
            width: size + 8,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: t.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed-outline circle used for "add" affordances, so an empty avatar row
/// still reads as an invitation rather than a bug.
class DottedCircle extends StatelessWidget {
  const DottedCircle({
    super.key,
    required this.size,
    required this.color,
    required this.child,
  });

  final double size;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DashedCirclePainter(color: color),
        child: Center(child: child),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = color;

    const dashes = 22;
    final r = size.width / 2 - 1;
    final c = Offset(size.width / 2, size.height / 2);
    const sweep = 6.28318 / dashes;

    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        i * sweep,
        sweep * 0.55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) => old.color != color;
}
