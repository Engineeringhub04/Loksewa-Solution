import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/user/bookmark_tracks.dart';

void main() {
  group('bookmarkTrackKey', () {
    test('subject contexts group into the subject track', () {
      for (final ctx in ['practice', 'read', 'chapter']) {
        expect(bookmarkTrackKey({'context': ctx}), 'subject',
            reason: 'context=$ctx');
      }
    });

    test('GK/PM topic screens are detected via sourceLabel prefix', () {
      expect(
          bookmarkTrackKey(
              {'context': 'practice', 'sourceLabel': 'gk · Read Mode'}),
          'gk');
      expect(
          bookmarkTrackKey(
              {'context': 'read', 'sourceLabel': 'gk · Practice Mode'}),
          'gk');
      expect(
          bookmarkTrackKey(
              {'context': 'practice', 'sourceLabel': 'pm · Read Mode'}),
          'pm');
    });

    test('sourceLabel without gk/pm prefix stays on the context track', () {
      expect(
          bookmarkTrackKey({
            'context': 'practice',
            'sourceLabel': 'Practice Mode · Geography'
          }),
          'subject');
    });

    test('exam/article/daily-test keep their own tracks', () {
      expect(bookmarkTrackKey({'context': 'exam'}), 'exam');
      expect(bookmarkTrackKey({'context': 'article'}), 'article');
      expect(bookmarkTrackKey({'context': 'daily-test'}), 'daily-test');
    });

    test('unknown contexts fall back to other', () {
      expect(bookmarkTrackKey({'context': 'mystery'}), 'other');
      expect(bookmarkTrackKey({}), 'other');
    });
  });

  group('bookmarkTrackOf', () {
    test('subject track is named "Subject Question"', () {
      final t = bookmarkTrackOf({'context': 'practice'});
      expect(t.key, 'subject');
      expect(t.label, 'Subject Question');
    });

    test('gk track label is GK', () {
      expect(bookmarkTrackOf(
          {'context': 'read', 'sourceLabel': 'gk · Read Mode'}).label, 'GK');
    });

    test('never returns null', () {
      expect(bookmarkTrackOf({'context': '???'}).key, 'other');
    });

    test('tracks carry an icon and a color', () {
      for (final t in bookmarkTracks.values) {
        expect(t.icon, isA<IconData>(), reason: t.key);
        expect(t.color, isA<Color>(), reason: t.key);
      }
    });
  });

  group('buildTrackChips', () {
    test('creates one chip per present track, sorted by count desc', () {
      final items = [
        {'context': 'practice'},
        {'context': 'read'},
        {'context': 'chapter'},
        {'context': 'exam'},
        {'context': 'exam'},
        {'context': 'article'},
      ];
      final chips = buildTrackChips(items);
      expect(chips.length, 3);
      // subject has 3, exam has 2, article has 1
      expect(chips[0].key, 'subject');
      expect(chips[0].value, 3);
      expect(chips[1].key, 'exam');
      expect(chips[1].value, 2);
      expect(chips[2].key, 'article');
      expect(chips[2].value, 1);
    });

    test('GK bookmarks land on the gk chip, not subject', () {
      final items = [
        {'context': 'practice', 'sourceLabel': 'gk · Read Mode'},
        {'context': 'practice'},
      ];
      final chips = buildTrackChips(items);
      expect(chips.map((e) => e.key), containsAll(['gk', 'subject']));
      expect(chips.firstWhere((e) => e.key == 'gk').value, 1);
    });

    test('empty list yields no chips', () {
      expect(buildTrackChips([]), isEmpty);
    });
  });
}
