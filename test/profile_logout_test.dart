// Widget tests for the profile logout button + confirm dialog (Part 3).
//
// (a) The logout FilledButton must render the strong danger red in BOTH
// themes — the dark theme's lightened danger tint (0xFFF87171) used to wash
// it out to pink.
// (b) The logout confirm dialog's icon tile must be a solid white chip with
// a strong-red glyph in both themes — the old tinted tile (danger @12% +
// danger glyph) made icon and background nearly identical, worst in dark
// mode.
//
// The logout LOGIC (destructive confirm, 550ms spinner floor, 1400ms
// sign-out ceiling, cancel disabled while logging out) is untouched by this
// round and is not re-tested here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:loksewa_solution/screens/learn/profile_tab.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';

/// The strong red every filled danger surface uses in both themes.
const _strongRed = Color(0xFFDC2626);

/// Pumps the real ProfileTab with the store primed so it renders content
/// (error counts as ready) instead of the infinite preloader. Tall surface
/// so every lazily-built section mounts at once; many small pumps settle the
//  SyllabusEntrance choreography (a single big pump can leave taps
/// unregistered).
Future<void> _pumpTab(WidgetTester tester, {bool dark = false}) async {
  ProfileStore.instance.error = true;
  addTearDown(() {
    ProfileStore.instance.error = false;
  });
  tester.view.physicalSize = const Size(800, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: dark ? ThemeData.dark() : ThemeData.light(),
    home: const Scaffold(body: ProfileTab()),
  ));
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Color? _filledBg(WidgetTester tester, Finder button) {
  final style = tester.widget<FilledButton>(button).style;
  return style?.backgroundColor?.resolve(<WidgetState>{});
}

void main() {
  group('ProfileTab logout danger styling', () {
    testWidgets('logout button is strong red in light theme',
        (tester) async {
      await _pumpTab(tester);

      final button = find.widgetWithText(FilledButton, 'Logout');
      expect(button, findsOneWidget);
      expect(_filledBg(tester, button), _strongRed);
    });

    testWidgets('logout button is strong red in dark theme too',
        (tester) async {
      await _pumpTab(tester, dark: true);

      final button = find.widgetWithText(FilledButton, 'Logout');
      expect(button, findsOneWidget);
      // Regression: this used to resolve to the washed-out 0xFFF87171.
      expect(_filledBg(tester, button), _strongRed);
    });

    testWidgets('confirm dialog icon is distinct from its chip in dark theme',
        (tester) async {
      await _pumpTab(tester, dark: true);

      await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog is up.
      expect(find.byType(AppModalShell), findsOneWidget);

      // Strong-red glyph...
      final icon = find.byIcon(Icons.logout);
      expect(icon, findsOneWidget);
      expect(tester.widget<Icon>(icon).color, _strongRed);

      // ...on a solid white chip, not a same-hue tint.
      final tile = find.ancestor(
        of: icon,
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.white),
      );
      expect(tile, findsOneWidget);
    });

    testWidgets('confirm CTA is strong red in dark theme', (tester) async {
      await _pumpTab(tester, dark: true);

      await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      final cta = find.descendant(
        of: find.byType(AppModalShell),
        matching: find.widgetWithText(FilledButton, 'Logout'),
      );
      expect(cta, findsOneWidget);
      expect(_filledBg(tester, cta), _strongRed);
    });
  });
}
