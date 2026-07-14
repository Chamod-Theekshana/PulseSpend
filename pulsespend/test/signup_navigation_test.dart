import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pulsespend/providers/auth_provider.dart';
import 'package:pulsespend/features/auth/screens/signup_password_screen.dart';

/// Fake that flips straight to authenticated without touching the network,
/// sockets, secure storage or Firebase (all singletons in the real controller).
class _FakeAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);

  @override
  Future<void> completeSignup({
    required String email,
    required String password,
    required String signupToken,
  }) async {
    state = const AuthState(status: AuthStatus.authenticated, userId: '1', email: 'a@b.com');
  }
}

void main() {
  testWidgets('Create Account pops the signup screens back to root', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(_FakeAuthController.new)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SignupPasswordScreen(email: 'a@b.com', signupToken: 'tok'),
                  ),
                ),
                child: const Text('ROOT'),
              ),
            ),
          ),
        ),
      ),
    ));

    // Navigate to the (pushed) signup password screen.
    await tester.tap(find.text('ROOT'));
    await tester.pumpAndSettle();
    expect(find.text('Create Account'), findsOneWidget);

    // Fill the form and submit.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'password123');
    await tester.enterText(fields.at(1), 'password123');
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    // The signup screen must be gone and the root revealed — otherwise
    // "nothing happens" after Create Account.
    expect(find.text('Create Account'), findsNothing);
    expect(find.text('ROOT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
