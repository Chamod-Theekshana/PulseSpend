import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/transactions_provider.dart';
import '../../../providers/budgets_provider.dart';
import '../../../providers/goals_provider.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/recurring_provider.dart';
import '../../../providers/reminders_provider.dart';
import '../../home/home_shell.dart';
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
        return const SignInScreen();
    }
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
              child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              'PulseSpend',
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
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
    
    // Explicitly wait for all essential data providers to finish fetching from the backend
    await Future.wait([
      ref.read(profileControllerProvider.notifier).refresh(),
      ref.read(transactionsControllerProvider.notifier).refresh(),
      ref.read(budgetsControllerProvider.notifier).refresh(),
      ref.read(goalsControllerProvider.notifier).refresh(),
      ref.read(categoriesControllerProvider.notifier).refresh(),
      ref.read(recurringControllerProvider.notifier).refresh(),
      ref.read(remindersControllerProvider.notifier).refresh(),
    ]);

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
