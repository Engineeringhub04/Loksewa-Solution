// v1.0.106 payment-UX correction round tests.
//
// Covers the user-tested findings from v1.0.105:
//  1. Gateway-pending filter: fresh initiated gateway payments are hidden
//     from the Your-Request list; stale/failed ones still show (recovery);
//     manual QR pending still shows immediately.
//  2. No "Edit Request" for gateway (eSewa/Khalti) records on the detail
//     screen — editing a completed gateway payment is meaningless.
//  3. Subscription page has "Plan" | "Your Request" tabs below the header.
//  4. Non-active request rows show a delete icon; active rows do not.
//
// Pumps stay small and repeated (SyllabusEntrance draw-ins); no
// pumpAndSettle, per the AGENTS.md widget-test lessons.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/shop/subscription_detail_screen.dart';
import 'package:loksewa_solution/screens/shop/subscription_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/subscription_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/syllabus_entrance.dart';
import 'package:loksewa_solution/widgets/trash_icon.dart';

SubscriptionRecord _record({
  required String id,
  required String method,
  required SubscriptionStatus status,
  String? gatewayStatus,
  String? failureReason,
  DateTime? submittedAt,
}) {
  return SubscriptionRecord(
    id: id,
    uid: 'u1',
    planId: 'monthly',
    planName: 'Premium Monthly',
    billingCycle: BillingCycle.monthly,
    amount: 299,
    currency: 'NPR',
    method: method,
    status: status,
    transactionRef: 'txn_test123',
    screenshotUrl: 'https://example.com/r.jpg',
    customerMessage: null,
    adminMessage: null,
    submittedAt: submittedAt ?? DateTime.now(),
    reviewedAt: null,
    rejectionReason: null,
    startDate: null,
    expiryDate: null,
    couponCode: null,
    userName: null,
    userEmail: null,
    gatewayStatus: gatewayStatus,
    failureReason: failureReason,
  );
}

SubscriptionPlan _plan(String id, String name) => SubscriptionPlan(
      id: id,
      name: name,
      billingCycle: BillingCycle.monthly,
      price: 299,
      currency: 'NPR',
      durationDays: 30,
      features: const [],
      categories: const [],
      customFeatures: const [],
      isActive: true,
      order: 0,
      colorFrom: '#7C3AED',
      colorTo: '#DB2777',
    );

GoRouter _subRouter(Future<SubscriptionScreenData> Function() loader) {
  return GoRouter(
    initialLocation: '/subscription',
    routes: [
      GoRoute(
          path: '/subscription',
          builder: (_, __) => SubscriptionScreen(loader: loader)),
      GoRoute(
          path: '/subscription/:id',
          builder: (_, s) => Scaffold(
              body:
                  Center(child: Text('detail-marker:${s.pathParameters['id']}')))),
    ],
  );
}

Future<void> _pumpSub(
    WidgetTester tester, Future<SubscriptionScreenData> Function() loader) async {
  tester.view.physicalSize = const Size(1080, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp.router(routerConfig: _subRouter(loader)));
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

GoRouter _detailRouter(Future<SubscriptionRecord?> Function(String) loader) {
  return GoRouter(
    initialLocation: '/subscription/r1',
    routes: [
      GoRoute(
          path: '/subscription/:id',
          builder: (_, s) => SubscriptionDetailScreen(
              id: s.pathParameters['id']!, loader: loader)),
      GoRoute(
          path: '/contact-us',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('contact-marker')))),
    ],
  );
}

