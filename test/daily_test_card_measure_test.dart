import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/widgets/daily_test_card.dart';
import 'package:loksewa_solution/widgets/stagger_entrance.dart';
import 'package:loksewa_solution/services/exam_service.dart';

DailyTestModel _model() => DailyTestModel(
      id: 'm1',
      name: 'Model 1',
      modelName: 'Model 1 \u2014 Warm Up',
      courseId: 'c1',
      subcourseId: 's1',
      testDate: '2026-09-29',
      questions: List.generate(
        5,
        (i) => DailyTestQuestion(
          category: 'Medium',
          question: 'Q$i?',
          options: const ['A', 'B', 'C', 'D'],
          correctIndex: 0,
          explanation: '',
          timeSeconds: 40,
          marks: 1,
        ),
      ),
      category: 'medium',
      perQuestionTimeSeconds: 40,
      negativeMarking: true,
      negativeMarkPercent: 0.25,
      marksPerQuestion: 1,
      passPercent: 40,
      rules: const [],
      isPro: false,
      subscriptionType: 'off',
      price: 0,
      active: true,
      order: 0,
    );

void main() {
  testWidgets('measureContent card lays out unbounded without flex errors',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DailyTestCard(
                  model: _model(),
                  slot: DailyTestSlot.missed,
                  measureContent: true,
                  onPrimaryPress: () {},
                  onSubscribePress: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(DailyTestCard));
    // Content height should be >= minHeight 300 and well under old 372 box.
    expect(size.height, greaterThanOrEqualTo(300));
    expect(size.height, lessThan(360));
  });

  testWidgets('StaggerEntrance reveals child after delay', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StaggerEntrance(
            delayMs: 60,
            child: Text('hello'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('mini card accent spine is clipped to the card radius',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: DailyTestMiniCard(
              model: _model(),
              slot: DailyTestSlot.missed,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // The 4px verdict spine with rounded outer corners…
    final spines = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxWidth == 4.0 &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).borderRadius ==
            const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ));
    expect(spines, findsOneWidget);
    // …must sit under a ClipRRect cut to the card's radius (React clips the
    // card with overflow: hidden), so the spine's square inner corners can't
    // poke past the rounded card corners.
    var clipped = false;
    spines.evaluate().single.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is ClipRRect &&
          widget.borderRadius == BorderRadius.circular(12)) {
        clipped = true;
        return false;
      }
      return true;
    });
    expect(clipped, isTrue,
        reason: 'mini card spine is not clipped to the card radius');
  });

  testWidgets('history card accent spine is clipped to the card radius',
      (tester) async {
    final activity = DailyTestActivity(
      id: 'a1',
      modelId: 'm1',
      modelName: 'Model 1 — Warm Up',
      score: 80,
      totalQuestions: 5,
      correct: 4,
      incorrect: 1,
      skipped: 0,
      timeTakenSeconds: 200,
      completedAt: DateTime(2026, 9, 29, 10).millisecondsSinceEpoch,
      passed: true,
      passPercent: 40,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: DailyTestHistoryCard(activity: activity),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // The 4px verdict spine with rounded outer corners…
    final spines = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxWidth == 4.0 &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).borderRadius ==
            const BorderRadius.only(
              topLeft: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ));
    expect(spines, findsOneWidget);
    // …must sit under a ClipRRect cut to the card's radius (React clips the
    // card with overflow: hidden), so the spine's square inner corners can't
    // poke past the rounded card corners.
    var clipped = false;
    spines.evaluate().single.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is ClipRRect &&
          widget.borderRadius == BorderRadius.circular(16)) {
        clipped = true;
        return false;
      }
      return true;
    });
    expect(clipped, isTrue,
        reason: 'history card spine is not clipped to the card radius');
  });
}
