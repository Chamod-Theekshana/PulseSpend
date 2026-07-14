import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/session_sync.dart';
import '../../home/home_shell.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import 'sign_in_screen.dart';

/// Root gate: shows a brief splash while [AuthController] bootstraps from
/// secure storage, then routes to either the authenticated shell or sign-in.
class SplashGate extends ConsumerWidget {
  const SplashGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    switch (authState.status) {
      case AuthStatus.unknown:
        return const _SplashView();
      case AuthStatus.authenticated:
        return const _DataLoadGate(child: HomeShell());
      case AuthStatus.unauthenticated:
        return const _OnboardingGate();
    }
  }
}

/// For signed-out users: shows the first-run walkthrough once (device-scoped),
/// then the sign-in screen. The "seen" flag lives in secure storage so it
/// survives restarts and account switches.
class _OnboardingGate extends StatefulWidget {
  const _OnboardingGate();

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  // null = still reading the flag; true/false = resolved. A plain bool (rather
  // than a FutureBuilder) makes the "finish → show sign-in" transition
  // deterministic instead of depending on FutureBuilder's snapshot timing.
  bool? _seen;

  @override
  void initState() {
    super.initState();
    SecureStorageService.instance.onboardingSeen.then((value) {
      if (mounted) setState(() => _seen = value);
    }).catchError((_) {
      // If the flag can't be read, don't get stuck on the splash — just show
      // the walkthrough.
      if (mounted) setState(() => _seen = false);
    });
  }

  Future<void> _finishOnboarding() async {
    // Persist the "seen" flag, but never let a storage failure trap the user on
    // the walkthrough — advance to sign-in regardless.
    try {
      await SecureStorageService.instance.setOnboardingSeen();
    } catch (_) {
      // ignore — the transition below is what matters to the user
    }
    if (mounted) setState(() => _seen = true);
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    if (seen == null) return const _SplashView();
    if (seen) return const SignInScreen();
    return OnboardingScreen(onDone: _finishOnboarding);
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    // Theme-aware: the background follows the active ThemeData (which itself
    // follows the user's saved theme once profile loads, or system brightness
    // beforehand) so there's no flash of the wrong colour on launch.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A rounded surface keeps the light-on-white logo legible in dark mode.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Image.asset(
                'assets/pulsespend_logo.png',
                width: 132,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 36),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataLoadGate extends ConsumerStatefulWidget {
  final Widget child;
  const _DataLoadGate({required this.child});

  @override
  ConsumerState<_DataLoadGate> createState() => _DataLoadGateState();
}

class _DataLoadGateState extends ConsumerState<_DataLoadGate> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    // Wait for the auth listener to setup and initial microtasks to fire
    await Future.delayed(const Duration(milliseconds: 100));

    // Fetch every account-scoped provider from scratch. Because account
    // switches route through a fresh SplashGate, this doubles as the
    // per-account isolation reset — the incoming account's data fully replaces
    // whatever the previous account left in the app-scoped providers.
    await ref.read(sessionSyncProvider.notifier).resync();

    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const _SplashView();
    }
    return widget.child;
  }
}
