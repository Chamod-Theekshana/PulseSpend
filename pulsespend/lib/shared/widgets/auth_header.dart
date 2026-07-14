import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Consistent header for the signup steps: a tinted icon badge, a bold title,
/// and a subtitle (passed as a widget so callers can use rich text).
class AuthHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget subtitle;

  const AuthHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: isDark ? 0.20 : 0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: AppColors.primary, size: 26),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                height: 1.4,
              ),
          child: subtitle,
        ),
      ],
    );
  }
}
