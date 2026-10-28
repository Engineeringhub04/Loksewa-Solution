// Content purchase requests (user side).
//
// Mirrors src/core/firebase/services/contentPurchases.ts:
// the ContentPurchaseRecord shape, the 30-minute edit window helpers,
// fetch-my-records (newest-first), the submit guard (one pending request
// per user/contentType/contentId, doc id
// `{uid}_{contentType}_{contentId}_{Date.now()}`), and owner updates.
// Phase-5: all data flows through the loksewa-api (/purchases/*);
// admin review lives in the Phase-3 admin API.
import 'package:loksewa_solution/services/admin_notify_service.dart';
import 'dart:async';

import 'package:loksewa_solution/services/cf_api.dart';

/// Edit window after submission during which the user may still change the
/// transaction ref / screenshot / message (matches
/// CONTENT_PURCHASE_EDIT_WINDOW_MS).
const int contentPurchaseEditWindowMs = 30 * 60 * 1000;

class ContentPurchaseRecord {
  final String id;
  final String uid;
  final String? userName;
  final String? userEmail;
  final String? courseId;
  final String? subcourseId;
  final String contentType; // 'subject' | 'unit' | 'chapter'
  final String contentId;
  final String contentTitle;
  final String contentTitleNe;
  final String subjectId;
  final String? unitId;
  final num amount;
  final String currency;
  final String method; // 'qr'
  final String status; // 'pending' | 'active' | 'rejected'
  final String? transactionRef;
  final String screenshotUrl;
  final String? customerMessage;
  final String? couponCode;
  final String? adminMessage;
  final String? submittedAt;
  final String? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;
  // Gateway fields (written by the worker for eSewa/Khalti purchases).
  final String? gatewayStatus; // 'initiated' | 'verified' | 'failed'
  final String? failureReason; // 'payment_not_completed' | 'amount_mismatch' | 'duplicate'
  final String? verifiedBy; // 'gateway' | 'user' | 'admin'
  final String? platform; // 'app'

  const ContentPurchaseRecord({
    required this.id,
    required this.uid,
    this.userName,
    this.userEmail,
    this.courseId,
    this.subcourseId,
    required this.contentType,
    required this.contentId,
    required this.contentTitle,
    required this.contentTitleNe,
    required this.subjectId,
    this.unitId,
    required this.amount,
    required this.currency,
    required this.method,
    required this.status,
    this.transactionRef,
    required this.screenshotUrl,
    this.customerMessage,
    this.couponCode,
    this.adminMessage,
    this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
    this.gatewayStatus,
    this.failureReason,
    this.verifiedBy,
    this.platform,
  });

  static String? _str(dynamic v) =>
      v is String && v.trim().isNotEmpty ? v : null;
  static num _num(dynamic v) =>
      v is num && v.isFinite ? v : (num.tryParse('$v') ?? 0);
  static String _type(dynamic v) {
    final s = v?.toString();
    return s == 'subject' || s == 'unit' ? s! : 'chapter';
  }

  factory ContentPurchaseRecord.fromMap(Map<String, dynamic> doc) {
    final status = doc['status']?.toString();
    return ContentPurchaseRecord(
      id: doc['id']?.toString() ?? '',
      uid: doc['uid']?.toString() ?? '',
      userName: _str(doc['userName']),
      userEmail: _str(doc['userEmail']),
      courseId: _str(doc['courseId']),
      subcourseId: _str(doc['subcourseId']),
      contentType: _type(doc['contentType']),
      contentId: doc['contentId']?.toString() ?? '',
      contentTitle: doc['contentTitle']?.toString() ?? '',
      contentTitleNe: doc['contentTitleNe']?.toString() ?? '',
      subjectId: doc['subjectId']?.toString() ?? '',
      unitId: _str(doc['unitId']),
      amount: _num(doc['amount']),
      currency: doc['currency']?.toString() ?? 'NPR',
      method: doc['method']?.toString() ?? 'qr',
      status:
          status == 'active' || status == 'rejected' ? status! : 'pending',
      transactionRef: _str(doc['transactionRef']),
      screenshotUrl: doc['screenshotUrl']?.toString() ?? '',
      customerMessage: _str(doc['customerMessage']),
      couponCode: _str(doc['couponCode']),
      adminMessage: _str(doc['adminMessage']),
      submittedAt: _str(doc['submittedAt']),
      reviewedAt: _str(doc['reviewedAt']),
      reviewedBy: _str(doc['reviewedBy']),
      rejectionReason: _str(doc['rejectionReason']),
      gatewayStatus: _str(doc['gatewayStatus']),
      failureReason: _str(doc['failureReason']),
      verifiedBy: _str(doc['verifiedBy']),
      platform: _str(doc['platform']),
    );
  }

