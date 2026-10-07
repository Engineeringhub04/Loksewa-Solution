// Exam purchase requests (user side + admin review).
//
// Mirrors src/core/firebase/services/examPurchases.ts:
// the ExamPurchaseRecord shape, the 30-minute edit window helpers,
// fetch-my-records (server-side uid filter via structured query,
// newest-first), the submit guard (one pending request per user/exam,
// doc id `{uid}_{examSetId}_{Date.now()}`), updates, and the admin
// approve / reject / price-seeding writes.
import 'package:loksewa_solution/services/admin_notify_service.dart';
import 'dart:async';

import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

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
      examTitle: doc['examTitle']?.toString() ?? '',
      examContentType:
          doc['examContentType']?.toString() == 'pdf' ? 'pdf' : 'mcq',
      amount: _num(doc['amount']),
      currency: doc['currency']?.toString() ?? 'NPR',
      method: 'qr',
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
    );
  }
}

List<ExamPurchaseRecord> _newestFirst(List<ExamPurchaseRecord> records) {
  records.sort((a, b) =>
      (b.submittedAt ?? '').compareTo(a.submittedAt ?? ''));
  return records;
}

/// Mirrors fetchMyExamPurchases: server-side `uid ==` filter (React's runQuery),
/// newest first.
Future<List<ExamPurchaseRecord>> fetchMyExamPurchases(String uid) async {
  final docs = await ExamRest.runQuery(
    'app_exam_purchases',
    where: ExamRest.fieldFilter('uid', 'EQUAL', uid),
    limit: 200,
  );
  return _newestFirst(docs.map(ExamPurchaseRecord.fromMap).toList());
}

/// Mirrors fetchMyApprovedExamSetIds.
Future<List<String>> fetchMyApprovedExamSetIds(String uid) async {
  final records = await fetchMyExamPurchases(uid);
  return records
      .where((r) => r.status == 'active')
      .map((r) => r.examSetId)
      .toList();
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

/// Mirrors fetchExamPurchaseById.
Future<ExamPurchaseRecord?> fetchExamPurchaseById(String id) async {
  final doc =
      await FirestoreRest.getDocument('app_exam_purchases/$id');
  return doc == null ? null : ExamPurchaseRecord.fromMap(doc);
}

/// Mirrors fetchAllExamPurchases (admin).
Future<List<ExamPurchaseRecord>> fetchAllExamPurchases() async {
  final docs = await FirestoreRest.listDocuments('app_exam_purchases',
      pageSize: 200);
  return _newestFirst(docs.map(ExamPurchaseRecord.fromMap).toList());
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
Future<String> submitExamPurchase(SubmitExamPurchaseInput input) async {
  final existing = await fetchPendingExamPurchase(input.uid, input.examSetId);
  if (existing != null) return existing.id;

  final id = '${input.uid}_${input.examSetId}_${DateTime.now().millisecondsSinceEpoch}';
  await FirestoreRest.setDocument('app_exam_purchases/$id', {
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
    'createdAt': FirestoreRest.serverTimestamp(),
    'updatedAt': FirestoreRest.serverTimestamp(),
  });
  // Fire-and-forget admin push — the request is recorded; never blocks.
  final buyerName = (input.userName ?? '').trim();
  unawaited(AdminNotifyService.notifyAdmin(
    kind: 'exam_purchase',
    title: 'New Purchase Request 💳',
    body:
        '${buyerName.isEmpty ? 'Someone' : buyerName} requested to purchase "${input.examTitle}" — Rs. ${input.amount}',
    deepLink: '/admin/exam-purchases/$id',
  ));
  return id;
}

/// Mirrors updateMyExamPurchaseDetails.
Future<void> updateMyExamPurchaseDetails(
  String id, {
  required String transactionRef,
  required String screenshotUrl,
  String? customerMessage,
}) async {
  await FirestoreRest.updateDocument('app_exam_purchases/$id', {
    'transactionRef': transactionRef.trim(),
    'screenshotUrl': screenshotUrl,
    'customerMessage': customerMessage,
    'updatedAt': FirestoreRest.serverTimestamp(),
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

/// Mirrors approveExamPurchase (admin).
Future<void> approveExamPurchase(String id, String reviewerUid,
    {String? adminMessage}) async {
  await FirestoreRest.updateDocument('app_exam_purchases/$id', {
    'status': 'active',
    'reviewedAt': DateTime.now().toIso8601String(),
    'reviewedBy': reviewerUid,
    'adminMessage': adminMessage,
    'rejectionReason': null,
    'updatedAt': FirestoreRest.serverTimestamp(),
  });
}

/// Mirrors rejectExamPurchase (admin).
Future<void> rejectExamPurchase(String id, String reviewerUid, String reason,
    {String? adminMessage}) async {
  await FirestoreRest.updateDocument('app_exam_purchases/$id', {
    'status': 'rejected',
    'reviewedAt': DateTime.now().toIso8601String(),
    'reviewedBy': reviewerUid,
    'rejectionReason': reason,
    'adminMessage': adminMessage,
    'updatedAt': FirestoreRest.serverTimestamp(),
  });
}

/// Mirrors seedMissingExamPrices: backfills a default price onto exam sets
/// that have none. Returns (updated, total).
Future<(int updated, int total)> seedMissingExamPrices(
    {num defaultPrice = 50}) async {
  final docs =
      await FirestoreRest.listDocuments('app_exam_sets', pageSize: 500);
  var updated = 0;
  for (final doc in docs) {
    final price = doc['price'];
    if (price is num && price.isFinite) continue;
    final id = doc['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    await FirestoreRest.updateDocument('app_exam_sets/$id', {
      'price': defaultPrice,
      'currency': 'NPR',
      'priceSeeded': true,
      'updatedAt': FirestoreRest.serverTimestamp(),
    });
    updated++;
  }
  return (updated, docs.length);
}

/// Mirrors updateExamPrice (admin).
Future<void> updateExamPrice(String examSetId, num price) async {
  await FirestoreRest.updateDocument('app_exam_sets/$examSetId', {
    'price': price < 0 ? 0 : price.round(),
    'currency': 'NPR',
    'updatedAt': FirestoreRest.serverTimestamp(),
  });
}
