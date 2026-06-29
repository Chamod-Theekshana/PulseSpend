import 'package:flutter/material.dart';

/// PulseSpend palette. Built around a deep "ink" neutral scale plus a single
/// confident accent (electric indigo) rather than a generic Material teal —
/// finance apps live or die on whether numbers feel trustworthy and legible.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF5B5FEF); // electric indigo
  static const Color primaryDark = Color(0xFF4347C4);
  static const Color primaryLight = Color(0xFFE8E9FD);

  // Semantic — money
  static const Color income = Color(0xFF1FAE6F); // confident green
  static const Color incomeBg = Color(0xFFE5F8EE);
  static const Color expense = Color(0xFFE25C5C); // muted coral-red, not alarmist
  static const Color expenseBg = Color(0xFFFCEAEA);
  static const Color warning = Color(0xFFE2A33D);
  static const Color warningBg = Color(0xFFFBF1E0);

  // Neutrals — light theme
  static const Color lightBg = Color(0xFFF7F7FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF0F0F7);
  static const Color lightBorder = Color(0xFFE7E7F0);
  static const Color lightTextPrimary = Color(0xFF14142B);
  static const Color lightTextSecondary = Color(0xFF6E7191);
  static const Color lightTextTertiary = Color(0xFFA0A3BD);

  // Neutrals — dark theme
  static const Color darkBg = Color(0xFF0F0F1A);
  static const Color darkSurface = Color(0xFF181826);
  static const Color darkSurfaceAlt = Color(0xFF1F1F33);
  static const Color darkBorder = Color(0xFF2B2B45);
  static const Color darkTextPrimary = Color(0xFFF4F4FB);
  static const Color darkTextSecondary = Color(0xFFA0A3BD);
  static const Color darkTextTertiary = Color(0xFF6E7191);

  // Category color wheel — assigned round-robin to keep charts legible
  static const List<Color> categoryPalette = [
    Color(0xFF5B5FEF),
    Color(0xFFE25C5C),
    Color(0xFFE2A33D),
    Color(0xFF1FAE6F),
    Color(0xFF3DAEE2),
    Color(0xFFB15CE2),
    Color(0xFFE25C9E),
    Color(0xFF5CE2C4),
    Color(0xFFE2D45C),
    Color(0xFF8A8FF0),
  ];

  static Color categoryColor(String category) {
    final hash = category.toLowerCase().codeUnits.fold<int>(0, (a, b) => a + b);
    return categoryPalette[hash % categoryPalette.length];
  }
}
