import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Design tokens that Material's [ThemeData] has no native slot for.
///
/// Read them anywhere with `context.tokens` (see the extension at the bottom of
/// this file) so that no widget ever hardcodes a hex value, a corner radius or
/// a magic padding number. If a value is needed in two places, it belongs here.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.heroGradient,
    required this.primaryGradient,
    required this.success,
    required this.danger,
    required this.warningAccent,
    required this.neutralShift,
    required this.successBg,
    required this.dangerBg,
    required this.warningBg,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.cardShadow,
    required this.heroShadow,
  });

  final Brightness brightness;

  /// Balance / portfolio hero card. Blue → deep navy, 135°.
  final Gradient heroGradient;

  /// Primary CTA fill. Kept subtler than the hero so a button never competes
  /// with the balance card sitting above it.
  final Gradient primaryGradient;

  final Color success;
  final Color danger;
  final Color warningAccent;

  /// Neither income nor expense — net movement, transfers, "shift" figures.
  final Color neutralShift;

  final Color successBg;
  final Color dangerBg;
  final Color warningBg;

  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Light theme leans on a soft, large-blur, low-opacity shadow. Dark theme
  /// returns an empty list — surfaces separate by tone and a hairline border
  /// instead, because shadows are invisible on a near-black ground and only
  /// cost fill rate.
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> heroShadow;

  bool get isDark => brightness == Brightness.dark;

  // ── Spacing — 8pt grid ────────────────────────────────────────────
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;

  /// Every screen's horizontal gutter. One number, no exceptions.
  static const double screenPadding = 20;

  // ── Radius scale ──────────────────────────────────────────────────
  static const double radiusHero = 24;
  static const double radiusCard = 20;
  static const double radiusCardSm = 16;
  static const double radiusButton = 16;
  static const double radiusChip = 12;
  static const double radiusBadge = 10;
  static const double radiusPill = 999;

  // ── Motion ────────────────────────────────────────────────────────
  static const Duration motionFast = Duration(milliseconds: 150);
  static const Duration motionBase = Duration(milliseconds: 200);
  static const Duration motionSlow = Duration(milliseconds: 250);
  static const Curve motionCurve = Curves.easeOutCubic;

  // ── Component sizing ──────────────────────────────────────────────
  static const double iconChipSize = 44;
  static const double iconSize = 22;
  static const double progressBarHeight = 6;

  /// Progress colour ramp: green while comfortable, orange as the limit
  /// approaches, red once it is breached. Used by budget bars and goal rings so
  /// the two never disagree about what "70% spent" looks like.
  Color progressColor(double fraction) {
    if (fraction >= 1.0) return danger;
    if (fraction >= 0.75) return warningAccent;
    return success;
  }

  /// Amount colour by sign — the single source of truth for "is this money
  /// coming in or going out".
  Color amountColor(num amount) => amount < 0 ? danger : success;

  static const AppTokens light = AppTokens(
    brightness: Brightness.light,
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.heroBlue, AppColors.heroNavy],
    ),
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primary, AppColors.primaryDark],
    ),
    success: AppColors.income,
    danger: AppColors.expense,
    warningAccent: AppColors.warning,
    neutralShift: AppColors.accentCyan,
    successBg: AppColors.incomeBg,
    dangerBg: AppColors.expenseBg,
    warningBg: AppColors.warningBg,
    surfaceAlt: AppColors.lightSurfaceAlt,
    border: AppColors.lightBorder,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textTertiary: AppColors.lightTextTertiary,
    cardShadow: [
      BoxShadow(
        color: Color(0x141E2978), // rgba(30,41,120,0.08)
        blurRadius: 30,
        offset: Offset(0, 12),
      ),
    ],
    heroShadow: [
      BoxShadow(
        color: Color(0x333D6FFF),
        blurRadius: 32,
        offset: Offset(0, 16),
      ),
    ],
  );

  static const AppTokens dark = AppTokens(
    brightness: Brightness.dark,
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.heroBlue, AppColors.heroNavy],
    ),
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primary, AppColors.primaryDark],
    ),
    success: AppColors.income,
    danger: AppColors.expense,
    warningAccent: AppColors.warning,
    neutralShift: AppColors.accentCyan,
    successBg: Color(0x2914C99B),
    dangerBg: Color(0x29F0454F),
    warningBg: Color(0x29FF9C42),
    surfaceAlt: AppColors.darkSurfaceAlt,
    border: AppColors.darkBorder,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textTertiary: AppColors.darkTextTertiary,
    cardShadow: [],
    heroShadow: [
      BoxShadow(
        color: Color(0x3D000000),
        blurRadius: 24,
        offset: Offset(0, 12),
      ),
    ],
  );

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Gradient? heroGradient,
    Gradient? primaryGradient,
    Color? success,
    Color? danger,
    Color? warningAccent,
    Color? neutralShift,
    Color? successBg,
    Color? dangerBg,
    Color? warningBg,
    Color? surfaceAlt,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? heroShadow,
  }) {
    return AppTokens(
      brightness: brightness ?? this.brightness,
      heroGradient: heroGradient ?? this.heroGradient,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warningAccent: warningAccent ?? this.warningAccent,
      neutralShift: neutralShift ?? this.neutralShift,
      successBg: successBg ?? this.successBg,
      dangerBg: dangerBg ?? this.dangerBg,
      warningBg: warningBg ?? this.warningBg,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      cardShadow: cardShadow ?? this.cardShadow,
      heroShadow: heroShadow ?? this.heroShadow,
    );
  }

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      heroGradient: Gradient.lerp(heroGradient, other.heroGradient, t) ?? heroGradient,
      primaryGradient:
          Gradient.lerp(primaryGradient, other.primaryGradient, t) ?? primaryGradient,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warningAccent: Color.lerp(warningAccent, other.warningAccent, t)!,
      neutralShift: Color.lerp(neutralShift, other.neutralShift, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t) ?? cardShadow,
      heroShadow: BoxShadow.lerpList(heroShadow, other.heroShadow, t) ?? heroShadow,
    );
  }
}

/// `context.tokens` — the only way a widget should reach a design value.
extension AppTokensContext on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ??
      (Theme.of(this).brightness == Brightness.dark ? AppTokens.dark : AppTokens.light);

  /// Convenience: most widgets branch on this at least once.
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
