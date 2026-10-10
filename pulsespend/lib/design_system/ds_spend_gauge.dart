import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';

/// Semicircular spend gauge — thick rounded stroke, centre icon, big amount,
/// caption, and 0%/100% end labels.
///
/// Hand-painted rather than pulled from a package because the reference's arc
/// has a specific weight and cap treatment, and because the sweep needs to
/// animate from zero on first build without a controller in every caller.
class DsSpendGauge extends StatelessWidget {
  const DsSpendGauge({
    super.key,
    required this.fraction,
    required this.amountText,
    required this.caption,
    this.icon = Icons.credit_card_rounded,
    this.color,
    this.size = 190,
    this.showEndLabels = true,
    this.startLabel = '0%',
    this.endLabel = '100%',
  });

  /// 0.0 – 1.0+. Above 1 the arc fills completely and turns [AppColors.expense].
  final double fraction;
  final String amountText;
  final String caption;
  final IconData icon;
  final Color? color;
  final double size;
  final bool showEndLabels;
  final String startLabel;
  final String endLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final arcColor = color ?? t.progressColor(fraction);
    final clamped = fraction.clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      // A semicircle plus room for the end labels beneath it.
      height: size * 0.62 + (showEndLabels ? 18 : 0),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: clamped),
              duration: AppTokens.motionSlow,
              curve: AppTokens.motionCurve,
              builder: (context, v, _) => CustomPaint(
                painter: _GaugePainter(
                  fraction: v,
                  color: arcColor,
                  track: t.surfaceAlt,
                  strokeWidth: size * 0.055,
                ),
              ),
            ),
          ),
          Positioned(
            top: size * 0.16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary
                        .withValues(alpha: t.isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(AppTokens.radiusBadge),
                  ),
                  child: Icon(icon, size: 19, color: AppColors.primary),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    amountText,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: t.textSecondary),
                ),
              ],
            ),
          ),
          if (showEndLabels) ...[
            Positioned(
              left: 0,
              bottom: 0,
              child: Text(
                startLabel,
                style: TextStyle(fontSize: 11, color: t.textTertiary),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Text(
                endLabel,
                style: TextStyle(fontSize: 11, color: t.textTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, radius + strokeWidth / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Half turn, drawn left → right across the top.
    const start = math.pi;
    const sweep = math.pi;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = track;

    canvas.drawArc(rect, start, sweep, false, trackPaint);

    if (fraction <= 0) return;

    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawArc(rect, start, sweep * fraction, false, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.strokeWidth != strokeWidth;
}

// ══════════════════════════════════════════════════════════════════════
// RING GAUGE  —  full circle variant, for goals and category donuts
// ══════════════════════════════════════════════════════════════════════

class DsRingGauge extends StatelessWidget {
  const DsRingGauge({
    super.key,
    required this.fraction,
    required this.size,
    this.color,
    this.strokeWidth,
    this.child,
  });

  final double fraction;
  final double size;
  final Color? color;
  final double? strokeWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final arcColor = color ?? t.progressColor(fraction);

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
        duration: AppTokens.motionSlow,
        curve: AppTokens.motionCurve,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(
            fraction: v,
            color: arcColor,
            track: t.surfaceAlt,
            strokeWidth: strokeWidth ?? size * 0.09,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = track,
    );

    if (fraction <= 0) return;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.strokeWidth != strokeWidth;
}