Future<void> _pumpDetail(WidgetTester tester,
    Future<SubscriptionRecord?> Function(String) loader) async {
  tester.view.physicalSize = const Size(1080, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
      MaterialApp.router(routerConfig: _detailRouter(loader)));
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => AppLanguage.current.value = 'en');
  tearDown(() => AppLanguage.current.value = 'en');
  group('filterHistoryForDisplay (v1.0.108 #1)', () {
    test('shows fresh initiated gateway payments (recovery entry point)', () {
      final fresh = _record(
        id: 'g1',
        method: 'esewa',
        status: SubscriptionStatus.pending,
        gatewayStatus: 'initiated',
        submittedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final out = SubscriptionService.filterHistoryForDisplay([fresh]);
      expect(out.map((r) => r.id), ['g1']);
    });

    test('hides cancelled gateway payments', () {
      final cancelled = _record(
        id: 'g5',
        method: 'esewa',
        status: SubscriptionStatus.cancelled,
        gatewayStatus: 'cancelled',
      );
      final out = SubscriptionService.filterHistoryForDisplay([cancelled]);
      expect(out, isEmpty);
    });

    test('keeps stale initiated gateway payments (recovery)', () {
      final stale = _record(
        id: 'g2',
        method: 'khalti',
        status: SubscriptionStatus.pending,
        gatewayStatus: 'initiated',
        submittedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      );
      final out = SubscriptionService.filterHistoryForDisplay([stale]);
      expect(out.map((r) => r.id), ['g2']);
    });

    test('keeps failed gateway payments', () {
      final failed = _record(
        id: 'g3',
        method: 'esewa',
        status: SubscriptionStatus.pending,
        gatewayStatus: 'failed',
        failureReason: 'payment_not_completed',
      );
      final out = SubscriptionService.filterHistoryForDisplay([failed]);
      expect(out.map((r) => r.id), ['g3']);
    });

    test('keeps manual QR pending requests', () {
      final qr = _record(
        id: 'q1',
        method: 'qr',
        status: SubscriptionStatus.pending,
      );
      final out = SubscriptionService.filterHistoryForDisplay([qr]);
      expect(out.map((r) => r.id), ['q1']);
    });

    test('keeps active gateway subscriptions', () {
      final active = _record(
        id: 'g4',
        method: 'esewa',
        status: SubscriptionStatus.active,
        gatewayStatus: 'verified',
      );
      final out = SubscriptionService.filterHistoryForDisplay([active]);
      expect(out.map((r) => r.id), ['g4']);
    });
  });

  group('subscription page tabs (v1.0.106 #9)', () {
    testWidgets('shows Plan and Your Request tabs', (tester) async {
      final data = SubscriptionScreenData(
        plans: [_plan('monthly', 'Premium Monthly')],
        history: [
          _record(id: 'q1', method: 'qr', status: SubscriptionStatus.pending),
        ],
      );
      await _pumpSub(tester, () async => data);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Your Request'), findsOneWidget);
      // Plan tab content visible by default.
      expect(find.text('Choose Your Plan'), findsOneWidget);
      expect(find.text('Premium Monthly'), findsWidgets);
    });

    testWidgets('tapping Your Request shows the request list', (tester) async {
      final data = SubscriptionScreenData(
        plans: [_plan('monthly', 'Premium Monthly')],
        history: [
          _record(id: 'q1', method: 'qr', status: SubscriptionStatus.pending),
        ],
      );
      await _pumpSub(tester, () async => data);
      await tester.tap(find.text('Your Request'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Plan cards hidden, requests shown.
      expect(find.text('Choose Your Plan'), findsNothing);
      expect(find.text('Your Requests'), findsOneWidget);
    });
  });

  group('request row delete icon (v1.0.106 #10)', () {
    testWidgets('non-active rows show TrashIcon, active rows do not',
        (tester) async {
      final data = SubscriptionScreenData(
        plans: const [],
        history: [
          _record(id: 'q1', method: 'qr', status: SubscriptionStatus.pending),
          _record(
              id: 'g4',
              method: 'esewa',
              status: SubscriptionStatus.active,
              gatewayStatus: 'verified'),
        ],
      );
      await _pumpSub(tester, () async => data);
      await tester.tap(find.text('Your Request'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // One trash icon (the pending row); the active row has none.
      expect(find.byType(TrashIcon), findsOneWidget);
    });
  });

  group('detail screen: no edit for gateway (v1.0.106 #8)', () {
    testWidgets('gateway record hides the Edit Request section',
        (tester) async {
      final record = _record(
        id: 'r1',
        method: 'esewa',
        status: SubscriptionStatus.pending,
        gatewayStatus: 'initiated',
        submittedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await _pumpDetail(tester, (_) async => record);
      expect(find.text('Edit Request'), findsNothing);
      expect(find.text('You can still edit this request'), findsNothing);
    });

    testWidgets('manual QR record keeps the Edit Request section',
        (tester) async {
      final record = _record(
        id: 'r1',
        method: 'qr',
        status: SubscriptionStatus.pending,
        submittedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await _pumpDetail(tester, (_) async => record);
      expect(find.text('Edit Request'), findsOneWidget);
    });
  });
}
