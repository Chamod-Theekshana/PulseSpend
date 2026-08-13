import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';
import 'ds_controls.dart';
import 'ds_foundations.dart';

/// Empty, loading and error states.
///
/// These get their own file — and their own drawn illustrations — because a
/// generic grey icon on a blank screen is the single clearest tell that a UI
/// was generated rather than designed. Each state below composes real shapes
/// from the design system's own vocabulary.

// ══════════════════════════════════════════════════════════════════════
// ILLUSTRATIONS
// ══════════════════════════════════════════════════════════════════════

/// Which drawn scene an empty state shows. Each is built from the same chips,
/// bars and rings the rest of the app uses, so an empty screen still looks
/// like it belongs to this product.
enum DsEmptyArt {
  /// Ghosted transaction rows — for an empty feed.
  transactions,

  /// A part-filled progress ring — for budgets and goals.
  progress,

  /// A card outline — for wallets and accounts.
  wallet,

  /// A magnifier over a row — for "no results".
  search,

  /// A bell — for notifications.
  bell,

  /// A cloud-slash — for offline / error.
  offline,
}

class DsEmptyIllustration extends StatelessWidget {
  const DsEmptyIllustration({
    super.key,
    required this.art,
    this.color,
    this.size = 128,
  });

  final DsEmptyArt art;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = color ?? AppColors.primary;

    return SizedBox(
      width: size,
      height: size * 0.82,
      child: CustomPaint(
        painter: _EmptyArtPainter(
          art: art,
          accent: accent,
          surface: t.surfaceAlt,
          cardSurface: Theme.of(context).colorScheme.surface,
          line: t.border,
          isDark: t.isDark,
        ),
      ),
    );
  }
}

class _EmptyArtPainter extends CustomPainter {
  const _EmptyArtPainter({
    required this.art,
    required this.accent,
    required this.surface,
    required this.cardSurface,
    required this.line,
    required this.isDark,
  });

  final DsEmptyArt art;
  final Color accent;
  final Color surface;

  /// Opaque card colour, for shapes that must knock out what sits behind them.
  final Color cardSurface;
  final Color line;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // A soft halo behind every scene, so the art has a ground.
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      w * 0.40,
      Paint()..color = accent.withValues(alpha: isDark ? 0.10 : 0.07),
    );

    final fill = Paint()..color = surface;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = line;
    final accentFill = Paint()..color = accent;
    final accentStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = accent;

    switch (art) {
      case DsEmptyArt.transactions:
        // Three stacked rows, the middle one accented — a list waiting to fill.
        for (var i = 0; i < 3; i++) {
          final top = h * 0.24 + i * (h * 0.19);
          final inset = i == 1 ? w * 0.12 : w * 0.18;
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(inset, top, w - inset * 2, h * 0.13),
            const Radius.circular(7),
          );
          canvas.drawRRect(rect, fill);
          canvas.drawRRect(rect, stroke);
          // Leading chip.
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(inset + 7, top + h * 0.028, h * 0.075, h * 0.075),
              const Radius.circular(4),
            ),
            i == 1 ? accentFill : (Paint()..color = line),
          );
        }
        break;

      case DsEmptyArt.progress:
        final r = w * 0.26;
        final c = Offset(w / 2, h / 2);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..color = line,
        );
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          -1.5708,
          3.6,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round
            ..color = accent,
        );
        break;

      case DsEmptyArt.wallet:
        final card = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.18, h * 0.30, w * 0.64, h * 0.40),
          const Radius.circular(10),
        );
        canvas.drawRRect(card, fill);
        canvas.drawRRect(card, stroke);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.18, h * 0.40, w * 0.64, h * 0.075),
            Radius.zero,
          ),
          accentFill,
        );
        canvas.drawCircle(Offset(w * 0.70, h * 0.60), w * 0.045, accentFill);
        break;

      case DsEmptyArt.search:
        final row = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.16, h * 0.32, w * 0.60, h * 0.14),
          const Radius.circular(7),
        );
        canvas.drawRRect(row, fill);
        canvas.drawRRect(row, stroke);
        canvas.drawCircle(
          Offset(w * 0.60, h * 0.60),
          w * 0.16,
          Paint()..color = cardSurface,
        );
        canvas.drawCircle(Offset(w * 0.60, h * 0.60), w * 0.16, accentStroke);
        canvas.drawLine(
          Offset(w * 0.72, h * 0.74),
          Offset(w * 0.82, h * 0.88),
          accentStroke,
        );
        break;

      case DsEmptyArt.bell:
        final p = Path()
          ..moveTo(w * 0.34, h * 0.60)
          ..lineTo(w * 0.66, h * 0.60)
          ..lineTo(w * 0.62, h * 0.50)
          ..lineTo(w * 0.62, h * 0.40)
          ..arcToPoint(Offset(w * 0.38, h * 0.40),
              radius: Radius.circular(w * 0.12), clockwise: true)
          ..lineTo(w * 0.38, h * 0.50)
          ..close();
        canvas.drawPath(p, fill);
        canvas.drawPath(p, accentStroke);
        canvas.drawCircle(Offset(w / 2, h * 0.67), w * 0.035, accentFill);
        break;

      case DsEmptyArt.offline:
        final cloud = Path()
          ..addOval(Rect.fromCircle(center: Offset(w * 0.42, h * 0.48), radius: w * 0.13))
          ..addOval(Rect.fromCircle(center: Offset(w * 0.58, h * 0.50), radius: w * 0.11))
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.34, h * 0.50, w * 0.32, h * 0.13),
              const Radius.circular(9),
            ),
          );
        canvas.drawPath(cloud, fill);
        canvas.drawPath(cloud, stroke);
        canvas.drawLine(
          Offset(w * 0.34, h * 0.32),
          Offset(w * 0.68, h * 0.74),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = accent,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _EmptyArtPainter old) =>
      old.art != art ||
      old.accent != accent ||
      old.surface != surface ||
      old.cardSurface != cardSurface ||
      old.line != line;
}

