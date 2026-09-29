import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/learn/subject_practice_screen.dart';

// The practice screen was rewritten for React parity (app/subjects/practice.tsx):
// limit row, question badge + bookmark/report actions, option tiles with
// result states, explanation panel, curved bottom bar, AppDialog-style popups,
// and an AnimatedSwitcher question transition. These tests guard the states
// reachable without a signed-in user (loading is skipped synchronously when
// AuthService.currentUser is null) plus the full suite for regressions.
void main() {
  testWidgets('practice screen renders header and empty state with no layout errors',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SubjectPracticeScreen(
          subjectId: 'subject-1',
          chapterId: 'chapter-1',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Practice Mode'), findsOneWidget);
    expect(
        find.text('No questions are available for this chapter yet.'),
        findsOneWidget);
    expect(find.textContaining('Content is being prepared'),
        findsOneWidget);
    // No bottom bar without questions.
    expect(find.text('Previous'), findsNothing);
    expect(find.text('Next Question'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('practice screen empty state survives a frame advance',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SubjectPracticeScreen(
          subjectId: 'subject-1',
          chapterId: 'chapter-1',
          subjectName: 'General Awareness',
          chapterName: 'Chapter One',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Practice Mode'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
