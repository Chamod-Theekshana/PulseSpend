import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The PulseSpend logo in a rounded, softly-glowing card. Used at the top of
/// the auth screens for a consistent, premium entry experience.
class AuthLogo extends StatelessWidget {
  final double size;
  const AuthLogo({super.key, this.size = 88});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: isDark ? 0.30 : 0.22),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Image.asset('assets/pulsespend_logo.png', fit: BoxFit.contain),
    );
  }
}