// ══════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ══════════════════════════════════════════════════════════════════════

class DsEmptyState extends StatelessWidget {
  const DsEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.art = DsEmptyArt.transactions,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.accent,
    this.compact = false,
  });

  final String title;
  final String message;
  final DsEmptyArt art;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Color? accent;

  /// Tighter spacing for use inside a card rather than a full screen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppTokens.space32,
          vertical: compact ? AppTokens.space20 : AppTokens.space32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsEmptyIllustration(
              art: art,
              color: accent,
              size: compact ? 96 : 132,
            ),
            SizedBox(height: compact ? AppTokens.space12 : AppTokens.space20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: t.textSecondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? AppTokens.space16 : AppTokens.space24),
              DsPrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
                height: 46,
              ),
            ],
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: AppTokens.space8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// LOADING SKELETONS
// ══════════════════════════════════════════════════════════════════════

/// A single shimmering block. Composed into the skeletons below rather than
/// dropping one spinner in the middle of every screen — a skeleton that mirrors
/// the real layout makes the wait feel shorter and stops the page jumping.
class DsSkeletonBox extends StatefulWidget {
  const DsSkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 7,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;

  @override
  State<DsSkeletonBox> createState() => _DsSkeletonBoxState();
}

class _DsSkeletonBoxState extends State<DsSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              t.surfaceAlt,
              t.border,
              _c.value * 0.85,
            ),
            shape: widget.shape,
            borderRadius: widget.shape == BoxShape.rectangle
                ? BorderRadius.circular(widget.radius)
                : null,
          ),
        );
      },
    );
  }
}

/// Placeholder matching [DsTransactionTile]'s geometry.
class DsTransactionSkeleton extends StatelessWidget {
  const DsTransactionSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (i) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space12,
            vertical: AppTokens.space12,
          ),
          child: Row(
            children: [
              const DsSkeletonBox(
                width: AppTokens.iconChipSize,
                height: AppTokens.iconChipSize,
                radius: AppTokens.radiusChip,
              ),
              const SizedBox(width: AppTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Staggered widths so the block does not read as a table.
                    DsSkeletonBox(width: 120.0 + (i % 3) * 26, height: 13),
                    const SizedBox(height: 7),
                    DsSkeletonBox(width: 68.0 + (i % 2) * 18, height: 10),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.space12),
              const DsSkeletonBox(width: 62, height: 15),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder matching the hero balance card.
class DsHeroSkeleton extends StatelessWidget {
  const DsHeroSkeleton({super.key, this.height = 230});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppTokens.screenPadding),
      child: DsSkeletonBox(height: height, radius: AppTokens.radiusHero),
    );
  }
}

/// Placeholder matching a row of cards.
class DsCardRowSkeleton extends StatelessWidget {
  const DsCardRowSkeleton({super.key, this.height = 96, this.count = 2});

  final double height;
  final int count;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < count; i++) {
      if (i > 0) children.add(const SizedBox(width: AppTokens.space12));
      children.add(
        Expanded(
          child: DsSkeletonBox(height: height, radius: AppTokens.radiusCard),
        ),
      );
    }
    return Row(children: children);
  }
}

// ══════════════════════════════════════════════════════════════════════
// ERROR STATE
// ══════════════════════════════════════════════════════════════════════

class DsErrorState extends StatelessWidget {
  const DsErrorState({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return DsEmptyState(
      art: DsEmptyArt.offline,
      accent: AppColors.expense,
      title: title,
      message: message,
      actionLabel: onRetry == null ? null : retryLabel,
      onAction: onRetry,
    );
  }
}

/// Inline banner for a non-blocking failure — a section that could not refresh
/// while the rest of the screen is fine.
class DsInlineError extends StatelessWidget {
  const DsInlineError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DsCard(
      emphasis: DsCardEmphasis.outlined,
      borderColor: AppColors.expense.withValues(alpha: 0.35),
      color: t.dangerBg,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space16,
        vertical: AppTokens.space12,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 19,
            color: AppColors.expense,
          ),
          const SizedBox(width: AppTokens.space12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: t.isDark ? t.textPrimary : AppColors.expense,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.expense,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
