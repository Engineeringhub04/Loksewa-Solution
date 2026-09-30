import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/screens/shop/additional_feature_home.dart';

/// Tests for AdditionalFeatureHomeScreen:
/// - updateTime comparison (pure function unit tests)
/// - topic list renders plain title strings (regression: no "Instance of"
///   pill, no per-character stacks)
/// - offline button 3 states (never downloaded / saved / update available)
/// - offline download persists page.json + banks/<topicId>.json to the
///   app-documents dir (path_provider stubbed INSIDE testWidgets per
///   AGENTS.md), and records the updateTime pref
/// - header always shows widget.reactSubtitle, never the page doc title
///
/// Network is faked with http.runWithClient + MockClient so
/// FirestoreRest.getDocument never leaves the test. AuthService has no
/// session in tests, so getValidIdToken() returns '' without network.

const _oldUpdate = '2026-09-20T10:00:00Z';
const _newUpdate = '2026-09-30T10:00:00Z';

/// Encode a raw Dart value the way Firestore REST encodes a field value.
Map<String, dynamic> _encField(dynamic v) {
  if (v is String) return {'stringValue': v};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': '$v'};
  if (v is double) return {'doubleValue': v};
  if (v is List) {
    return {
      'arrayValue': {'values': v.map(_encField).toList()}
    };
  }
  if (v is Map) {
    return {
      'mapValue': {
        'fields': (v as Map<String, dynamic>)
            .map((k, val) => MapEntry(k, _encField(val))),
      }
    };
  }
  throw ArgumentError('unsupported test value: $v');
}

/// Build a JSON mock response. Uses Response.bytes with explicit UTF-8:
/// the plain Response(String) constructor defaults to latin1 and throws
/// "Contains invalid characters" on Devanagari bodies.
http.Response _jsonResponse(Map<String, dynamic> body) {
  return http.Response.bytes(
    utf8.encode(json.encode(body)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
/// Fake Firestore backend: page doc with two published topics (+ one
/// unpublished, which must be filtered out) and per-topic bank docs.
/// [bankRequests] records every bank doc id requested.
MockClient _mockHttp({
  required String pageUpdateTime,
  required List<String> bankRequests,
}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.contains('app_additional_feature_pages/')) {
      return _jsonResponse({
        'name': 'projects/p/databases/(default)/documents/page',
        'updateTime': pageUpdateTime,
        'fields': {
            'titleEn': _encField('Server Page Title'),
            'titleNp': _encField('सर्भर पृष्ठ शीर्षक'),
            'topics': _encField([
              {
                'topicId': 't1',
                'titleEn': 'General Knowledge',
                'titleNp': 'सामान्य ज्ञान',
                'order': 1,
                'questionCount': 10,
                'questionBankId': 'bank1',
                'isPublished': true,
              },
              {
                'topicId': 't2',
                'titleEn': 'Current Affairs',
                'titleNp': 'समसामयिक घटनाहरू',
                'order': 2,
                'questionCount': 5,
                'questionBankId': 'bank2',
                'isPublished': true,
              },
              {
                'topicId': 't3',
                'titleEn': 'Hidden Draft',
                'titleNp': 'मस्यौदा',
                'order': 3,
                'questionCount': 5,
                'questionBankId': 'bank3',
                'isPublished': false,
              },
            ]),
          },
        });
    }
    if (path.contains('app_additional_feature_question_banks/')) {
      final docId = path.split('/').last;
      bankRequests.add(docId);
      return _jsonResponse({
        'name': 'projects/p/databases/(default)/documents/$docId',
        'updateTime': _newUpdate,
        'fields': {
          'topicId': _encField(docId.split('__').last),
          'questionCount': _encField(10),
        },
      });
    }
    return http.Response('not found', 404);
  });
}

/// Stub path_provider's getApplicationDocumentsDirectory to [dirPath].
/// Must be called INSIDE testWidgets via tester.binding (AGENTS.md).
void _stubAppDocs(WidgetTester tester, String dirPath) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return dirPath;
      return null;
    },
  );
  Directory(dirPath).createSync(recursive: true);
}

Future<void> _seedPrefs(Map<String, String> values) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  for (final e in values.entries) {
    await prefs.setString(e.key, e.value);
  }
}

/// Pump the home screen with a faked backend; advance the clock manually
/// (no pumpAndSettle — PreloadingWidget animates while loading).
Future<void> _pumpHome(
  WidgetTester tester,
  MockClient client, {
  String reactSubtitle = 'GK & Current Affairs',
}) async {
  await http.runWithClient(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdditionalFeatureHomeScreen(
          featureId: 'gk',
          heroIcon: Icons.public,
          reactSubtitle: reactSubtitle,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }, () => client);
}

