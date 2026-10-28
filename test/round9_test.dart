// Tests for the v1.0.125 round (Round 9):
// - A: download popup lockdown — while a download is in progress the
//   popup has NO X close icon, PopScope vetoes back, and the barrier
//   (presented non-dismissible, as every call site now does) does not
//   dismiss it; after a failed settle the X returns.
// - B: the generalized dialog modes — generic URL mode saves non-PDF
//   bytes without the %PDF gate; local-bytes mode saves in-memory
//   bytes with no network.
// - C: the checked-PDF daily limit — Kathmandu day key boundaries and
//   the stamp/mirror "downloaded today" derivation (stamp lands only
//   on success by construction: it is written from the save-success
//   callback, never from the dialog's failure/cancel paths).
// - D: the Re-Apply derivation (published / rejected / other-pending /
//   other-reviewed), per-set grouping (latest wins), My Submissions
//   one-row-per-set, and the detail page's Previous Submissions
//   history.
//
// Network is fully mocked through CfApi.setTestClient (MockClient)
// with a seeded signed-in session — the exam_answer_v120_test pattern.
// Phase-2: fixtures are plain CF JSON ({ok, row}/{ok, rows}).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loksewa_solution/screens/shop/exam_answer_screen.dart';
import 'package:loksewa_solution/screens/shop/my_submissions_screen.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/pdf_download_dialog.dart';

/// Path-substring routes → CF response bodies, matched in insertion
/// order. Unmatched paths answer 404 {ok:false}.
Map<String, Object> _routes = {};

