import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/storage/secure_storage.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // NOTE: If you wire up Firebase Cloud Messaging (the backend already
  // expects an `fcm_token` via POST /api/notifications/save-token — see
  // pushService.ts), initialize Firebase.initializeApp() here before
  // runApp(), and request notification permissions on first launch.

  // Read the cached theme before the first frame so the correct light/dark
  // background is applied immediately (no flash while the profile loads).
  final cachedTheme = await SecureStorageService.instance.themePref;
  final seedMode = switch (cachedTheme) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };

  runApp(
    ProviderScope(
      overrides: [bootstrapThemeModeProvider.overrideWithValue(seedMode)],
      child: const PulseSpendApp(),
    ),
  );
}
