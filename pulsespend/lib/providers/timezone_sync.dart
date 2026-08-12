import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_time.dart';
import 'profile_provider.dart';

/// Reports the device's timezone to the backend so scheduled notifications
/// arrive in the user's own morning rather than the server's.
///
/// Without this, every scheduler falls back to UTC and a "9 AM" bill reminder
/// lands at 14:30 in Colombo. The backend prefers the IANA id when it has one
/// (DST-correct) and otherwise uses the raw offset, so this sends both.
///
/// It re-syncs on resume, not just at launch, because the two things that
/// invalidate a stored offset — crossing a DST boundary and getting on a plane
/// — both typically happen while the app is backgrounded.
class TimeZoneSync with WidgetsBindingObserver {
  TimeZoneSync(this._ref);

  final Ref _ref;

  /// The last value pushed, so a resume that didn't change anything is a no-op
  /// rather than a wasted PUT on every app switch.
  String? _lastPushed;

  /// Guards against two resumes racing a slow request.
  bool _inFlight = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    unawaitedSync();
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaitedSync();
  }

  void unawaitedSync() {
    // Fire-and-forget: a failure here degrades notification timing but must
    // never block or surface an error in the UI.
    sync().catchError((_) {});
  }

  Future<void> sync() async {
    if (_inFlight) return;

    final payload = AppTime.zonePayload();
    final signature = '${payload['timezone'] ?? '-'}@${payload['tz_offset_minutes']}';
    if (signature == _lastPushed) return;

    // Nothing to report until there's an authenticated profile to attach it to.
    final profile = _ref.read(profileControllerProvider).user;
    if (profile == null) return;

    _inFlight = true;
    try {
      await _ref.read(profileControllerProvider.notifier).updateTimeZone(
            timeZone: payload['timezone'] as String?,
            offsetMinutes: payload['tz_offset_minutes'] as int,
          );
      _lastPushed = signature;
    } finally {
      _inFlight = false;
    }
  }
}

/// Created once and kept alive for the session. Watch it somewhere near the
/// root (see `app.dart`) so `start()` actually runs.
final timeZoneSyncProvider = Provider<TimeZoneSync>((ref) {
  final sync = TimeZoneSync(ref);
  sync.start();
  ref.onDispose(sync.stop);

  // Push as soon as a profile appears — sign-in, account switch, or cold start
  // finishing its first fetch.
  ref.listen(
    profileControllerProvider.select((s) => s.user?.id),
    (previous, next) {
      if (next != null) sync.unawaitedSync();
    },
  );

  return sync;
});
