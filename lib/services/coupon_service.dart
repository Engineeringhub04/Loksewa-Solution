// Coupon code validation + usage increment.
//
// Mirrors `validateCoupon` and `incrementCouponUsage` in
// `src/core/firebase/services/subscription.ts`.
//
// app_coupon_codes/{code}
//   code, discountType: 'percent' | 'flat', discountValue, maxUses, usedCount,
//   validFrom, validUntil, isActive, appliesToBillingCycle: 'monthly'|'yearly'|'all'
//
// The usage increment uses a Firestore `:commit` field transform
// (`increment`), the same atomic operation the React `increment(1)` performs —
// never a read-then-write.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:loksewa_solution/services/app_config.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Billing-cycle categories `validateCoupon` understands. 'exam' is the
/// checkout-only category used for exam-set and content purchases.
class CouponService {
  /// Validates [rawCode] against `app_coupon_codes` for [billingCycle] and
  /// [originalAmount]. Returns (valid, discountedAmount, discountLabel,
  /// reason) — mirrors `CouponValidationResult`.
  static Future<CouponValidationResult> validateCoupon(
    String rawCode,
    String billingCycle,
    num originalAmount,
  ) async {
    final code = rawCode.trim().toUpperCase();
    final token = await AuthService.getValidIdToken();
    final coupon = await FirestoreRest.getDocument('app_coupon_codes/$code',
        idToken: token);
    if (coupon == null) {
      return const CouponValidationResult(
          valid: false, reason: 'Coupon code not found');
    }
    if (coupon['isActive'] != true) {
      return const CouponValidationResult(
          valid: false, reason: 'This coupon is no longer active');
    }
    final appliesTo = '${coupon['appliesToBillingCycle'] ?? 'all'}';
    final appliesToExam = billingCycle == 'exam' && appliesTo == 'all';
    if (!appliesToExam && appliesTo != 'all' && appliesTo != billingCycle) {
      return const CouponValidationResult(
          valid: false, reason: 'This coupon does not apply to the selected plan');
    }
    final maxUses = _asInt(coupon['maxUses']);
    final usedCount = _asInt(coupon['usedCount']);
    if (maxUses > 0 && usedCount >= maxUses) {
      return const CouponValidationResult(
          valid: false, reason: 'This coupon has reached its usage limit');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final validFrom = _asMillis(coupon['validFrom']);
    if (validFrom != null && now < validFrom) {
      return const CouponValidationResult(
          valid: false, reason: 'This coupon is not active yet');
    }
    final validUntil = _asMillis(coupon['validUntil']);
    if (validUntil != null && now > validUntil) {
      return const CouponValidationResult(
          valid: false, reason: 'This coupon has expired');
    }

    final discountType = '${coupon['discountType'] ?? ''}';
    final discountValue = _asNum(coupon['discountValue']);
    num discountedAmount;
    String discountLabel;
    if (discountType == 'percent') {
      discountedAmount = _maxNum(
          0, (originalAmount * (1 - discountValue / 100)).round());
      discountLabel = '${_numLabel(discountValue)}% off';
    } else {
      discountedAmount = _maxNum(0, originalAmount - discountValue);
      discountLabel = 'Rs. ${_numLabel(discountValue)} off';
    }
    return CouponValidationResult(
      valid: true,
      discountedAmount: discountedAmount,
      discountLabel: discountLabel,
    );
  }

  /// Atomically increments `usedCount` on `app_coupon_codes/{code}`.
  /// Best-effort like the React original (swallows failures).
  static Future<void> incrementCouponUsage(String code) async {
    try {
      final token = await AuthService.getValidIdToken();
      const base =
          'https://firestore.googleapis.com/v1/projects/${AppConfig.firebaseProjectId}/databases/(default)/documents';
      final res = await http.post(
        Uri.parse('$base:commit'),
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'writes': [
            {
              'update': {
                'name': '$base/app_coupon_codes/${code.toUpperCase()}',
              },
              'updateTransforms': [
                {
                  'fieldPath': 'usedCount',
                  'increment': {'integerValue': '1'},
                },
              ],
            },
          ],
        }),
      );
      if (res.statusCode != 200) throw Exception('increment failed');
    } catch (_) {
      // Coupon may not exist / no-code path — nothing to increment.
    }
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static num _asNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse('$v') ?? 0;
  }

  static num _maxNum(num a, num b) => a > b ? a : b;

  static int? _asMillis(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    final dt = DateTime.tryParse('$v');
    return dt?.millisecondsSinceEpoch;
  }

  static String _numLabel(num v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();
}

class CouponValidationResult {
  final bool valid;
  final num? discountedAmount;
  final String? discountLabel;
  final String? reason;
  const CouponValidationResult({
    required this.valid,
    this.discountedAmount,
    this.discountLabel,
    this.reason,
  });
}