void _mockCf() {
  CfApi.setTestClient(MockClient((request) async {
    final path = request.url.path;
    for (final entry in _routes.entries) {
      if (path.contains(entry.key)) {
        return http.Response.bytes(
            utf8.encode(json.encode(entry.value)), 200);
      }
    }
    return http.Response.bytes(
        utf8.encode(json.encode({'ok': false, 'error': 'not_found'})), 404);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsService.setString(
      CfApi.sessionPrefsKey,
      json.encode({
        'user': {
          'uid': 'u1',
          'email': 'a@b.c',
          'name': 'Test',
          'photoURL': null,
        },
        'accessToken': 'test-access-token',
        'refreshToken': 'ref',
      }),
    );
    await AuthService.peekSavedSession();
    _routes = {};
  });

  tearDown(() {
    CfApi.setTestClient(null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('C: kathmanduDayKey', () {
    test('Kathmandu is UTC+5:45 — the day flips at 18:15 UTC', () {
      // 18:14:59 UTC = 23:59:59 Kathmandu, same day.
      expect(kathmanduDayKey(DateTime.utc(2026, 1, 1, 18, 14, 59)),
          '2026-01-01');
      // 18:15:00 UTC = 00:00:00 Kathmandu, next day.
      expect(kathmanduDayKey(DateTime.utc(2026, 1, 1, 18, 15, 0)),
          '2026-01-02');
    });

    test('early UTC morning is the same Kathmandu day', () {
      expect(kathmanduDayKey(DateTime.utc(2026, 6, 15, 0, 0)), '2026-06-15');
      expect(
          kathmanduDayKey(DateTime.utc(2026, 6, 15, 12, 0)), '2026-06-15');
    });

    test('year boundary rolls over in Kathmandu first', () {
      expect(kathmanduDayKey(DateTime.utc(2025, 12, 31, 18, 15)),
          '2026-01-01');
      expect(kathmanduDayKey(DateTime.utc(2025, 12, 31, 18, 14)),
          '2025-12-31');
    });
  });

  group('C: checkedDownloadLimitReached', () {
    const today = '2026-10-21';

    test('server stamp from today reaches the limit', () {
      expect(
          checkedDownloadLimitReached(
              downloadedDay: today, mirrorDay: null, today: today),
          isTrue);
    });

    test('local mirror from today reaches the limit on its own', () {
      // The rules update that permits the server stamp may not be
      // published yet — the mirror alone must still hold the limit.
      expect(
          checkedDownloadLimitReached(
              downloadedDay: null, mirrorDay: today, today: today),
          isTrue);
      expect(
          checkedDownloadLimitReached(
              downloadedDay: '2026-10-19',
              mirrorDay: today,
              today: today),
          isTrue);
    });

    test('older stamps (yesterday) do not reach the limit', () {
      expect(
          checkedDownloadLimitReached(
              downloadedDay: '2026-10-20',
              mirrorDay: '2026-10-20',
              today: today),
          isFalse);
    });

    test('no stamps at all -> not reached (failed/cancelled stay free)',
        () {
      expect(
          checkedDownloadLimitReached(
              downloadedDay: null, mirrorDay: null, today: today),
          isFalse);
      expect(
          checkedDownloadLimitReached(
              downloadedDay: '', mirrorDay: '', today: today),
          isFalse);
    });

    test('mirror key is per-answer', () {
      expect(checkedPdfDownloadDayMirrorKey('a1'),
          'checked_pdf_downloaded_day_a1');
      expect(checkedPdfDownloadDayMirrorKey('a1'),
          isNot(checkedPdfDownloadDayMirrorKey('a2')));
    });
  });

  group('D: reappliable derivation', () {
    ExamAnswer answer(Map<String, Object?> fields) =>
        ExamAnswer.fromMap({'id': 'a1', 'uid': 'u1', 'examSetId': 's1', ...fields});

    test('published: reviewed + reviewedAt + no reason -> NOT reappliable',
        () {
      final a = answer({
        'status': 'reviewed',
        'rejectionReason': '',
        'reviewedAt': '2026-10-12T10:00:00.000Z',
        'passed': true,
      });
      expect(a.isPublished, isTrue);
      expect(a.isReappliable, isFalse);
      expect(
          examAnswerIsReappliable({
            'status': 'reviewed',
            'rejectionReason': '',
            'reviewedAt': '2026-10-12T10:00:00.000Z',
          }),
          isFalse);
    });

    test('rejected: reviewed + reason (passed null) -> reappliable', () {
      final a = answer({
        'status': 'reviewed',
        'rejectionReason': 'Answer sheet unclear',
        'reviewedAt': '2026-10-12T10:00:00.000Z',
        'passed': null,
      });
      expect(a.isRejected, isTrue);
      expect(a.isPublished, isFalse);
      expect(a.isReappliable, isTrue);
    });

    test('still pending -> NOT reappliable (request is in the queue)',
        () {
      final a = answer({'status': 'pending', 'reviewedAt': null});
      expect(a.isPublished, isFalse);
      expect(a.isReappliable, isFalse);
    });

    test(
        'other-save -> pending (reviewedAt cleared) -> NOT reappliable',
        () {
      // Admin "Other Reason and Save" with status Pending writes
      // status 'pending' + reviewedAt null: still queued.
      final a = answer({'status': 'pending', 'reviewedAt': null});
      expect(a.isReappliable, isFalse);
    });

    test(
        'other-save -> reviewed WITHOUT reviewedAt stamp -> closed, '
        'NOT published -> reappliable', () {
      // "Other Reason and Save" never stamps reviewedAt and (without a
      // pass override) leaves passed null: the app must not mistake
      // this for a published result.
      final a = answer({
        'status': 'reviewed',
        'rejectionReason': '',
        'reviewedAt': null,
        'passed': null,
      });
      expect(a.isPublished, isFalse);
      expect(a.isReappliable, isTrue);
      expect(
          examAnswerIsPublished({
            'status': 'reviewed',
            'rejectionReason': '',
            'reviewedAt': null,
          }),
          isFalse);
    });
  });

  group('D: grouping — latest wins per set', () {
    ExamAnswer a(String id, String setId, String createdAt) =>
        ExamAnswer.fromMap({
          'id': id,
          'uid': 'u1',
          'examSetId': setId,
          'status': 'pending',
          'createdAt': createdAt,
        });

    test('latestExamAnswersBySet picks the newest submission', () {
      final bySet = latestExamAnswersBySet([
        a('old', 's1', '2026-10-01T10:00:00.000Z'),
        a('solo', 's2', '2026-10-02T10:00:00.000Z'),
        a('new', 's1', '2026-10-05T10:00:00.000Z'),
        a('mid', 's1', '2026-10-03T10:00:00.000Z'),
      ]);
      expect(bySet.keys, containsAll(['s1', 's2']));
      expect(bySet['s1']!.id, 'new');
      expect(bySet['s2']!.id, 'solo');
    });

    test('groupExamAnswersBySet sorts each group newest-first', () {
      final groups = groupExamAnswersBySet([
        a('old', 's1', '2026-10-01T10:00:00.000Z'),
        a('new', 's1', '2026-10-05T10:00:00.000Z'),
        a('mid', 's1', '2026-10-03T10:00:00.000Z'),
      ]);
      expect(groups['s1']!.map((e) => e.id), ['new', 'mid', 'old']);
    });

    test('latestSubmissionsBySet: one row per set, newest-first rows',
        () {
      final rows = latestSubmissionsBySet([
        {
          'id': 'a1',
          'examSetId': 's1',
          'createdAt': '2026-10-01T10:00:00.000Z',
        },
        {
          'id': 'a3',
          'examSetId': 's2',
          'createdAt': '2026-10-04T10:00:00.000Z',
        },
        {
          'id': 'a2',
          'examSetId': 's1',
          'createdAt': '2026-10-05T10:00:00.000Z',
        },
      ]);
      expect(rows.map((r) => r['id']), ['a2', 'a3']);
    });

    test('latestSubmissionsBySet keeps docs without a set id', () {
      final rows = latestSubmissionsBySet([
        {'id': 'x1', 'createdAt': '2026-10-01T10:00:00.000Z'},
        {'id': 'x2', 'createdAt': '2026-10-02T10:00:00.000Z'},
      ]);
      expect(rows.length, 2);
    });
  });

  group('A+B: dialog lockdown and generic modes', () {
    testWidgets(
        'in progress: no X, back vetoed, barrier tap does not dismiss',
        (tester) async {
      _setView(tester);
      final gate = Completer<Uint8List>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (homeCtx) => Center(
              child: ElevatedButton(
                onPressed: () => AppModalShell.show(
                  context: homeCtx,
                  barrierDismissible: false,
                  builder: (ctx) => PdfDownloadDialog(
                    url: 'https://example.com/a.pdf',
                    fileName: 'checked.pdf',
                    downloadFn: (url, onProgress) => gate.future,
                    notifyProgress: false,
                    onDone: () {},
                    onClose: () => Navigator.of(ctx).pop(),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pump(const Duration(milliseconds: 300));

      // The popup is up, mid-download.
      expect(find.text('Downloading PDF'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // No X close icon while in progress.
      expect(find.byIcon(Icons.close), findsNothing);
      // Back is vetoed.
      final scope = tester.widget<PopScope>(find.descendant(
          of: find.byType(PdfDownloadDialog),
          matching: find.byType(PopScope)));
      expect(scope.canPop, isFalse);

      // A barrier tap must not dismiss it either.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Downloading PDF'), findsOneWidget);

      // Unmount cleanly (dispose aborts via the seam future).
      gate.completeError(Exception('aborted'));
      await _flush(tester);
    });

    testWidgets('failed settle: X returns and back is allowed again',
        (tester) async {
      _setView(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfDownloadDialog(
            url: 'https://example.com/a.pdf',
            fileName: 'checked.pdf',
            downloadFn: (url, onProgress) async {
              onProgress(10, 10);
              return Uint8List.fromList(
                  '<!DOCTYPE html><html>oops</html>'.codeUnits);
            },
            notifyProgress: false,
            onDone: () {},
            onClose: () {},
          ),
        ),
      ));
      await _pumpUntil(tester, find.text('Download failed'));
      expect(find.byIcon(Icons.close), findsOneWidget);
      final scope = tester.widget<PopScope>(find.descendant(
          of: find.byType(PdfDownloadDialog),
          matching: find.byType(PopScope)));
      expect(scope.canPop, isTrue);
      await _flush(tester);
    });

    testWidgets('generic mode: non-PDF bytes save without the PDF gate',
        (tester) async {
      _setView(tester);
      Uint8List? savedBytes;
      bool? saved;
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfDownloadDialog(
            url: 'https://example.com/qr.png',
            fileName: 'Ls-qr.png',
            validatePdf: false,
            mimeType: 'image/png',
            downloadFn: (url, onProgress) async {
              onProgress(png.length, png.length);
              return png;
            },
            saveFn: (bytes) async {
              savedBytes = bytes;
              return true;
            },
            notifyProgress: false,
            onDone: () {},
            onSaved: (v) => saved = v,
            onClose: () {},
          ),
        ),
      ));
      await _pumpUntilTrue(tester, () => saved != null);
      expect(saved, isTrue);
      expect(savedBytes, png);
      await _flush(tester);
    });

    testWidgets('local-bytes mode: in-memory bytes save, no fetch',
        (tester) async {
      _setView(tester);
      Uint8List? savedBytes;
      bool? saved;
      final payload = Uint8List.fromList('{"notes":[]}'.codeUnits);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfDownloadDialog(
            localBytes: payload,
            fileName: 'notes-backup.json',
            validatePdf: false,
            mimeType: 'application/json',
            saveFn: (bytes) async {
              savedBytes = bytes;
              return true;
            },
            notifyProgress: false,
            onDone: () {},
            onSaved: (v) => saved = v,
            onClose: () {},
          ),
        ),
      ));
      await _pumpUntilTrue(tester, () => saved != null);
      expect(saved, isTrue);
      expect(savedBytes, payload);
      await _flush(tester);
    });

    testWidgets('task mode: job result drives success/failure',
        (tester) async {
      _setView(tester);
      bool? saved;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfDownloadDialog(
            fileName: 'Some Feature',
            taskFn: (onProgress, isCancelled) async {
              onProgress(1, 2);
              onProgress(2, 2);
              return true;
            },
            validatePdf: false,
            notifyProgress: false,
            onDone: () {},
            onSaved: (v) => saved = v,
            onClose: () {},
          ),
        ),
      ));
      await _pumpUntilTrue(tester, () => saved != null);
      expect(saved, isTrue);
      await _flush(tester);
    });
  });

  group('D: My Submissions grouping + detail history', () {
    GoRouter routerFor(String loc) => GoRouter(
          initialLocation: loc,
          routes: [
            GoRoute(
              path: '/exam-answer/my-submissions',
              builder: (_, __) => const MySubmissionsScreen(),
            ),
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

    Map<String, Object?> answerFields({
      required String status,
      required String setId,
      required String title,
      required String createdAt,
      String? rejectionReason,
      String? reviewedAt,
      Object? passed,
      String? downloadedDay,
    }) =>
        {
          'uid': 'u1',
          'status': status,
          'studentName': 'Ram Bahadur',
          'examSetId': setId,
          'examSetTitle': title,
          'courseName': 'Loksewa Course',
          'subcourseName': 'Kharidar',
          'sectionName': 'Theory Desk',
          'pdfUrl': 'https://example.com/submitted.pdf',
          'message': 'Please check',
          'createdAt': createdAt,
          if (rejectionReason != null) 'rejectionReason': rejectionReason,
          if (reviewedAt != null) 'reviewedAt': reviewedAt,
          if (passed != null) 'passed': passed,
          if (downloadedDay != null) 'downloadedDay': downloadedDay,
        };

    testWidgets('list shows ONE row per set — the latest submission',
        (tester) async {
      _setView(tester);
      _routes = {
        '/exam-answers/mine': {
          'ok': true,
          'rows': [
            {
              'id': 'a1',
              ...answerFields(
                status: 'reviewed',
                setId: 's1',
                title: 'Set One',
                createdAt: '2026-10-01T10:00:00.000Z',
                rejectionReason: 'Answer sheet is unreadable',
                reviewedAt: '2026-10-02T10:00:00.000Z',
              ),
            },
            {
              'id': 'a2',
              ...answerFields(
                status: 'pending',
                setId: 's1',
                title: 'Set One',
                createdAt: '2026-10-05T10:00:00.000Z',
              ),
            },
            {
              'id': 'a3',
              ...answerFields(
                status: 'reviewed',
                setId: 's2',
                title: 'Set Two',
                createdAt: '2026-10-04T10:00:00.000Z',
                reviewedAt: '2026-10-06T10:00:00.000Z',
                passed: true,
              ),
            },
          ],
        },
      };
      _mockCf();
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: routerFor('/exam-answer/my-submissions')));
      await _pumpUntil(tester, find.text('Set One'));
      // Exactly one card per set…
      expect(find.text('Set One'), findsOneWidget);
      expect(find.text('Set Two'), findsOneWidget);
      // …and the s1 card is the LATEST (pending) one — the rejected
      // attempt's reason pill must not appear as a list row.
      expect(find.text('Answer sheet is unreadable'), findsNothing);
      await _flush(tester);
    });

    testWidgets(
        'detail: latest in full + Previous Submissions history + Re-Apply',
        (tester) async {
      _setView(tester);
      final a1 = {
        'id': 'a1',
        ...answerFields(
          status: 'reviewed',
          setId: 's1',
          title: 'Set One',
          createdAt: '2026-10-01T10:00:00.000Z',
          rejectionReason: 'Answer sheet is unreadable',
          reviewedAt: '2026-10-02T10:00:00.000Z',
        ),
      };
      final a2 = {
        'id': 'a2',
        ...answerFields(
          status: 'reviewed',
          setId: 's1',
          title: 'Set One',
          createdAt: '2026-10-05T10:00:00.000Z',
          rejectionReason: 'Wrong file uploaded',
          reviewedAt: '2026-10-06T10:00:00.000Z',
        ),
      };
      _routes = {
        '/exam-answers/a2': {'ok': true, 'row': a2},
        '/exam-answers/mine': {
          'ok': true,
          'rows': [a1, a2],
        },
      };
      _mockCf();
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: routerFor('/exam-answer/a2')));
      // The latest (a2, rejected) is the full view: its reason card…
      await _pumpUntil(tester, find.text('Wrong file uploaded'));
      // …the Re-Apply button (rejected -> reappliable)…
      await _pumpUntil(tester, find.text('Re-Apply'));
      expect(find.text('Re-Apply'), findsOneWidget);
      // …and the older attempt folded into the history section.
      await _pumpUntil(tester, find.text('Previous Submissions'));
      expect(find.text('Answer sheet is unreadable'), findsOneWidget);
      await _flush(tester);
    });
  });
}
