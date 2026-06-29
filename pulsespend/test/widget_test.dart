import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App should load', (WidgetTester tester) async {
    // TODO: Write your actual widget tests here.
    // Ensure you wrap your app in a ProviderScope since you're using Riverpod.
    // Example: await tester.pumpWidget(const ProviderScope(child: PulseSpendApp()));
    expect(true, isTrue);
  });
}
