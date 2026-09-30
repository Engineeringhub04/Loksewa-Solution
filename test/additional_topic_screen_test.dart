import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loksewa_solution/screens/shop/additional_topic_screen.dart';

// The topic screen fetches its bank via Firestore REST. These tests must never
// touch the network: every http call fails fast via HttpOverrides, so _load
// deterministically falls into the offline-cache fallback (or the error
// state when no cache is seeded).
class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('offline (test)');
  }
}

Map<String, dynamic> _bankJson() => {
      'topicTitleEn': 'Cached Topic',
      'questions': [
        {
          'questionId': 'q1',
          'question': 'What is 2+2?',
          'options': [
            {'id': 'a', 'text': '3'},
            {'id': 'b', 'text': '4'},
          ],
          'correctOption': 2,
          'explanation': 'Basic addition.',
          'difficulty': 'easy',
        },
      ],
    };

/// Seeds <tmp>/af_offline/gk/banks/t1.json + <tmp>/af_offline/gk/page.json and
/// mocks path_provider (via tester.binding, INSIDE the testWidgets body) to
/// serve <tmp> as the app-documents directory. With [seedFiles] false the
/// docs dir is empty, so the offline fallback finds no cache.
Future<void> _seedOfflineCache(WidgetTester tester,
    {bool seedFiles = true}) async {
  final tmp = Directory.systemTemp.createTempSync('af_offline_test');
  final banks = Directory('${tmp.path}/af_offline/gk/banks')
    ..createSync(recursive: true);
  if (seedFiles) {
    File('${banks.path}/t1.json').writeAsStringSync(json.encode(_bankJson()));
    File('${tmp.path}/af_offline/gk/page.json')
        .writeAsStringSync(json.encode({
      'topics': [
        {
          'topicId': 't1',
          'titleEn': 'Page Topic',
          'titleNp': 'Page Topic Np',
        },
      ],
    }));
  }
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tmp.path;
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    tmp.deleteSync(recursive: true);
  });
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _OfflineHttpOverrides();
    SharedPreferences.setMockInitialValues({});
  });

  /// Pumps 200ms frames until [finder] matches (or [max] frames elapse).
  /// Used instead of pumpAndSettle: the loading preloader animates forever,
  /// so settling is only possible after the load finishes.
  Future<void> pumpUntil(
      WidgetTester tester, Finder finder, {int max = 60}) async {
    for (var i = 0; i < max && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets(
      'header shows the route title immediately, before the bank loads',
      (WidgetTester tester) async {
    // No cache seeded: the offline fallback finds nothing, but the docs-dir
    // mock must still be installed — an unmocked getApplicationDocumentsDirectory
    // never resolves under testWidgets.
    await _seedOfflineCache(tester, seedFiles: false);
    await tester.pumpWidget(
      const MaterialApp(
        home: AdditionalTopicScreen(
          featureId: 'gk',
          topicId: 't1',
          topicTitleEn: 'Route Topic',
        ),
      ),
    );
    // First frame: the async load is still in flight — the title must
    // already be visible instead of the '...' placeholder.
    expect(find.text('Route Topic'), findsOneWidget);
    // The offline load then fails (no cache seeded) — the title survives
    // into the error state.
    await pumpUntil(tester, find.text('Unable to load questions.'));
    expect(find.text('Route Topic'), findsOneWidget);
    expect(find.text('Unable to load questions.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'offline fallback reads the cached bank and shows the Offline chip',
      (WidgetTester tester) async {
    await _seedOfflineCache(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: AdditionalTopicScreen(featureId: 'gk', topicId: 't1'),
      ),
    );
    await pumpUntil(tester, find.text('What is 2+2?'));
    // Header fell back to the cached page-doc title; the cached question
    // renders; the Offline chip marks the cached content.
    expect(find.text('Page Topic'), findsOneWidget);
    expect(find.text('What is 2+2?'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Show answer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expand all animates the answer open and closed',
      (WidgetTester tester) async {
    await _seedOfflineCache(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: AdditionalTopicScreen(featureId: 'gk', topicId: 't1'),
      ),
    );
    await pumpUntil(tester, find.text('What is 2+2?'));
    expect(find.text('Basic addition.'), findsNothing);
    await tester.tap(find.text('Expand all'));
    // The ~250ms AnimatedSize expand is finite — a bounded pump advances
    // past it without needing pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Basic addition.'), findsOneWidget);
    expect(find.text('Collapse all'), findsOneWidget);
    await tester.tap(find.text('Collapse all'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Basic addition.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('practice track shows badge, bookmark and report actions',
      (WidgetTester tester) async {
    await _seedOfflineCache(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: AdditionalTopicScreen(featureId: 'gk', topicId: 't1'),
      ),
    );
    await pumpUntil(tester, find.text('What is 2+2?'));
    await tester.tap(find.text('Practice'));
    await tester.pump(const Duration(milliseconds: 500));
    // One more pump: the option-stagger's zero-delay Future is created during
    // the build above, so it only fires on the next fake-async elapse.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Question 1'), findsOneWidget);
    expect(find.byTooltip('Bookmark'), findsOneWidget);
    expect(find.byTooltip('Report'), findsOneWidget);
    expect(find.text("Today's practice: 0/1"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
