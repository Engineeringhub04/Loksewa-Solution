// Exam purchase requests (user side + admin review).
//
// Mirrors src/core/firebase/services/examPurchases.ts:
// the ExamPurchaseRecord shape, the 30-minute edit window helpers,
// fetch-my-records (newest-first), the submit guard (one pending
// request per user/exam, doc id `{uid}_{examSetId}_{Date.now()}`), and
// owner updates. Phase-5: all data flows through the loksewa-api
// (/purchases/*); admin review lives in the Phase-3 admin API.
import 'package:loksewa_solution/services/admin_notify_service.dart';
import 'dart:async';

import 'package:loksewa_solution/services/cf_api.dart';

/// Edit window after submission during which the user may still change the
/// transaction ref / screenshot / message (matches
/// EXAM_PURCHASE_EDIT_WINDOW_MS).
const int examPurchaseEditWindowMs = 30 * 60 * 1000;

class ExamPurchaseRecord {
  final String id;
  final String uid;
  final String? userName;
  final String? userEmail;
  final String? courseId;
  final String? courseName;
  final String? subcourseId;
  final String? subcourseName;
  final String examSetId;
  final String examTitle;
  final String examContentType; // 'mcq' | 'pdf'
  final num amount;
  final String currency;
  final String method; // 'qr' | 'esewa' | 'khalti'
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

