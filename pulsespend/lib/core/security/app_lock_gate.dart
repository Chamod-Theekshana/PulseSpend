import 'package:flutter/material.dart';
import '../storage/secure_storage.dart';
import '../theme/app_colors.dart';
import 'biometric_service.dart';

/// Wraps the app content and enforces a biometric/device-credential lock when
/// the user has enabled it. Challenges on cold start and again whenever the app
/// returns from the background, covering the UI in between for privacy.
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _lockThenPrompt());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Lock only when the feature is on, a session exists, and the device can
  /// actually authenticate — never strand a user on a lock screen they can't pass.
  Future<bool> _shouldLock() async {
    if (!await SecureStorageService.instance.biometricEnabled) return false;
    if (!await SecureStorageService.instance.hasSession) return false;
    return BiometricService.instance.canAuthenticate();
  }

  Future<void> _lockThenPrompt() async {
    if (await _shouldLock()) {
      if (!mounted) return;
      setState(() => _locked = true);
      _promptUnlock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ignore lifecycle churn caused by the system auth sheet itself.
    if (_authenticating) return;

    if (state == AppLifecycleState.paused) {
      _shouldLock().then((should) {
        if (should && mounted) setState(() => _locked = true);
      });
    } else if (state == AppLifecycleState.resumed && _locked) {
      _promptUnlock();
    }
  }

  Future<void> _promptUnlock() async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      final ok =
          await BiometricService.instance.authenticate(reason: 'Unlock PulseSpend');
      if (ok && mounted) setState(() => _locked = false);
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked) _LockOverlay(onUnlock: _promptUnlock),
      ],
    );
  }
}

class _LockOverlay extends StatelessWidget {
  final VoidCallback onUnlock;
  const _LockOverlay({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 56, color: AppColors.primary),
              const SizedBox(height: 20),
              Text('PulseSpend is locked', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Authenticate to continue', style: theme.textTheme.bodySmall),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
