/// Central time layer for PulseSpend.
///
/// The backend stores two *different* kinds of temporal values, and the whole
/// timezone bug in this app came from treating them as one thing:
///
/// 1. **Instants** — Postgres `TIMESTAMP` columns: `notifications.created_at`,
///    `group_messages.created_at`, `debts.created_at`, `wallets.created_at`,
///    `goal_contributions.created_at`, `groups.created_at`.
///    These are real points on the timeline. Neon serialises them to UTC
///    ISO-8601 (`2026-08-10T04:20:00.000Z`). `DateTime.parse` therefore returns
///    a **UTC** `DateTime`, and `DateFormat(...).format(utcValue)` prints the
///    UTC wall clock. That is why a Colombo user sees a message sent at 09:50
///    labelled 04:20 — 5h30m out. Instants MUST go through [instant].
///
/// 2. **Calendar dates** — Postgres `DATE` columns: `transactions.created_at`,
///    `reminders.due_date`, `recurring_transactions.next_run`,
///    `goals.deadline`, `users.date_of_birth`.
///    These have no time and no zone. "31 Dec 2026" is the same day in Colombo
///    and in New York. Neon still serialises them as `...T00:00:00.000Z`, so
///    naively calling `.toLocal()` on them would roll the day *backwards* for
///    every user west of UTC (a UTC-05:00 user would see 30 Dec). Calendar
///    dates MUST go through [calendarDate], which keeps the Y/M/D untouched.
///
/// Getting this distinction wrong in either direction is a silent, data-shaped
/// bug, so every date that enters the app from JSON goes through this class.
library;

class AppTime {
  AppTime._();

  // ── Parsing from the API ────────────────────────────────────────────────

  /// Parses a server **instant** (a `TIMESTAMP` column) and returns it in the
  /// device's local zone, ready for display.
  ///
  /// Handles values that already carry an offset (`...Z`, `+05:30`) as well as
  /// naive strings. A naive string is assumed to be UTC, because that is what
  /// the backend emits — see `toUtcIso` in `backend/src/utils/time.ts`.
  static DateTime instant(Object? raw) => instantOrNull(raw) ?? DateTime.now();

  /// Nullable form of [instant] — returns null for null/blank/unparseable input
  /// instead of silently substituting "now".
  static DateTime? instantOrNull(Object? raw) {
    final parsed = _parse(raw);
    if (parsed == null) return null;
    // A string without an offset parses as local; re-tag it as UTC first so the
    // conversion below is meaningful rather than a no-op.
    final asUtc = parsed.isUtc ? parsed : _assumeUtc(parsed, raw);
    return asUtc.toLocal();
  }

  /// Parses a server **calendar date** (a `DATE` column) as a floating date.
  ///
  /// The returned value is a local `DateTime` at midnight whose Y/M/D match the
  /// digits the server sent, with **no** zone conversion applied.
  static DateTime calendarDate(Object? raw) =>
      calendarDateOrNull(raw) ?? today();

  /// Nullable form of [calendarDate].
  static DateTime? calendarDateOrNull(Object? raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;

    // Fast path: the server sends `2026-12-31` or `2026-12-31T00:00:00.000Z`.
    // Reading the digits directly is both cheaper and immune to zone shifts.
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    }

    // Fallback for any other shape: take the UTC calendar fields, because a
    // DATE round-trips through UTC midnight.
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    final u = parsed.isUtc ? parsed : parsed.toUtc();
    return DateTime(u.year, u.month, u.day);
  }

  // ── Serialising to the API ──────────────────────────────────────────────

  /// `yyyy-MM-dd` built from the **local** calendar fields.
  ///
  /// Never use `toIso8601String().split('T').first` for this: on a device at
  /// UTC+05:30 that yields yesterday's date for anything before 05:30 local.
  static String apiDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Full UTC instant for the API (used for anything the server stores in a
  /// `TIMESTAMP`).
  static String apiInstant(DateTime value) => value.toUtc().toIso8601String();

  // ── Local "now" helpers ─────────────────────────────────────────────────

  /// Local midnight today. All day-bucketing ("Today", "Yesterday", streaks,
  /// budget pacing) must be anchored here, not on a UTC value.
  static DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isToday(DateTime value) => isSameDay(value, DateTime.now());

  static bool isYesterday(DateTime value) => isSameDay(
        value,
        DateTime.now().subtract(const Duration(days: 1)),
      );

  /// Whole days between two values, compared as calendar days rather than as
  /// 24-hour blocks — so 23:00 yesterday to 01:00 today is 1, not 0.
  static int daysBetween(DateTime from, DateTime to) =>
      startOfDay(to).difference(startOfDay(from)).inDays;

  // ── Device zone (reported to the backend for scheduling) ────────────────

  /// Minutes east of UTC for the device right now (Colombo = 330, New York in
  /// winter = -300). Recomputed on demand so a DST transition or a flight is
  /// picked up as soon as the app next syncs.
  static int get offsetMinutes => DateTime.now().timeZoneOffset.inMinutes;

  /// The platform's abbreviation for the current zone (`+0530`, `IST`, `GMT`).
  /// Not an IANA id — see [ianaTimeZone].
  static String get timeZoneAbbreviation => DateTime.now().timeZoneName;

  /// Best-effort IANA zone id.
  ///
  /// Dart has no built-in IANA lookup, so this is null unless the app is built
  /// with a platform plugin that supplies one; install it via [registerIanaTimeZone]
  /// during bootstrap. The backend treats this as an optional refinement and
  /// falls back to [offsetMinutes], which is correct except across a DST
  /// boundary that happens between two syncs.
  static String? get ianaTimeZone => _iana;
  static String? _iana;

  /// Called once at startup by whoever can resolve the platform zone
  /// (e.g. `flutter_timezone`). Safe to never call.
  static void registerIanaTimeZone(String? zoneId) {
    final trimmed = zoneId?.trim();
    _iana = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// The payload sent to `PUT /api/profile/:id` so the server can schedule
  /// reminders and digests in the user's own morning rather than the server's.
  static Map<String, dynamic> zonePayload() => {
        'tz_offset_minutes': offsetMinutes,
        if (_iana != null) 'timezone': _iana,
      };

  /// `UTC+05:30` — for showing the user which zone the app thinks it is in.
  static String get offsetLabel {
    final minutes = offsetMinutes;
    final sign = minutes < 0 ? '-' : '+';
    final abs = minutes.abs();
    final h = (abs ~/ 60).toString().padLeft(2, '0');
    final m = (abs % 60).toString().padLeft(2, '0');
    return 'UTC$sign$h:$m';
  }

  // ── internals ───────────────────────────────────────────────────────────

  static DateTime? _parse(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is int) {
      // Epoch values: seconds if it looks too small to be milliseconds.
      return raw.abs() < 100000000000
          ? DateTime.fromMillisecondsSinceEpoch(raw * 1000, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  /// True when the source string carried no zone designator, in which case the
  /// backend convention says it is UTC.
  static DateTime _assumeUtc(DateTime parsed, Object? raw) {
    final text = raw.toString().trim();
    final hasZone = text.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(text);
    if (hasZone) return parsed.toUtc();
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  }
}
