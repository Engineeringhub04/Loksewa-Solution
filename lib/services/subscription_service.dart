// Subscription service — plans (with embedded feature categories),
// per-user subscription requests, and plan analytics.
//
// Mirrors src/core/firebase/services/subscription.ts (the client-side surface
// used by app/subscription/index.tsx and app/subscription/[id].tsx).
//
// Gateway model (from the React docs): the QR/manual method is ALWAYS
// available. eSewa and Khalti are each independently gated by their own
// `enabled` flag in app_subscription_settings/config. Provider secret keys
// are intentionally never read by the client.
//
// Collections:
//   app_subscription_plans/{planId}
//     id, name, billingCycle: 'monthly' | 'yearly' | 'free', price, currency,
//     durationDays, features: string[], isActive, order, colorFrom, colorTo
//   app_subscriptions/{id}
//     uid, planId, planName, billingCycle, amount, currency,
//     method: 'esewa' | 'khalti' | 'qr',
//     status: 'pending' | 'active' | 'rejected' | 'expired',
//     transactionRef, screenshotUrl, customerMessage, adminMessage,
//     submittedAt, reviewedAt, reviewedBy, rejectionReason, startDate,
//     expiryDate, couponCode, createdAt, updatedAt
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Billing cycles a plan (or request) can carry. Mirrors BillingCycle.
enum BillingCycle { monthly, yearly, free, exam }

/// Request lifecycle. Mirrors SubscriptionStatus.
enum SubscriptionStatus { pending, active, rejected, expired, cancelled }

BillingCycle billingCycleFrom(String? value) {
  switch (value) {
    case 'monthly':
      return BillingCycle.monthly;
    case 'yearly':
      return BillingCycle.yearly;
    case 'free':
      return BillingCycle.free;
    case 'exam':
      return BillingCycle.exam;
    default:
      return BillingCycle.monthly;
  }
}

SubscriptionStatus subscriptionStatusFrom(String? value) {
  switch (value) {
    case 'active':
      return SubscriptionStatus.active;
    case 'rejected':
      return SubscriptionStatus.rejected;
    case 'expired':
      return SubscriptionStatus.expired;
    case 'cancelled':
      return SubscriptionStatus.cancelled;
    default:
      return SubscriptionStatus.pending;
  }
}

/// One row of app_subscription_plans. Mirrors SubscriptionPlan.
class SubscriptionPlan {
  final String id;
  final String name;
  final BillingCycle billingCycle;
  final num price;
  final String currency;
  final int durationDays;
  final List<String> features;

  /// Embedded feature categories (v1.0.103+). Missing on old docs → empty.
  final List<PlanCategory> categories;

  /// Extra strings shown under "Also included", always ✓. Missing → empty.
  final List<String> customFeatures;

  final bool isActive;
  final num order;

