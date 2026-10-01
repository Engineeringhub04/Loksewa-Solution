import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/widgets/syllabus_entrance.dart';

/// Verifies SyllabusEntrance — the syllabus gold-standard motion:
/// 380ms controller, opacity easeOut, 24px→0 rise easeOut, no spring
/// overshoot, staggered via [delayMs].
void main() {
  // Many small pumps (AGENTS.md lesson): a single big pump can leave the
  // delayed Future un-advanced in the FakeAsync zone.
  Future<void> pumpMs(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms; i += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpEntrance(WidgetTester tester, {int delayMs = 200}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyllabusEntrance(delayMs: delayMs, child: const Text('hello')),
        ),
      ),
    );
  }

  double opacityOf(WidgetTester tester) => tester
      .widget<Opacity>(find.descendant(
          of: find.byType(SyllabusEntrance), matching: find.byType(Opacity)))
      .opacity;

  double dyOf(WidgetTester tester) => tester
      .widget<Transform>(find.descendant(
          of: find.byType(SyllabusEntrance), matching: find.byType(Transform)))
      .transform
      .getTranslation()
      .y;

  testWidgets('starts invisible and translated down 24px', (tester) async {
    await pumpEntrance(tester);
    await tester.pump();
    expect(opacityOf(tester), 0.0);
    expect(dyOf(tester), 24.0);
    expect(find.text('hello'), findsOneWidget);
    // Flush the pending delay timer so teardown sees no pending timers.
    await pumpMs(tester, 1000);
  });

  testWidgets('stays hidden until the delay elapses', (tester) async {
    await pumpEntrance(tester);
    await pumpMs(tester, 150);
    expect(opacityOf(tester), 0.0);
    expect(dyOf(tester), 24.0);
    // Flush the pending delay timer so teardown sees no pending timers.
    await pumpMs(tester, 1000);
  });

  testWidgets('fades and rises after the delay, with no overshoot',
      (tester) async {
    await pumpEntrance(tester);
    await pumpMs(tester, 350); // 200ms delay + 150ms into the 380ms run
    final opacity = opacityOf(tester);
    final dy = dyOf(tester);
    expect(opacity, greaterThan(0.0));
    expect(opacity, lessThan(1.0));
    expect(dy, greaterThan(0.0));
    // easeOutBack would overshoot below 0; easeOut never leaves [0, 24].
    expect(dy, lessThanOrEqualTo(24.0));
  });

  testWidgets('settles fully visible at its rest position', (tester) async {
    await pumpEntrance(tester);
    await pumpMs(tester, 1000); // well past 200ms delay + 380ms run
    expect(opacityOf(tester), 1.0);
    expect(dyOf(tester), 0.0);
  });

  testWidgets('zero delay starts animating immediately', (tester) async {
    await pumpEntrance(tester, delayMs: 0);
    await pumpMs(tester, 100);
    expect(opacityOf(tester), greaterThan(0.0));
  });
}
