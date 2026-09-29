import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/learn/subject_chapters_screen.dart';

// The stats card was restructured so the decorative glow bubbles bleed past
// the card and are clipped by the outer ClipRRect along the rounded border
// (the inner Stack uses Clip.none) — they are never cut with a hard straight
// edge inside the content padding (the old "D" sticker look).
void main() {
  List<Map<String, dynamic>> chapters(int n) => List.generate(
        n,
        (i) => {
          'id': 'ch$i',
          'name': 'Chapter $i',
          'nameNe': 'अध्याय $i',
          'order': i + 1,
          'pro': i == 2,
          'progress': {
            'percentage': i == 0 ? 100 : 33,
            'completed': i == 0,
          },
        },
      );

  testWidgets(
      'summary card renders with no overflow; bubbles bleed and are clipped '
      'by the outer ClipRRect', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ChapterSummaryCard(
                subjectName: 'General Awareness (सामान्य ज्ञान)',
                chapters: chapters(10),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    // No RenderFlex overflow or other layout errors.
    expect(tester.takeException(), isNull);

    // The decorative Stack must not hard-clip its bubbles inside the padding.
    final card = find.byType(ChapterSummaryCard);
    final stacks = tester
        .widgetList<Stack>(find.descendant(of: card, matching: find.byType(Stack)))
        .toList();
    expect(stacks, hasLength(1));
    expect(stacks.single.clipBehavior, Clip.none);

    // The outer ClipRRect clips them along the rounded border instead.
    final clips = tester
        .widgetList<ClipRRect>(
            find.descendant(of: card, matching: find.byType(ClipRRect)))
        .toList();
    expect(clips, hasLength(1));
    expect(clips.single.borderRadius, BorderRadius.circular(28));

    // Both glow bubbles are positioned to bleed outside the card bounds.
    final bleeders = tester
        .widgetList<Positioned>(
            find.descendant(of: card, matching: find.byType(Positioned)))
        .where((p) => (p.top ?? 0) < 0 || (p.bottom ?? 0) < 0)
        .toList();
    expect(bleeders, hasLength(2));

    // Stats reflect the dummy data: 10 total, avg (100 + 9*33)/10 = 40%.
    expect(find.text('10'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('View Practice Analytics'), findsOneWidget);
  });

  testWidgets('summary card handles an empty chapter list',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChapterSummaryCard(
            subjectName: 'Subject',
            chapters: [],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(find.text('0%'), findsOneWidget);
  });
}
