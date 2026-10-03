// Tests for the v1.0.46 answers-review round:
// - ExamAnswer.fromMap parses the admin-desk fields (studentName,
//   profileName, examSetTitle, sectionName, createdAt) with safe defaults.
// - createdAtMillis parses ISO dates, 0 when missing/garbage.
// - clearExamRulesCache runs clean (the session cache itself is exercised
//   by prefetch on section load; network fetch is not unit-tested).
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/exam_service.dart';

void main() {
  group('ExamAnswer.fromMap (admin desk fields)', () {
    test('parses all fields', () {
      final a = ExamAnswer.fromMap({
        'id': 'a1',
        '_fields': {
          'uid': 'u1',
          'examSetId': 's1',
          'status': 'pending',
          'studentName': 'Ram Bahadur',
          'profileName': 'Ram B.',
          'email': 'ram@example.com',
          'examSetTitle': 'Theory Paper 1',
          'sectionName': 'Theory Desk',
          'message': 'Please check',
          'pdfUrl': 'https://x/y.pdf',
          'createdAt': '2026-10-03T10:00:00.000Z',
        },
      });
      expect(a.id, 'a1');
      expect(a.uid, 'u1');
      expect(a.examSetId, 's1');
      expect(a.status, 'pending');
      expect(a.studentName, 'Ram Bahadur');
      expect(a.profileName, 'Ram B.');
      expect(a.email, 'ram@example.com');
      expect(a.examSetTitle, 'Theory Paper 1');
      expect(a.sectionName, 'Theory Desk');
      expect(a.message, 'Please check');
      expect(a.pdfUrl, 'https://x/y.pdf');
      expect(a.createdAtMillis,
          DateTime.parse('2026-10-03T10:00:00.000Z').millisecondsSinceEpoch);
    });

    test('missing fields default safely', () {
      final a = ExamAnswer.fromMap({
        'id': 'a2',
        '_fields': {'uid': 'u2'},
      });
      expect(a.status, 'pending');
      expect(a.studentName, '');
      expect(a.profileName, '');
      expect(a.examSetTitle, '');
      expect(a.sectionName, '');
      expect(a.createdAt, '');
      expect(a.createdAtMillis, 0);
    });

    test('garbage createdAt gives 0 millis', () {
      final a = ExamAnswer.fromMap({
        'id': 'a3',
        '_fields': {'createdAt': 'not-a-date'},
      });
      expect(a.createdAtMillis, 0);
    });

    test('works without the _fields envelope', () {
      final a = ExamAnswer.fromMap({
        'id': 'a4',
        'uid': 'u4',
        'status': 'reviewed',
        'studentName': 'Sita',
      });
      expect(a.uid, 'u4');
      expect(a.status, 'reviewed');
      expect(a.studentName, 'Sita');
    });
  });

  group('exam rules session cache', () {
    test('clearExamRulesCache runs without error', () {
      expect(clearExamRulesCache, returnsNormally);
    });
  });
}