  /// Gradient start/end for this plan's card — each plan gets its own colour
  /// identity. Null when Firestore has no colours for the plan.
  final String? colorFrom;
  final String? colorTo;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.billingCycle,
    required this.price,
    required this.currency,
    required this.durationDays,
    required this.features,
    this.categories = const [],
    this.customFeatures = const [],
    required this.isActive,
    required this.order,
    this.colorFrom,
    this.colorTo,
  });

  factory SubscriptionPlan.fromMap(Map<String, dynamic> m) {
    num numOf(dynamic v) => v is num ? v : num.tryParse(v.toString()) ?? 0;
    String strOf(dynamic v, [String fallback = '']) =>
        v == null ? fallback : v.toString();
    final rawFeatures = m['features'];

    List<PlanCategory> parseCategories(dynamic raw) {
      if (raw is! List) return const [];
      final cats = <PlanCategory>[];
      for (final c in raw) {
        try {
          final cm = (c as Map).cast<String, dynamic>();
          final pc = PlanCategory.fromMap(cm);
          if (pc != null) cats.add(pc);
        } catch (_) {
          // Skip malformed category entries; never crash the plan.
        }
      }
      return cats;
    }

    final rawCustom = m['customFeatures'];
    return SubscriptionPlan(
      id: strOf(m['id']),
      name: strOf(m['name'], 'Plan'),
      billingCycle: billingCycleFrom(m['billingCycle']?.toString()),
      price: numOf(m['price']),
      currency: strOf(m['currency'], 'NPR'),
      durationDays: numOf(m['durationDays']).toInt(),
      features: rawFeatures is List
          ? rawFeatures.map((e) => e.toString()).toList()
          : const [],
      categories: parseCategories(m['categories']),
      customFeatures: rawCustom is List
          ? rawCustom
              .map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList()
          : const [],
      isActive: m['isActive'] != false,
      order: numOf(m['order']),
      colorFrom: (m['colorFrom']?.toString().isNotEmpty ?? false)
          ? m['colorFrom'].toString()
          : null,
      colorTo: (m['colorTo']?.toString().isNotEmpty ?? false)
          ? m['colorTo'].toString()
          : null,
    );
  }
}

/// One row of app_subscriptions. Mirrors SubscriptionRecord.
class SubscriptionRecord {
  final String id;
  final String uid;
  final String planId;
  final String planName;
  final BillingCycle billingCycle;
  final num amount;
  final String currency;

  /// 'esewa' | 'khalti' | 'qr'
  final String method;
  final SubscriptionStatus status;
  final String? transactionRef;
  final String screenshotUrl;

  /// Optional note the user attaches when submitting.
  final String? customerMessage;

  /// Optional note the admin attaches when approving/rejecting.
  final String? adminMessage;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final DateTime? startDate;
  final DateTime? expiryDate;
  final String? couponCode;
  final String? userName;
  final String? userEmail;

  /// Gateway lifecycle for eSewa/Khalti records:
  /// 'initiated' | 'verified' | 'failed' | 'cancelled'. Null for QR/manual.
  final String? gatewayStatus;

  /// Machine reason when gatewayStatus == 'failed':
  /// 'payment_not_completed' | 'amount_mismatch' | 'duplicate' | 'app_closed'.
  final String? failureReason;

  /// Why an active subscription was expired by the worker:
  /// 'plan_change' when a newer purchase superseded it.
  final String? expiredReason;

  /// Who verified/activated this subscription:
  /// 'gateway' (automatic server verification) | 'user' (manual
  /// "Check My Payment") | 'admin' (admin panel approval).
  final String? verifiedBy;

  /// Where the payment was made: 'app' (mobile app) | 'web' (website,
  /// future). Set server-side by the worker at init.
  final String? platform;

  const SubscriptionRecord({
    required this.id,
    required this.uid,
    required this.planId,
    required this.planName,
    required this.billingCycle,
    required this.amount,
    required this.currency,
    required this.method,
    required this.status,
    this.transactionRef,
    required this.screenshotUrl,
    this.customerMessage,
    this.adminMessage,
    this.submittedAt,
    this.reviewedAt,
    this.rejectionReason,
    this.startDate,
    this.expiryDate,
    this.couponCode,
    this.userName,
    this.userEmail,
    this.gatewayStatus,
    this.failureReason,
    this.expiredReason,
    this.verifiedBy,
    this.platform,
  });

  /// Minimal copy — only status is ever patched client-side (expiry sweep).
  SubscriptionRecord copyWith({SubscriptionStatus? status}) {
    return SubscriptionRecord(
      id: id,
      uid: uid,
      planId: planId,
      planName: planName,
      billingCycle: billingCycle,
      amount: amount,
      currency: currency,
      method: method,
      status: status ?? this.status,
      transactionRef: transactionRef,
      screenshotUrl: screenshotUrl,
      customerMessage: customerMessage,
      adminMessage: adminMessage,
      submittedAt: submittedAt,
      reviewedAt: reviewedAt,
      rejectionReason: rejectionReason,
      startDate: startDate,
      expiryDate: expiryDate,
      couponCode: couponCode,
      userName: userName,
      userEmail: userEmail,
      gatewayStatus: gatewayStatus,
      failureReason: failureReason,
      expiredReason: expiredReason,
      verifiedBy: verifiedBy,
      platform: platform,
    );
  }

