import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/session_sync.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../home/home_shell.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import 'sign_in_screen.dart';

class SplashGate extends ConsumerWidget {
  const SplashGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return switch (authState.status) {
      AuthStatus.unknown => const _SplashView(),
      AuthStatus.authenticated => const _DataLoadGate(child: HomeShell()),
      AuthStatus.unauthenticated => const _OnboardingGate(),
    };
  }
}

class _OnboardingGate extends StatefulWidget {
  const _OnboardingGate();

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  bool? _hasSeenOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    try {
      final seen = await SecureStorageService.instance.onboardingSeen;
      if (mounted) setState(() => _hasSeenOnboarding = seen);
    } catch (_) {
      if (mounted) setState(() => _hasSeenOnboarding = false);
    }
  }

  Future<void> _completeOnboarding() async {
    try {
      await SecureStorageService.instance.setOnboardingSeen();
    } catch (_) {
      // Proceed to sign-in even if local storage fails
    } finally {
      if (mounted) setState(() => _hasSeenOnboarding = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSeenOnboarding == null) {
      return const _SplashView();
    }
    
    return _hasSeenOnboarding! 
        ? const SignInScreen() 
        : OnboardingScreen(onDone: _completeOnboarding);
  }
}

class _DataLoadGate extends ConsumerStatefulWidget {
  final Widget child;
  const _DataLoadGate({required this.child});

  @override
  ConsumerState<_DataLoadGate> createState() => _DataLoadGateState();
}

class _DataLoadGateState extends ConsumerState<_DataLoadGate> {
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      await ref.read(sessionSyncProvider.notifier).resync();
    } finally {
      if (mounted) setState(() => _isReady = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isReady ? widget.child : const _SplashView();
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              
              child: Image.asset(
                'assets/pulsespend_logo.png',
                width: 132,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 36),
            const AppLoader(size: 28),
          ],
        ),
      ),
    );
  }
}