  /// Gateway purchase (eSewa/Khalti) still awaiting verification.
  bool get isGateway => method == 'esewa' || method == 'khalti';

  /// Pending gateway request that needs payment recovery (Check My Payment).
  bool get needsPaymentRecovery =>
      isGateway && status == 'pending' && gatewayStatus == 'initiated';

  /// Definitive gateway failure (amount mismatch / duplicate) — no retry.
  bool get isFraud =>
      isGateway &&
      status == 'pending' &&
      (gatewayStatus == 'failed' || (failureReason ?? '').isNotEmpty);

  /// Initiated but never verified and past the 15-minute gateway window —
  /// the app was closed mid-payment.
  bool get isStaleInitiated =>
      needsPaymentRecovery &&
      submittedAtDate != null &&
      DateTime.now().difference(submittedAtDate!).inMinutes >= 15;

  DateTime? get submittedAtDate =>
      submittedAt == null ? null : DateTime.tryParse(submittedAt!);
}

List<ContentPurchaseRecord> _newestFirst(
    List<ContentPurchaseRecord> records) {
  records.sort((a, b) =>
      (b.submittedAt ?? '').compareTo(a.submittedAt ?? ''));
  return records;
}

/// Mirrors fetchMyContentPurchases: newest first.
/// Phase-5: GET /purchases/mine returns the caller's content rows in
/// one call (the server resolves the contentPurchaseIds index itself).
/// NOTE: exam_service.dart has a namesake fetcher for content-unlock
/// checks (Phase-1 GET /purchases/content) — this one serves the
/// history / detail / submit paths.
Future<List<ContentPurchaseRecord>> fetchMyContentPurchases(
    String uid) async {
  final mine = await CfApi.getMyPurchases();
  return _newestFirst(mine.content.map(ContentPurchaseRecord.fromMap).toList());
}

/// Mirrors fetchPendingContentPurchase.
Future<ContentPurchaseRecord?> fetchPendingContentPurchase(
    String uid, String contentType, String contentId) async {
  final records = await fetchMyContentPurchases(uid);
  for (final r in records) {
    if (r.contentType == contentType &&
        r.contentId == contentId &&
        r.status == 'pending') {
      return r;
    }
  }
  return null;
}

/// Mirrors fetchContentPurchaseById. Phase-5: the record is the
/// caller's own, so it is resolved from GET /purchases/mine.
Future<ContentPurchaseRecord?> fetchContentPurchaseById(String id) async {
  final records = await fetchMyContentPurchases(CfApi.currentUser?.uid ?? '');
  for (final r in records) {
    if (r.id == id) return r;
  }
  return null;
}

class SubmitContentPurchaseInput {
  final String uid;
  final String? userName;
  final String? userEmail;
  final String? courseId;
  final String? subcourseId;
  final String contentType; // 'subject' | 'unit' | 'chapter'
  final String contentId;
  final String contentTitle;
  final String contentTitleNe;
  final String subjectId;
  final String? unitId;
  final num amount;
  final String transactionRef;
  final String screenshotUrl;
  final String? customerMessage;
  final String? couponCode;

  const SubmitContentPurchaseInput({
    required this.uid,
    this.userName,
    this.userEmail,
    this.courseId,
    this.subcourseId,
    required this.contentType,
    required this.contentId,
    required this.contentTitle,
    required this.contentTitleNe,
    required this.subjectId,
    this.unitId,
    required this.amount,
    required this.transactionRef,
    required this.screenshotUrl,
    this.customerMessage,
    this.couponCode,
  });
}

