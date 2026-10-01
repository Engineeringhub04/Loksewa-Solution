// Subscription service — plans, per-user subscription requests, and the
// plan feature catalogue.
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
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Billing cycles a plan (or request) can carry. Mirrors BillingCycle.
enum BillingCycle { monthly, yearly, free, exam }

/// Request lifecycle. Mirrors SubscriptionStatus.
enum SubscriptionStatus { pending, active, rejected, expired }

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
  });

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
    );
  }
}

// ===================== Plan feature catalogue =====================
//
// Mirrors PLAN_FEATURE_GROUPS in subscription.ts. The catalogue supplies
// structure, order and the Nepali wording (presentation); the plan's own
// `features: string[]` in Firestore is the source of truth for what a given
// plan includes. A feature is "included" iff its id appears in that array.
//
// IDENTITY: a feature's `id` IS the exact string stored in Firestore.
// Changing an id is a data migration, not a rename.

/// One catalogue feature. `id` is the exact string stored on the plan
/// document; `ne` is the Nepali label shown when the app language is Nepali.
class PlanFeature {
  final String id;
  final String ne;
  const PlanFeature(this.id, this.ne);
}

/// One catalogue group. `icon` is a key mapped to an IconData by the UI.
class PlanFeatureGroup {
  final String key;
  final String icon;
  final String titleEn;
  final String titleNe;
  final List<PlanFeature> features;
  const PlanFeatureGroup({
    required this.key,
    required this.icon,
    required this.titleEn,
    required this.titleNe,
    required this.features,
  });
}

/// Everything the app ships, grouped the way a person would shop for it.
/// Mirrors PLAN_FEATURE_GROUPS exactly.
const List<PlanFeatureGroup> planFeatureGroups = [
  PlanFeatureGroup(
    key: 'learning',
    icon: 'library',
    titleEn: 'Learning & Content',
    titleNe: 'अध्ययन तथा सामग्री',
    features: [
      PlanFeature('All subjects, units & chapters', 'सबै विषय, एकाइ र अध्याय'),
      PlanFeature('Syllabus & study notes library', 'पाठ्यक्रम तथा नोट्स संग्रह'),
      PlanFeature('Constitution & legal reference', 'संविधान तथा कानुनी सन्दर्भ'),
      PlanFeature('Gorkhapatra daily edition', 'गोरखापत्र दैनिक संस्करण'),
      PlanFeature('Notices & exam updates', 'सूचना तथा परीक्षा अपडेट'),
      PlanFeature('Downloadable PDF materials', 'डाउनलोड गर्न मिल्ने PDF सामग्री'),
    ],
  ),
  PlanFeatureGroup(
    key: 'practice',
    icon: 'practice',
    titleEn: 'Practice & Exams',
    titleNe: 'अभ्यास तथा परीक्षा',
    features: [
      PlanFeature('Daily practice questions', 'दैनिक अभ्यास प्रश्नहरू'),
      PlanFeature('Question of the Day', 'आजको प्रश्न'),
      PlanFeature('Daily Test full access', 'दैनिक परीक्षामा पूर्ण पहुँच'),
      PlanFeature('Unlimited mock exams & model sets', 'असीमित मक परीक्षा तथा मोडेल सेट'),
      PlanFeature('Past year question papers', 'विगत वर्षका प्रश्नपत्रहरू'),
      PlanFeature('Instant results with answer review', 'तत्काल नतिजा र उत्तर समीक्षा'),
      PlanFeature('Theory answer submission & review', 'सैद्धान्तिक उत्तर पेस तथा समीक्षा'),
    ],
  ),
  PlanFeatureGroup(
    key: 'progress',
    icon: 'progress',
    titleEn: 'Progress & Analytics',
    titleNe: 'प्रगति तथा विश्लेषण',
    features: [
      PlanFeature('Bookmarks & reading history', 'बुकमार्क तथा पढाइ इतिहास'),
      PlanFeature('Leaderboard & exam rankings', 'लिडरबोर्ड तथा परीक्षा र्‍यांकिङ'),
      PlanFeature('Performance analytics & charts', 'प्रदर्शन विश्लेषण तथा चार्टहरू'),
      PlanFeature('Exam history & progress report', 'परीक्षा इतिहास तथा प्रगति प्रतिवेदन'),
      PlanFeature('Streaks, milestones & coverage', 'स्ट्रिक, माइलस्टोन तथा कभरेज'),
      PlanFeature('Strength & weakness insights', 'बलियो तथा कमजोर पक्षको विश्लेषण'),
    ],
  ),
  PlanFeatureGroup(
    key: 'community',
    icon: 'community',
    titleEn: 'Community & Support',
    titleNe: 'समुदाय तथा सहयोग',
    features: [
      PlanFeature('Discussion community access', 'छलफल समुदायमा पहुँच'),
      PlanFeature('Ask questions & post answers', 'प्रश्न सोध्ने तथा उत्तर दिने'),
      PlanFeature('Verified premium badge & ring', 'भेरिफाइड प्रिमियम ब्याज तथा रिङ'),
      PlanFeature('Priority support', 'प्राथमिकता सहयोग'),
      PlanFeature('Early access to new features', 'नयाँ फिचरमा अग्रिम पहुँच'),
    ],
  ),
];

