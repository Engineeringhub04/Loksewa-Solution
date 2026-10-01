// Unit tests for the exam/content purchase services: the edit-window
// helpers and the record parsers. Pure logic, no network.
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/content_purchases.dart';
import 'package:loksewa_solution/services/exam_purchases.dart';

Map<String, dynamic> _exam({
  required String status,
  required String submittedAt,
  String id = 'u_exam_1',
  num amount = 299,
}) =>
    {
      'id': id,
      'uid': 'u',
      'examSetId': 'exam_1',
      'examTitle': 'Set 1',
      'amount': amount,
      'status': status,
      'submittedAt': submittedAt,
    };

Map<String, dynamic> _content({
  required String status,
  required String submittedAt,
  String type = 'chapter',
}) =>
    {
      'id': 'u_content_1',
      'uid': 'u',
      'contentType': type,
      'contentId': 'c1',
      'contentTitle': 'Title',
      'contentTitleNe': 'शीर्षक',
      'subjectId': 's1',
      'amount': 99,
      'status': status,
      'submittedAt': submittedAt,
    };

String _minsAgo(int m) =>
    DateTime.now().subtract(Duration(minutes: m)).toIso8601String();

void main() {
  group('exam purchase edit window', () {
    test('fresh pending purchase is editable', () {
      final r = ExamPurchaseRecord.fromMap(
          _exam(status: 'pending', submittedAt: _minsAgo(5)));
      expect(isExamPurchaseEditable(r), isTrue);
      final remaining = examPurchaseEditRemainingMs(r);
      expect(remaining, greaterThan(0));
      expect(remaining, lessThanOrEqualTo(examPurchaseEditWindowMs));
    });

    test('expired pending purchase is not editable', () {
      final r = ExamPurchaseRecord.fromMap(
          _exam(status: 'pending', submittedAt: _minsAgo(45)));
      expect(isExamPurchaseEditable(r), isFalse);
      expect(examPurchaseEditRemainingMs(r), 0);
    });

    test('active / rejected purchases are never editable', () {
      for (final status in ['active', 'rejected']) {
        final r = ExamPurchaseRecord.fromMap(
            _exam(status: status, submittedAt: _minsAgo(1)));
        expect(isExamPurchaseEditable(r), isFalse,
            reason: 'status=$status');
        // The remaining-ms helper is a pure clock computation — the edit
        // UI is gated on isExamPurchaseEditable, which is false here.
      }
    });

    test('unparseable submittedAt is not editable', () {
      final r = ExamPurchaseRecord.fromMap(
          _exam(status: 'pending', submittedAt: 'not-a-date'));
      expect(isExamPurchaseEditable(r), isFalse);
    });

    test('explicit nowMs makes the boundary deterministic', () {
      final submitted =
          DateTime.now().subtract(const Duration(minutes: 29));
      final r = ExamPurchaseRecord.fromMap(_exam(
          status: 'pending', submittedAt: submitted.toIso8601String()));
      final nowMs = submitted.millisecondsSinceEpoch +
          examPurchaseEditWindowMs -
          1000;
      expect(isExamPurchaseEditable(r, nowMs), isTrue);
      expect(
          isExamPurchaseEditable(
              r, nowMs + 2000),
          isFalse);
    });
  });

  group('exam purchase record parsing', () {
    test('fromMap reads every field', () {
      final r = ExamPurchaseRecord.fromMap({
        ..._exam(status: 'active', submittedAt: _minsAgo(60)),
        'courseName': 'Engineering',
        'subcourseName': 'Civil',
        'transactionRef': 'REF123',
        'screenshotUrl': 'http://img/x.png',
        'rejectionReason': '',
        'adminMessage': 'ok',
        'reviewedAt': _minsAgo(30),
      });
      expect(r.examTitle, 'Set 1');
      expect(r.status, 'active');
      expect(r.amount, 299);
      expect(r.courseName, 'Engineering');
      expect(r.transactionRef, 'REF123');
      expect(r.screenshotUrl, 'http://img/x.png');
      expect(r.adminMessage, 'ok');
      expect(r.reviewedAt, isNotNull);
      expect(r.method, 'qr');
      expect(r.currency, 'NPR');
    });

    test('unknown status defaults to pending', () {
      final r = ExamPurchaseRecord.fromMap(
          _exam(status: 'weird', submittedAt: _minsAgo(1)));
      expect(r.status, 'pending');
    });
  });

  group('content purchase edit window', () {
    test('fresh pending content purchase is editable', () {
      final r = ContentPurchaseRecord.fromMap(
          _content(status: 'pending', submittedAt: _minsAgo(10)));
      expect(isContentPurchaseEditable(r), isTrue);
      expect(contentPurchaseEditRemainingMs(r), greaterThan(0));
      expect(contentPurchaseEditRemainingMs(r),
          lessThanOrEqualTo(contentPurchaseEditWindowMs));
    });

    test('expired pending content purchase is not editable', () {
      final r = ContentPurchaseRecord.fromMap(
          _content(status: 'pending', submittedAt: _minsAgo(31)));
      expect(isContentPurchaseEditable(r), isFalse);
      expect(contentPurchaseEditRemainingMs(r), 0);
    });

    test('active content purchase is not editable', () {
      final r = ContentPurchaseRecord.fromMap(
          _content(status: 'active', submittedAt: _minsAgo(1)));
      expect(isContentPurchaseEditable(r), isFalse);
    });
  });

  group('content purchase record parsing', () {
    test('contentType accepts only subject|unit, else chapter', () {
      for (final t in ['subject', 'unit', 'chapter']) {
        final r = ContentPurchaseRecord.fromMap(
            _content(status: 'pending', submittedAt: _minsAgo(1), type: t));
        expect(r.contentType, t);
      }
      final bad = ContentPurchaseRecord.fromMap(
          _content(status: 'pending', submittedAt: _minsAgo(1), type: 'video'));
      expect(bad.contentType, 'chapter');
    });

    test('fromMap reads content fields', () {
      final r = ContentPurchaseRecord.fromMap({
        ..._content(status: 'pending', submittedAt: _minsAgo(1)),
        'unitId': 'u9',
        'transactionRef': 'TX1',
        'rejectionReason': 'blurry',
      });
      expect(r.contentTitleNe, 'शीर्षक');
      expect(r.subjectId, 's1');
      expect(r.unitId, 'u9');
      expect(r.transactionRef, 'TX1');
      expect(r.rejectionReason, 'blurry');
    });
  });
}
