import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/content_purchases.dart';
import 'package:loksewa_solution/services/coupon_service.dart';
import 'package:loksewa_solution/services/exam_purchases.dart';
import 'package:loksewa_solution/services/gateway_payment_service.dart';
import 'package:loksewa_solution/services/subscription_service.dart';

/// Phase-5 focused tests: Shop tree + payments client + push tokens +
/// Login Devices at the loksewa-api HTTP seam — coupon redeem fires
/// exactly once per submit, coupon validate feeds the local scope
/// rules, subscription expiry arrives from /subscriptions/mine (the
/// app-side sweep writes nothing), the payments client hits the new
/// base with the CF Bearer, and the token/probe/devices calls carry
/// their contract shapes.

/// A recorded request: method, path, auth header, decoded JSON body.
typedef Seen = ({String method, String path, String? auth, Object? body});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CfApi.storeAuthResult(const CfAuthResult(
      user: CfUser(uid: 'u1', email: 'a@b.c', name: 'Test'),
      accessToken: 'acc-1',
      refreshToken: 'ref-1',
    ));
  });

  tearDown(() {
    CfApi.setTestClient(null);
    GatewayPaymentService.setTestClient(null);
  });

  List<Seen> installCf(
      Map<String, Object?> Function(String method, String path) responder) {
    final seen = <Seen>[];
    CfApi.setTestClient(MockClient((request) async {
      Object? body;
      try {
        body = json.decode(request.body);
      } catch (_) {}
      seen.add((
        method: request.method,
        path: request.url.path,
        auth: request.headers['Authorization'],
        body: body,
      ));
      final payload = responder(request.method, request.url.path);
      return http.Response(json.encode(payload ?? {'ok': true}), 200);
    }));
    return seen;
  }

  group('coupons', () {
    test('redeem posts exactly once with code + context + Bearer', () async {
      final seen = installCf((m, p) => {'ok': true});
      await CouponService.incrementCouponUsage('save10',
          planId: 'plan-1', userId: 'u1');
      expect(seen, hasLength(1));
      expect(seen.single.method, 'POST');
      expect(seen.single.path, '/coupons/redeem');
      expect(seen.single.auth, 'Bearer acc-1');
      expect(seen.single.body, {
        'code': 'SAVE10',
        'planId': 'plan-1',
        'userId': 'u1',
      });
    });

    test('validate (doc mode) feeds validateCouponData', () async {
      final seen = installCf((m, p) => {
            'coupon': {
              'code': 'SAVE10',
              'discountType': 'percent',
              'discountValue': 10,
              'isActive': true,
            },
            'perUserUsedCount': 0,
          });
      final result =
          await CouponService.validateCoupon('save10', 'monthly', 1000);
      expect(seen.single.path, '/coupons/validate');
      expect((seen.single.body as Map)['code'], 'SAVE10');
      expect(result.valid, isTrue);
      expect(result.discountedAmount, 900);
    });

    test('validate (verdict mode) is used as-is', () async {
      installCf((m, p) => {
            'valid': false,
            'reason': 'Coupon has expired',
          });
      final result =
          await CouponService.validateCoupon('OLD', 'monthly', 1000);
      expect(result.valid, isFalse);
      expect(result.reason, 'Coupon has expired');
    });
  });

  group('subscriptions', () {
    test('server-expired record shows expired; expireIfPastDue writes nothing',
        () async {
      final seen = installCf((m, p) => {
            'items': [
              {
                'id': 's-old',
                'uid': 'u1',
                'status': 'expired',
                'planName': 'Pro',
                'submittedAt': '2026-01-01T00:00:00.000Z',
              },
              {
                'id': 's-due',
                'uid': 'u1',
                'status': 'active',
                'planName': 'Pro',
                'expiryDate': '2020-01-01T00:00:00.000Z',
                'submittedAt': '2026-02-01T00:00:00.000Z',
              },
            ],
          });
      final history =
          await SubscriptionService.fetchMySubscriptionHistory('u1');
      final byId = {for (final r in history) r.id: r};
      expect(byId['s-old']?.status, SubscriptionStatus.expired);
      expect(byId['s-due']?.status, SubscriptionStatus.active);
      final requestsAfterFetch = seen.length;
      final due =
          await SubscriptionService.expireIfPastDue('u1', history: history);
      expect(due, ['s-due']);
      // The sweep is a pure derivation now — zero extra HTTP calls.
      expect(seen.length, requestsAfterFetch);
      expect(seen.every((s) => s.method == 'GET'), isTrue);
    });

    test('createSubscription posts the payload and returns the row',
        () async {
      final seen = installCf((m, p) => {
            'row': {'id': 'sub_new', 'status': 'pending'},
          });
      final row = await CfApi.createSubscription(
          {'planId': 'plan-1', 'amount': 999, 'status': 'pending'});
      expect(seen.single.method, 'POST');
      expect(seen.single.path, '/subscriptions');
      expect((seen.single.body as Map)['planId'], 'plan-1');
      expect(row['id'], 'sub_new');
    });
  });

  group('purchases', () {
    test('mine lists map + sort newest-first', () async {
      installCf((m, p) => {
            'exam': [
              {
                'id': 'e-old',
                'uid': 'u1',
                'examSetId': 'set-1',
                'submittedAt': '2026-01-01T00:00:00.000Z',
              },
              {
                'id': 'e-new',
                'uid': 'u1',
                'examSetId': 'set-2',
                'submittedAt': '2026-03-01T00:00:00.000Z',
              },
            ],
            'content': [
              {
                'id': 'c-old',
                'uid': 'u1',
                'contentType': 'subject',
                'contentId': 'sub-1',
                'submittedAt': '2026-01-15T00:00:00.000Z',
              },
              {
                'id': 'c-new',
                'uid': 'u1',
                'contentType': 'chapter',
                'contentId': 'ch-1',
                'submittedAt': '2026-02-15T00:00:00.000Z',
              },
            ],
          });
      final exams = await fetchMyExamPurchases('u1');
      expect(exams.map((r) => r.id).toList(), ['e-new', 'e-old']);
      final contents = await fetchMyContentPurchases('u1');
      expect(contents.map((r) => r.id).toList(), ['c-new', 'c-old']);
    });

    test('purchaseProbe parses exists/mine', () async {
      final seen = installCf((m, p) => {'exists': true, 'mine': false});
      final probe = await CfApi.purchaseProbe('content', 'c9');
      expect(seen.single.path, '/purchase-probe/content/c9');
      expect(probe.exists, isTrue);
      expect(probe.mine, isFalse);
    });
  });

  group('payments client', () {
    test('initPayment hits loksewa-api with the CF Bearer + same body',
        () async {
      Uri? seenUrl;
      String? seenAuth;
      Object? seenBody;
      GatewayPaymentService.setTestClient(MockClient((request) async {
        seenUrl = request.url;
        seenAuth = request.headers['Authorization'];
        seenBody = json.decode(request.body);
        return http.Response(
            json.encode({'ok': true, 'formUrl': 'https://x/form'}), 200);
      }));
      final res = await GatewayPaymentService.initPayment(
        gateway: 'esewa',
        purchaseType: 'subscription',
        planId: 'plan-1',
        couponCode: 'SAVE10',
      );
      expect(seenUrl.toString(),
          'https://loksewa-api.loksewa-solution-api.workers.dev/payments/init');
      expect(seenAuth, 'Bearer acc-1');
      expect(seenBody, {
        'gateway': 'esewa',
        'purchaseType': 'subscription',
        'planId': 'plan-1',
        'couponCode': 'SAVE10',
      });
      expect(res['ok'], isTrue);
    });
  });

  group('push tokens + login devices', () {
    test('registerPushToken body shape + Bearer', () async {
      final seen = installCf((m, p) => {'ok': true});
      await CfApi.registerPushToken({
        'token': 'fcm-tok-1',
        'deviceId': 'dev-1',
        'platform': 'android',
        'language': 'en',
        'courseId': 'c1',
        'subcourseId': 'sc1',
        'userName': 'Test',
        'updatedAt': '2026-10-28T00:00:00.000Z',
      });
      expect(seen.single.method, 'POST');
      expect(seen.single.path, '/push-tokens');
      expect(seen.single.auth, 'Bearer acc-1');
      final body = seen.single.body as Map;
      expect(body['token'], 'fcm-tok-1');
      expect(body['deviceId'], 'dev-1');
      expect(body['courseId'], 'c1');
    });

    test('device registration is anonymous (no Bearer)', () async {
      final seen = installCf((m, p) => {'ok': true});
      await CfApi.registerDevicePushToken(
          {'token': 'fcm-tok-2', 'deviceId': 'dev-2'});
      expect(seen.single.path, '/push-tokens/device');
      expect(seen.single.auth, isNull);
    });

    test('getLoginDevices reads /login-devices', () async {
      final seen = installCf((m, p) => {
            'items': [
              {'deviceId': 'dev-1', 'deviceModel': 'itel Vision 3'},
            ],
          });
      final rows = await CfApi.getLoginDevices();
      expect(seen.single.path, '/login-devices');
      expect(rows, hasLength(1));
      expect(rows.single['deviceModel'], 'itel Vision 3');
    });
  });
}
