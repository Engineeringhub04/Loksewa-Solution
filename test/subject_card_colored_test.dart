import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/widgets/home/subject_card_colored.dart';

// The card was restructured (shadow moved outside ClipRRect, Stack set to
// Clip.none so the glow bubble tucks under the rounded border). This guards
// against layout regressions like the unbounded-Stack black screen.
void main() {
  testWidgets('subject card renders with no layout errors',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SubjectCardColored(
              name: 'General Awareness',
              icon: Icons.public,
              backgroundColor: const Color(0xFF2563EB),
              premium: true,
              footerLabel: 'View Chapter',
              width: 160,
              height: 150,
              onPress: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('General Awareness'), findsOneWidget);
    expect(find.text('View Chapter'), findsOneWidget);
    expect(find.text('Premium'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
