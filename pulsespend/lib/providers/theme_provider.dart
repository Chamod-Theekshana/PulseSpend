import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/secure_storage.dart';
import 'profile_provider.dart';

/// Seeded in `main()` with the theme read synchronously from secure storage,
/// so the very first frame already uses the correct light/dark background.
final bootstrapThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

/// The active [ThemeMode]. Starts from the bootstrap seed and then tracks the
/// user's saved `profile.theme`, persisting every change locally so the next
/// cold start doesn't flash the wrong theme.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    ref.listen(profileControllerProvider, (prev, next) {
      final theme = next.user?.theme;
      if (theme == null) return;
      final mode = switch (theme) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };
      if (mode != state) {
        state = mode;
        SecureStorageService.instance.setThemePref(theme);
      }
    });
    return ref.read(bootstrapThemeModeProvider);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