  factory SubscriptionRecord.fromMap(Map<String, dynamic> m) {
    num numOf(dynamic v) => v is num ? v : num.tryParse(v.toString()) ?? 0;
    String strOf(dynamic v, [String fallback = '']) =>
        v == null ? fallback : v.toString();
    String? optStr(dynamic v) {
      final s = v?.toString() ?? '';
      return s.isEmpty ? null : s;
    }

    DateTime? dt(dynamic v) => DateTime.tryParse(v.toString());
    return SubscriptionRecord(
      id: strOf(m['id']),
      uid: strOf(m['uid']),
      planId: strOf(m['planId']),
      planName: strOf(m['planName'], 'Subscription'),
      billingCycle: billingCycleFrom(m['billingCycle']?.toString()),
      amount: numOf(m['amount']),
      currency: strOf(m['currency'], 'NPR'),
      method: strOf(m['method'], 'qr'),
      status: subscriptionStatusFrom(m['status']?.toString()),
      transactionRef: optStr(m['transactionRef']),
      screenshotUrl: strOf(m['screenshotUrl']),
      customerMessage: optStr(m['customerMessage']),
      adminMessage: optStr(m['adminMessage']),
      submittedAt: m['submittedAt'] == null ? null : dt(m['submittedAt']),
      reviewedAt: m['reviewedAt'] == null ? null : dt(m['reviewedAt']),
      rejectionReason: optStr(m['rejectionReason']),
      startDate: m['startDate'] == null ? null : dt(m['startDate']),
      expiryDate: m['expiryDate'] == null ? null : dt(m['expiryDate']),
      couponCode: optStr(m['couponCode']),
      userName: optStr(m['userName']),
      userEmail: optStr(m['userEmail']),
      gatewayStatus: optStr(m['gatewayStatus']),
      failureReason: optStr(m['failureReason']),
      expiredReason: optStr(m['expiredReason']),
      verifiedBy: optStr(m['verifiedBy']),
      platform: optStr(m['platform']),
    );
  }

  /// True for gateway (automatic) payments: eSewa / Khalti.
  bool get isGateway => method == 'esewa' || method == 'khalti';

  /// Human label for where the payment was made, e.g. "App - eSewa".
  /// Platform comes from the server ('app' | 'web'); method is local.
  String get platformLabel {
    final p = (platform ?? 'app').toLowerCase();
    final prefix = p == 'web'
        ? AppLanguage.tr('Web', 'वेब')
        : AppLanguage.tr('App', 'एप');
    final methodLabel = method == 'esewa'
        ? 'eSewa'
        : method == 'khalti'
            ? 'Khalti'
            : AppLanguage.tr('Manual QR', 'म्यानुअल QR');
    return '$prefix - $methodLabel';
  }

  /// True when the gateway payment failed verification or the app was
  /// closed before verification completed (stale initiated).
  ///
  /// Pending-only: once the request leaves pending (active / rejected /
  /// expired / cancelled) the problem UI must disappear — e.g. an admin
  /// approval writes status directly without touching gatewayStatus, so
  /// keying this on gatewayStatus alone left the section visible on
  /// approved requests (v1.0.111).
  bool get isFraud =>
      status == SubscriptionStatus.pending &&
      (failureReason == 'amount_mismatch' || failureReason == 'duplicate');

