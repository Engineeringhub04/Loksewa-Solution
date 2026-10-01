// Widget tests for the shared premium gate dialog:
// - renders the amber gate card with title, message, tag, and both buttons;
// - Close (via onCancel) removes the gate; the confirm action fires onConfirm.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/widgets/premium_gate_dialog.dart';

/// Stateful harness: the gate does not dismiss itself — the parent removes
/// it when onCancel fires, exactly like the real call sites.
class _GateHarness extends StatefulWidget {
  final void Function()? onConfirmTap;
  const _GateHarness({this.onConfirmTap});

  @override
  State<_GateHarness> createState() => _GateHarnessState();
}

class _GateHarnessState extends State<_GateHarness> {
  var _show = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Text('behind'),
            if (_show)
              PremiumGateDialog(
                title: 'Premium Subject',
                message: 'A subscription is required.',
                confirmLabel: 'Go To Subscription Plan',
                cancelLabel: 'Close',
                onConfirm: () => widget.onConfirmTap?.call(),
                onCancel: () => setState(() => _show = false),
              ),
          ],
        ),
      ),
    );
  }
}

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1612);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('renders title, message, tag and both buttons',
      (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(const _GateHarness());
    await tester.pumpAndSettle();

    expect(find.text('Premium Subject'), findsOneWidget);
    expect(find.text('A subscription is required.'), findsOneWidget);
    expect(find.text('Go To Subscription Plan'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('PREMIUM'), findsOneWidget);
  });

  testWidgets('Close removes the gate via onCancel', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(const _GateHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Premium Subject'), findsNothing);
    // The page behind is still there.
    expect(find.text('behind'), findsOneWidget);
  });

  testWidgets('confirm button fires onConfirm', (tester) async {
    _tallScreen(tester);
    var confirmed = false;
    await tester.pumpWidget(_GateHarness(
      onConfirmTap: () => confirmed = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go To Subscription Plan'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });
}
