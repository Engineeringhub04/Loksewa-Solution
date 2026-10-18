// Widget tests for the gateway payment status overlay:
// - verifying state shows the title/subtitle and NO action buttons;
// - success state shows the Continue button and fires onClose;
// - failure state shows Try Again + Close and fires the right callbacks.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/widgets/payment_status_overlay.dart';

void main() {
  testWidgets('verifying state shows text and no buttons', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PaymentStatusOverlay(
          state: PaymentOverlayState.verifying,
          title: 'Verifying payment…',
          subtitle: 'Do not close the app.',
        ),
      ),
    ));
    // pumpAndSettle never terminates with the repeating pulse animation,
    // so advance manually instead.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Verifying payment…'), findsOneWidget);
    expect(find.text('Do not close the app.'), findsOneWidget);
    expect(find.text('Try Again'), findsNothing);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('success state shows Continue and fires onClose', (tester) async {
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PaymentStatusOverlay(
          state: PaymentOverlayState.success,
          title: 'Payment successful',
          subtitle: 'Enjoy learning!',
          onClose: () => closed = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Payment successful'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('failure state shows both buttons with correct callbacks',
      (tester) async {
    var retried = false;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PaymentStatusOverlay(
          state: PaymentOverlayState.failure,
          title: 'Payment failed',
          subtitle: 'Something went wrong.',
          onRetry: () => retried = true,
          onClose: () => closed = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Payment failed'), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    await tester.pump();
    expect(retried, isTrue);
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(closed, isTrue);
  });
}
