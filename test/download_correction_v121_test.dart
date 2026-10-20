// Tests for the v1.0.121 download correction round:
// - looksLikePdf: the dialog's save gate ('%PDF-' magic within the
//   first 1024 bytes; HTML/empty/short bodies rejected).
// - checkedAnswerFileName: clean short save names from the exam set
//   title (the v1.0.120 name embedded the raw answer doc id — a
//   literal space + extreme length that phone viewers rejected).
// - PdfDownloadDialog: non-PDF bytes settle as a FAILED download and
//   save nothing; a MediaStore content-URI answer counts as a public
//   save (onSaved(true)) with no app-folder fallback file.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:loksewa_solution/screens/shop/exam_answer_screen.dart';
import 'package:loksewa_solution/widgets/pdf_download_dialog.dart';

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 40 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('looksLikePdf', () {
    test('accepts a plain PDF header', () {
      expect(
          looksLikePdf(Uint8List.fromList('%PDF-1.7\nbody'.codeUnits)),
          isTrue);
    });

    test('accepts a header after small leading junk', () {
      final bytes = Uint8List.fromList(
          [...List.filled(100, 0x20), ...'%PDF-1.4'.codeUnits]);
      expect(looksLikePdf(bytes), isTrue);
    });

    test('accepts a header ending exactly at byte 1024', () {
      final bytes = Uint8List.fromList(
          [...List.filled(1019, 0x00), ...'%PDF-'.codeUnits]);
      expect(bytes.length, 1024);
      expect(looksLikePdf(bytes), isTrue);
    });

    test('rejects a header that starts past the first 1024 bytes', () {
      final bytes = Uint8List.fromList(
          [...List.filled(1024, 0x00), ...'%PDF-1.7'.codeUnits]);
      expect(looksLikePdf(bytes), isFalse);
    });

    test('rejects an HTML body', () {
      expect(
          looksLikePdf(Uint8List.fromList(
              '<!DOCTYPE html><html><body>Not found</body></html>'
                  .codeUnits)),
          isFalse);
    });

    test('rejects empty and truncated headers', () {
      expect(looksLikePdf(Uint8List(0)), isFalse);
      expect(looksLikePdf(Uint8List.fromList('%PD'.codeUnits)), isFalse);
      expect(looksLikePdf(Uint8List.fromList('%PDFX'.codeUnits)), isFalse);
    });
  });

  group('checkedAnswerFileName', () {
    test('sanitizes spaces and punctuation into single dashes', () {
      expect(
        checkedAnswerFileName('Civil Sub-Engineer: Theory Desk (Set 1)'),
        'checked-answer-civil-sub-engineer-theory-desk-set-1.pdf',
      );
      expect(
        checkedAnswerFileName('Loksewa   Solution___Test'),
        'checked-answer-loksewa-solution-test.pdf',
      );
    });

    test('falls back when nothing keepable remains', () {
      expect(checkedAnswerFileName(''), 'checked-answer-sheet.pdf');
      expect(checkedAnswerFileName('   '), 'checked-answer-sheet.pdf');
      expect(checkedAnswerFileName('!!! ???'), 'checked-answer-sheet.pdf');
      // Non-ASCII-only titles keep nothing ASCII-safe → fallback.
      expect(checkedAnswerFileName('सिविल इन्जिनियर'),
          'checked-answer-sheet.pdf');
    });

    test('caps the title part at 48 chars with no trailing dash', () {
      expect(
        checkedAnswerFileName('a' * 60),
        'checked-answer-${'a' * 48}.pdf',
      );
      // The cap lands right after a separator: the dangling dash the
      // cut leaves behind must be trimmed too.
      expect(
        checkedAnswerFileName('${'a' * 47} bcdefghij'),
        'checked-answer-${'a' * 47}.pdf',
      );
    });

    test('never contains spaces or the doc-id shape', () {
      final name =
          checkedAnswerFileName('iFNwtqjcSKR1xmj6KV 08dg0iLFg2 Set');
      expect(name.contains(' '), isFalse);
      expect(name, startsWith('checked-answer-'));
      expect(name, endsWith('.pdf'));
    });
  });

  group('PdfDownloadDialog v1.0.121 gates', () {
    testWidgets('non-PDF bytes: failure state, nothing saved',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('pdfdlg_v121_a');
      addTearDown(() => tmp.deleteSync(recursive: true));
      bool? saved;
      var done = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfDownloadDialog(
            url: 'http://example.com/a.pdf',
            fileName: 'checked.pdf',
            downloadFn: (url, onProgress) async {
              onProgress(10, 10);
              return Uint8List.fromList(
                  '<!DOCTYPE html><html>oops</html>'.codeUnits);
            },
            saveFn: (bytes) async => true,
            resolveDir: () async => tmp,
            onDone: () => done = true,
            onSaved: (v) => saved = v,
            onClose: () {},
          ),
        ),
      ));

      await _pumpUntil(
          tester, () => find.text('Download failed').evaluate().isNotEmpty);
      expect(find.text('Download failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // The HTML body must not have been saved anywhere, and neither
      // completion callback may have fired.
      expect(saved, isNull);
      expect(done, isFalse);
      expect(File('${tmp.path}/checked.pdf').existsSync(), isFalse);
    });

    testWidgets('content-URI save: onSaved(true), no fallback file',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('loksewa_solution/media'),
        (call) async =>
            call.method == 'saveToDownloads' ? 'content://dl/42' : null,
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('loksewa_solution/media'), null));

      final tmp = Directory.systemTemp.createTempSync('pdfdlg_v121_b');
      addTearDown(() => tmp.deleteSync(recursive: true));
      bool? saved;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfDownloadDialog(
            url: 'http://example.com/a.pdf',
            fileName: 'checked.pdf',
            downloadFn: (url, onProgress) async {
              onProgress(10, 10);
              return Uint8List.fromList('%PDF-1.7 checked'.codeUnits);
            },
            // No saveFn: the dialog must use the URI-returning
            // MediaStore save (mocked above).
            resolveDir: () async => tmp,
            onDone: () {},
            onSaved: (v) => saved = v,
            onClose: () {},
          ),
        ),
      ));

      await _pumpUntil(tester, () => saved != null);
      expect(saved, isTrue);
      expect(File('${tmp.path}/checked.pdf').existsSync(), isFalse);
      // Restored inline: testWidgets asserts foundation debug vars
      // are unset at body end, before addTearDown would run.
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
