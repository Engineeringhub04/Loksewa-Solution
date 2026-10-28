// Coupon code validation + usage increment.
//
// Mirrors `validateCoupon` and `incrementCouponUsage` in
// `src/core/firebase/services/subscription.ts`.
//
// app_coupon_codes/{code}
//   code, discountType: 'percent' | 'flat', discountValue, maxUses, usedCount,
//   validFrom, validUntil (ISO datetime, may include time), isActive,
//   appliesToBillingCycle: 'monthly'|'yearly'|'all' (legacy),
//   applicableTo: string[] ('subscription'|'subject'|'chapter'|'exam'),
//   courseIds, subcourseIds: string[] ([] = all; legacy courseId/subcourseId
//   string still honored when the arrays are absent),
//   subjectIds, chapterIds, examModelIds: string[] ([] = all),
//   userIds: string[] ([] = all users),
//   minPurchaseAmount: number (0/absent = no minimum),
//   maxUsesPerUser: number (0/absent = unlimited per user),
//   firstTimeOnly: boolean,
//   examTiers: string[] (e.g. ['pro'] or ['pro','free'])
//
// Per-user usage is tracked in app_coupon_usages/{CODE}_{uid} {count}.
//
// Phase-5: validation state (coupon doc + per-user usage + first-buyer
// history) is fetched in ONE POST /coupons/validate — the scope rules
// themselves still run locally in [CouponService.validateCouponData],
// the single source of truth for reasons + discount math. Redemption
// (usage-row creation + usedCount increment) is POST /coupons/redeem,
// one atomic server operation replacing the two raw Firestore `:commit`
// calls this file used to make.
import 'package:loksewa_solution/services/cf_api.dart';

/// Billing-cycle categories `validateCoupon` understands. 'exam' is the
/// checkout-only category used for exam-set and content purchases.
///
/// New scoping fields (written by the admin panel to `app_coupon_codes/{code}`):
/// - `applicableTo`: string[] — purchase types this coupon covers
///   ('subscription' | 'subject' | 'chapter' | 'exam'). When missing/empty,
///   the legacy `appliesToBillingCycle` check is used instead.
/// - `courseIds`/`subcourseIds`: string[] ([] = all courses/sub-courses);
///   the legacy `courseId`/`subcourseId` string is honored as a single-item
///   list when the array is absent.
/// - `subjectIds`/`chapterIds`/`examModelIds`: string[] ([] = all).
/// - `userIds`: string[] ([] = all users).
/// - `validFrom`/`validUntil`: ISO datetime strings (may include time).
/// - `minPurchaseAmount`: number (0/absent = no minimum).
/// - `maxUsesPerUser`: number (0/absent = unlimited per user); usage tracked
///   in `app_coupon_usages/{CODE}_{uid}` (read fail-open).
/// - `firstTimeOnly`: boolean — coupon requires no prior purchase history
///   (checked via users/{uid} subscriptionIds/contentPurchaseIds/
///   examPurchaseIds; read fail-open treats the user as first-time).
/// - `examTiers`: string[] — exam purchase tiers this coupon covers
///   ('pro' | 'free'); enforced only when the caller passes `examTier`.
class CouponService {
  /// Validates [rawCode] against `app_coupon_codes` for [billingCycle] and
  /// [originalAmount]. The optional named params describe the purchase being
  /// made so the new scope fields can be enforced; omit them (or pass null)
  /// and only the legacy checks run. Returns (valid, discountedAmount,
  /// discountLabel, reason) — mirrors `CouponValidationResult`.
  static Future<CouponValidationResult> validateCoupon(
    String rawCode,
    String billingCycle,
    num originalAmount, {
    String? purchaseType, // 'subscription' | 'subject' | 'chapter' | 'exam'
    String? contentId, // subject/chapter/exam ID being purchased
    String? courseId,
    String? subcourseId,
    String? uid,
    String? examTier, // 'pro' | 'free' — the exam set's tier, if known
  }) async {
    final code = rawCode.trim().toUpperCase();
    // One round trip: the server reads the coupon doc, the per-user
    // usage row and the buyer's purchase history (three collections the
    // client can no longer read) and returns them together.
    final body = await CfApi.validateCoupon({
      'code': code,
      'billingCycle': billingCycle,
      'originalAmount': originalAmount,
      if (purchaseType != null) 'purchaseType': purchaseType,
      if (contentId != null) 'contentId': contentId,
      if (courseId != null) 'courseId': courseId,
      if (subcourseId != null) 'subcourseId': subcourseId,
      if (examTier != null) 'examTier': examTier,
    });
    // A finished verdict ({valid, ...} with no coupon row attached) is
    // used as-is.
    final rawCoupon = body['coupon'];
    final coupon = rawCoupon is Map
        ? rawCoupon.cast<String, dynamic>()
        : (body.containsKey('discountType') ||
                body.containsKey('isActive') ||
                body.containsKey('code')
            ? body
            : null);
    if (coupon == null) {
      if (body.containsKey('valid')) {
        return CouponValidationResult(
          valid: body['valid'] == true,
          discountedAmount: _asNumOrNull(body['discountedAmount']),
          discountLabel: body['discountLabel']?.toString(),
          reason: body['reason']?.toString(),
        );
      }
      return const CouponValidationResult(
          valid: false, reason: 'Coupon code not found');
    }
    // Per-user state computed server-side — fail-open like the old
    // client reads: absent values skip those checks entirely.
    final perUserUsedCount = body['perUserUsedCount'] is num
        ? (body['perUserUsedCount'] as num).toInt()
        : (body['perUserUsedCount'] != null
            ? int.tryParse('${body['perUserUsedCount']}')
            : null);
    final isFirstTimeBuyer =
        body['isFirstTimeBuyer'] is bool ? body['isFirstTimeBuyer'] as bool : null;
    return validateCouponData(
      CfApi.normalizeRow(coupon),
      billingCycle,
      originalAmount,
      purchaseType: purchaseType,
      contentId: contentId,
      courseId: courseId,
      subcourseId: subcourseId,
      uid: uid,
      perUserUsedCount: perUserUsedCount,
      isFirstTimeBuyer: isFirstTimeBuyer,
      examTier: examTier,
    );
  }

