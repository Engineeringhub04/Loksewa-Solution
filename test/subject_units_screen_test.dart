import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/learn/subject_units_screen.dart';

// Units page fixes (bubble-clipped stats card, full-screen sheet/gate
// overlays above the header, accordion auto-scroll, animated mode sheet,
// canonical UserProfile.hasActivePremium):
// - build() is now Scaffold > Stack[ Column[SubpageHeader, Expanded[...]],
//   overlays ] so the dim barrier covers the header curve (no light-mode
//   white slivers), mirroring the chapter page.
// - _reload() clears the cached _page and re-issues _trackPage(_load());
//   the error Retry button and both RefreshIndicators route through it.
// These tests drive the states reachable without a signed-in user or
// backend: loading -> error -> retry, guarding the restructured build
// against layout errors.
void main() {
  // Pumps the screen and advances until the backend calls settle.
  // With no session, getValidIdToken() returns '' immediately and the
  // Firestore REST calls fail fast (401) -> the error branch renders.
  Future<void> settleBackend(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Failed to load units.').evaluate().isNotEmpty) return;
    }
  }

  testWidgets('units screen shows header + loading, then the error state '
      'with a working Retry button', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SubjectUnitsScreen(subjectId: 'test-subject'),
      ),
    );
    await tester.pump();

    // Header renders above the content (Stack restructure). In tests the
    // mocked HttpClient fails fast, so the first frame already shows the
    // error branch — both are valid; what matters is no layout crash.
    expect(find.text('Units'), findsOneWidget);
    expect(find.text('Failed to load units.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Retry re-issues the load: the very next frame must show the loading
    // indicator again (deterministic — the new future is still pending).
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Loading Units...'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await settleBackend(tester);
    expect(find.text('Failed to load units.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('units screen survives frame advances in the loading state',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SubjectUnitsScreen(subjectId: 'test-subject'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Units'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
