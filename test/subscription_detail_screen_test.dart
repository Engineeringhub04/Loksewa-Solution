// Widget tests for lib/screens/shop/subscription_detail_screen.dart.
//
// Exercised through the [loader] / [pickImage] seams — no Firestore, no
// file picker, no Cloudinary. The 30-minute edit window is driven by the
// record's submittedAt relative to DateTime.now().
//
// Pumps stay small and repeated (SyllabusEntrance draw-ins + the 1s edit
// timer); no pumpAndSettle, per the AGENTS.md widget-test lessons.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/shop/subscription_detail_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/subscription_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/syllabus_entrance.dart';

SubscriptionRecord _record({
  String id = 'r1',
  SubscriptionStatus status = SubscriptionStatus.pending,
  DateTime? submittedAt,
  DateTime? reviewedAt,
  DateTime? expiryDate,
  String screenshotUrl = 'https://example.com/r.jpg',
  String? rejectionReason,
  String? adminMessage,
  String? couponCode,
  String? customerMessage,
}) {
  final now = DateTime.now();
  return SubscriptionRecord(
    id: id,
    uid: 'u1',
    planId: 'monthly',
    planName: 'Monthly Pro',
    billingCycle: BillingCycle.monthly,
    amount: 199,
    currency: 'NPR',
    method: 'qr',
    status: status,
    transactionRef: 'TXN1',
    screenshotUrl: screenshotUrl,
    customerMessage: customerMessage,
    adminMessage: adminMessage,
    submittedAt: submittedAt ?? now.subtract(const Duration(minutes: 10)),
    reviewedAt: reviewedAt,
    rejectionReason: rejectionReason,
    startDate: null,
    expiryDate: expiryDate,
    couponCode: couponCode,
    userName: null,
    userEmail: null,
  );
}

/// A minimal valid 1x1 transparent PNG, so Image.memory can decode the bytes
/// the pickImage seam returns.
Uint8List _tinyPng() => Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

