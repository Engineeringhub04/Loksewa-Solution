import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:loksewa_solution/screens/shop/checkout_screen.dart';

/// fetchCheckoutContent (Method B resilient fetch):
/// direct-hit returns the doc; direct-miss falls back to the slug query;
/// total-miss returns null.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> subjectDoc(String id, String course) => {
        'id': id,
        'course': course,
        'name': 'General Awareness',
      };

  test('direct hit returns the doc without querying', () async {
    var queried = false;
    final doc = subjectDoc(
        'civil-engineering__civil-engineering-7th__general-awareness',
        'civil-engineering');
    final got = await fetchCheckoutContent(
      'subject',
      'civil-engineering__civil-engineering-7th__general-awareness',
      token: 'tok',
      getDoc: (path, t) async {
        expect(
            path,
            'app_subjects_details/'
            'civil-engineering__civil-engineering-7th__general-awareness');
        expect(t, 'tok');
        return doc;
      },
      queryDocs: (collection, where) async {
        queried = true;
        return [];
      },
    );
    expect(got, doc);
    expect(queried, isFalse);
  });

  test('direct 404 falls back to slug query and returns the match', () async {
    String? queriedCollection;
    bool whereWasNull = false;
    final docs = [
      subjectDoc(
          'civil-engineering__civil-engineering-7th__public-management',
          'civil-engineering'),
      subjectDoc(
          'civil-engineering__civil-engineering-7th__general-awareness',
          'civil-engineering'),
    ];
    final got = await fetchCheckoutContent(
      'subject',
      // Wrong subcourse in the constructed ID -> direct 404, but the slug
      // still resolves via the fallback query.
      'civil-engineering__civil-assistant-sub-engineer__general-awareness',
      token: 'tok',
      getDoc: (path, t) async => null,
      queryDocs: (collection, where) async {
        queriedCollection = collection;
        whereWasNull = where == null;
        return docs;
      },
    );
    expect(queriedCollection, 'app_subjects_details');
    expect(whereWasNull, isTrue,
        reason: 'fallback must not depend on any field filter');
    expect(got?['id'],
        'civil-engineering__civil-engineering-7th__general-awareness');
  });

  test('direct throw also falls back to the query', () async {
    final docs = [
      subjectDoc('other-course__sub__general-awareness', 'other-course'),
    ];
    final got = await fetchCheckoutContent(
      'subject',
      'civil-engineering__civil-engineering-7th__general-awareness',
      token: 'tok',
      getDoc: (path, t) async => throw Exception('403'),
      queryDocs: (collection, where) async => docs,
    );
    expect(got?['id'], 'other-course__sub__general-awareness');
  });

  test('total miss returns null', () async {
    final got = await fetchCheckoutContent(
      'subject',
      'civil-engineering__civil-engineering-7th__general-awareness',
      token: 'tok',
      getDoc: (path, t) async => null,
      queryDocs: (collection, where) async => [
        subjectDoc(
            'civil-engineering__civil-engineering-7th__public-management',
            'civil-engineering'),
      ],
    );
    expect(got, isNull);
  });

  test('chapter type has no fallback: direct miss returns null', () async {
    var queried = false;
    final got = await fetchCheckoutContent(
      'chapter',
      'some-chapter-id',
      token: 'tok',
      getDoc: (path, t) async {
        expect(path, 'app_subjects_chapter_details/some-chapter-id');
        return null;
      },
      queryDocs: (collection, where) async {
        queried = true;
        return [];
      },
    );
    expect(got, isNull);
    expect(queried, isFalse);
  });

  test('unit type resolves the units collection on direct hit', () async {
    String? seenPath;
    final got = await fetchCheckoutContent(
      'unit',
      'unit-123',
      token: 'tok',
      getDoc: (path, t) async {
        seenPath = path;
        return {'id': 'unit-123'};
      },
      queryDocs: (collection, where) async => [],
    );
    expect(seenPath, 'app_subjects_units_details/unit-123');
    expect(got?['id'], 'unit-123');
  });

  testWidgets('fetchCheckoutContent is exported from checkout_screen',
      (tester) async {
    // Smoke: the top-level function exists and is callable (already covered
    // above); this just guards the import surface.
    expect(fetchCheckoutContent, isNotNull);
    debugPrint('ok');
  });
}
