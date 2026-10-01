import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/user/analytics_screen.dart';
import 'package:loksewa_solution/services/analytics/analytics_store.dart';
import 'package:loksewa_solution/services/analytics/analytics_types.dart';

String _dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

const _identity = AnalyticsIdentity(
  courseId: 'c1', subcourseId: 's1',
  courseName: 'GK & Current Affairs', subcourseName: 'GK Basics',
);

List<AnalyticsSubcourseRow> _rows(List<String> ids) => ids
    .map((id) => AnalyticsSubcourseRow(
        subcourseId: id, courseId: '', percent: 80, points: 1234))
    .toList();

AnalyticsDocument _fakeDocument({required String subcourseId, int finalPoints = 1234}) {
  final now = DateTime.now();
  final first = now.subtract(const Duration(days: 19));
  final daysMap = <String, DayBucket>{};
  for (var i = 0; i < 20; i++) {
    daysMap[_dayKey(first.add(Duration(days: i)))] =
        DayBucket(p: 60 * (i + 1), pc: 80, ta: 10 * (i + 1), tc: 8 * (i + 1));
  }
  return AnalyticsDocument(subcourseId: subcourseId, firstDay: _dayKey(first), days: daysMap);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 1000));
  for (var i = 0; i < 20; i++) {
    var pending = false;
    for (final e in find.byType(SlideTransition).evaluate()) {
      if ((e.widget as SlideTransition).position.value != Offset.zero) { pending = true; break; }
    }
    if (!pending) break;
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('debug picker', (tester) async {
    tester.view.physicalSize = const Size(800, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalyticsScreen(
          debugUid: 'test-uid',
          loadIdentity: (_) async => _identity,
          fetchDocument: (_, sid) async => _fakeDocument(subcourseId: sid),
          listSubcourses: (_) async => _rows(const ['s1', 's2']),
        ),
      ),
    ));
    await _settle(tester);
    debugPrint('GK Basics count: ${find.text('GK Basics').evaluate().length}');
    await tester.tap(find.text('GK Basics'));
    await tester.pump(const Duration(milliseconds: 500));
    debugPrint('after tap: Unnamed count=${find.text('Unnamed sub-course').evaluate().length}');
    debugPrint('after tap: GK Basics count=${find.text('GK Basics').evaluate().length}');
  });
}