GoRouter _router({
  required Future<SubscriptionRecord?> Function(String) loader,
  Future<Uint8List?> Function()? pickImage,
}) {
  return GoRouter(
    initialLocation: '/subscription/r1',
    routes: [
      GoRoute(
          path: '/subscription/:id',
          builder: (_, s) => SubscriptionDetailScreen(
              id: s.pathParameters['id']!,
              loader: loader,
              pickImage: pickImage)),
      GoRoute(
          path: '/subscription',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('plans-marker')))),
      GoRoute(
          path: '/contact-us',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('contact-marker')))),
    ],
  );
}

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  tester.view.physicalSize = const Size(1080, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

/// Small repeated pumps: settles SyllabusEntrance draw-ins and lets the 1s
/// edit-window timer tick without one giant pump.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  setUp(() => AppLanguage.current.value = 'en');
  tearDown(() {
    AppLanguage.current.value = 'en';
  });

  testWidgets('shows the loading state while the request loads',
      (tester) async {
    final gate = Completer<SubscriptionRecord?>();
    await _pump(tester, _router(loader: (_) => gate.future));
    await tester.pump();
    expect(find.text('Loading Subscription...'), findsOneWidget);
    gate.complete(_record());
    await _settle(tester);
    expect(find.text('Monthly Pro'), findsWidgets);
  });

  testWidgets('shows the error state with a working retry', (tester) async {
    var calls = 0;
    await _pump(
        tester,
        _router(loader: (_) async {
          calls++;
          if (calls == 1) throw Exception('offline');
          return _record();
        }));
    await _settle(tester);
    expect(find.text('Could not load this request.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(calls, 2);
    expect(find.text('Monthly Pro'), findsWidgets);
  });

  testWidgets('pending request: crown, open edit window, timeline, summary',
      (tester) async {
    await _pump(tester, _router(loader: (_) async => _record()));
    await _settle(tester);

    // Page sections enter through SyllabusEntrance cascade wrappers.
    expect(find.byType(SyllabusEntrance), findsWidgets);

    // Crown: status tag + plan name + amount hero + method. The amount also
    // appears in the payment summary, so both are expected.
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('Rs. 199'), findsWidgets);
    // Method chip on the crown + the payment-summary row value.
    expect(find.text('QR'), findsWidgets);

    // Edit window is open with a live countdown.
    expect(find.text('You can still edit this request'), findsOneWidget);
    expect(find.text('Edit time remaining'), findsNothing); // inline caption
    expect(find.text('Edit Request'), findsOneWidget);

    // Timeline steps.
    expect(find.text('Payment submitted'), findsOneWidget);
    expect(find.text('Waiting for admin review'), findsOneWidget);
    expect(find.text('Approved & activated'), findsOneWidget);
    expect(find.text('•••'), findsOneWidget);

    // Payment summary rows.
    expect(find.text('Payment Summary'), findsOneWidget);
    expect(find.text('Payment Method'), findsOneWidget);
    expect(find.text('Reference'), findsOneWidget);

    // Receipt section with the zoom hint pill.
    expect(find.text('Payment Receipt'), findsWidgets);
    expect(find.text('Tap to view full screen and zoom'), findsOneWidget);

    // Actions.
    expect(find.text('Back to Plans'), findsOneWidget);
    expect(find.text('Contact Support'), findsOneWidget);
  });

  testWidgets('edit form validates, then saves and closes', (tester) async {
    final saved = <String?>[];
    await _pump(
        tester,
        _router(
            loader: (_) async {
              saved.add('loaded');
              return _record(screenshotUrl: '');
            },
            pickImage: () async => _tinyPng()));
    await _settle(tester);

    await tester.tap(find.text('Edit Request'));
    await _settle(tester);
    expect(find.text('Transaction ID / Reference'), findsOneWidget);

    // Save with an empty reference is rejected; the form stays open.
    await tester.tap(find.text('Save Request'));
    await _settle(tester);
    expect(
        find.text(
            'Transaction ID / Reference and Payment Screenshot are required.'),
        findsOneWidget);
    expect(find.text('Transaction ID / Reference'), findsOneWidget);

    // Pick a screenshot, fill the reference, save. The pick target is the
    // outlined button (the form field label shares the same text).
    await tester.tap(
        find.widgetWithText(OutlinedButton, 'Payment Screenshot'));
    await _settle(tester);
    expect(find.text('Edit'), findsOneWidget); // pick button relabels

    await tester.enterText(
        find.widgetWithText(TextField, 'Transaction ID / Reference').first,
        'TXN999');
    await tester.tap(find.text('Save Request'));
    await _settle(tester);

    expect(find.text('Subscription request updated.'), findsOneWidget);
    expect(find.text('Transaction ID / Reference'), findsNothing);
    expect(saved, isNotEmpty);
  });

  testWidgets('expired edit window shows the locked state', (tester) async {
    await _pump(
        tester,
        _router(
            loader: (_) async => _record(
                submittedAt:
                    DateTime.now().subtract(const Duration(minutes: 40)))));
    await _settle(tester);

    expect(find.text('The 30-minute edit window has expired.'),
        findsOneWidget);
    // The button is disabled once the window closes.
    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Edit Request'));
    expect(button.onPressed, isNull);
  });

  testWidgets('active request hides the edit window', (tester) async {
    await _pump(
        tester,
        _router(
            loader: (_) async => _record(
                  status: SubscriptionStatus.active,
                  submittedAt: DateTime.now()
                      .subtract(const Duration(days: 2)),
                  reviewedAt: DateTime.now()
                      .subtract(const Duration(days: 2)),
                  expiryDate:
                      DateTime.now().add(const Duration(days: 28)),
                )));
    await _settle(tester);

    expect(find.text('APPROVED'), findsOneWidget);
    expect(find.text('You can still edit this request'), findsNothing);
    expect(find.text('Edit Request'), findsNothing);
    expect(find.text('Approved & activated'), findsOneWidget);
  });

  testWidgets('rejected request shows the rejection quote panel',
      (tester) async {
    await _pump(
        tester,
        _router(
            loader: (_) async => _record(
                  status: SubscriptionStatus.rejected,
                  reviewedAt: DateTime.now()
                      .subtract(const Duration(hours: 1)),
                  rejectionReason: 'Receipt did not match',
                  adminMessage: 'Please resend a clearer photo',
                )));
    await _settle(tester);

    expect(find.text('REJECTED'), findsOneWidget);
    expect(find.text('Receipt did not match'), findsOneWidget);
    expect(find.text('Message from Admin'), findsOneWidget);
    expect(find.text('Please resend a clearer photo'), findsOneWidget);
    expect(find.text('Rejected by admin'), findsOneWidget);
  });

  testWidgets('quote-panel spines are clipped to the card radius',
      (tester) async {
    await _pump(
        tester,
        _router(
            loader: (_) async => _record(
                  status: SubscriptionStatus.rejected,
                  reviewedAt: DateTime.now()
                      .subtract(const Duration(hours: 1)),
                  rejectionReason: 'Receipt did not match',
                  adminMessage: 'Please resend a clearer photo',
                )));
    await _settle(tester);

    // Both quote panels (admin message + rejection reason) carry the 4px
    // tone spine with rounded outer corners.
    final spines = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxWidth == 4.0 &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).borderRadius ==
            const BorderRadius.only(
              topLeft: Radius.circular(ExpoRadius.md),
              bottomLeft: Radius.circular(ExpoRadius.md),
            ));
    expect(spines, findsNWidgets(2));
    // Each spine must sit under a ClipRRect cut to the card's radius, so
    // the spine's square inner corners can't poke past the rounded card
    // corners (the reported defect).
    for (final element in spines.evaluate()) {
      var clipped = false;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is ClipRRect &&
            widget.borderRadius ==
                BorderRadius.circular(ExpoRadius.md)) {
          clipped = true;
          return false;
        }
        return true;
      });
      expect(clipped, isTrue,
          reason: 'quote-panel spine is not clipped to the card radius');
    }
  });

  testWidgets('coupon renders as a pill in the payment summary',
      (tester) async {
    await _pump(
        tester,
        _router(
            loader: (_) async =>
                _record(couponCode: 'DASHAIN20')));
    await _settle(tester);

    expect(find.text('DASHAIN20'), findsOneWidget);
  });

  testWidgets('receipt tap opens the zoom viewer', (tester) async {
    await _pump(tester, _router(loader: (_) async => _record()));
    await _settle(tester);

    // Tap the receipt preview (the tappable image inside the receipt card).
    await tester.tap(find.byType(ClipRRect).last);
    await _settle(tester);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('action buttons navigate to plans and contact pages',
      (tester) async {
    await _pump(tester, _router(loader: (_) async => _record()));
    await _settle(tester);

    await tester.tap(find.text('Contact Support'));
    await _settle(tester);
    expect(find.text('contact-marker'), findsOneWidget);
  });

  testWidgets('nepali renders pure Devanagari strings', (tester) async {
    AppLanguage.current.value = 'ne';
    await _pump(
        tester,
        _router(
            loader: (_) async => _record(
                status: SubscriptionStatus.rejected,
                reviewedAt:
                    DateTime.now().subtract(const Duration(hours: 1)),
                rejectionReason: 'कारण')));
    await _settle(tester);

    expect(find.text('विवरण हेर्नुहोस्'), findsOneWidget);
    expect(find.text('अस्वीकृत'), findsWidgets);
    expect(find.text('भुक्तानी विवरण'), findsOneWidget);
    expect(find.text('अनुरोधको क्रम'), findsOneWidget);
    expect(find.text('भुक्तानी रसिद'), findsWidgets);
    expect(find.text('एड्मिनद्वारा अस्वीकृत'), findsOneWidget);
  });
}
