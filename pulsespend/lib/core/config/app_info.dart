/// Static app metadata surfaced in the About screen and attached to feedback
/// reports. Keep [version]/[build] in sync with `pubspec.yaml`.
class AppInfo {
  AppInfo._();

  static const String name = 'PulseSpend';
  static const String version = '1.0.0';
  static const String build = '1';
  static const String tagline = 'Smart, simple money tracking.';
  static const String description =
      'PulseSpend helps you track spending, set budgets and savings goals, and '
      'stay on top of bills — all in one clean, fast app.';

  static const String supportEmail = 'support@pulsespend.app';
  static const String website = 'https://pulsespend.app';
}
