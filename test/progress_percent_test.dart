// Unit tests for the headline progress percent (2026-10-02, user spec):
// percent = activity points ÷ total content marks (DYNAMIC denominator from
// app_content_totals — no fixed 12000). Adding questions/models raises the
// denominator so every percent eases down automatically; growth is slow so no
// user hits 100% fast. Accuracy is untouched (analytics page only).
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/services/main_leaderboard.dart';

// Mirrors _fallbackContentTotals in main_leaderboard.dart.
const _fallbackTotals = <String, int>{
  'practice': 4000,
  'theory': 150,
  'exam': 60,
  'gkPm': 1200,
  'read': 4000,
  'dailyTest': 120,
  'constitution': 35,
};

// 4000*7 + 150*6 + 60*110 + 1200*7 + 4000*1 + 120*56 + 35*4
const _fallbackMarks = 54760.0;

void main() {
  group('contentMarksForTotals', () {
    test('fallback totals yield the expected total marks', () {
      expect(contentMarksForTotals(_fallbackTotals), _fallbackMarks);
    });

    test('missing sources count as zero, unknown keys ignored', () {
      expect(contentMarksForTotals({}), 0);
      expect(
        contentMarksForTotals({'practice': 100, 'nope': 999}),
        700.0,
      );
    });
  });

  group('computeProgressPercent', () {
    test('600 points on the fallback bank is ~1.1% (slow growth)', () {
      final p = computeProgressPercent(600, _fallbackMarks);
      expect(p, greaterThan(1.0));
      expect(p, lessThan(1.2));
    });

    test('zero points is 0%', () {
      expect(computeProgressPercent(0, _fallbackMarks), 0);
    });

    test('zero/negative marks never divides by zero', () {
      expect(computeProgressPercent(600, 0), 0);
      expect(computeProgressPercent(600, -5), 0);
    });

    test('points equal to total marks is exactly 100%', () {
      expect(computeProgressPercent(_fallbackMarks, _fallbackMarks), 100);
    });

    test('grinder points are capped at 100%', () {
      expect(computeProgressPercent(_fallbackMarks * 3, _fallbackMarks), 100);
    });

    test('negative points clamp to 0%', () {
      expect(computeProgressPercent(-50, _fallbackMarks), 0);
    });

    test('doubling the content halves every percent (auto-low on content add)',
        () {
      final before = computeProgressPercent(600, _fallbackMarks);
      final after = computeProgressPercent(600, _fallbackMarks * 2);
      expect(after, closeTo(before / 2, 1e-9));
    });

    test('small bank (real totals doc) gives a higher percent than fallback',
        () {
      final smallMarks = contentMarksForTotals({'practice': 500});
      expect(smallMarks, 3500.0);
      final p = computeProgressPercent(600, smallMarks);
      expect(p, closeTo(600 / 3500 * 100, 1e-9));
      expect(p, greaterThan(computeProgressPercent(600, _fallbackMarks)));
    });
  });
}
