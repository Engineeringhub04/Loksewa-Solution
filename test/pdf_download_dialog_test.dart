import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:loksewa_solution/widgets/pdf_download_dialog.dart';

/// Stubs the native media channel's saveToDownloads (v1.0.120) to answer
/// null — "public Downloads unavailable" — so the dialog exercises its
/// app-folder fallback write, exactly like an old-Android device.
/// Without a stub the unregistered channel's future never completes
/// under FakeAsync and the dialog would hang before saving.
void _stubMediaSave(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('loksewa_solution/media'),
    (call) async => null,
  );
}

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

/// URL-keyed fake client for the candidate walk (v1.0.122): answers
/// 200 with the mapped bytes, 404 for anything unmapped, and records
/// every requested URL in order.
class _MapClient extends http.BaseClient {
  final Map<String, List<int>> responses;
  final List<String> requested = [];
  _MapClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = request.url.toString();
    requested.add(key);
    final bytes = responses[key];
    if (bytes == null) {
      return http.StreamedResponse(const Stream.empty(), 404,
          contentLength: 0);
    }
    return http.StreamedResponse(
      Stream.fromIterable([bytes]),
      200,
      contentLength: bytes.length,
    );
  }
}

Future<void> _pumpUntil(
    WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 40 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// PDF-shaped fake bytes (v1.0.121): the dialog refuses to save
/// anything without the '%PDF-' magic, so success-path fakes must
/// carry the header.
Uint8List pdfBytes(int length) {
  final header = '%PDF-1.7\n'.codeUnits;
  return Uint8List.fromList([
    ...header,
    ...List.generate(length - header.length, (i) => i % 256),
  ]);
}

void main() {
  group('downloadPdfBytes', () {
    test('returns full bytes with byte-counted progress', () async {
      // v1.0.122: downloadPdfBytes validates the payload, so the
      // success-path fake must be PDF-shaped (pdfBytes helper).
      final bytes = pdfBytes(100);
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

    test('candidate walk: HTML first candidate falls through to PDF',
        () async {
      const shareUrl = 'https://drive.google.com/file/d/ABC123/view';
      const c0 =
          'https://drive.usercontent.google.com/download?id=ABC123&export=download&confirm=t';
      const c1 =
          'https://drive.google.com/uc?export=download&id=ABC123&confirm=t';
      final pdf = pdfBytes(64);
      final client = _MapClient({
        // Drive's share/interstitial answer: HTTP 200 but HTML.
        c0: '<!DOCTYPE html><html>preview</html>'.codeUnits,
        c1: pdf,
      });
      final out = await downloadPdfBytes(shareUrl, (_, __) {},
          client: client);
      expect(out, pdf);
      // Tried in candidate order and stopped at the first real PDF.
      expect(client.requested, [c0, c1]);
    });

    test('candidate walk: every candidate bad → throws', () async {
      const shareUrl = 'https://drive.google.com/file/d/ABC123/view';
      final html = '<!DOCTYPE html><html>nope</html>'.codeUnits;
      final client = _MapClient({
        'https://drive.usercontent.google.com/download?id=ABC123&export=download&confirm=t':
            html,
        'https://drive.google.com/uc?export=download&id=ABC123&confirm=t':
            html,
        'https://drive.google.com/uc?export=download&id=ABC123': html,
      });
      await expectLater(
        downloadPdfBytes(shareUrl, (_, __) {}, client: client),
        throwsA(isA<Exception>()),
      );
      // All three Drive candidates were attempted before giving up.
      expect(client.requested.length, 3);
    });
  });

  group('PdfDownloadDialog', () {
    testWidgets('downloads, saves to dir and calls onDone',
        (tester) async {
      _stubMediaSave(tester);
      final bytes = pdfBytes(50);
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
      _stubMediaSave(tester);
      var attempts = 0;
      final tmp = Directory.systemTemp.createTempSync('pdfdlg2');
      var done = false;

      Future<Uint8List> flaky(
          String url, void Function(int, int?) onProgress) async {
        attempts++;
        if (attempts == 1) throw Exception('boom');
        onProgress(10, 10);
        return pdfBytes(12);
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
