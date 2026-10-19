// v1.0.110 tests: verifiedBy timeline steps, platform labels, and the
// parallelized history fetch contract.
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/subscription_service.dart';

SubscriptionRecord _rec({
  String id = 'r1',
  String method = 'esewa',
  SubscriptionStatus status = SubscriptionStatus.active,
  String? gatewayStatus = 'verified',
  String? verifiedBy,
  String? platform,
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
    screenshotUrl: '',
    gatewayStatus: gatewayStatus,
    verifiedBy: verifiedBy,
    platform: platform,
  );
}

void main() {
  setUp(() => AppLanguage.current.value = 'en');
  tearDown(() => AppLanguage.current.value = 'en');

  group('verifiedBy (v1.0.110)', () {
    test('parses from map', () {
      final r = SubscriptionRecord.fromMap({
        'id': 'x',
        'verifiedBy': 'user',
        'platform': 'app',
      });
      expect(r.verifiedBy, 'user');
      expect(r.platform, 'app');
    });

    test('defaults to null when absent', () {
      final r = SubscriptionRecord.fromMap({'id': 'x'});
      expect(r.verifiedBy, isNull);
      expect(r.platform, isNull);
    });

    test('copyWith preserves verifiedBy/platform', () {
      final r = _rec(verifiedBy: 'user', platform: 'app');
      final c = r.copyWith(status: SubscriptionStatus.expired);
      expect(c.status, SubscriptionStatus.expired);
      expect(c.verifiedBy, 'user');
      expect(c.platform, 'app');
    });
  });

  group('platformLabel (v1.0.110)', () {
    test('app + esewa', () {
      expect(_rec(method: 'esewa', platform: 'app').platformLabel,
          'App - eSewa');
    });

    test('app + khalti', () {
      expect(_rec(method: 'khalti', platform: 'app').platformLabel,
          'App - Khalti');
    });

    test('app + qr', () {
      expect(_rec(method: 'qr', platform: 'app').platformLabel,
          'App - Manual QR');
    });

    test('missing platform defaults to app', () {
      expect(_rec(method: 'esewa', platform: null).platformLabel,
          'App - eSewa');
    });

    test('web platform', () {
      expect(_rec(method: 'esewa', platform: 'web').platformLabel,
          'Web - eSewa');
    });
  });

  group('problem section pending-only (v1.0.111)', () {
    test('needsPaymentRecovery is false for ACTIVE + initiated (admin-approved bug)', () {
      final r = _rec(
        status: SubscriptionStatus.active,
        gatewayStatus: 'initiated',
      );
      expect(r.needsPaymentRecovery, isFalse);
    });

    test('needsPaymentRecovery is false for rejected/expired/cancelled + initiated', () {
      for (final s in [
        SubscriptionStatus.rejected,
        SubscriptionStatus.expired,
        SubscriptionStatus.cancelled,
      ]) {
        expect(
          _rec(status: s, gatewayStatus: 'initiated').needsPaymentRecovery,
          isFalse,
          reason: 'status $s',
        );
      }
    });

    test('needsPaymentRecovery stays true for pending + initiated', () {
      final r = _rec(
        status: SubscriptionStatus.pending,
        gatewayStatus: 'initiated',
      );
      expect(r.needsPaymentRecovery, isTrue);
    });

    test('isFraud is false once the request leaves pending', () {
      const fraud = SubscriptionRecord(
        id: 'f1',
        uid: 'u1',
        planId: 'monthly',
        planName: 'Premium Monthly',
        billingCycle: BillingCycle.monthly,
        amount: 299,
        currency: 'NPR',
        method: 'khalti',
        status: SubscriptionStatus.rejected,
        screenshotUrl: '',
        gatewayStatus: 'failed',
        failureReason: 'amount_mismatch',
      );
      expect(fraud.isFraud, isFalse);
      const pendingFraud = SubscriptionRecord(
        id: 'f2',
        uid: 'u1',
        planId: 'monthly',
        planName: 'Premium Monthly',
        billingCycle: BillingCycle.monthly,
        amount: 299,
        currency: 'NPR',
        method: 'khalti',
        status: SubscriptionStatus.pending,
        screenshotUrl: '',
        gatewayStatus: 'failed',
        failureReason: 'amount_mismatch',
      );
      expect(pendingFraud.isFraud, isTrue);
    });

    test('hasDefinitiveFailure is false once the request leaves pending', () {
      const r = SubscriptionRecord(
        id: 'd1',
        uid: 'u1',
        planId: 'monthly',
        planName: 'Premium Monthly',
        billingCycle: BillingCycle.monthly,
        amount: 299,
        currency: 'NPR',
        method: 'esewa',
        status: SubscriptionStatus.active,
        screenshotUrl: '',
        gatewayStatus: 'failed',
        failureReason: 'payment_not_completed',
      );
      expect(r.hasDefinitiveFailure, isFalse);
    });
  });
}
