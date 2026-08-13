import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';
import 'ds_controls.dart';
import 'ds_foundations.dart';

/// Card-shaped feature surfaces: payment cards, promo banners, plan selectors.

// ══════════════════════════════════════════════════════════════════════
// BANK / PAYMENT CARD
// ══════════════════════════════════════════════════════════════════════

/// A realistic payment-card component. Sized to a real card's 1.586 aspect so
/// it reads as an object rather than a rectangle with text on it.
class DsBankCard extends StatelessWidget {
  const DsBankCard({
    super.key,
    required this.balanceLabel,
    required this.balance,
    this.holderName,
    this.maskedNumber,
    this.brandLabel,
    this.brandLogo,
    this.gradient,
    this.width,
    this.onTap,
    this.height = 190,
  });

  final String balanceLabel;
  final String balance;
  final String? holderName;

  /// Already masked by the caller — this widget never truncates a PAN itself.
  final String? maskedNumber;

  final String? brandLabel;
  final Widget? brandLogo;
  final Gradient? gradient;
  final double? width;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: gradient ?? t.heroGradient,
          borderRadius: BorderRadius.circular(AppTokens.radiusHero),
          boxShadow: t.heroShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusHero),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _CardTexturePainter())),
              Padding(
                padding: const EdgeInsets.all(AppTokens.space20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (brandLogo != null) brandLogo!,
                        const Spacer(),
                        if (brandLabel != null)
                          Text(
                            brandLabel!.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      balanceLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        balance,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (holderName != null)
                          Expanded(
                            child: Text(
                              holderName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (maskedNumber != null)
                          Text(
                            maskedNumber!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.07);

    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
        Offset(size.width * 1.02, size.height * 0.42),
        size.height * (0.35 + i * 0.24),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A stack of payment cards where the next card peeks out behind the active
/// one — the reference's multi-account treatment.
class DsBankCardStack extends StatelessWidget {
  const DsBankCardStack({
    super.key,
    required this.front,
    this.behindCount = 0,
    this.height = 190,
  });

  final Widget front;

  /// How many "there are more accounts" slivers to show behind the front card.
  final int behindCount;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (behindCount <= 0) return front;

    final layers = <Widget>[];
    final n = behindCount.clamp(0, 2);
    for (var i = n; i >= 1; i--) {
      layers.add(
        Positioned(
          top: 0,
          left: i * 14.0,
          right: -i * 14.0,
          child: Opacity(
            opacity: 0.34 - (i - 1) * 0.12,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                gradient: t.heroGradient,
                borderRadius: BorderRadius.circular(AppTokens.radiusHero),
              ),
            ),
          ),
        ),
      );
    }
    layers.add(front);

    return SizedBox(
      height: height,
      child: Stack(clipBehavior: Clip.none, children: layers),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// PROMO / REFERRAL BANNER
// ══════════════════════════════════════════════════════════════════════

class DsPromoBanner extends StatelessWidget {
  const DsPromoBanner({
    super.key,
    required this.headline,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.card_giftcard_rounded,
    this.gradient,
    this.onDismiss,
  });

  final String headline;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;
  final Gradient? gradient;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return GestureDetector(
      onTap: onAction,
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient ?? t.primaryGradient,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          boxShadow: t.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          child: Stack(
            children: [
              // The illustration slot: a soft glyph cluster bleeding off the
              // right edge, so the banner has a focal point without an asset.
              Positioned(
                right: -14,
                top: -10,
                bottom: -10,
                child: Opacity(
                  opacity: 0.24,
                  child: Icon(icon, size: 118, color: Colors.white),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 110, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      headline,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (actionLabel != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            actionLabel!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onDismiss != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    onPressed: onDismiss,
                    iconSize: 17,
                    color: Colors.white.withValues(alpha: 0.85),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// PLAN / SUBSCRIPTION SELECTOR
// ══════════════════════════════════════════════════════════════════════

class DsPlanCard extends StatelessWidget {
  const DsPlanCard({
    super.key,
    required this.duration,
    required this.price,
    required this.perMonth,
    required this.selected,
    required this.onTap,
    this.accent,
    this.badgeLabel,
    this.icon = Icons.star_rounded,
    this.width = 132,
  });

  final String duration;
  final String price;
  final String perMonth;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;
  final String? badgeLabel;
  final IconData icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final color = accent ?? AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTokens.motionBase,
        curve: AppTokens.motionCurve,
        width: width,
        padding: const EdgeInsets.all(AppTokens.space16),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: t.isDark ? 0.16 : 0.08)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(
            color: selected ? color : t.border,
            width: selected ? 1.8 : 1,
          ),
          boxShadow: selected ? t.cardShadow : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                DsIconChip(icon: icon, color: color, size: 30, iconSize: 16),
                const Spacer(),
                if (badgeLabel != null)
                  DsBadge(label: badgeLabel!, color: color, dense: true),
              ],
            ),
            const SizedBox(height: AppTokens.space12),
            Text(
              duration,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: t.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                price,
                style: theme.textTheme.titleLarge?.copyWith(color: color),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              perMonth,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: t.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The feature checklist that sits above a plan row on a paywall.
class DsFeatureChecklist extends StatelessWidget {
  const DsFeatureChecklist({
    super.key,
    required this.features,
    this.columns = 2,
    this.color,
  });

  final List<String> features;
  final int columns;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tick = color ?? t.success;

    final rows = <Widget>[];
    for (var i = 0; i < features.length; i += columns) {
      final slice = features.skip(i).take(columns).toList();
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        cells.add(
          Expanded(
            child: j < slice.length
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 15, color: tick),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          slice[j],
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: t.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        );
        if (j < columns - 1) cells.add(const SizedBox(width: AppTokens.space12));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: AppTokens.space12));
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

/// Convenience wrapper: checklist + horizontally scrolling plans + CTA.
class DsPlanSelector extends StatelessWidget {
  const DsPlanSelector({
    super.key,
    required this.plans,
    required this.ctaLabel,
    required this.onSubscribe,
    this.features = const [],
    this.isLoading = false,
  });

  final List<Widget> plans;
  final String ctaLabel;
  final VoidCallback? onSubscribe;
  final List<String> features;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (features.isNotEmpty) {
      children.add(DsFeatureChecklist(features: features));
      children.add(const SizedBox(height: AppTokens.space24));
    }

    children.add(
      SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: plans.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppTokens.space12),
          itemBuilder: (_, i) => plans[i],
        ),
      ),
    );
    children.add(const SizedBox(height: AppTokens.space20));
    children.add(
      DsPrimaryButton(
        label: ctaLabel,
        onPressed: onSubscribe,
        isLoading: isLoading,
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
