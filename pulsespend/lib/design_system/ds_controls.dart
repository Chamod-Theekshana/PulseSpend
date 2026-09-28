import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';
import 'ds_foundations.dart';

/// Interactive controls: toggles, buttons, chips, action rows.

// ══════════════════════════════════════════════════════════════════════
// SEGMENTED PILL TOGGLE  —  "Manage / Invest"
// ══════════════════════════════════════════════════════════════════════

/// A pill track with a sliding filled thumb. The thumb animates between
/// segments rather than snapping, which is what makes it read as a physical
/// control instead of two buttons.
class DsSegmentedToggle extends StatelessWidget {
  const DsSegmentedToggle({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.activeColor,
    this.height = 44,
    this.expand = false,
  });

  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Color? activeColor;
  final double height;

  /// When false the control hugs its content (as in the reference header);
  /// when true it fills the available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final active = activeColor ?? AppColors.primary;
    final theme = Theme.of(context);

    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.isDark ? t.surfaceAlt : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: t.border),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final n = segments.length;
          final hasBoundedWidth = c.maxWidth.isFinite;
          final segWidth = hasBoundedWidth && (expand || n > 0)
              ? c.maxWidth / n
              : null;

          final children = <Widget>[];
          for (var i = 0; i < n; i++) {
            final isActive = i == selectedIndex;
            final tile = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                // Fires even when the segment is already active. Several call
                // sites replaced hand-rolled buttons whose handler ran on every
                // tap and had side effects beyond selection (clearing a
                // dependent field, refetching a period) — swallowing the repeat
                // tap here would silently drop that behaviour.
                onChanged(i);
              },
              child: AnimatedContainer(
                duration: AppTokens.motionBase,
                curve: AppTokens.motionCurve,
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: segWidth == null ? 22 : 0),
                decoration: BoxDecoration(
                  color: isActive ? active : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: AnimatedDefaultTextStyle(
                  duration: AppTokens.motionBase,
                  style: theme.textTheme.titleSmall!.copyWith(
                    color: isActive ? Colors.white : t.textSecondary,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  ),
                  child: Text(segments[i], maxLines: 1),
                ),
              ),
            );

            children.add(
              segWidth == null ? tile : SizedBox(width: segWidth, child: tile),
            );
          }

          return Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: children,
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// PRIMARY CTA
// ══════════════════════════════════════════════════════════════════════

/// Full-width call to action. Press scales it down a hair — the same 150ms
/// feedback the nav FAB uses, so taps feel consistent app-wide.
class DsPrimaryButton extends StatefulWidget {
  const DsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = DsButtonVariant.primary,
    this.expand = true,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final DsButtonVariant variant;
  final bool expand;
  final double height;

  @override
  State<DsPrimaryButton> createState() => _DsPrimaryButtonState();
}

enum DsButtonVariant {
  /// Solid brand blue. The one action a screen most wants you to take.
  primary,

  /// Deep navy — for premium / paywall contexts where blue would read as
  /// "just another button".
  navy,

  /// Quiet outline for secondary actions sitting beside a primary.
  ghost,

  /// Destructive.
  danger,
}

class _DsPrimaryButtonState extends State<DsPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final disabled = widget.onPressed == null || widget.isLoading;

    late final Color bg;
    late final Color fg;
    Border? border;

    switch (widget.variant) {
      case DsButtonVariant.primary:
        bg = AppColors.primary;
        fg = Colors.white;
        break;
      case DsButtonVariant.navy:
        bg = AppColors.heroNavy;
        fg = Colors.white;
        break;
      case DsButtonVariant.ghost:
        bg = Colors.transparent;
        fg = t.textPrimary;
        border = Border.all(color: t.border, width: 1.2);
        break;
      case DsButtonVariant.danger:
        bg = AppColors.expense;
        fg = Colors.white;
        break;
    }

    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: disabled
          ? null
          : (_) {
              setState(() => _pressed = false);
              HapticFeedback.lightImpact();
              widget.onPressed!();
            },
      onTapCancel: disabled ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1,
        duration: AppTokens.motionFast,
        curve: AppTokens.motionCurve,
        child: AnimatedOpacity(
          opacity: disabled && !widget.isLoading ? 0.5 : 1,
          duration: AppTokens.motionFast,
          child: Container(
            height: widget.height,
            width: widget.expand ? double.infinity : null,
            padding: widget.expand
                ? null
                : const EdgeInsets.symmetric(horizontal: 26),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              border: border,
              borderRadius: BorderRadius.circular(AppTokens.radiusButton),
              boxShadow: disabled || widget.variant == DsButtonVariant.ghost
                  ? null
                  : [
                      BoxShadow(
                        color: bg.withValues(alpha: 0.32),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: widget.isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(fg),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 19, color: fg),
                        const SizedBox(width: 9),
                      ],
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(color: fg),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// FILTER / DROPDOWN CHIP
// ══════════════════════════════════════════════════════════════════════

/// The small "Total ▾" / "26/09/21 ▾" chip. Two tones: [onHero] for placement
/// on the gradient card, default for placement on a normal surface.
class DsFilterChip extends StatelessWidget {
  const DsFilterChip({
    super.key,
    required this.label,
    this.onTap,
    this.leadingIcon,
    this.showChevron = true,
    this.onHero = false,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? leadingIcon;
  final bool showChevron;
  final bool onHero;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final Color bg;
    final Color fg;
    final Color? line;

    if (onHero) {
      bg = Colors.white.withValues(alpha: 0.18);
      fg = Colors.white;
      line = Colors.white.withValues(alpha: 0.22);
    } else if (selected) {
      bg = AppColors.primary;
      fg = Colors.white;
      line = null;
    } else {
      bg = t.surfaceAlt;
      fg = t.textPrimary;
      line = t.border;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppTokens.radiusChip),
            border: line == null ? null : Border.all(color: line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
              if (showChevron) ...[
                const SizedBox(width: 3),
                Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// QUICK ACTION ROW
// ══════════════════════════════════════════════════════════════════════

class DsQuickAction {
  const DsQuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// Equal-width rounded-square icon buttons with a caption underneath. Each chip
/// takes a different accent so the row scans as three distinct destinations
/// rather than one repeated shape.
class DsQuickActionRow extends StatelessWidget {
  const DsQuickActionRow({super.key, required this.actions, this.spacing = 12});

  final List<DsQuickAction> actions;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) children.add(SizedBox(width: spacing));
      children.add(Expanded(child: _DsQuickActionTile(action: actions[i])));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _DsQuickActionTile extends StatelessWidget {
  const _DsQuickActionTile({required this.action});

  final DsQuickAction action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          action.onTap();
        },
        borderRadius: BorderRadius.circular(AppTokens.radiusCardSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              DsIconChip(
                icon: action.icon,
                color: action.color,
                size: 52,
                iconSize: 24,
              ),
              const SizedBox(height: 8),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: t.textSecondary,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
