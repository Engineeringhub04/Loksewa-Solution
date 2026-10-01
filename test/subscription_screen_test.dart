// Widget tests for lib/screens/shop/subscription_screen.dart.
//
// The screen is exercised through its [loader] seam, so no test touches
// Firestore. A GoRouter with marker routes verifies the subscribe /
// request-row navigation targets.
//
// Animation note: plan cards enter through SyllabusEntrance (min(index, 8)
// * 60ms delay + 380ms draw-in), so pumps stay small and repeated instead
// of one big pumpAndSettle (per the AGENTS.md widget-test lessons).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/shop/subscription_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/subscription_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/syllabus_entrance.dart';

SubscriptionPlan _plan({
  required String id,
  required String name,
  required BillingCycle cycle,
  required num price,
  List<String> features = const [],
}) =>
    SubscriptionPlan(
      id: id,
      name: name,
      billingCycle: cycle,
      price: price,
      currency: 'NPR',
      durationDays: 30,
      features: features,
      isActive: true,
      order: 0,
      colorFrom: '#7C3AED',
      colorTo: '#DB2777',
    );

SubscriptionRecord _record({
  required String id,
  required SubscriptionStatus status,
  String planId = 'monthly',
  String planName = 'Monthly Pro',
  DateTime? submittedAt,
  DateTime? reviewedAt,
  DateTime? startDate,
  DateTime? expiryDate,
  String? rejectionReason,
}) =>
    SubscriptionRecord(
      id: id,
      uid: 'u1',
      planId: planId,
      planName: planName,
      billingCycle: BillingCycle.monthly,
      amount: 199,
      currency: 'NPR',
      method: 'qr',
      status: status,
      transactionRef: 'TXN1',
      screenshotUrl: 'https://example.com/r.jpg',
      customerMessage: null,
      adminMessage: null,
      submittedAt: submittedAt,
      reviewedAt: reviewedAt,
      rejectionReason: rejectionReason,
      startDate: startDate,
      expiryDate: expiryDate,
      couponCode: null,
      userName: null,
      userEmail: null,
    );

SubscriptionScreenData _data() {
  final now = DateTime.now();
  return SubscriptionScreenData(
    plans: [
      _plan(
          id: 'monthly',
          name: 'Monthly Pro',
          cycle: BillingCycle.monthly,
          price: 199,
          features: ['All subjects, units & chapters']),
      _plan(
          id: 'yearly',
          name: 'Yearly Pro',
          cycle: BillingCycle.yearly,
          price: 1990,
          features: ['Priority support', 'Hand-typed bonus']),
      _plan(
          id: 'free',
          name: 'Free',
          cycle: BillingCycle.free,
          price: 0,
          features: ['All subjects, units & chapters']),
    ],
    history: [
      _record(
          id: 'r-active',
          status: SubscriptionStatus.active,
          submittedAt: now.subtract(const Duration(days: 2)),
          expiryDate: now.add(const Duration(days: 5))),
      _record(
          id: 'r-pending',
          status: SubscriptionStatus.pending,
          submittedAt: now.subtract(const Duration(minutes: 10))),
      _record(
          id: 'r-rejected',
          status: SubscriptionStatus.rejected,
          submittedAt: now.subtract(const Duration(days: 9)),
          rejectionReason: 'Receipt did not match'),
    ],
  );
}

GoRouter _router(Future<SubscriptionScreenData> Function() loader) {
  return GoRouter(
    initialLocation: '/subscription',
    routes: [
      GoRoute(
          path: '/subscription',
          builder: (_, __) => SubscriptionScreen(loader: loader)),
      GoRoute(
          path: '/checkout',
          builder: (_, s) => Scaffold(
              body: Center(
                  child: Text(
                      'checkout-marker:${s.uri.queryParameters['planId']}')))),
      GoRoute(
          path: '/subscription/:id',
          builder: (_, s) => Scaffold(
              body:
                  Center(child: Text('detail-marker:${s.pathParameters['id']}')))),
    ],
  );
}

/// Small repeated pumps: settles every SyllabusEntrance (≤480ms delay here)
/// plus its 380ms draw-in without one giant pump.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  tester.view.physicalSize = const Size(1080, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

