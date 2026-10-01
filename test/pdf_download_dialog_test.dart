import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:loksewa_solution/widgets/pdf_download_dialog.dart';

/// Fake HTTP client returning fixed bytes in small chunks with a real
/// contentLength, so progress callbacks are byte-counted and determinate.
class _FakeClient extends http.BaseClient {
  final Uint8List bytes;
  _FakeClient(this.bytes);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    const chunkSize = 7;
    final chunks = <List<int>>[];
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end =
          (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      chunks.add(bytes.sublist(i, end));
    }
    return http.StreamedResponse(
      Stream.fromIterable(chunks),
      200,
      contentLength: bytes.length,
    );
  }
}

class _FailingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream.empty(), 500, contentLength: 0);
}

Future<void> _pumpUntil(
    WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 40 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('downloadPdfBytes', () {
    test('returns full bytes with byte-counted progress', () async {
      final bytes =
          Uint8List.fromList(List.generate(100, (i) => i % 256));
      final seen = <List<int>>[];
      final out = await downloadPdfBytes(
        'http://example.com/a.pdf',
        (r, t) => seen.add([r, t ?? -1]),
        client: _FakeClient(bytes),
      );
      expect(out, bytes);
      expect(seen, isNotEmpty);
      // Final callback reports the full byte count against the total.
      expect(seen.last, [100, 100]);
      // Progress never goes backwards.
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i][0], greaterThanOrEqualTo(seen[i - 1][0]));
      }
    });

    test('throws on non-200 status', () async {
      expect(
        () => downloadPdfBytes('http://example.com/a.pdf', (_, __) {},
            client: _FailingClient()),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PdfDownloadDialog', () {
    testWidgets('downloads, saves to dir and calls onDone',
        (tester) async {
      final bytes = Uint8List.fromList(List.generate(50, (i) => i));
      final tmp = Directory.systemTemp.createTempSync('pdfdlg');
      var done = false;
      var progressCalls = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfDownloadDialog(
            url: 'http://example.com/a.pdf',
            fileName: 'test.pdf',
            // NOTE: the byte-counting of downloadPdfBytes is covered by the
            // unit tests above (real async zone). Stream.timeout never
            // completes its done event under testWidgets' FakeAsync, so the
            // widget test uses a trivial fake for the dialog behavior.
            downloadFn: (url, onProgress) async {
              progressCalls++;
              onProgress(25, 50);
              progressCalls++;
              onProgress(50, 50);
              return bytes;
            },
            resolveDir: () async => tmp,
            onDone: () => done = true,
            onClose: () {},
          ),
        ),
      ));

      // Progress bar is visible while downloading.
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Downloading PDF'), findsOneWidget);

      await _pumpUntil(tester, () => done);
      expect(done, isTrue);
      expect(progressCalls, greaterThan(0));

      final file = File('${tmp.path}/test.pdf');
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), bytes);
      tmp.deleteSync(recursive: true);
    });

    testWidgets('shows error with retry on failure', (tester) async {
      var attempts = 0;
      final tmp = Directory.systemTemp.createTempSync('pdfdlg2');
      var done = false;

      Future<Uint8List> flaky(
          String url, void Function(int, int?) onProgress) async {
        attempts++;
        if (attempts == 1) throw Exception('boom');
        onProgress(10, 10);
        return Uint8List.fromList([1, 2, 3]);
      }

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfDownloadDialog(
            url: 'http://example.com/a.pdf',
            fileName: 'test.pdf',
            downloadFn: flaky,
            resolveDir: () async => tmp,
            onDone: () => done = true,
            onClose: () {},
          ),
        ),
      ));

      await _pumpUntil(tester, () => attempts > 0);
      await _pumpUntil(tester, () => find.text('Retry').evaluate().isNotEmpty);
      expect(find.text('Download failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await _pumpUntil(tester, () => done);
      expect(done, isTrue);
      expect(attempts, 2);
      expect(File('${tmp.path}/test.pdf').existsSync(), isTrue);
      tmp.deleteSync(recursive: true);
    });
  });
}
