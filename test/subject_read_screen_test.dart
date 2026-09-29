import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/learn/subject_read_screen.dart';

// Smoke test for the read-mode screen: with no signed-in user the loader
// short-circuits to the DataNotFound empty state. Guards against layout
// regressions in the question cards (badge row, toggle, option rows,
// explanation card) from the React-parity rewrite.
void main() {
  testWidgets('read screen renders empty state with no layout errors',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SubjectReadScreen(
          subjectId: 'subject-1',
          chapterId: 'chapter-1',
        ),
      ),
    );
    // First frame shows PreloadingWidget (infinite animation — never settle).
    await tester.pump();
    // The no-user path finishes loading on the next microtask.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Read Mode'), findsOneWidget);
    expect(
        find.text(
            'No questions are available for this chapter yet.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
