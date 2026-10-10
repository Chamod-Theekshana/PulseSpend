import 'package:flutter/material.dart';
import '../../design_system/ds.dart';

/// The app's primary call-to-action.
///
/// API unchanged from before the redesign — every existing call site keeps
/// working. Internally this now delegates to [DsPrimaryButton] so the CTA on a
/// signup screen is pixel-identical to the CTA on a paywall.
///
/// Passing [backgroundColor] still overrides the fill; the destructive red the
/// app already uses maps onto the danger variant automatically.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color? backgroundColor;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final variant = switch (backgroundColor) {
      null => DsButtonVariant.primary,
      AppColors.expense => DsButtonVariant.danger,
      AppColors.heroNavy => DsButtonVariant.navy,
      _ => DsButtonVariant.primary,
    };

    // A colour the design system has no variant for still has to be honoured —
    // callers pass one to mean something (a category tint, a wallet colour).
    final needsCustomFill = backgroundColor != null &&
        backgroundColor != AppColors.expense &&
        backgroundColor != AppColors.heroNavy;

    if (needsCustomFill) {
      return _CustomFillButton(
        label: label,
        onPressed: onPressed,
        isLoading: isLoading,
        icon: icon,
        color: backgroundColor!,
      );
    }

    return DsPrimaryButton(
      label: label,
      onPressed: onPressed,
      isLoading: isLoading,
      icon: icon,
      variant: variant,
    );
  }
}

/// Same geometry and press behaviour as [DsPrimaryButton], with an arbitrary
/// fill. Kept private so the design system stays the only public source of
/// button shapes.
class _CustomFillButton extends StatelessWidget {
  const _CustomFillButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    required this.icon,
    required this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = isLoading || onPressed == null;

    return AnimatedOpacity(
      duration: AppTokens.motionFast,
      opacity: disabled ? 0.55 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppTokens.radiusButton),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: color.withValues(alpha: 0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusButton),
            onTap: disabled ? null : onPressed,
            child: SizedBox(
              height: 54,
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 19, color: Colors.white),
                            const SizedBox(width: 9),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
