import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/secure_storage.dart';
import '../core/utils/date_formatter.dart';
import 'profile_provider.dart';

/// Seeded in `main()` from secure storage so the first frame after a cold start
/// already uses the saved format instead of flashing `DD/MM/YYYY` until the
/// network profile lands. Same trick as [bootstrapThemeModeProvider].
final bootstrapDateFormatProvider =
    Provider<String>((ref) => DateFormatter.defaultPattern);

/// The active `date_format` token (`DD/MM/YYYY` | `MM/DD/YYYY` | `YYYY-MM-DD`).
///
/// This is the piece that was missing: the Settings picker always saved the
/// preference correctly, but nothing ever read it back, so
/// `DateFormatter.display()` fell through to its `DD/MM/YYYY` default on every
/// screen. Widgets now `ref.watch(dateFormatProvider)`, which both rebuilds
/// them when the preference changes and keeps [DateFormatter.globalPattern] in
/// sync for the handful of call sites that can't reach a `ref`.
final dateFormatProvider = Provider<String>((ref) {
  final fromProfile =
      ref.watch(profileControllerProvider.select((s) => s.user?.dateFormat));

  final resolved =
      DateFormatter.supportedPatterns.contains(fromProfile)
          ? fromProfile!
          : ref.watch(bootstrapDateFormatProvider);

  // Keep the static mirror and the local cache aligned. Writing the cache here
  // (rather than in the settings screen) means it also picks up a change made
  // on another device and pushed down over `profile:updated`.
  if (DateFormatter.globalPattern != resolved) {
    DateFormatter.globalPattern = resolved;
    SecureStorageService.instance.setDateFormatPref(resolved);
  }

  return resolved;
});

/// Convenience wrappers so screens read as `ref.formatDate(tx.createdAt)`
/// instead of threading the pattern through by hand.
extension DateFormatX on WidgetRef {
  String formatDate(DateTime date) =>
      DateFormatter.display(date, pattern: watch(dateFormatProvider));

  String formatLongDate(DateTime date) =>
      DateFormatter.longDate(date, pattern: watch(dateFormatProvider));

  String formatDateTime(DateTime value) =>
      DateFormatter.dateTime(value, pattern: watch(dateFormatProvider));
}

/// Keeps [DateFormatter.use24Hour] aligned with the device's clock setting, so
/// times render as `21:05` where the user expects that rather than `9:05 PM`.
/// Call once from a widget that has a `MediaQuery` ancestor.
void syncClockConvention(BuildContext context) {
  DateFormatter.use24Hour = MediaQuery.of(context).alwaysUse24HourFormat;
}