  /// An initiated gateway payment with no verification after 15 minutes
  /// is treated as abandoned (app closed / user never finished).
  bool get isStaleInitiated {
    if (gatewayStatus != 'initiated') return false;
    final submitted = submittedAt;
    if (submitted == null) return true;
    return DateTime.now().difference(submitted).inMinutes >= 15;
  }

  /// Shows the "Payment Problem" recovery section with the
  /// "Check My Payment" button.
  ///
  /// User rule: the button appears for EVERY initiated gateway payment,
  /// fresh or stale — the 15-minute rule is ONLY the gateway payment
  /// window / sweep auto-delete timer, never a UI gate. A payment whose
  /// money arrived must be recoverable immediately, with no waiting.
  /// Definitive failures (failureReason == 'payment_not_completed') get a
  /// plain "no money was charged" notice instead — no button. Fraud cases
  /// (amount_mismatch / duplicate) keep their admin-only message.
  ///
  /// Pending-only (v1.0.111): active / rejected / expired / cancelled
  /// requests never show the section, even when gatewayStatus is still
  /// 'initiated' (admin approvals don't touch gatewayStatus).
  bool get needsPaymentRecovery =>
      isGateway &&
      status == SubscriptionStatus.pending &&
      gatewayStatus == 'initiated';

  /// True when the gateway definitively reported no money arrived.
  /// Pending-only, like the rest of the problem UI.
  bool get hasDefinitiveFailure =>
      isGateway &&
      status == SubscriptionStatus.pending &&
      gatewayStatus == 'failed' &&
      failureReason == 'payment_not_completed' &&
      !isFraud;
}

// ===================== Plan feature catalogue =====================
//
// Admin-managed in Firestore:
//   app_plan_feature_categories/{key}
//     key, icon, titleEn, titleNe, order, isActive
//   app_plan_feature_categories/{key}/features/{featureId}
//     en (== the exact string stored in plan `features`), ne, order, isActive
//
// The catalogue supplies structure, order and the Nepali wording
// (presentation); the plan's own `features: string[]` in Firestore is the
// DATA MODEL (v1.0.103): plans carry their feature categories EMBEDDED.
// app_subscription_plans/{planId}:
//   categories: [{key, titleEn, titleNe, icon, order,
//                 features: [{id, en, ne, order, included}]}]
//   customFeatures: [string] — extras shown under "Also included", always ✓.
// The old app_plan_feature_categories collection is retired and never read.
// The legacy `features[]` array is IGNORED (the admin keeps it stale).

/// One feature embedded on a plan document's category. `included` is the
/// ✓/✗ truth — there is no catalogue to match against anymore.
class PlanFeature {
  final String id;
  final String en;
  final String ne;
  final num order;
  final bool included;

  const PlanFeature({
    required this.id,
    required this.en,
    required this.ne,
    required this.order,
    required this.included,
  });

  /// Null when the entry is malformed (missing/empty id) — callers skip it.
  static PlanFeature? fromMap(Map<String, dynamic> m) {
    final id = (m['id'] ?? '').toString();
    if (id.isEmpty) return null;
    num orderOf(dynamic v) => v is num ? v : num.tryParse(v.toString()) ?? 0;
    return PlanFeature(
      id: id,
      en: (m['en'] ?? id).toString(),
      ne: (m['ne'] ?? '').toString(),
      order: orderOf(m['order']),
      included: m['included'] != false,
    );
  }
}

/// One feature category embedded on a plan document. The admin edits these
/// per plan; a deleted category simply stops being fetched, so it stops
/// being shown — no hide lists, no scoping.
class PlanCategory {
  final String key;
  final String titleEn;
  final String titleNe;
  final String icon;
  final num order;
  final List<PlanFeature> features;

  const PlanCategory({
    required this.key,
    required this.titleEn,
    required this.titleNe,
    required this.icon,
    required this.order,
    required this.features,
  });

