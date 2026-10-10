import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/notifications/notification_router.dart';
import 'core/security/app_lock_gate.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/splash_gate.dart';
import 'l10n/app_localizations.dart';
import 'providers/date_format_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/timezone_sync.dart';
import 'shared/widgets/connectivity_banner.dart';

class PulseSpendApp extends ConsumerWidget {
  const PulseSpendApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Theme is seeded from cache at startup then tracks the saved profile
    // preference — see [themeModeProvider]. Locale tracks profile.language.
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    // Watched at the root so the provider stays alive for the whole session and
    // `DateFormatter.globalPattern` is refreshed the moment the preference
    // changes — including when the change arrives from another device over the
    // `profile:updated` socket event.
    ref.watch(dateFormatProvider);
    // Reports the device zone to the backend on launch and on every resume, so
    // scheduled reminders fire in the user's own morning.
    ref.watch(timeZoneSyncProvider);

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
      builder: (context, child) {
        // 12h vs 24h is a device setting, not an app setting, so it is read
        // from MediaQuery rather than the profile.
        syncClockConvention(context);
        return ConnectivityBanner(child: child ?? const SizedBox.shrink());
      },
      home: const AppLockGate(child: SplashGate()),
    );
  }
}
