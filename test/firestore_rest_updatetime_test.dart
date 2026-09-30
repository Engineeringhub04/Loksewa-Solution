import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

// Tests for the Part B3 contract: FirestoreRest.getDocument preserves the
// doc-level Firestore `updateTime` (raw RFC3339 string) under `__updateTime`.
// Network is not involved — decodeDocument() is the exact body-to-map step
// that getDocument runs after the 200 response.

Map<String, dynamic> _docBody({String? updateTime}) => {
      'name':
          'projects/p/databases/(default)/documents/app_main_leaderboard/uid1',
      'fields': {
        'points': {'integerValue': '42'},
        'name': {'stringValue': 'ram'},
        'ratio': {'doubleValue': 1.5},
        'active': {'booleanValue': true},
        'note': {'nullValue': null},
        'seen': {'timestampValue': '2026-09-30T00:00:00Z'},
        'meta': {
          'mapValue': {
            'fields': {'k': {'stringValue': 'v'}}
          }
        },
        'tags': {
          'arrayValue': {
            'values': [
              {'integerValue': '1'},
              {'stringValue': 'two'}
            ]
          }
        },
      },
      'createTime': '2026-09-29T00:00:00.000Z',
      if (updateTime != null) 'updateTime': updateTime,
    };

void main() {
  group('FirestoreRest.decodeDocument (getDocument body step)', () {
    test('result contains __updateTime matching the response updateTime', () {
      const updateTime = '2026-09-30T16:00:00.000Z';
      final result = FirestoreRest.decodeDocument(_docBody(updateTime: updateTime));
      expect(result['__updateTime'], updateTime);
    });

    test('__updateTime is the raw string, not a parsed DateTime', () {
      final result =
          FirestoreRest.decodeDocument(_docBody(updateTime: '2026-09-30T16:00:00.000Z'));
      expect(result['__updateTime'], isA<String>());
    });

    test('field decoding is unchanged alongside __updateTime', () {
      final result = FirestoreRest.decodeDocument(
          _docBody(updateTime: '2026-09-30T16:00:00.000Z'));
      expect(result['points'], 42);
      expect(result['name'], 'ram');
      expect(result['ratio'], 1.5);
      expect(result['active'], isTrue);
      expect(result['note'], isNull);
      expect(result['seen'], DateTime.utc(2026, 9, 30));
      expect(result['meta'], {'k': 'v'});
      expect(result['tags'], [1, 'two']);
      // Doc-level metadata must not leak in as regular fields.
      expect(result.containsKey('createTime'), isFalse);
      expect(result.containsKey('name'), isTrue); // the 'name' FIELD still decodes
    });

    test('omits __updateTime when the response body has none', () {
      final result = FirestoreRest.decodeDocument(_docBody());
      expect(result.containsKey('__updateTime'), isFalse);
      expect(result['points'], 42);
    });
  });
}