  const ExamPurchaseRecord({
    required this.id,
    required this.uid,
    this.userName,
    this.userEmail,
    this.courseId,
    this.courseName,
    this.subcourseId,
    this.subcourseName,
    required this.examSetId,
    required this.examTitle,
    required this.examContentType,
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

  factory ExamPurchaseRecord.fromMap(Map<String, dynamic> doc) {
    final status = doc['status']?.toString();
    return ExamPurchaseRecord(
      id: doc['id']?.toString() ?? '',
      uid: doc['uid']?.toString() ?? '',
      userName: _str(doc['userName']),
      userEmail: _str(doc['userEmail']),
      courseId: _str(doc['courseId']),
      courseName: _str(doc['courseName']),
      subcourseId: _str(doc['subcourseId']),
      subcourseName: _str(doc['subcourseName']),
      examSetId: doc['examSetId']?.toString() ?? '',
      // The worker writes `examSetTitle` on gateway purchase docs while the
      // manual flow writes `examTitle` — accept both so list cards and the
      // request page always show the real exam name.
      examTitle: _str(doc['examTitle']) ?? _str(doc['examSetTitle']) ?? '',
      examContentType:
          doc['examContentType']?.toString() == 'pdf' ? 'pdf' : 'mcq',
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

List<ExamPurchaseRecord> _newestFirst(List<ExamPurchaseRecord> records) {
  records.sort((a, b) =>
      (b.submittedAt ?? '').compareTo(a.submittedAt ?? ''));
  return records;
}

/// Mirrors fetchMyExamPurchases: newest first.
/// Phase-5: GET /purchases/mine returns the caller's exam rows in one
/// call (the server resolves the examPurchaseIds index itself).
Future<List<ExamPurchaseRecord>> fetchMyExamPurchases(String uid) async {
  final mine = await CfApi.getMyPurchases();
  return _newestFirst(mine.exam.map(ExamPurchaseRecord.fromMap).toList());
}

/// Mirrors fetchPendingExamPurchase.
Future<ExamPurchaseRecord?> fetchPendingExamPurchase(
    String uid, String examSetId) async {
  final records = await fetchMyExamPurchases(uid);
  for (final r in records) {
    if (r.examSetId == examSetId && r.status == 'pending') return r;
  }
  return null;
}

/// Mirrors fetchExamPurchaseById. Phase-5: the record is the caller's
/// own, so it is resolved from GET /purchases/mine.
Future<ExamPurchaseRecord?> fetchExamPurchaseById(String id) async {
  final records = await fetchMyExamPurchases(CfApi.currentUser?.uid ?? '');
  for (final r in records) {
    if (r.id == id) return r;
  }
  return null;
}

class SubmitExamPurchaseInput {
  final String uid;
  final String? userName;
  final String? userEmail;
  final String? courseId;
  final String? courseName;
  final String? subcourseId;
  final String? subcourseName;
  final String examSetId;
  final String examTitle;
  final String examContentType; // 'mcq' | 'pdf'
  final num amount;
  final String transactionRef;
  final String screenshotUrl;
  final String? customerMessage;
  final String? couponCode;

  const SubmitExamPurchaseInput({
    required this.uid,
    this.userName,
    this.userEmail,
    this.courseId,
    this.courseName,
    this.subcourseId,
    this.subcourseName,
    required this.examSetId,
    required this.examTitle,
    required this.examContentType,
    required this.amount,
    required this.transactionRef,
    required this.screenshotUrl,
    this.customerMessage,
    this.couponCode,
  });
}

/// Mirrors submitExamPurchase: keeps one active review request per user/exam —
/// an existing pending request's id is returned instead of creating a new one.
/// Phase-5: POST /purchases/exam — the server stamps ownership and
/// appends the id to the user's examPurchaseIds index itself.
Future<String> submitExamPurchase(SubmitExamPurchaseInput input) async {
  final existing = await fetchPendingExamPurchase(input.uid, input.examSetId);
  if (existing != null) return existing.id;

  final id = '${input.uid}_${input.examSetId}_${DateTime.now().millisecondsSinceEpoch}';
  final row = await CfApi.createExamPurchase({
    'id': id,
    'uid': input.uid,
    'userName': input.userName,
    'userEmail': input.userEmail,
    'courseId': input.courseId,
    'courseName': input.courseName,
    'subcourseId': input.subcourseId,
    'subcourseName': input.subcourseName,
    'examSetId': input.examSetId,
    'examTitle': input.examTitle,
    'examContentType': input.examContentType,
    'amount': input.amount,
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
    kind: 'exam_purchase',
    title: 'New Purchase Request 💳',
    body:
        '${buyerName.isEmpty ? 'Someone' : buyerName} requested to purchase "${input.examTitle}" — Rs. ${input.amount}',
    deepLink: '/admin/exam-purchases/$purchaseId',
  ));
  return purchaseId;
}

/// Mirrors updateMyExamPurchaseDetails. Phase-5: PATCH /purchases/exam/:id.
Future<void> updateMyExamPurchaseDetails(
  String id, {
  required String transactionRef,
  required String screenshotUrl,
  String? customerMessage,
}) async {
  await CfApi.patchPurchase('exam', id, {
    'transactionRef': transactionRef.trim(),
    'screenshotUrl': screenshotUrl,
    'customerMessage': customerMessage,
  });
}

/// Mirrors isExamPurchaseEditable.
bool isExamPurchaseEditable(ExamPurchaseRecord record,
    [int? nowMs]) {
  if (record.status != 'pending' || record.submittedAt == null) return false;
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final submitted = DateTime.tryParse(record.submittedAt!);
  if (submitted == null) return false;
  return now - submitted.millisecondsSinceEpoch <= examPurchaseEditWindowMs;
}

/// Mirrors examPurchaseEditRemainingMs.
int examPurchaseEditRemainingMs(ExamPurchaseRecord record, [int? nowMs]) {
  if (record.submittedAt == null) return 0;
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final submitted = DateTime.tryParse(record.submittedAt!);
  if (submitted == null) return 0;
  final remaining =
      examPurchaseEditWindowMs - (now - submitted.millisecondsSinceEpoch);
  return remaining < 0 ? 0 : remaining;
}

// Phase-5 cleanup: the admin functions that used to live here
// (fetchAllExamPurchases, approveExamPurchase, rejectExamPurchase,
// seedMissingExamPrices, updateExamPrice, fetchMyApprovedExamSetIds)
// had zero callers — the in-app admin screens run on the Phase-3 admin
// API (CfApi.getAdminPurchases / approveAdminPurchase /
// rejectAdminPurchase) — so they were deleted with their Firestore
// writes instead of being migrated.