  /// Null when the entry is malformed (missing/empty key) — callers skip it.
  static PlanCategory? fromMap(Map<String, dynamic> m) {
    final key = (m['key'] ?? '').toString();
    if (key.isEmpty) return null;
    num orderOf(dynamic v) => v is num ? v : num.tryParse(v.toString()) ?? 0;
    final features = <PlanFeature>[];
    final rawFeatures = m['features'];
    if (rawFeatures is List) {
      for (final f in rawFeatures) {
        try {
          final fm = (f as Map).cast<String, dynamic>();
          final pf = PlanFeature.fromMap(fm);
          if (pf != null) features.add(pf);
        } catch (_) {
          // Skip malformed feature entries; never crash the plan.
        }
      }
    }
    features.sort((a, b) => a.order.compareTo(b.order));
    return PlanCategory(
      key: key,
      titleEn: (m['titleEn'] ?? key).toString(),
      titleNe: (m['titleNe'] ?? '').toString(),
      icon: (m['icon'] ?? '').toString(),
      order: orderOf(m['order']),
      features: features,
    );
  }
}

// ===================== Feature matrix =====================

/// One rendered matrix row: a catalogue feature marked included/excluded.
class FeatureMatrixRow {
  final String id;
  final String label;
  final bool included;
  const FeatureMatrixRow({
    required this.id,
    required this.label,
    required this.included,
  });
}

/// One rendered matrix group.
class FeatureMatrixGroup {
  final String key;
  final String icon;
  final String titleEn;
  final String titleNe;
  final List<FeatureMatrixRow> rows;
  const FeatureMatrixGroup({
    required this.key,
    required this.icon,
    required this.titleEn,
    required this.titleNe,
    required this.rows,
  });

  int get includedCount => rows.where((r) => r.included).length;
}

/// Builds the grouped matrix for one plan from its EMBEDDED categories.
/// Categories are rendered in `order`; each feature's ✓/✗ comes from its
/// `included` flag. [customFeatures] (non-empty only) are appended as a
/// trailing "Also included" group, all ✓.
List<FeatureMatrixGroup> buildFeatureMatrix({
  required List<PlanCategory> categories,
  required List<String> customFeatures,
  required bool isNepali,
}) {
  final groups = <FeatureMatrixGroup>[];
  final cats = categories.toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  for (final cat in cats) {
    groups.add(FeatureMatrixGroup(
      key: cat.key,
      icon: cat.icon,
      titleEn: cat.titleEn,
      titleNe: cat.titleNe,
      rows: [
        for (final f in cat.features)
          FeatureMatrixRow(
            id: f.id,
            label: isNepali && f.ne.isNotEmpty ? f.ne : f.en,
            included: f.included,
          ),
      ],
    ));
  }
  if (customFeatures.isNotEmpty) {
    groups.add(FeatureMatrixGroup(
      key: 'extras',
      icon: 'extras',
      titleEn: 'Also included',
      titleNe: 'थप समावेश',
      rows: [
        for (final f in customFeatures)
          FeatureMatrixRow(id: f, label: f, included: true),
      ],
    ));
  }
  return groups;
}

// ===================== Service =====================

int _cmpDesc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

class SubscriptionService {
  /// Active plans, ordered by `order`. Mirrors fetchSubscriptionPlans().
  static Future<List<SubscriptionPlan>> fetchSubscriptionPlans() async {
    final token = await AuthService.getValidIdToken();
    final docs = await FirestoreRest.listDocuments(
      'app_subscription_plans',
      idToken: token,
      pageSize: 100,
    );
    final plans = docs
        .map(SubscriptionPlan.fromMap)
        .where((p) => p.isActive)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return plans;
  }