/// Mirrors submitContentPurchase: keeps one active review request per
/// user/content — an existing pending request's id is returned instead of
/// creating a new one.
/// Phase-5: POST /purchases/content — the server stamps ownership and
/// appends the id to the user's contentPurchaseIds index itself.
Future<String> submitContentPurchase(
    SubmitContentPurchaseInput input) async {
  final existing = await fetchPendingContentPurchase(
      input.uid, input.contentType, input.contentId);
  if (existing != null) return existing.id;

  final id =
      '${input.uid}_${input.contentType}_${input.contentId}_${DateTime.now().millisecondsSinceEpoch}';
  final row = await CfApi.createContentPurchase({
    'id': id,
    'uid': input.uid,
    'userName': input.userName,
    'userEmail': input.userEmail,
    'courseId': input.courseId,
    'subcourseId': input.subcourseId,
    'contentType': input.contentType,
    'contentId': input.contentId,
    'contentTitle': input.contentTitle,
    'contentTitleNe': input.contentTitleNe,
    'subjectId': input.subjectId,
    'unitId': input.unitId,
    'amount': input.amount < 0 ? 0 : input.amount.round(),
    'currency': 'NPR',
    'method': 'qr',
    'status': 'pending',
    'transactionRef': input.transactionRef.trim(),
    'screenshotUrl': input.screenshotUrl,
    'customerMessage': input.customerMessage,
    'couponCode': input.couponCode,
    'adminMessage': null,
    'submittedAt': DateTime.now().toIso8601String(),
    'reviewedAt': null,
    'reviewedBy': null,
    'rejectionReason': null,
  });
  final createdId = (row['id'] ?? '').toString();
  final purchaseId = createdId.isNotEmpty ? createdId : id;
  // Fire-and-forget admin push — the request is recorded; never blocks.
  final buyerName = (input.userName ?? '').trim();
  unawaited(AdminNotifyService.notifyAdmin(
    kind: 'content_purchase',
    title: 'New Purchase Request 💳',
    body:
        '${buyerName.isEmpty ? 'Someone' : buyerName} requested to purchase "${input.contentTitle}" — Rs. ${input.amount}',
    deepLink: '/admin/content-purchases/$purchaseId',
  ));
  return purchaseId;
}

/// Mirrors updateMyContentPurchaseDetails.
/// Phase-5: PATCH /purchases/content/:id.
Future<void> updateMyContentPurchaseDetails(
  String id, {
  required String transactionRef,
  required String screenshotUrl,
  String? customerMessage,
}) async {
  await CfApi.patchPurchase('content', id, {
    'transactionRef': transactionRef.trim(),
    'screenshotUrl': screenshotUrl,
    'customerMessage': customerMessage,
  });
}

/// Mirrors isContentPurchaseEditable.
bool isContentPurchaseEditable(ContentPurchaseRecord record,
    [int? nowMs]) {
  if (record.status != 'pending' || record.submittedAt == null) return false;
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final submitted = DateTime.tryParse(record.submittedAt!);
  if (submitted == null) return false;
  return now - submitted.millisecondsSinceEpoch <= contentPurchaseEditWindowMs;
}

/// Mirrors contentPurchaseEditRemainingMs.
int contentPurchaseEditRemainingMs(ContentPurchaseRecord record,
    [int? nowMs]) {
  if (record.submittedAt == null) return 0;
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final submitted = DateTime.tryParse(record.submittedAt!);
  if (submitted == null) return 0;
  final remaining =
      contentPurchaseEditWindowMs - (now - submitted.millisecondsSinceEpoch);
  return remaining < 0 ? 0 : remaining;
}

// Phase-5 cleanup: the admin functions that used to live here
// (fetchAllContentPurchases, approveContentPurchase,
// rejectContentPurchase) and the superseded approved-ids fetchers
// (fetchMyApprovedContentIds / fetchMyApprovedContentIdsFromDoc — the
// unlock path uses exam_service's CF variant) had zero callers in lib/,
// so they were deleted with their Firestore reads/writes instead of
// being migrated. Admin review runs on the Phase-3 admin API.
