import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/notifications/notification_router.dart';
import 'core/security/app_lock_gate.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/splash_gate.dart';
import 'l10n/app_localizations.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'shared/widgets/connectivity_banner.dart';

class PulseSpendApp extends ConsumerWidget {
  const PulseSpendApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Theme is seeded from cache at startup then tracks the saved profile
    // preference — see [themeModeProvider]. Locale tracks profile.language.
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'PulseSpend',
      // Root navigator key so notification taps can deep-link from anywhere.
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => ConnectivityBanner(child: child ?? const SizedBox.shrink()),
      home: const AppLockGate(child: SplashGate()),
    );
  }
}