  /// Pure (sync, testable) validation of an already-fetched coupon doc.
  /// See [validateCoupon] for the field contract. [perUserUsedCount] and
  /// [isFirstTimeBuyer] carry the async per-user lookups done by
  /// [validateCoupon]; pass null to skip those checks.
  static CouponValidationResult validateCouponData(
    Map<String, dynamic> coupon,
    String billingCycle,
    num originalAmount, {
    String? purchaseType, // 'subscription' | 'subject' | 'chapter' | 'exam'
    String? contentId, // subject/chapter/exam ID being purchased
    String? courseId,
    String? subcourseId,
    String? uid,
    int? perUserUsedCount,
    bool? isFirstTimeBuyer,
    String? examTier, // 'pro' | 'free'
  }) {
    if (coupon['isActive'] != true) {
      return const CouponValidationResult(
          valid: false, reason: 'This coupon is no longer active');
    }
    // 1. User scope — a non-empty userIds list restricts the coupon to
    // those users only.
    final userIds = _asStringList(coupon['userIds']);
    if (userIds.isNotEmpty &&
        (uid == null || uid.isEmpty || !userIds.contains(uid))) {
      return const CouponValidationResult(
          valid: false,
          reason: 'This coupon is not available for your account');
    }
    // 2. Applicability — new `applicableTo` wins; otherwise the legacy
    // `appliesToBillingCycle` check keeps old coupons working.
    final applicableTo = _asStringList(coupon['applicableTo']);
    if (applicableTo.isNotEmpty) {
      if (purchaseType != null &&
          purchaseType.isNotEmpty &&
          !applicableTo.contains(purchaseType)) {
        return const CouponValidationResult(
            valid: false,
            reason: 'This coupon cannot be used for this purchase');
      }
    } else {
      final appliesTo = '${coupon['appliesToBillingCycle'] ?? 'all'}';
      final appliesToExam = billingCycle == 'exam' && appliesTo == 'all';
      if (!appliesToExam && appliesTo != 'all' && appliesTo != billingCycle) {
        return const CouponValidationResult(
            valid: false,
            reason: 'This coupon does not apply to the selected plan');
      }
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
    // 3. Content scope — only enforced when the caller passed purchaseType.
    if (purchaseType == 'subject') {
      final subjectIds = _asStringList(coupon['subjectIds']);
      if (subjectIds.isNotEmpty &&
          (contentId == null || !subjectIds.contains(contentId))) {
        return const CouponValidationResult(
            valid: false,
            reason: 'This coupon does not apply to this subject');
      }
      final allowedCourses = _scopedIds(coupon, 'courseIds', 'courseId');
      if (allowedCourses.isNotEmpty &&
          !allowedCourses.contains(courseId ?? '')) {
        return const CouponValidationResult(
            valid: false, reason: 'This coupon does not apply to this course');
      }
      final allowedSubcourses =
          _scopedIds(coupon, 'subcourseIds', 'subcourseId');
      if (allowedSubcourses.isNotEmpty &&
          !allowedSubcourses.contains(subcourseId ?? '')) {
        return const CouponValidationResult(
            valid: false,
            reason: 'This coupon does not apply to this sub-course');
      }
    } else if (purchaseType == 'chapter') {
      final chapterIds = _asStringList(coupon['chapterIds']);
      if (chapterIds.isNotEmpty &&
          (contentId == null || !chapterIds.contains(contentId))) {
        return const CouponValidationResult(
            valid: false,
            reason: 'This coupon does not apply to this chapter');
      }
    } else if (purchaseType == 'exam') {
      final examIds = _asStringList(coupon['examModelIds']);
      if (examIds.isNotEmpty &&
          (contentId == null || !examIds.contains(contentId))) {
        return const CouponValidationResult(
            valid: false, reason: 'This coupon does not apply to this exam');
      }
    }
    // 4. Minimum purchase amount.
    final minAmt = _asNum(coupon['minPurchaseAmount']);
    if (minAmt > 0 && originalAmount < minAmt) {
      return CouponValidationResult(
          valid: false,
          reason:
              'This coupon requires a minimum purchase of Rs. ${_numLabel(minAmt)}');
    }
    // 5. Per-user usage limit.
    final maxPerUser = _asInt(coupon['maxUsesPerUser']);
    if (maxPerUser > 0 &&
        perUserUsedCount != null &&
        perUserUsedCount >= maxPerUser) {
      return const CouponValidationResult(
          valid: false,
          reason:
              'You have already used this coupon the maximum number of times');
    }
    // 6. First-time buyers only.
    if (coupon['firstTimeOnly'] == true && isFirstTimeBuyer == false) {
      return const CouponValidationResult(
          valid: false, reason: 'This coupon is for first-time buyers only');
    }
    // 7. Exam tier — enforced only when the caller knows the exam's tier.
    if (purchaseType == 'exam') {
      final tiers = _asStringList(coupon['examTiers']);
      if (tiers.isNotEmpty &&
          examTier != null &&
          examTier.isNotEmpty &&
          !tiers.contains(examTier)) {
        return const CouponValidationResult(
            valid: false,
            reason: 'This coupon does not apply to this exam type');
      }
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

  /// Redeems [code] at checkout submit time: POST /coupons/redeem
  /// creates the per-user usage row AND increments the code's
  /// `usedCount` in one atomic server operation (the pair of raw
  /// Firestore `:commit` calls this replaces). Call ONCE per successful
  /// submit. Best-effort like the React original (swallows failures).
  static Future<void> incrementCouponUsage(String code,
      {String? planId, String? userId}) async {
    try {
      await CfApi.redeemCoupon({
        'code': code.trim().toUpperCase(),
        if (planId != null && planId.isNotEmpty) 'planId': planId,
        if (userId != null && userId.isNotEmpty) 'userId': userId,
      });
    } catch (_) {
      // Coupon may not exist / no-code path — nothing to redeem.
    }
  }

  /// Legacy companion of [incrementCouponUsage]: the per-user half of
  /// the redemption. POST /coupons/redeem performs BOTH halves in one
  /// call, so this now delegates to the same single redeem — callers
  /// must invoke only ONE of the two per submit (the checkout calls
  /// [incrementCouponUsage] only). [uid] is accepted for signature
  /// compatibility; the server derives the user from the Bearer.
  /// Best-effort (swallows failures).
  static Future<void> incrementCouponUsageForUser(
      String code, String uid) async {
    await incrementCouponUsage(code);
  }

  static List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => '$e').where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  /// New array field (e.g. `courseIds`) wins; falls back to the legacy
  /// single string field (e.g. `courseId`). Empty/absent = all.
  static List<String> _scopedIds(
      Map<String, dynamic> coupon, String listKey, String legacyKey) {
    final list = _asStringList(coupon[listKey]);
    if (list.isNotEmpty) return list;
    final legacy = '${coupon[legacyKey] ?? ''}';
    return legacy.isNotEmpty ? [legacy] : const [];
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

  static num? _asNumOrNull(dynamic v) {
    if (v is num) return v;
    return num.tryParse('$v');
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