  /// All of the current user's subscription requests, newest first.
  /// Per-user index: rules deny LIST queries on app_subscriptions for
  /// non-admins (resource.data is unavailable on lists), so the user's
  /// subscription IDs are read from their own doc and each is fetched
  /// with getDocument (which the rules allow for the owner).
  static Future<List<SubscriptionRecord>> fetchMySubscriptionHistory(
      String uid) async {
    final token = await AuthService.getValidIdToken();
    final userDoc = await FirestoreRest.getDocument('users/$uid', idToken: token);
    final ids = <String>[
      for (final e in (userDoc?['subscriptionIds'] as List? ?? [])) e.toString(),
    ];
    if (ids.isEmpty) return [];
    // v1.0.110: fetch the per-doc records IN PARALLEL (was a sequential
    // for-loop — N round trips on the itel). Failures are skipped per-doc.
    final docs = await Future.wait(
      ids.map((sid) => FirestoreRest.getDocument('app_subscriptions/$sid',
              idToken: token)
          .then((doc) => doc == null
              ? null
              : SubscriptionRecord.fromMap(doc))
          .catchError((_) => null)),
    );
    final records = docs.whereType<SubscriptionRecord>().toList();
    records.sort((a, b) => _cmpDesc(a.submittedAt, b.submittedAt));
    return filterHistoryForDisplay(records);
  }

  /// Display filter for the Your-Request list.
  ///
  /// User rule: a gateway payment is a real, visible request from the
  /// moment it is initiated — this list is the recovery entry point for
  /// app-closed payments. The ONLY gateway records hidden here are
  /// cancelled ones (user backed out / no money arrived); those are
  /// deleted server-side and must never show. Manual (QR) requests keep
  /// their existing visibility.
  static List<SubscriptionRecord> filterHistoryForDisplay(
      List<SubscriptionRecord> records) {
    return records
        .where((r) =>
            !(r.isGateway && r.status == SubscriptionStatus.cancelled))
        .toList();
  }

  /// The current user's most relevant subscription record (active, else
  /// latest by submission). Mirrors fetchMySubscription().
  static Future<SubscriptionRecord?> fetchMySubscription(String uid) async {
    final history = await fetchMySubscriptionHistory(uid);
    if (history.isEmpty) return null;
    final current = currentActiveRecord(history);
    if (current != null) return current;
    return history.first;
  }

  /// The ACTIVE record the users/{uid} premium mirror describes.
  ///
  /// Approving a request never retires previously-active records, so several
  /// `status == 'active'` records can coexist (out-of-order or concurrent
  /// approvals, re-approvals). The mirror (isPremium / premiumPlanName /
  /// premiumBillingCycle / premiumExpiryDate) is written atomically with
  /// each approval, so it always describes the LAST-APPROVED request — which
  /// is also what every premium gate and the profile plan pill read. Picking
  /// the active record with the latest approval (startDate, else reviewedAt,
  /// else submittedAt) keeps this page's hero and "currently active" plan
  /// card on that same record, instead of on whichever active request was
  /// submitted most recently (the old first-active-by-submittedAt pick that
  /// disagreed with the profile page).
  static SubscriptionRecord? currentActiveRecord(
      List<SubscriptionRecord> records) {
    SubscriptionRecord? best;
    DateTime? bestTime;
    for (final r in records) {
      if (r.status != SubscriptionStatus.active) continue;
      final t = r.startDate ?? r.reviewedAt ?? r.submittedAt;
      if (best == null ||
          (t != null && (bestTime == null || t.isAfter(bestTime)))) {
        best = r;
        bestTime = t;
      }
    }
    return best;
  }

