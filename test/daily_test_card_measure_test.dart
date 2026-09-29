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
}