/// Pump frames until the in-flight download (or update) settles.
Future<void> _settleDownload(WidgetTester tester, MockClient client) async {
  await http.runWithClient(() async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }, () => client);
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('isAdditionalFeatureUpdateAvailable', () {
    test('false when nothing was ever stored (old installs)', () {
      expect(
        isAdditionalFeatureUpdateAvailable(
            storedUpdateTime: null, liveUpdateTime: _newUpdate),
        isFalse,
      );
      expect(
        isAdditionalFeatureUpdateAvailable(
            storedUpdateTime: '', liveUpdateTime: _newUpdate),
        isFalse,
      );
    });

    test('false when the live doc has no updateTime', () {
      expect(
        isAdditionalFeatureUpdateAvailable(
            storedUpdateTime: _oldUpdate, liveUpdateTime: null),
        isFalse,
      );
    });

    test('false when timestamps are equal', () {
      expect(
        isAdditionalFeatureUpdateAvailable(
            storedUpdateTime: _newUpdate, liveUpdateTime: _newUpdate),
        isFalse,
      );
    });

    test('true when the live doc is newer (RFC3339)', () {
      expect(
        isAdditionalFeatureUpdateAvailable(
            storedUpdateTime: _oldUpdate, liveUpdateTime: _newUpdate),
        isTrue,
      );
    });

    test('false when the live doc is older (RFC3339)', () {
      expect(
        isAdditionalFeatureUpdateAvailable(
            storedUpdateTime: _newUpdate, liveUpdateTime: _oldUpdate),
        isFalse,
      );
    });

    test('string fallback when values are not parseable dates', () {
      expect(
        isAdditionalFeatureUpdateAvailable(
            storedUpdateTime: 'a', liveUpdateTime: 'b'),
        isTrue,
      );
      expect(
        isAdditionalFeatureUpdateAvailable(
            storedUpdateTime: 'b', liveUpdateTime: 'a'),
        isFalse,
      );
    });
  });

  group('topic list rendering', () {
    testWidgets(
        'titles render as plain strings, never "Instance of" or char stacks',
        (WidgetTester tester) async {
      final docsDir =
          Directory.systemTemp.createTempSync('af_home_topics_');
      addTearDown(() => docsDir.deleteSync(recursive: true));
      _stubAppDocs(tester, docsDir.path);
      await _seedPrefs({});
      final bankRequests = <String>[];
      await _pumpHome(
          tester, _mockHttp(pageUpdateTime: _newUpdate, bankRequests: bankRequests));

      // Big Nepali title + small English subtitle, as plain strings.
      expect(find.text('सामान्य ज्ञान'), findsOneWidget);
      expect(find.text('General Knowledge'), findsOneWidget);
      expect(find.text('समसामयिक घटनाहरू'), findsOneWidget);
      expect(find.text('Current Affairs'), findsOneWidget);
      // Unpublished topic is filtered out.
      expect(find.text('Hidden Draft'), findsNothing);
      // The reported bug: a stringified List<_Topic> or per-char columns.
      expect(find.textContaining('Instance of'), findsNothing);
      expect(find.textContaining('_Topic'), findsNothing);
      // Count badge shows the plain topic count (regression: the old
      // '$_topics.length' interpolation rendered "[Instance of '_Topic', ...]").
      expect(find.text('2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('header always shows reactSubtitle, not the page doc title',
        (WidgetTester tester) async {
      final docsDir =
          Directory.systemTemp.createTempSync('af_home_header_');
      addTearDown(() => docsDir.deleteSync(recursive: true));
      _stubAppDocs(tester, docsDir.path);
      await _seedPrefs({});
      final bankRequests = <String>[];
      await _pumpHome(
        tester,
        _mockHttp(pageUpdateTime: _newUpdate, bankRequests: bankRequests),
        reactSubtitle: 'Public Management',
      );

      // Header keeps the React subtitle even though the fetched page doc
      // carries a different titleEn.
      expect(find.text('Public Management'), findsOneWidget);
      // Hero card still mirrors React with the page doc titles.
      expect(find.text('Server Page Title'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('offline button states', () {
    testWidgets('state (a): never downloaded -> Offline Access, downloads',
        (WidgetTester tester) async {
      final docsDir =
          Directory.systemTemp.createTempSync('af_home_dl_');
      addTearDown(() => docsDir.deleteSync(recursive: true));
      _stubAppDocs(tester, docsDir.path);
      await _seedPrefs({});
      final bankRequests = <String>[];
      final client =
          _mockHttp(pageUpdateTime: _newUpdate, bankRequests: bankRequests);
      await _pumpHome(tester, client);

      expect(find.text('Offline Access'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      expect(find.text('Update available'), findsNothing);
      // Normal hint, no update banner.
      expect(
          find.text(
              'Tap Offline Access to save all questions on your phone for offline use.'),
          findsOneWidget);

      await http.runWithClient(() async {
        await tester.tap(find.text('Offline Access'));
        await _settleDownload(tester, client);
      }, () => client);

      // Both banks fetched with the {fid}__all__all__{topicId} doc ids.
      expect(
          bankRequests,
          containsAll(
              ['gk__all__all__t1', 'gk__all__all__t2']));
      // Files persisted under <appDocs>/af_offline/gk/.
      final pageFile = File('${docsDir.path}/af_offline/gk/page.json');
      final bank1 = File('${docsDir.path}/af_offline/gk/banks/t1.json');
      final bank2 = File('${docsDir.path}/af_offline/gk/banks/t2.json');
      expect(pageFile.existsSync(), isTrue);
      expect(bank1.existsSync(), isTrue);
      expect(bank2.existsSync(), isTrue);
      final pageJson =
          json.decode(pageFile.readAsStringSync()) as Map<String, dynamic>;
      expect(pageJson['__updateTime'], _newUpdate);
      expect((pageJson['topics'] as List).length, 3);
      // Prefs recorded: complete flag, date, and updateTime.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('af_offline_gk_complete'), 'true');
      expect(prefs.getString('af_offline_gk_date'), isNotNull);
      expect(
          prefs.getString('af_offline_gk_update_time'), _newUpdate);
      // Button flips to the disabled Saved state.
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Offline Access'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('state (b): downloaded + current -> Saved, disabled',
        (WidgetTester tester) async {
      final docsDir =
          Directory.systemTemp.createTempSync('af_home_saved_');
      addTearDown(() => docsDir.deleteSync(recursive: true));
      _stubAppDocs(tester, docsDir.path);
      await _seedPrefs({
        'af_offline_gk_complete': 'true',
        'af_offline_gk_date': '2026-09-20',
        'af_offline_gk_update_time': _newUpdate,
      });
      final bankRequests = <String>[];
      final client =
          _mockHttp(pageUpdateTime: _newUpdate, bankRequests: bankRequests);
      await _pumpHome(tester, client);

      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Offline Access'), findsNothing);
      expect(find.text('Update available'), findsNothing);
      expect(
          find.text(
              'Tap Offline Access to save all questions on your phone for offline use.'),
          findsOneWidget);

      // Tapping the disabled Saved button must not download anything.
      await http.runWithClient(() async {
        await tester.tap(find.text('Saved'));
        await _settleDownload(tester, client);
      }, () => client);
      expect(bankRequests, isEmpty);
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'state (c): downloaded + newer page doc -> Update available, re-downloads',
        (WidgetTester tester) async {
      final docsDir =
          Directory.systemTemp.createTempSync('af_home_update_');
      addTearDown(() => docsDir.deleteSync(recursive: true));
      _stubAppDocs(tester, docsDir.path);
      await _seedPrefs({
        'af_offline_gk_complete': 'true',
        'af_offline_gk_date': '2026-09-20',
        'af_offline_gk_update_time': _oldUpdate,
      });
      final bankRequests = <String>[];
      final client =
          _mockHttp(pageUpdateTime: _newUpdate, bankRequests: bankRequests);
      await _pumpHome(tester, client);

      // Update banner + accent button.
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      expect(
          find.text(
              'New questions available \u2014 tap Update to get the latest questions.'),
          findsOneWidget);

      // Same-day re-tap works when new data arrived.
      await http.runWithClient(() async {
        await tester.tap(find.text('Update available'));
        await _settleDownload(tester, client);
      }, () => client);

      expect(bankRequests, isNotEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getString('af_offline_gk_update_time'), _newUpdate);
      final pageFile = File('${docsDir.path}/af_offline/gk/page.json');
      expect(pageFile.existsSync(), isTrue);
      // Back to Saved; banner cleared.
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Update available'), findsNothing);
      expect(
          find.text(
              'New questions available \u2014 tap Update to get the latest questions.'),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'old install without stored updateTime never shows update available',
        (WidgetTester tester) async {
      final docsDir =
          Directory.systemTemp.createTempSync('af_home_legacy_');
      addTearDown(() => docsDir.deleteSync(recursive: true));
      _stubAppDocs(tester, docsDir.path);
      await _seedPrefs({
        'af_offline_gk_complete': 'true',
        'af_offline_gk_date': '2026-09-20',
      });
      final bankRequests = <String>[];
      await _pumpHome(
          tester, _mockHttp(pageUpdateTime: _newUpdate, bankRequests: bankRequests));

      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Update available'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
