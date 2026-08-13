import 'package:flutter/material.dart';

/// PulseSpend palette — rebuilt against the fintech-dashboard reference design.
///
/// The scale is a soft lavender-white ground with a single confident blue
/// accent, and three semantic money colours (green / red / orange) that carry
/// meaning rather than decoration: a user should be able to scan a screen and
/// tell income from expense from neutral without reading a single number.
///
/// Every name in this class predates the redesign and is referenced across the
/// feature screens — the *values* moved, the API did not. Nothing that consumed
/// `AppColors.primary` before needs to change.
class AppColors {
  AppColors._();

  // ── Aliases used across feature screens ───────────────────────────
  static const Color primaryAccent = primary; // chat bubbles, send buttons
  static const Color background = lightBg; // scaffold background
  static const Color surfaceDark = darkSurface; // dark-mode card backgrounds

  // ── Brand ─────────────────────────────────────────────────────────
  /// Buttons, active states, links, selected nav items.
  static const Color primary = Color(0xFF3D6FFF);

  /// The deeper end of the brand ramp — button gradients, pressed states.
  static const Color primaryDark = Color(0xFF2B55D6);

  /// Pastel chip/badge ground for primary-tinted surfaces.
  static const Color primaryLight = Color(0xFFE4ECFF);

  /// Cyan used by the reference for the active segment of pill toggles and
  /// for "shift"/neutral-movement figures that are neither income nor expense.
  static const Color accentCyan = Color(0xFF21C7E8);

  /// Deep navy that terminates the hero gradient.
  static const Color heroNavy = Color(0xFF16215C);

  /// Bright end of the hero gradient.
  static const Color heroBlue = Color(0xFF4C7EFF);

  // ── Semantic — money ──────────────────────────────────────────────
  /// Positive amounts, income, on-track budget progress.
  static const Color income = Color(0xFF14C99B);
  static const Color incomeBg = Color(0xFFE3F9F3);

  /// Negative amounts, expenses, over-budget progress.
  static const Color expense = Color(0xFFF0454F);
  static const Color expenseBg = Color(0xFFFDEAEB);

  /// Mid-budget warning, shopping category, "approaching limit" states.
  static const Color warning = Color(0xFFFF9C42);
  static const Color warningBg = Color(0xFFFFF1E4);

  // ── Neutrals — light theme ────────────────────────────────────────
  static const Color lightBg = Color(0xFFF3F1FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF7F6FB);
  static const Color lightBorder = Color(0xFFEDEBF6);
  static const Color lightTextPrimary = Color(0xFF14141A);
  static const Color lightTextSecondary = Color(0xFF7A7A85);
  static const Color lightTextTertiary = Color(0xFFA8A8B3);

  // ── Neutrals — dark theme ─────────────────────────────────────────
  static const Color darkBg = Color(0xFF0E0E12);
  static const Color darkSurface = Color(0xFF1B1B20);
  static const Color darkSurfaceAlt = Color(0xFF232329);
  static const Color darkBorder = Color(0xFF2A2A30);
  static const Color darkTextPrimary = Color(0xFFF5F5F7);
  static const Color darkTextSecondary = Color(0xFF9797A1);
  static const Color darkTextTertiary = Color(0xFF6E6E78);

  // ── Category wheel ────────────────────────────────────────────────
  /// Assigned round-robin by name hash. Tuned so adjacent slices in a pie or
  /// donut chart stay distinguishable, and so every entry survives being
  /// dropped to a 14% tint behind an icon without turning to mud.
  static const List<Color> categoryPalette = [
    Color(0xFF3D6FFF), // brand blue
    Color(0xFFF0454F), // red
    Color(0xFFFF9C42), // orange
    Color(0xFF14C99B), // green
    Color(0xFF21C7E8), // cyan
    Color(0xFF9B6BFF), // violet
    Color(0xFFFF6BAA), // pink
    Color(0xFF00B4A6), // teal
    Color(0xFFE8B93D), // amber
    Color(0xFF6E8BFF), // periwinkle
  ];

  static Color categoryColor(String category) {
    final hash = category.toLowerCase().codeUnits.fold<int>(0, (a, b) => a + b);
    return categoryPalette[hash % categoryPalette.length];
  }

  /// The pastel ground a category icon sits on. Dark mode needs more tint to
  /// stay visible against a near-black surface.
  static Color categoryChipBg(String category, {required bool isDark}) =>
      categoryColor(category).withValues(alpha: isDark ? 0.22 : 0.13);
}