  /// Sweeps expired active subscriptions and re-derives the users/{uid}
  /// premium mirror from whatever is still valid. Called opportunistically
  /// from the Subscription page's load. Mirrors expireIfPastDue().
  ///
  /// Multiple `status == 'active'` records can coexist (approvals never
  /// retire the previous one), so this expires EVERY past-due active — not
  /// just the first one found — and then mirrors the last-approved remaining
  /// active (the same record [currentActiveRecord] picks, and the one the
  /// profile pill reads through the user doc). With no valid active left,
  /// the premium flag is cleared. When nothing is past due, nothing is
  /// written.
  /// Returns the IDs it expired (so callers can patch an already-fetched
  /// list instead of re-reading).
  static Future<List<String>> expireIfPastDue(String uid,
      {List<SubscriptionRecord>? history}) async {
    // v1.0.110: accept pre-fetched history to avoid a second N+1 fetch
    // (the Subscription page already loads it in the same pass).
    final records = history ?? await fetchMySubscriptionHistory(uid);
    if (records.isEmpty) return const [];
    final now = DateTime.now();
    final expiredIds = <String>[];
    for (final r in records) {
      if (r.status != SubscriptionStatus.active) continue;
      final expiry = r.expiryDate;
      if (expiry != null && !expiry.isAfter(now)) expiredIds.add(r.id);
    }
    if (expiredIds.isEmpty) return const [];
    final remaining = records
        .where((r) =>
            r.status == SubscriptionStatus.active &&
            !expiredIds.contains(r.id))
        .toList();
    final current = currentActiveRecord(remaining);
    final token = await AuthService.getValidIdToken();
    await FirestoreRest.commitWrites(
      [
        for (final id in expiredIds)
          FirestoreWrite(
            'app_subscriptions/$id',
            {
              'status': 'expired',
              'updatedAt': FirestoreRest.serverTimestamp(),
            },
            merge: true,
          ),
        if (current != null)
          FirestoreWrite(
            'users/$uid',
            {
              'isPremium': true,
              'premiumPlanName': current.planName,
              'premiumBillingCycle': current.billingCycle.name,
              'premiumExpiryDate': current.expiryDate?.toIso8601String(),
              'updatedAt': FirestoreRest.serverTimestamp(),
            },
            merge: true,
          )
        else
          FirestoreWrite(
            'users/$uid',
            {
              'isPremium': false,
              'updatedAt': FirestoreRest.serverTimestamp(),
            },
            merge: true,
          ),
      ],
      idToken: token,
    );
    return expiredIds;
  }

  /// One request by id. Mirrors fetchSubscriptionById().
  static Future<SubscriptionRecord?> fetchSubscriptionById(String id) async {
    final token = await AuthService.getValidIdToken();
    final doc =
        await FirestoreRest.getDocument('app_subscriptions/$id', idToken: token);
    if (doc == null) return null;
    return SubscriptionRecord.fromMap(doc);
  }

  /// Lets the signed-in owner correct their own payment reference, receipt
  /// URL, or customer note. Mirrors updateMySubscriptionDetails().
  static Future<void> updateMySubscriptionDetails(
    String id, {
    required String transactionRef,
    required String screenshotUrl,
    String? customerMessage,
  }) async {
    final token = await AuthService.getValidIdToken();
    await FirestoreRest.setDocument(
      'app_subscriptions/$id',
      {
        'transactionRef': transactionRef,
        'screenshotUrl': screenshotUrl,
        'customerMessage': customerMessage,
        'updatedAt': FirestoreRest.serverTimestamp(),
      },
      merge: true,
      idToken: token,
    );
  }

  /// Yearly's discount against paying monthly for twelve months, computed
  /// from the two live plans rather than stored — so it can never contradict
  /// the prices printed beside it. Mirrors the yearlySavePercent useMemo.
  static int? yearlySavePercent(List<SubscriptionPlan> plans) {
    SubscriptionPlan? monthly;
    SubscriptionPlan? yearly;
    for (final plan in plans) {
      if (plan.billingCycle == BillingCycle.monthly) monthly ??= plan;
      if (plan.billingCycle == BillingCycle.yearly) yearly ??= plan;
    }
    if (monthly == null || yearly == null) return null;
    final m = monthly.price;
    final y = yearly.price;
    if (m <= 0 || y <= 0) return null;
    final twelve = m * 12;
    if (twelve <= y) return null;
    return (((twelve - y) / twelve) * 100).round();
  }
}
