import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/learn/practice_analytics_screen.dart';

// Regression tests for the unit-scoped analytics blank page (v1.0.22):
// the practice save stores `unitId` canonicalized (`_canonicalLearningId`
// in exam_service.dart), while the units screen passes the raw track id.
// The filter must compare canonical forms — the old raw string comparison
// filtered out every doc, so opening Practice Analytics with a unit
// selected always showed "No practice data yet".
void main() {
  test('unitMatches: canonical stored id vs composite track id', () {
    expect(
      PracticeAnalyticsScreen.debugUnitMatches(
          'surveying-1', 'bachelor__bba__surveying-1'),
      isTrue,
    );
  });

  test('unitMatches: canonical stored id vs already-canonical id', () {
    expect(
      PracticeAnalyticsScreen.debugUnitMatches('surveying-1', 'surveying-1'),
      isTrue,
    );
  });

  test('unitMatches: different units do not match', () {
    expect(
      PracticeAnalyticsScreen.debugUnitMatches(
          'surveying-1', 'bachelor__bba__surveying-2'),
      isFalse,
    );
  });

  test('unitMatches: empty scope matches everything (All view)', () {
    expect(
        PracticeAnalyticsScreen.debugUnitMatches('surveying-1', ''), isTrue);
    expect(
        PracticeAnalyticsScreen.debugUnitMatches('surveying-1', null), isTrue);
  });

  test('unitMatches: missing stored id does not match a unit scope', () {
    expect(
      PracticeAnalyticsScreen.debugUnitMatches(
          null, 'bachelor__bba__surveying-1'),
      isFalse,
    );
  });
}