void main() {
  setUp(() => AppLanguage.current.value = 'en');
  tearDown(() {
    AppLanguage.current.value = 'en';
  });

  testWidgets('shows the loading state while plans load',
      (tester) async {
    final gate = Completer<SubscriptionScreenData>();
    await _pump(tester, _router(() => gate.future));
    await tester.pump();
    expect(find.text('Loading Subscription...'), findsOneWidget);
    gate.complete(_data());
    await _settle(tester);
    expect(find.text('Monthly Pro'), findsWidgets);
  });

  testWidgets('shows the error state with a working retry', (tester) async {
    var calls = 0;
    Future<SubscriptionScreenData> loader() async {
      calls++;
      if (calls == 1) throw Exception('offline');
      return _data();
    }

    await _pump(tester, _router(loader));
    await _settle(tester);
    expect(find.text('Could not load subscription details.'),
        findsOneWidget);
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(calls, 2);
    expect(find.text('Monthly Pro'), findsWidgets);
  });

  testWidgets('hero shows the active plan with expiry, days-left and pending chips',
      (tester) async {
    await _pump(tester, _router(() async => _data()));
    await _settle(tester);

    expect(find.text('YOUR PLAN'), findsOneWidget);
    expect(find.text('Monthly Pro'), findsWidgets);
    expect(find.textContaining('Active until'), findsOneWidget);
    expect(find.text('5 days left'), findsOneWidget);
    expect(find.text('Pending Review · 1'), findsOneWidget);
  });

  testWidgets(
      'with two active records the hero shows the last-approved plan, '
      'matching the users/{uid} premium mirror the profile pill reads',
      (tester) async {
    final now = DateTime.now();
    // Out-of-order approval: the monthly request was submitted most
    // recently but the yearly one was approved last, so the mirror (and the
    // profile pill) describe the yearly plan.
    final data = SubscriptionScreenData(
      plans: const [],
      history: [
        _record(
          id: 'r-monthly',
          status: SubscriptionStatus.active,
          planId: 'monthly',
          planName: 'Monthly Entitlement',
          submittedAt: now.subtract(const Duration(hours: 1)),
          startDate: now.subtract(const Duration(days: 5)),
          expiryDate: now.add(const Duration(days: 25)),
        ),
        _record(
          id: 'r-yearly',
          status: SubscriptionStatus.active,
          planId: 'yearly',
          planName: 'Yearly Entitlement',
          submittedAt: now.subtract(const Duration(days: 10)),
          startDate: now.subtract(const Duration(days: 1)),
          expiryDate: now.add(const Duration(days: 364)),
        ),
      ],
    );
    await _pump(tester, _router(() async => data));
    await _settle(tester);

    expect(find.text('YOUR PLAN'), findsOneWidget);
    // The hero wears the yearly record's expiry (364 days), not the monthly
    // one's (25 days) — the request rows never render a days-left chip, so
    // this pins the hero's choice unambiguously.
    expect(find.text('364 days left'), findsOneWidget);
    expect(find.text('25 days left'), findsNothing);
    expect(find.text('Yearly Entitlement'), findsWidgets);
    expect(find.text('Monthly Entitlement'), findsOneWidget);
  });

  testWidgets('request rows show status pills and the rejection reason',
      (tester) async {
    await _pump(tester, _router(() async => _data()));
    await _settle(tester);

    expect(find.text('Your Requests'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Receipt did not match'), findsOneWidget);
    expect(find.textContaining('Rs. 199 · QR'), findsWidgets);
  });

  testWidgets('plan cards render the feature matrix and correct footers',
      (tester) async {
    await _pump(tester, _router(() async => _data()));
    await _settle(tester);

    // Each plan card enters through a SyllabusEntrance cascade wrapper.
    expect(find.byType(SyllabusEntrance), findsWidgets);

    // Matrix: known feature labelled, excluded rows still legible. 'Priority
    // support' appears in both the free card (excluded row) and the yearly
    // card (included row) because every card renders the full catalogue.
    expect(find.text('All subjects, units & chapters'), findsWidgets);
    expect(find.text('Priority support'), findsWidgets);
    // Unknown stored feature renders in the trailing extras group.
    expect(find.text('Also included'), findsOneWidget);
    expect(find.text('Hand-typed bonus'), findsOneWidget);

    // Badges + save chip.
    expect(find.text('MOST POPULAR'), findsOneWidget);
    expect(find.text('BEST VALUE'), findsOneWidget);
    // 12*199=2388, (2388-1990)/2388 = 16.7% -> 17
    expect(find.text('Save 17%'), findsOneWidget);

    // Footers: current plan is active, free plan is "Your Free Services",
    // only the non-current paid plan offers Subscribe.
    expect(find.text('Currently Active'), findsOneWidget);
    expect(find.text('Your Free Services'), findsOneWidget);
    expect(find.text('Subscribe Now'), findsOneWidget);
    expect(find.text('/ month'), findsOneWidget);
    expect(find.text('/ year'), findsOneWidget);
  });

  testWidgets('subscribe navigates to checkout with the plan id',
      (tester) async {
    await _pump(tester, _router(() async => _data()));
    await _settle(tester);

    await tester.tap(find.text('Subscribe Now'));
    await _settle(tester);
    expect(find.text('checkout-marker:yearly'), findsOneWidget);
  });

  testWidgets('tapping a request row opens its detail page', (tester) async {
    await _pump(tester, _router(() async => _data()));
    await _settle(tester);

    await tester.tap(find.text('New').first);
    await _settle(tester);
    expect(find.text('detail-marker:r-pending'), findsOneWidget);
  });

  testWidgets('nepali renders pure Devanagari strings', (tester) async {
    AppLanguage.current.value = 'ne';
    await _pump(tester, _router(() async => _data()));
    await _settle(tester);

    expect(find.text('तपाईंको योजना'), findsOneWidget);
    expect(find.text('तपाईंका अनुरोधहरू'), findsOneWidget);
    expect(find.text('आफ्नो योजना छान्नुहोस्'), findsOneWidget);
    expect(find.text('सबै विषय, एकाइ र अध्याय'), findsWidgets);
    expect(find.text('अहिले सदस्यता लिनुहोस्'), findsOneWidget);
    expect(find.text('तपाईंका निःशुल्क सेवा'), findsOneWidget);
  });

  testWidgets('rejected request quote-panel spine is clipped to the card',
      (tester) async {
    await _pump(tester, _router(() async => _data()));
    await _settle(tester);

    expect(find.text('Receipt did not match'), findsOneWidget);
    // The 4px tone spine with rounded outer corners…
    final spines = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxWidth == 4.0 &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).borderRadius ==
            const BorderRadius.only(
              topLeft: Radius.circular(ExpoRadius.md),
              bottomLeft: Radius.circular(ExpoRadius.md),
            ));
    expect(spines, findsOneWidget);
    // …must sit under a ClipRRect cut to the card's radius, so the spine's
    // square inner corners can't poke past the rounded card corners.
    var clipped = false;
    spines.evaluate().single.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is ClipRRect &&
          widget.borderRadius == BorderRadius.circular(ExpoRadius.md)) {
        clipped = true;
        return false;
      }
      return true;
    });
    expect(clipped, isTrue,
        reason: 'quote-panel spine is not clipped to the card radius');
  });
}
