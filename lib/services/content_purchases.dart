// Content purchase requests (user side + admin review).
//
// Mirrors src/core/firebase/services/contentPurchases.ts:
// the ContentPurchaseRecord shape, the 30-minute edit window helpers,
// fetch-my-records (server-side uid filter via structured query,
// newest-first), the submit guard (one pending request per
// user/contentType/contentId, doc id
// `{uid}_{contentType}_{contentId}_{Date.now()}`), updates, and the admin
// approve / reject writes.
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

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

List<ContentPurchaseRecord> _newestFirst(
    List<ContentPurchaseRecord> records) {
  records.sort((a, b) =>
      (b.submittedAt ?? '').compareTo(a.submittedAt ?? ''));
  return records;
}

/// Mirrors fetchMyContentPurchases: server-side `uid ==` filter (React's
/// runQuery), newest first.
Future<List<ContentPurchaseRecord>> fetchMyContentPurchases(
    String uid) async {
  final docs = await ExamRest.runQuery(
    'app_content_purchases',
    where: ExamRest.fieldFilter('uid', 'EQUAL', uid),
    limit: 200,
  );
  return _newestFirst(docs.map(ContentPurchaseRecord.fromMap).toList());
}

/// Mirrors fetchMyApprovedContentIds.
Future<List<String>> fetchMyApprovedContentIds(String uid) async {
  final records = await fetchMyContentPurchases(uid);
  return records
      .where((r) => r.status == 'active')
      .map((r) => r.contentId)
      .toList();
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

/// Mirrors fetchContentPurchaseById.
Future<ContentPurchaseRecord?> fetchContentPurchaseById(String id) async {
  final doc =
      await FirestoreRest.getDocument('app_content_purchases/$id');
  return doc == null ? null : ContentPurchaseRecord.fromMap(doc);
}

/// Mirrors fetchAllContentPurchases (admin).
Future<List<ContentPurchaseRecord>> fetchAllContentPurchases() async {
  final docs = await FirestoreRest.listDocuments('app_content_purchases',
      pageSize: 200);
  return _newestFirst(docs.map(ContentPurchaseRecord.fromMap).toList());
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
Future<String> submitContentPurchase(
    SubmitContentPurchaseInput input) async {
  final existing = await fetchPendingContentPurchase(
      input.uid, input.contentType, input.contentId);
  if (existing != null) return existing.id;

  final id =
      '${input.uid}_${input.contentType}_${input.contentId}_${DateTime.now().millisecondsSinceEpoch}';
  await FirestoreRest.setDocument('app_content_purchases/$id', {
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
    'createdAt': FirestoreRest.serverTimestamp(),
    'updatedAt': FirestoreRest.serverTimestamp(),
  });
  return id;
}

/// Mirrors updateMyContentPurchaseDetails.
Future<void> updateMyContentPurchaseDetails(
  String id, {
  required String transactionRef,
  required String screenshotUrl,
  String? customerMessage,
}) async {
  await FirestoreRest.updateDocument('app_content_purchases/$id', {
    'transactionRef': transactionRef.trim(),
    'screenshotUrl': screenshotUrl,
    'customerMessage': customerMessage,
    'updatedAt': FirestoreRest.serverTimestamp(),
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

/// Mirrors approveContentPurchase (admin).
Future<void> approveContentPurchase(String id, String reviewerUid,
    {String? adminMessage}) async {
  await FirestoreRest.updateDocument('app_content_purchases/$id', {
    'status': 'active',
    'reviewedAt': DateTime.now().toIso8601String(),
    'reviewedBy': reviewerUid,
    'adminMessage': adminMessage,
    'rejectionReason': null,
    'updatedAt': FirestoreRest.serverTimestamp(),
  });
}

/// Mirrors rejectContentPurchase (admin).
Future<void> rejectContentPurchase(String id, String reviewerUid,
    String reason, {String? adminMessage}) async {
  await FirestoreRest.updateDocument('app_content_purchases/$id', {
    'status': 'rejected',
    'reviewedAt': DateTime.now().toIso8601String(),
    'reviewedBy': reviewerUid,
    'rejectionReason': reason,
    'adminMessage': adminMessage,
    'updatedAt': FirestoreRest.serverTimestamp(),
  });
}
