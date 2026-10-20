// Tests for the v1.0.120 theory-answer round:
// - P1: My Submissions renders before name resolution finishes.
// - P2: a rejected submission's list card shows the rejection reason
//   pill and NO score pill / "Not passed" verdict.
// - P2b: ExamAnswer parses rejectionReason (feeds the Exam tab badge).
// - P3: crown cards — pending gets the amber "Pending Review" crown.
// - P5: one-edit rule — detail caption/button states (active / used /
//   expired), the upload edit gate blocks spent/reviewed/expired docs,
//   and a successful edit PATCH writes `editUsedAt`.
// - P6: PdfDownloadDialog save seam — public-Downloads success reports
//   onSaved(true) without a fallback file; false falls back to the
//   directory write and reports onSaved(false). PublicDownloads channel
//   helper returns true only on a non-null channel result.
//
// Network is fully mocked through FirestoreRest.setTestClient (MockClient)
// with a seeded signed-in session — the exam_answer_v119_test pattern.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loksewa_solution/screens/shop/exam_answer_screen.dart';
import 'package:loksewa_solution/screens/shop/my_submissions_screen.dart';
import 'package:loksewa_solution/screens/shop/upload_answer_screen.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/services/public_downloads.dart';
import 'package:loksewa_solution/widgets/pdf_download_dialog.dart';

/// Encodes a plain field map as a Firestore REST document body.
Map<String, dynamic> _doc(String path, Map<String, Object?> fields) {
  final enc = <String, dynamic>{};
  fields.forEach((k, v) {
    if (v == null) {
      enc[k] = {'nullValue': null};
    } else if (v is String) {
      enc[k] = {'stringValue': v};
    } else if (v is bool) {
      enc[k] = {'booleanValue': v};
    } else if (v is int) {
      enc[k] = {'integerValue': '$v'};
    } else if (v is List) {
      enc[k] = {
        'arrayValue': {
          'values': [for (final e in v) {'stringValue': '$e'}]
        }
      };
    }
  });
  return {
    'name': 'projects/p/databases/(default)/documents/$path',
    'fields': enc,
  };
}

/// Path-substring routes → response bodies, matched in insertion order.
Map<String, Object> _routes = {};

/// Captured non-GET requests (method, path, body) for write assertions.
final List<(String, String, String)> _writes = [];

