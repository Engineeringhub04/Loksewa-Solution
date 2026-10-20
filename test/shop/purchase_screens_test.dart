// Widget tests for the purchase screens, with no signed-in user so the
// backends fail fast (existing convention): error branch with retry on the
// request-detail screens and the landing screen, the empty state on the
// index. Plus the Payment Summary row rules: method value colours and the
// copy Reference value aligning with the other rows' value column.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/shop/content_purchase_detail_screen.dart';
import 'package:loksewa_solution/screens/shop/exam_purchase_screen.dart';
import 'package:loksewa_solution/screens/shop/purchase_details_screen.dart';
import 'package:loksewa_solution/screens/shop/subscription_exam_purchase_screen.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/request_info_row.dart';

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1612);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget home) => MaterialApp(home: Scaffold(body: home));

void main() {
  testWidgets('purchase index shows empty state when not signed in',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(_app(const PurchaseDetailsScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Purchase Details'), findsWidgets);
    expect(find.text('No exam purchase requests yet.'), findsOneWidget);
    // Track filter carries counts.
    expect(find.textContaining('All (0)'), findsOneWidget);
    expect(find.textContaining('Exam Purchase (0)'), findsOneWidget);
    expect(find.textContaining('Subject Purchase (0)'), findsOneWidget);
  });

  testWidgets('exam purchase detail errors and offers retry',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
        _app(const SubscriptionExamPurchaseScreen(id: 'rid')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Could not load this purchase.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Retry re-issues the load and stays on the error branch.
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Could not load this purchase.'), findsOneWidget);
  });

  testWidgets('content purchase detail errors and offers retry',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
        _app(const ContentPurchaseDetailScreen(id: 'rid')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Could not load this purchase.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('exam purchase landing errors and offers retry',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(_app(const ExamPurchaseScreen(id: 'exam1')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Could not load this exam set.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('payment method colours: eSewa green, Khalti red, QR app blue',
      (tester) async {
    Color? esewa, khalti, qr;
    ExpoPalette? pal;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        esewa = requestMethodColor(context, 'esewa');
        khalti = requestMethodColor(context, 'khalti');
        qr = requestMethodColor(context, 'qr');
        pal = ExpoPalette.of(context);
        return const SizedBox.shrink();
      }),
    ));
    expect(esewa, pal!.success);
    expect(khalti, pal!.danger);
    expect(qr, pal!.primary);
    expect(esewa, isNot(khalti));
    expect(qr, isNot(esewa));
  });

  testWidgets(
      'reference value aligns with the value column; copy icon follows text',
      (tester) async {
    await tester.pumpWidget(_app(
      const SizedBox(
        width: 360,
        child: Column(
          children: [
            RequestInfoRow(
              icon: Icons.diamond_outlined,
              label: 'Plan',
              value: Text('Premium Yearly'),
            ),
            RequestInfoRow(
              icon: Icons.qr_code_outlined,
              label: 'Reference',
              value: RequestReferenceValue(ref: 'ABCD1234'),
              last: true,
            ),
          ],
        ),
      ),
    ));
    await tester.pump();

    // Both values start at the SAME x — the row's fixed label column.
    final planX = tester.getTopLeft(find.text('Premium Yearly')).dx;
    final refX = tester.getTopLeft(find.byType(SelectableText)).dx;
    expect(refX, planX);

    // The copy icon sits right after the (short) reference text — NOT
    // pushed against the row's right edge (360 wide here).
    final iconRight = tester.getTopRight(find.byIcon(Icons.copy_outlined)).dx;
    expect(iconRight, lessThan(300));

    // Empty reference renders a plain dash, no copy icon.
    await tester.pumpWidget(_app(
      const RequestInfoRow(
        icon: Icons.qr_code_outlined,
        label: 'Reference',
        value: RequestReferenceValue(ref: null),
        last: true,
      ),
    ));
    await tester.pump();
    expect(find.text('—'), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
  });
}
