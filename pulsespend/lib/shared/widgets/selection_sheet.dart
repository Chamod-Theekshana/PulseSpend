import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// One selectable row in a [showSelectionSheet].
class SelectionOption<T> {
  final T value;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;

  const SelectionOption({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
  });
}

/// A themed modal bottom sheet that presents a list of options with the current
/// selection ticked. Returns the chosen value, or null if dismissed.
///
/// Used across Settings for Theme / Currency / Date Format / Language pickers so
/// they all share one consistent, accessible presentation.
Future<T?> showSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required List<SelectionOption<T>> options,
  required T? selected,
  String? subtitle,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
      final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, subtitleGap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final opt = options[i];
                    final isSelected = opt.value == selected;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Material(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.of(ctx).pop(opt.value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                if (opt.leading != null) ...[
                                  opt.leading!,
                                  const SizedBox(width: 14),
                                ] else if (opt.icon != null) ...[
                                  Icon(opt.icon,
                                      size: 22,
                                      color: isSelected ? AppColors.primary : textSecondary),
                                  const SizedBox(width: 14),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        opt.title,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight:
                                              isSelected ? FontWeight.w700 : FontWeight.w500,
                                          color: isSelected ? AppColors.primary : textPrimary,
                                        ),
                                      ),
                                      if (opt.subtitle != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          opt.subtitle!,
                                          style: TextStyle(fontSize: 12, color: textSecondary),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded,
                                      color: AppColors.primary, size: 22),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

const double subtitleGap = 12;
