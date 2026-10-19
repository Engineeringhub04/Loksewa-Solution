import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:loksewa_solution/widgets/gateway_popups.dart';

void main() {
  testWidgets('cancel confirm returns true on Cancel Payment',
      (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showCancelPaymentConfirm(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel payment?'), findsOneWidget);
    await tester.tap(find.text('Cancel Payment'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('cancel confirm returns false on Stay', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showCancelPaymentConfirm(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