void _mockFirestore() {
  FirestoreRest.setTestClient(MockClient((request) async {
    final path = request.url.path;
    if (request.method != 'GET') {
      _writes.add((request.method, path, request.body));
    }
    for (final entry in _routes.entries) {
      if (path.contains(entry.key)) {
        return http.Response.bytes(utf8.encode(json.encode(entry.value)), 200);
      }
    }
    return http.Response('{}', 404);
  }));
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder,
    {int tries = 60}) async {
  for (var i = 0; i < tries; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Never appeared: $finder');
}

Future<void> _pumpUntilTrue(WidgetTester tester, bool Function() done,
    {int tries = 60}) async {
  for (var i = 0; i < tries; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (done()) return;
  }
  fail('Condition never became true');
}

/// Unmounts the tree (disposing periodic timers) and runs out the finite
/// entrance delays/animations so no timer is left pending at test end.
Future<void> _flush(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void _setView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _freshIso(Duration ago) =>
    DateTime.now().subtract(ago).toIso8601String();

Map<String, Object?> _pendingAnswer({
  String? editUsedAt,
  Duration age = const Duration(minutes: 5),
}) =>
    {
      'uid': 'u1',
      'status': 'pending',
      'studentName': 'Ram Bahadur',
      'examSetId': 's1',
      'examSetTitle': 'Theory Paper 1',
      'courseName': 'Loksewa Course',
      'subcourseName': 'Kharidar',
      'sectionName': 'Theory Desk',
      'pdfUrl': 'https://example.com/submitted.pdf',
      'message': 'Please check',
      'createdAt': _freshIso(age),
      if (editUsedAt != null) 'editUsedAt': editUsedAt,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsService.setString(
      PrefsService.sessionKey,
      json.encode({
        'user': {
          'uid': 'u1',
          'email': 'a@b.c',
          'displayName': 'Test',
          'photoURL': null,
        },
        'idToken': 'test-id-token',
        'refreshToken': 'ref',
        'expiresAt':
            DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      }),
    );
    await AuthService.peekSavedSession();
    _routes = {};
    _writes.clear();
  });

  tearDown(() {
    FirestoreRest.setTestClient(null);
    PublicDownloads.channelInvoker = null;
    debugDefaultTargetPlatformOverride = null;
  });

  group('P2b model', () {
    test('ExamAnswer parses rejectionReason and isRejected', () {
      final rejected = ExamAnswer.fromMap(const {
        'id': 'a1',
        'uid': 'u1',
        'examSetId': 's1',
        'status': 'reviewed',
        'rejectionReason': 'Answer sheet is unreadable',
      });
      expect(rejected.rejectionReason, 'Answer sheet is unreadable');
      expect(rejected.isRejected, isTrue);

      final published = ExamAnswer.fromMap(const {
        'id': 'a2',
        'uid': 'u1',
        'examSetId': 's1',
        'status': 'reviewed',
      });
      expect(published.rejectionReason, '');
      expect(published.isRejected, isFalse);

      final pending = ExamAnswer.fromMap(const {
        'id': 'a3',
        'uid': 'u1',
        'examSetId': 's1',
        'status': 'pending',
        'rejectionReason': 'stale',
      });
      expect(pending.isRejected, isFalse);
    });
  });

  group('P2 list card', () {
    testWidgets('rejected card: reason pill, no score pill, no verdict',
        (tester) async {
      _setView(tester);
      _routes = {
        'users/u1': _doc('users/u1', {
          'examAnswerIds': ['a1'],
        }),
        'app_exam_answers/a1': _doc('app_exam_answers/a1', {
          'uid': 'u1',
          'status': 'reviewed',
          'studentName': 'Ram Bahadur',
          'examSetTitle': 'Theory Paper 1',
          'courseName': 'Loksewa Course',
          'subcourseName': 'Kharidar',
          'rejectionReason': 'Answer sheet is unreadable',
          'passed': null,
          'score': 0,
          'fullMarks': 100,
          'createdAt': '2026-10-10T10:00:00.000Z',
          'reviewedAt': '2026-10-12T10:00:00.000Z',
        }),
      };
      _mockFirestore();
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/exam-answer/my-submissions',
          routes: [
            GoRoute(
              path: '/exam-answer/my-submissions',
              builder: (_, __) => const MySubmissionsScreen(),
            ),
            GoRoute(
              path: '/exam-answer/:id',
              builder: (_, __) => const Scaffold(body: Text('Detail')),
            ),
          ],
        ),
      ));
      await _pumpUntil(tester, find.text('Answer sheet is unreadable'));
      expect(find.text('Answer sheet is unreadable'), findsOneWidget);
      expect(find.text('Not passed'), findsNothing);
      expect(find.text('0/100'), findsNothing);
      await _flush(tester);
    });
  });

  group('P3 + P5 detail page (pending)', () {
    GoRouter routerFor() => GoRouter(
          initialLocation: '/exam-answer/a1',
          routes: [
            GoRoute(
              path: '/exam-answer/upload',
              builder: (_, __) => const Scaffold(body: Text('Upload')),
            ),
            GoRoute(
              path: '/exam-answer/:id',
              builder: (_, s) =>
                  ExamAnswerScreen(id: s.pathParameters['id']!),
            ),
            GoRoute(
              path: '/pdf/:id',
              builder: (_, __) => const Scaffold(body: Text('PDF')),
            ),
            GoRoute(
              path: '/contact-us',
              builder: (_, __) => const Scaffold(body: Text('Contact')),
            ),
          ],
        );

    testWidgets('pending: amber crown + active one-edit caption',
        (tester) async {
      _setView(tester);
      _routes = {
        'app_exam_answers/a1':
            _doc('app_exam_answers/a1', _pendingAnswer()),
      };
      _mockFirestore();
      await tester.pumpWidget(MaterialApp.router(routerConfig: routerFor()));
      await _pumpUntil(tester, find.text('Pending Review'));

      // Crown (P3): big status word + set/course subtitle.
      expect(find.text('Pending Review'), findsOneWidget);
      expect(find.textContaining('Theory Paper 1 · Loksewa Course'),
          findsWidgets);
      // One-edit caption (P5) rides along with the live countdown.
      await _pumpUntil(
          tester, find.textContaining('You can edit only once.'));
      final editBtn = tester.widget<ElevatedButton>(find
          .ancestor(
              of: find.textContaining('Edit / Re-upload Answer'),
              matching: find.byType(ElevatedButton))
          .first);
      expect(editBtn.onPressed, isNotNull);
      await _flush(tester);
    });

    testWidgets('edit used: greyed button + already-used caption',
        (tester) async {
      _setView(tester);
      _routes = {
        'app_exam_answers/a1': _doc(
            'app_exam_answers/a1',
            _pendingAnswer(
                editUsedAt: _freshIso(const Duration(minutes: 2)))),
      };
      _mockFirestore();
      await tester.pumpWidget(MaterialApp.router(routerConfig: routerFor()));
      await _pumpUntil(
          tester,
          find.text(
              'You have already used your one edit for this submission.'));
      final editBtn = tester.widget<ElevatedButton>(find
          .ancestor(
              of: find.text('Edit / Re-upload Answer'),
              matching: find.byType(ElevatedButton))
          .first);
      expect(editBtn.onPressed, isNull);
      await _flush(tester);
    });

    testWidgets('window expired: expired caption, button disabled',
        (tester) async {
      _setView(tester);
      _routes = {
        'app_exam_answers/a1': _doc('app_exam_answers/a1',
            _pendingAnswer(age: const Duration(hours: 2))),
      };
      _mockFirestore();
      await tester.pumpWidget(MaterialApp.router(routerConfig: routerFor()));
      await _pumpUntil(
          tester, find.text('The 1-hour edit window has expired.'));
      final editBtn = tester.widget<ElevatedButton>(find
          .ancestor(
              of: find.text('Edit / Re-upload Answer'),
              matching: find.byType(ElevatedButton))
          .first);
      expect(editBtn.onPressed, isNull);
      await _flush(tester);
    });
  });

  group('P5 upload edit gate', () {
    GoRouter routerFor(String loc) => GoRouter(
          initialLocation: loc,
          routes: [
            GoRoute(
              path: '/exam-answer/upload',
              builder: (_, __) => const UploadAnswerScreen(),
            ),
            GoRoute(
              path: '/exam-answer/my-submissions',
              builder: (_, __) => const Scaffold(body: Text('List')),
            ),
            GoRoute(
              path: '/exam-answer/:id',
              builder: (_, __) => const Scaffold(body: Text('Detail')),
            ),
          ],
        );

    testWidgets('spent edit is blocked with the already-used message',
        (tester) async {
      _setView(tester);
      _routes = {
        'app_exam_answers/a1': _doc(
            'app_exam_answers/a1',
            _pendingAnswer(
                editUsedAt: _freshIso(const Duration(minutes: 2)))),
      };
      _mockFirestore();
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: routerFor('/exam-answer/upload?editId=a1')));
      await _pumpUntil(
          tester,
          find.text(
              'You have already used your one edit for this submission.'));
      expect(find.text('Update Data'), findsNothing);
      expect(find.text('View My Answer Sheets'), findsOneWidget);
      await _flush(tester);
    });

    testWidgets('reviewed doc is blocked', (tester) async {
      _setView(tester);
      final doc = _pendingAnswer();
      doc['status'] = 'reviewed';
      _routes = {'app_exam_answers/a1': _doc('app_exam_answers/a1', doc)};
      _mockFirestore();
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: routerFor('/exam-answer/upload?editId=a1')));
      await _pumpUntil(
          tester,
          find.text(
              'This submission has already been reviewed, so it can no longer be edited.'));
      expect(find.text('Update Data'), findsNothing);
      await _flush(tester);
    });

    test('gate logic: examAnswerEditBlockMessage cases', () {
      final now = DateTime.now();
      Map<String, dynamic> base() => {
            'uid': 'u1',
            'status': 'pending',
            'createdAt':
                now.subtract(const Duration(minutes: 5)).toIso8601String(),
          };
      expect(examAnswerEditBlockMessage(base(), 'u1'), isNull);
      expect(examAnswerEditBlockMessage(null, 'u1'), isNotNull);
      expect(examAnswerEditBlockMessage(base(), 'someone-else'),
          isNotNull);
      expect(
          examAnswerEditBlockMessage(
              base()..['editUsedAt'] = now.toIso8601String(), 'u1'),
          contains('already used your one edit'));
      expect(
          examAnswerEditBlockMessage(
              base()
                ..['createdAt'] = now
                    .subtract(const Duration(hours: 2))
                    .toIso8601String(),
              'u1'),
          contains('1-hour edit window has expired'));
    });

    testWidgets('successful edit PATCH writes editUsedAt', (tester) async {
      _setView(tester);
      final doc = _pendingAnswer();
      doc['message'] = 'Please check';
      _routes = {'app_exam_answers/a1': _doc('app_exam_answers/a1', doc)};
      _mockFirestore();
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: routerFor('/exam-answer/upload?editId=a1')));
      await _pumpUntil(tester, find.text('Update Data'));

      // Open the confirm popup and confirm.
      await tester.tap(find.text('Update Data').first);
      await _pumpUntil(tester, find.text('Save these changes?'));
      await tester
          .tap(find.widgetWithText(ElevatedButton, 'Update Data'));
      await _pumpUntil(tester, find.text('View My Answer Sheets'));

      final patch = _writes.firstWhere(
          (w) => w.$1 == 'PATCH' && w.$2.contains('app_exam_answers/a1'));
      expect(patch.$3, contains('editUsedAt'));
      expect(patch.$3, contains('updatedAt'));
      await _flush(tester);
    });
  });

  group('P6 download save seam', () {
    testWidgets('public save success: onSaved(true), no fallback file',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('pdfdlg_v120_a');
      addTearDown(() => tmp.deleteSync(recursive: true));
      bool? saved;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfDownloadDialog(
            url: 'http://example.com/a.pdf',
            fileName: 'checked.pdf',
            downloadFn: (url, onProgress) async {
              onProgress(10, 10);
              return Uint8List.fromList([1, 2, 3]);
            },
            saveFn: (bytes) async => true,
            resolveDir: () async => tmp,
            onDone: () {},
            onSaved: (v) => saved = v,
            onClose: () {},
          ),
        ),
      ));
      await _pumpUntilTrue(tester, () => saved != null);
      expect(saved, isTrue);
      expect(File('${tmp.path}/checked.pdf').existsSync(), isFalse);
      await _flush(tester);
    });

    testWidgets('public save failure: fallback file write, onSaved(false)',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('pdfdlg_v120_b');
      addTearDown(() => tmp.deleteSync(recursive: true));
      bool? saved;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfDownloadDialog(
            url: 'http://example.com/a.pdf',
            fileName: 'checked.pdf',
            downloadFn: (url, onProgress) async {
              onProgress(10, 10);
              return Uint8List.fromList([4, 5, 6]);
            },
            saveFn: (bytes) async => false,
            resolveDir: () async => tmp,
            onDone: () {},
            onSaved: (v) => saved = v,
            onClose: () {},
          ),
        ),
      ));
      await _pumpUntilTrue(tester, () => saved != null);
      expect(saved, isFalse);
      final file = File('${tmp.path}/checked.pdf');
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), [4, 5, 6]);
      await _flush(tester);
    });

    test('PublicDownloads channel helper semantics', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      PublicDownloads.channelInvoker = (args) async => 'content://dl/1';
      expect(
          await PublicDownloads.saveToPublicDownloads(
              Uint8List.fromList([1]), 'a.pdf'),
          isTrue);
      PublicDownloads.channelInvoker = (args) async => null;
      expect(
          await PublicDownloads.saveToPublicDownloads(
              Uint8List.fromList([1]), 'a.pdf'),
          isFalse);
      PublicDownloads.channelInvoker =
          (args) async => throw Exception('no channel');
      expect(
          await PublicDownloads.saveToPublicDownloads(
              Uint8List.fromList([1]), 'a.pdf'),
          isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      PublicDownloads.channelInvoker = (args) async => 'content://dl/1';
      expect(
          await PublicDownloads.saveToPublicDownloads(
              Uint8List.fromList([1]), 'a.pdf'),
          isFalse);
    });
  });
}
