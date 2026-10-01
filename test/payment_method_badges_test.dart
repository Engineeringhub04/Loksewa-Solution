import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/widgets/payment_method_badges.dart';

/// Widget test for PaymentMethodBadges (port of PaymentMethodBadges.tsx):
/// the "Accepted payment methods" label plus the three brand badges.
void main() {
  testWidgets('renders the label and all three brand badges',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PaymentMethodBadges()),
      ),
    );

    expect(find.text('Accepted payment methods'), findsOneWidget);
    expect(find.text('eSewa'), findsOneWidget);
    expect(find.text('Khalti'), findsOneWidget);
    expect(find.text('Fonepay'), findsOneWidget);
  });
}
