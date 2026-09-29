import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/learn/pdf_screen.dart';

/// path_provider has no platform implementation under flutter_test — stub
/// getTemporaryDirectory so the cache-dir step behaves like a real device.
void _stubPathProvider(WidgetTester tester, String dirPath) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getTemporaryDirectory') return dirPath;
      return null;
    },
  );
  Directory(dirPath).createSync(recursive: true);
}

void main() {
  testWidgets('no paper attached shows the not-found state',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PdfScreen(id: 's1', uri: '', title: 'Syllabus'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Syllabus'), findsOneWidget);
    expect(find.text('No paper attached'), findsOneWidget);
    expect(find.text('Go Back'), findsOneWidget);
    // No download attempted: no loading indicator, no retry button.
    expect(find.text("Couldn't load paper"), findsNothing);
  });

  testWidgets('failed download shows the error state with retry',
      (WidgetTester tester) async {
    _stubPathProvider(tester, '/tmp/pdf_screen_test_cache');
    await tester.pumpWidget(
      MaterialApp(
        home: PdfScreen(
          id: 's1',
          uri: 'https://example.com/syllabus.pdf',
          title: 'Syllabus',
          downloadBytes: (_) async => throw Exception('offline'),
        ),
      ),
    );
    // Download throws -> error state. (No pumpAndSettle: PreloadingWidget
    // animates forever, so advance the clock manually instead.)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text("Couldn't load paper"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('header chrome renders on the viewer',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PdfScreen(id: 's1', uri: '', title: 'My Paper'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My Paper'), findsOneWidget);
  });

  testWidgets('loading state shows only the Loading Pdf label',
      (WidgetTester tester) async {
    _stubPathProvider(tester, '/tmp/pdf_screen_test_cache');
    // Never-completing download: the screen stays in the loading state.
    final gate = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfScreen(
          id: 's1',
          uri: 'https://example.com/syllabus.pdf',
          title: 'Syllabus',
          downloadBytes: (_) => gate.future,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Loading Pdf'), findsOneWidget);
    // No download progress UI: no %, no MB counter, no progress bar.
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('MB'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text("Couldn't load paper"), findsNothing);
  });

  double headerFactor(WidgetTester tester) =>
      tester.widget<SizeTransition>(find.byType(SizeTransition))
          .sizeFactor
          .value;

  double crossOpacity(WidgetTester tester) =>
      tester
          .widget<FadeTransition>(
              find.byKey(const ValueKey('pdf-fullscreen-close')))
          .opacity
          .value;

  testWidgets('fullscreen slides the header away and fades in the close',
      (WidgetTester tester) async {
    _stubPathProvider(tester, '/tmp/pdf_screen_test_cache');
    await tester.pumpWidget(
      MaterialApp(
        home: PdfScreen(
          id: 's1',
          uri: 'https://example.com/syllabus.pdf',
          title: 'Syllabus',
          downloadBytes: (_) async => throw Exception('offline'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text("Couldn't load paper"), findsOneWidget);

    // Header fully shown, close button fully transparent.
    expect(headerFactor(tester), 1.0);
    expect(crossOpacity(tester), 0.0);

    // Enter fullscreen: header collapses, close fades in.
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(headerFactor(tester), 0.0);
    expect(crossOpacity(tester), 1.0);

    // Exit via the close button: header slides back, close fades out.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(headerFactor(tester), 1.0);
    expect(crossOpacity(tester), 0.0);
    expect(find.text('Syllabus'), findsOneWidget);
  });
}
