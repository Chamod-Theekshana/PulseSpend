import 'package:intl/intl.dart';

import 'app_time.dart';

/// Display formatting for dates and times.
///
/// Two rules this class exists to enforce:
///
/// * **The user's `date_format` preference is actually applied.** Previously
///   [display] took a `pattern` parameter that literally no caller ever passed,
///   so every screen rendered `dd/MM/yyyy` regardless of what Settings said.
///   The pattern now comes from [globalPattern], which
///   `dateFormatSyncProvider` keeps in sync with the profile, so a call site
///   that just writes `DateFormatter.display(x)` still gets the right answer.
///
/// * **Instants are rendered in the device's zone, calendar dates are not.**
///   See [AppTime] for why those two cases must stay separate. Anything here
///   that prints a clock time normalises through `toLocal()` first.
class DateFormatter {
  DateFormatter._();

  /// The three values `validators.ts` accepts for `date_format`.
  static const supportedPatterns = <String>[
    'DD/MM/YYYY',
    'MM/DD/YYYY',
    'YYYY-MM-DD',
  ];

  static const defaultPattern = 'DD/MM/YYYY';

  static String _globalPattern = defaultPattern;
  static bool _use24Hour = false;

  /// The pattern used by every `display`/`longDate` call that doesn't pass one.
  /// Set from the profile (and from the local cache at cold start) so the
  /// preference survives before the network profile arrives.
  static String get globalPattern => _globalPattern;

  static set globalPattern(String value) {
    _globalPattern =
        supportedPatterns.contains(value) ? value : defaultPattern;
  }

  /// Mirrors `MediaQuery.alwaysUse24HourFormat` so times follow the device
  /// convention instead of being hard-coded to AM/PM.
  static bool get use24Hour => _use24Hour;
  static set use24Hour(bool value) => _use24Hour = value;

  // ── API serialisation ───────────────────────────────────────────────────

  /// `yyyy-MM-dd` from the local calendar fields. Delegates to [AppTime.apiDate]
  /// so there is exactly one implementation.
  static String forApi(DateTime date) => AppTime.apiDate(date);

  // ── Dates ───────────────────────────────────────────────────────────────

  /// A calendar date in the user's chosen order. Pass [pattern] only to
  /// override the user preference for a specific screen.
  static String display(DateTime date, {String? pattern}) {
    return DateFormat(_skeleton(pattern ?? _globalPattern)).format(date);
  }

  /// A longer, month-name form that still respects the user's field order:
  /// `31 Dec 2026`, `Dec 31, 2026` or `2026 Dec 31`.
  static String longDate(DateTime date, {String? pattern}) {
    final p = pattern ?? _globalPattern;
    return switch (p) {
      'MM/DD/YYYY' => DateFormat('MMM d, yyyy').format(date),
      'YYYY-MM-DD' => DateFormat('yyyy MMM d').format(date),
      _ => DateFormat('d MMM yyyy').format(date),
    };
  }

  /// Same as [longDate] but without the year — for headers inside the current
  /// year, where repeating "2026" is noise.
  static String shortDate(DateTime date, {String? pattern}) {
    final p = pattern ?? _globalPattern;
    return switch (p) {
      'MM/DD/YYYY' => DateFormat('MMM d').format(date),
      'YYYY-MM-DD' => DateFormat('MM-dd').format(date),
      _ => DateFormat('d MMM').format(date),
    };
  }

  static String monthLabel(DateTime date) => DateFormat('MMMM yyyy').format(date);

  // ── Times ───────────────────────────────────────────────────────────────

  /// Clock time in the device's zone. Accepts a UTC instant straight from the
  /// API and converts it — the old `_formatTime` in the chat screen read
  /// `.hour` off a UTC value, which is what made every message stamp wrong.
  static String time(DateTime value) {
    final local = value.isUtc ? value.toLocal() : value;
    return DateFormat(_use24Hour ? 'HH:mm' : 'h:mm a').format(local);
  }

  /// Date + time together, e.g. `31/12/2026 · 9:05 PM`.
  static String dateTime(DateTime value, {String? pattern}) {
    final local = value.isUtc ? value.toLocal() : value;
    return '${display(local, pattern: pattern)} · ${time(local)}';
  }

  // ── Relative / grouped labels ───────────────────────────────────────────

  /// "Just now", "5m ago", "Yesterday", a weekday name, or an absolute date.
  ///
  /// The day comparisons are done on **local** calendar days. The previous
  /// implementation compared `DateTime.now().day` (local) against a UTC value's
  /// `.day`, so anything logged after 18:30 in Colombo was bucketed into the
  /// wrong day.
  static String relative(DateTime value) {
    final local = value.isUtc ? value.toLocal() : value;
    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.isNegative) return 'Just now'; // clock skew / optimistic write
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (AppTime.isSameDay(local, now)) return '${diff.inHours}h ago';
    if (AppTime.isYesterday(local)) return 'Yesterday';
    if (AppTime.daysBetween(local, now) < 7) {
      return DateFormat('EEEE').format(local);
    }
    return longDate(local);
  }

  /// Section header for a day-grouped list.
  static String dayHeader(DateTime value) {
    final local = value.isUtc ? value.toLocal() : value;
    if (AppTime.isToday(local)) return 'Today';
    if (AppTime.isYesterday(local)) return 'Yesterday';
    if (local.year == DateTime.now().year) {
      return DateFormat('EEEE, ').format(local) + shortDate(local);
    }
    return DateFormat('EEEE, ').format(local) + longDate(local);
  }

  /// Human label for a due date relative to today: "Overdue", "Due today",
  /// "In 3 days".
  static String dueLabel(DateTime dueDate) {
    final days = AppTime.daysBetween(DateTime.now(), dueDate);
    if (days < 0) return days == -1 ? 'Overdue by 1 day' : 'Overdue by ${-days} days';
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    return 'In $days days';
  }

  // ── internals ───────────────────────────────────────────────────────────

  /// Maps the stored preference token to an ICU skeleton.
  static String _skeleton(String pattern) => switch (pattern) {
        'MM/DD/YYYY' => 'MM/dd/yyyy',
        'YYYY-MM-DD' => 'yyyy-MM-dd',
        _ => 'dd/MM/yyyy',
      };
}
