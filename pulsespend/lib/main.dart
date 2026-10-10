import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/notifications/firebase_messaging_service.dart';
import 'core/storage/outbox_service.dart';
import 'core/storage/secure_storage.dart';
import 'core/utils/date_formatter.dart';
import 'providers/date_format_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Push notifications (Firebase Cloud Messaging). Fully guarded: if Firebase
  // isn't configured yet (no google-services.json — run `flutterfire configure`)
  // this no-ops and the app runs normally with the in-app inbox only. The token
  // is registered with the backend once the user is authenticated (auth_provider).
  await FirebaseMessagingService.instance.init();

  // Rehydrate any writes queued while offline in a previous session. Doing it
  // here — before the first frame — means a transaction added on the tube and
  // then killed by the OS is replayed on the next reconnect rather than lost.
  await OutboxService.instance.load();

  // Read the cached theme before the first frame so the correct light/dark
  // background is applied immediately (no flash while the profile loads).
  final cachedTheme = await SecureStorageService.instance.themePref;
  final seedMode = switch (cachedTheme) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };

  // Same idea for the date format: read the cached `date_format` preference
  // before the first frame so dates are never rendered in the wrong order
  // while the profile request is still in flight.
  final cachedDateFormat = await SecureStorageService.instance.dateFormatPref;
  final seedDateFormat =
      DateFormatter.supportedPatterns.contains(cachedDateFormat)
          ? cachedDateFormat!
          : DateFormatter.defaultPattern;
  DateFormatter.globalPattern = seedDateFormat;

  runApp(
    ProviderScope(
      overrides: [
        bootstrapThemeModeProvider.overrideWithValue(seedMode),
        bootstrapDateFormatProvider.overrideWithValue(seedDateFormat),
      ],
      child: const PulseSpendApp(),
    ),
  );
}
