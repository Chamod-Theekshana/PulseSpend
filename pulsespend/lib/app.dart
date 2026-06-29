import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/splash_gate.dart';
import 'providers/profile_provider.dart';

class PulseSpendApp extends ConsumerWidget {
  const PulseSpendApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Respect the user's saved theme preference once profile loads; falls
    // back to system brightness before that (and for guests on sign-in).
    final savedTheme = ref.watch(profileControllerProvider).user?.theme;
    final themeMode = switch (savedTheme) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };

    return MaterialApp(
      title: 'PulseSpend',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const SplashGate(),
    );
  }
}