/// Nepali label for a stored feature string. Falls back to the stored string
/// itself, so a hand-written feature an admin typed into Firestore still
/// renders instead of disappearing. Mirrors planFeatureLabel().
String planFeatureLabel(String id, bool isNepali) {
  if (!isNepali) return id;
  for (final group in planFeatureGroups) {
    for (final feature in group.features) {
      if (feature.id == id) return feature.ne;
    }
  }
  return id;
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

/// Builds the grouped matrix for one plan. The catalogue supplies structure
/// and order; the plan's stored `features` supply truth. Anything stored that
/// the catalogue does not recognise is kept in a trailing "extras" group —
/// dropping it would silently hide a feature an admin deliberately typed onto
/// a paid plan. Mirrors usePlanMatrix().
List<FeatureMatrixGroup> buildFeatureMatrix(
  List<String> planFeatures,
  bool isNepali,
) {
  final owned = planFeatures.toSet();
  final known = <String>{};
  final groups = <FeatureMatrixGroup>[];
  for (final group in planFeatureGroups) {
    final rows = group.features.map((feature) {
      known.add(feature.id);
      return FeatureMatrixRow(
        id: feature.id,
        label: planFeatureLabel(feature.id, isNepali),
        included: owned.contains(feature.id),
      );
    }).toList();
    groups.add(FeatureMatrixGroup(
      key: group.key,
      icon: group.icon,
      titleEn: group.titleEn,
      titleNe: group.titleNe,
      rows: rows,
    ));
  }
  final extras = planFeatures.where((f) => !known.contains(f)).toList();
  if (extras.isNotEmpty) {
    groups.add(FeatureMatrixGroup(
      key: 'extras',
      icon: 'extras',
      titleEn: 'Also included',
      titleNe: 'थप सुविधा',
      rows: extras
          .map((f) => FeatureMatrixRow(id: f, label: f, included: true))
          .toList(),
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
  /// Mirrors fetchMySubscriptionHistory().
  static Future<List<SubscriptionRecord>> fetchMySubscriptionHistory(
      String uid) async {
    final token = await AuthService.getValidIdToken();
    final docs = await FirestoreRest.listDocuments(
      'app_subscriptions',
      idToken: token,
      pageSize: 200,
    );
    final records = docs
        .map(SubscriptionRecord.fromMap)
        .where((r) => r.uid == uid)
        .toList()
      ..sort((a, b) => _cmpDesc(a.submittedAt, b.submittedAt));
    return records;
  }

  /// The current user's most relevant subscription record (active, else
  /// latest by submission). Mirrors fetchMySubscription().
  static Future<SubscriptionRecord?> fetchMySubscription(String uid) async {
    final history = await fetchMySubscriptionHistory(uid);
    if (history.isEmpty) return null;
    for (final record in history) {
      if (record.status == SubscriptionStatus.active) return record;
    }
    return history.first;
  }

  /// Sweeps an expired active subscription back to 'expired' + clears the
  /// user's premium flag. Called opportunistically from the Subscription
  /// page's load. Mirrors expireIfPastDue().
  static Future<void> expireIfPastDue(String uid) async {
    final record = await fetchMySubscription(uid);
    if (record == null || record.status != SubscriptionStatus.active) return;
    final expiry = record.expiryDate;
    if (expiry == null || expiry.isAfter(DateTime.now())) return;
    final token = await AuthService.getValidIdToken();
    await FirestoreRest.setDocument(
      'app_subscriptions/${record.id}',
      {
        'status': 'expired',
        'updatedAt': FirestoreRest.serverTimestamp(),
      },
      merge: true,
      idToken: token,
    );
    await FirestoreRest.setDocument(
      'users/$uid',
      {
        'isPremium': false,
        'updatedAt': FirestoreRest.serverTimestamp(),
      },
      merge: true,
      idToken: token,
    );
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
