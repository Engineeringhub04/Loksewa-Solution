// Widget tests for the purchase screens, with no signed-in user so the
// backends fail fast (existing convention): error branch with retry on the
// request-detail screens and the landing screen, the empty state on the
// index.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/shop/content_purchase_detail_screen.dart';
import 'package:loksewa_solution/screens/shop/exam_purchase_screen.dart';
import 'package:loksewa_solution/screens/shop/purchase_details_screen.dart';
import 'package:loksewa_solution/screens/shop/subscription_exam_purchase_screen.dart';

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
    expect(find.textContaining('Exam Details (0)'), findsOneWidget);
    expect(find.textContaining('Content Details (0)'), findsOneWidget);
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
}
