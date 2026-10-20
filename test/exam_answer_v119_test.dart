// Tests for the v1.0.119 theory-answer round:
// - resolveAnswerDisplayNames fills blank course/subcourse/section names
//   from the parent exam set's IDs (old submissions saved only IDs).
// - My Answer Sheet: published outcome renders the result card and never
//   the admin message; rejected outcome renders the Reason card instead.
// - Upload/Edit form: message is required, the submit button stays
//   disabled until name + PDF + message are all present, and edit mode
//   labels the button "Update Data".
// - My Submissions header reads "My Answer Submissions".
//
// Network is fully mocked through FirestoreRest.setTestClient (MockClient)
// with a seeded signed-in session — the purchase_detail_reads_test pattern.
import 'dart:convert';

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

void _mockFirestore() {
  FirestoreRest.setTestClient(MockClient((request) async {
    final path = request.url.path;
    for (final entry in _routes.entries) {
      if (path.contains(entry.key)) {
        // Bytes, not String: http.Response(String) is Latin-1 and throws
        // on Devanagari fixture values (real Firestore serves UTF-8 JSON).
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

/// Unmounts the tree (disposing periodic timers) and runs out the finite
/// entrance delays/animations so no timer is left pending at test end.
Future<void> _flush(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

GoRouter _router(String initial, List<RouteBase> routes) =>
    GoRouter(initialLocation: initial, routes: routes);

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
  });

  tearDown(() {
    FirestoreRest.setTestClient(null);
  });

  group('resolveAnswerDisplayNames', () {
    test('fills blank names from the exam set IDs', () async {
      _routes = {
        'app_exam_sets/s1': _doc('app_exam_sets/s1', {
          'courseId': 'c1',
          'subcourseId': 'sc1',
          'sectionId': 'theory-desk',
        }),
        'app_courses/c1/subcourses/sc1':
            _doc('app_courses/c1/subcourses/sc1', {'name': 'Kharidar'}),
        'app_courses/c1': _doc('app_courses/c1', {'name': 'Loksewa Course'}),
        'documents/app_exam_sections': {
          'documents': [
            _doc('app_exam_sections/theory-desk', {
              'nameEn': 'Theory Desk',
              'nameNe': 'थ्योरी डेस्क',
              'kind': 'theory',
            }),
          ],
        },
      };
      _mockFirestore();
      final names = await resolveAnswerDisplayNames(const {
        'examSetId': 's1',
        'courseName': '',
        'subcourseName': '',
        'sectionName': '',
      });
      expect(names.courseName, 'Loksewa Course');
      expect(names.subcourseName, 'Kharidar');
      expect(names.sectionName, 'Theory Desk');
    });

    test('stored names win and need no lookups', () async {
      _mockFirestore(); // every route 404s
      final names = await resolveAnswerDisplayNames(const {
        'examSetId': 's1',
        'courseName': 'Stored Course',
        'subcourseName': 'Stored Sub',
        'sectionName': 'Stored Section',
      });
      expect(names.courseName, 'Stored Course');
      expect(names.subcourseName, 'Stored Sub');
      expect(names.sectionName, 'Stored Section');
    });
  });

  group('ExamAnswerScreen outcomes', () {
    GoRouter routerFor() => _router('/exam-answer/a1', [
          GoRoute(
            path: '/exam-answer/upload',
            builder: (_, __) => const Scaffold(body: Text('Upload')),
          ),
          GoRoute(
            path: '/exam-answer/:id',
            builder: (_, s) => ExamAnswerScreen(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/pdf/:id',
            builder: (_, __) => const Scaffold(body: Text('PDF')),
          ),
          GoRoute(
            path: '/contact-us',
            builder: (_, __) => const Scaffold(body: Text('Contact')),
          ),
        ]);

    testWidgets('published: result card, note, view-checked; no admin msg',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      _routes = {
        'app_exam_answers/a1': _doc('app_exam_answers/a1', {
          'uid': 'u1',
          'status': 'reviewed',
          'studentName': 'Ram Bahadur',
          'examSetTitle': 'Theory Paper 1',
          'courseName': 'Loksewa Course',
          'subcourseName': 'Kharidar',
          'sectionName': 'Theory Desk',
          'score': 80,
          'fullMarks': 100,
          'passed': true,
          'reviewNote': 'Well done, Ram.',
          'adminMessage': 'SECRET ADMIN MESSAGE',
          'checkedPdfUrl': 'https://example.com/checked.pdf',
          'pdfUrl': 'https://example.com/submitted.pdf',
          'message': 'Please check',
          'createdAt': '2026-10-10T10:00:00.000Z',
          'reviewedAt': '2026-10-12T10:00:00.000Z',
        }),
      };
      _mockFirestore();
      await tester.pumpWidget(MaterialApp.router(routerConfig: routerFor()));
      await _pumpUntil(tester, find.text('Passed'));

      expect(find.text('80 / 100'), findsOneWidget);
      expect(find.text("Teacher's Note"), findsOneWidget);
      expect(find.text('Well done, Ram.'), findsOneWidget);
      expect(find.text('View Checked PDF'), findsOneWidget);
      expect(find.text('Download Checked PDF'), findsNothing);
      expect(find.text('SECRET ADMIN MESSAGE'), findsNothing);
      expect(find.text('Reason'), findsNothing);
      expect(find.text('Submission Info'), findsOneWidget);
      expect(find.text('Reviewed'), findsOneWidget);
      await _flush(tester);
    });

    testWidgets('rejected: reason card shows, result card absent',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      _routes = {
        'app_exam_answers/a1': _doc('app_exam_answers/a1', {
          'uid': 'u1',
          'status': 'reviewed',
          'studentName': 'Ram Bahadur',
          'examSetTitle': 'Theory Paper 1',
          'courseName': 'Loksewa Course',
          'subcourseName': 'Kharidar',
          'sectionName': 'Theory Desk',
          'rejectionReason': 'Answer sheet is unreadable',
          'adminMessage': 'Please re-upload a clearer scan.',
          'reviewNote': '',
          'checkedPdfUrl': '',
          'pdfUrl': 'https://example.com/submitted.pdf',
          'createdAt': '2026-10-10T10:00:00.000Z',
          'reviewedAt': '2026-10-12T10:00:00.000Z',
        }),
      };
      _mockFirestore();
      await tester.pumpWidget(MaterialApp.router(routerConfig: routerFor()));
      await _pumpUntil(tester, find.text('Reason'));

      // v1.0.120: the reason shows twice — the Rejected crown's
      // subtitle and the Reason card's title below it.
      expect(find.text('Answer sheet is unreadable'), findsWidgets);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Please re-upload a clearer scan.'), findsOneWidget);
      expect(find.text('Passed'), findsNothing);
      expect(find.text('Not Passed'), findsNothing);
      expect(find.text('View Checked PDF'), findsNothing);
      expect(find.text("Teacher's Note"), findsNothing);
      await _flush(tester);
    });
  });

  group('UploadAnswerScreen form', () {
    GoRouter routerFor(String loc) => _router(loc, [
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
        ]);

    GestureDetector buttonOf(WidgetTester tester, String label) =>
        tester.widget<GestureDetector>(find
            .ancestor(
                of: find.text(label), matching: find.byType(GestureDetector))
            .first);

    testWidgets('edit mode: Update Data label, gated until message filled',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      _routes = {
        'app_exam_answers/a1': _doc('app_exam_answers/a1', {
          // v1.0.120: edit mode is gated (owner + pending + inside the
          // 1-hour window + edit unused) — the fixture must qualify.
          'uid': 'u1',
          'studentName': 'Ram Bahadur',
          'pdfUrl': 'https://example.com/a.pdf',
          'message': '',
          'status': 'pending',
          'createdAt': DateTime.now()
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
        }),
      };
      _mockFirestore();
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: routerFor('/exam-answer/upload?editId=a1')));
      await _pumpUntil(tester, find.text('Update Data'));

      expect(find.text('Save Changes'), findsNothing);
      expect(find.text('Message for the teacher *'), findsOneWidget);
      expect(find.textContaining('(optional)'), findsNothing);
      // Name + PDF are present but the message is empty → disabled.
      expect(buttonOf(tester, 'Update Data').onTap, isNull);

      await tester.enterText(find.byType(TextField).last, 'Please check');
      await tester.pump(const Duration(milliseconds: 100));
      expect(buttonOf(tester, 'Update Data').onTap, isNotNull);
      await _flush(tester);
    });

    testWidgets('new upload: Submit label, disabled while incomplete',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      _routes = {
        'app_exam_sets/s1': _doc('app_exam_sets/s1', {
          'title': 'Theory Paper 1',
          'courseId': 'c1',
          'subcourseId': 'sc1',
          'sectionId': 'theory-desk',
        }),
        'users/u1': _doc('users/u1', {'examAnswerIds': <String>[]}),
      };
      _mockFirestore();
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: routerFor('/exam-answer/upload?examSetId=s1')));
      await _pumpUntil(tester, find.text('Submit'));

      expect(find.text('Theory Paper 1'), findsOneWidget);
      expect(buttonOf(tester, 'Submit').onTap, isNull);
      await _flush(tester);
    });
  });

  testWidgets('My Submissions header reads My Answer Submissions',
      (tester) async {
    _routes = {
      'users/u1': _doc('users/u1', {'examAnswerIds': <String>[]}),
    };
    _mockFirestore();
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: _router('/exam-answer/my-submissions', [
        GoRoute(
          path: '/exam-answer/my-submissions',
          builder: (_, __) => const MySubmissionsScreen(),
        ),
        GoRoute(
          path: '/exam-answer/:id',
          builder: (_, __) => const Scaffold(body: Text('Detail')),
        ),
      ]),
    ));
    await _pumpUntil(tester, find.text('My Answer Submissions'));
    // Page header + hero band both carry the full name now.
    expect(find.text('My Answer Submissions'), findsWidgets);
    expect(find.text('No submissions yet'), findsOneWidget);
    await _flush(tester);
  });

  group('Back behavior (post-submit / deep-link landings)', () {
    Map<String, Object> publishedAnswer() => {
          'app_exam_answers/a1': _doc('app_exam_answers/a1', {
            'uid': 'u1',
            'status': 'reviewed',
            'studentName': 'Ram Bahadur',
            'examSetId': 's1',
            'examSetTitle': 'Theory Paper 1',
            'courseName': 'Loksewa Course',
            'subcourseName': 'Kharidar',
            'sectionName': 'Theory Desk',
            'score': 80,
            'fullMarks': 100,
            'passed': true,
            'pdfUrl': 'https://example.com/submitted.pdf',
            'createdAt': '2026-10-10T10:00:00.000Z',
            'reviewedAt': '2026-10-12T10:00:00.000Z',
          }),
          'users/u1': _doc('users/u1', {'examAnswerIds': <String>[]}),
        };

    List<RouteBase> backRoutes() => [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('HOME HUB')),
          ),
          GoRoute(
            path: '/exam-answer/upload',
            builder: (_, __) => const UploadAnswerScreen(),
          ),
          GoRoute(
            path: '/exam-answer/my-submissions',
            builder: (_, __) => const MySubmissionsScreen(),
          ),
          GoRoute(
            path: '/exam-answer/:id',
            builder: (_, s) => ExamAnswerScreen(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/pdf/:id',
            builder: (_, __) => const Scaffold(body: Text('PDF')),
          ),
          GoRoute(
            path: '/contact-us',
            builder: (_, __) => const Scaffold(body: Text('Contact')),
          ),
        ];

    void setView(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    String location(GoRouter r) =>
        r.routerDelegate.currentConfiguration.last.matchedLocation;

    testWidgets(
        'answer page as ROOT: back falls back to My Submissions over home',
        (tester) async {
      setView(tester);
      _routes = publishedAnswer();
      _mockFirestore();
      final router = _router('/exam-answer/a1', backRoutes());
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _pumpUntil(tester, find.text('Passed'));
      expect(location(router), '/exam-answer/a1');

      // System back must NOT close the app: it lands on the parent
      // (My Submissions) with home underneath.
      await tester.binding.handlePopRoute();
      await _pumpUntil(tester, find.text('My Answer Submissions'));
      expect(location(router), '/exam-answer/my-submissions');

      // Back again reaches the hub (in the real app the tabs shell's
      // exit confirmation takes over from there — never a silent close).
      await tester.binding.handlePopRoute();
      await _pumpUntil(tester, find.text('HOME HUB'));
      expect(location(router), '/');
      await _flush(tester);
    });

    testWidgets('answer page IN a stack: back pops normally', (tester) async {
      setView(tester);
      _routes = publishedAnswer();
      _mockFirestore();
      final router = _router('/', backRoutes());
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _pumpUntil(tester, find.text('HOME HUB'));

      router.push('/exam-answer/a1');
      await _pumpUntil(tester, find.text('Passed'));
      expect(location(router), '/exam-answer/a1');

      await tester.binding.handlePopRoute();
      await _pumpUntil(tester, find.text('HOME HUB'));
      expect(location(router), '/');
      await _flush(tester);
    });

    testWidgets(
        'post-submit landing stack: My Submissions over home, back returns home',
        (tester) async {
      setView(tester);
      _routes = publishedAnswer();
      _mockFirestore();
      final router = _router('/', backRoutes());
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _pumpUntil(tester, find.text('HOME HUB'));

      // The stack the fixed submit redirect builds: home -> My Submissions.
      router.push('/exam-answer/my-submissions');
      await _pumpUntil(tester, find.text('My Answer Submissions'));

      await tester.binding.handlePopRoute();
      await _pumpUntil(tester, find.text('HOME HUB'));
      expect(location(router), '/');
      await _flush(tester);
    });

    testWidgets(
        'duplicate guard lands on the existing answer OVER home (no root trap)',
        (tester) async {
      setView(tester);
      _routes = {
        ...publishedAnswer(),
        'users/u1': _doc('users/u1', {
          'examAnswerIds': ['a1'],
        }),
        'app_exam_sets/s1': _doc('app_exam_sets/s1', {
          'title': 'Theory Paper 1',
          'courseId': 'c1',
          'subcourseId': 'sc1',
          'sectionId': 'theory-desk',
        }),
      };
      _mockFirestore();
      final router = _router('/', backRoutes());
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _pumpUntil(tester, find.text('HOME HUB'));

      // Opening the upload page for a set the user already answered
      // triggers the duplicate guard during init.
      router.push('/exam-answer/upload?examSetId=s1');
      await _pumpUntil(tester, find.text('Passed'));
      expect(location(router), '/exam-answer/a1');

      // The guard preserved home underneath: back pops there instead
      // of closing the app.
      await tester.binding.handlePopRoute();
      await _pumpUntil(tester, find.text('HOME HUB'));
      expect(location(router), '/');
      await _flush(tester);
    });
  });
}
