import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pulsespend/features/onboarding/screens/onboarding_screen.dart';

void main() {
  testWidgets('Skip on the first slide invokes onDone', (tester) async {
    var called = false;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onDone: () async => called = true),
    ));
    await tester.pump();

    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(called, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Get Started on the last slide invokes onDone', (tester) async {
    var called = false;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onDone: () async => called = true),
    ));
    await tester.pump();

    // Advance to the final slide via the "Next" button.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Get Started'), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pump();

    expect(called, isTrue);
    expect(tester.takeException(), isNull);
  });
}
