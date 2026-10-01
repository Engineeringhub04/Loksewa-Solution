import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/admin/admin_subscription_detail_screen.dart';
import 'package:loksewa_solution/screens/auth/delete_account_screen.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/subpage_header.dart';

// Regression tests for the 2026-10-01 "white slivers" report: on the admin
// Subscription Requests screen, small white slivers showed at the left/right
// edges of the blue curved header while the body was dimmed by the busy
// barrier.
//
// Root cause was NOT the header — its 26px bottom-corner radius clip is
// correct (matches React's SubpageHeader) and full-bleed. The busy dim
// barrier lived INSIDE the body Stack, below the header, so the rounded
// corner cutouts showed the undimmed page background. The barrier now sits
// ABOVE everything (Scaffold > Stack > [Column[header, body], barrier]),
// the same pattern as the chapter/units pages. SubpageHeader itself is
// untouched, so all 82 screens using it render pixel-identical.

double _lum(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

class _Shot {
  final ui.Image image;
  final Uint8List pixels;
  _Shot(this.image, this.pixels);

  int get w => image.width;

  Color at(int x, int y) {
    final i = (y * w + x) * 4;
    return Color.fromARGB(
        pixels[i + 3], pixels[i], pixels[i + 1], pixels[i + 2]);
  }
}

Future<_Shot> _capture(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  // NOTE: toImage()/toByteData() must run inside tester.runAsync — called
  // directly in the fake-async test zone their futures never complete and
  // the test hangs (observed 2026-10-01).
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1.0));
  final bytes = await tester
      .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
  return _Shot(image!, bytes!.buffer.asUint8List());
}

/// The two corner bands flanking the header's rounded bottom corners:
/// x in [0, 34] / [w-34, w], y in [headerBottom-30, headerBottom+12].
/// Covers the cutout triangles plus a margin; the 26px curve itself passes
/// through the middle of each band.
void _scanCornerBands(
    _Shot shot, Rect headerRect, void Function(int x, int y, Color c) visit) {
  final left = headerRect.left.toInt();
  final right = headerRect.right.toInt();
  final bottom = headerRect.bottom.toInt();
  for (int y = bottom - 30; y < bottom + 12; y++) {
    for (int x = left; x < left + 34; x++) {
      visit(x, y, shot.at(x, y));
    }
    for (int x = right - 34; x < right; x++) {
      visit(x, y, shot.at(x, y));
    }
  }
}

double _brightestInBands(_Shot shot, Rect rect) {
  var brightest = 0.0;
  _scanCornerBands(shot, rect, (x, y, c) {
    brightest = math.max(brightest, _lum(c));
  });
  return brightest;
}

void main() {
  testWidgets('header paints no light pixels in its corner regions (dark)',
      (WidgetTester tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            body: Column(
              children: [
                const SubpageHeader(title: 'Subscription Requests'),
                Expanded(
                  child: Container(color: ExpoPalette.dark.background),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final rect = tester.getRect(find.byType(SubpageHeader));
    final shot = await _capture(tester, key);
    // Dark header blue (~0.38 luminance) and dark page bg (~0.07) are both
    // far below the threshold; a white sliver (1.0) would fail loudly.
    _scanCornerBands(shot, rect, (x, y, c) {
      expect(_lum(c), lessThan(0.67),
          reason: 'light pixel at ($x, $y) in dark-mode corner region');
    });
  });

  testWidgets('header clips a true 26px radius (light)',
      (WidgetTester tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: key,
          child: const Scaffold(
            body: Column(
              children: [
                SubpageHeader(title: 'Subscription Requests'),
                Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final rect = tester.getRect(find.byType(SubpageHeader));
    final shot = await _capture(tester, key);
    final left = rect.left.toInt();
    final right = rect.right.toInt();
    final bottom = rect.bottom.toInt();

    // Points just inside the 26px corner squares, outside the curve: their
    // distance from the curve centre (26px in) is ~32px > 26px radius, so
    // they must show the page background. Square (unclipped) corners would
    // paint blue here instead.
    for (final x in [left + 3, right - 3]) {
      expect(_lum(shot.at(x, bottom - 3)), greaterThan(0.85),
          reason: 'corner cutout at ($x, ${bottom - 3}) should show page bg');
    }
    // Points 40px above the bottom edge are above the curve: gradient blue.
    for (final x in [left + 3, right - 3]) {
      final c = shot.at(x, bottom - 40);
      expect(c.b, greaterThan(c.r + 0.2),
          reason: 'expected header blue at ($x, ${bottom - 40})');
    }
  });

  testWidgets('dim barrier above the header leaves no white slivers',
      (WidgetTester tester) async {
    // The reported scenario: light mode + a black45 busy barrier.
    Future<({Rect rect, _Shot shot})> pumpBarrier(
        {required bool aboveHeader}) async {
      final key = GlobalKey();
      const header = SubpageHeader(title: 'Subscription Requests');
      final barrier = Container(color: Colors.black45);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: aboveHeader
                  // Fixed structure: barrier above everything.
                  ? Stack(children: [
                      Column(children: [
                        header,
                        Expanded(child: Container(color: Colors.white)),
                      ]),
                      barrier,
                    ])
                  // Old (buggy) structure: barrier only over the body.
                  : Column(children: [
                      header,
                      Expanded(
                        child: Stack(children: [
                          Container(color: Colors.white),
                          barrier,
                        ]),
                      ),
                    ]),
            ),
          ),
        ),
      );
      await tester.pump();
      final rect = tester.getRect(find.byType(SubpageHeader));
      return (rect: rect, shot: await _capture(tester, key));
    }

    // Fixed structure: the corner cutouts are dimmed like everything else
    // (~0.55 luminance), never raw white.
    final fixed = await pumpBarrier(aboveHeader: true);
    expect(_brightestInBands(fixed.shot, fixed.rect), lessThan(0.82),
        reason: 'white sliver in the header corner region');

    // Negative control: the OLD structure DOES show a white sliver, proving
    // this test can actually catch the bug.
    final buggy = await pumpBarrier(aboveHeader: false);
    expect(_brightestInBands(buggy.shot, buggy.rect), greaterThan(0.9),
        reason:
            'negative control failed: old structure should show the sliver');
  });

  testWidgets(
      'admin subscription detail keeps the busy barrier above the '
      'header', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AdminSubscriptionDetailScreen(id: 'test-id')),
    );
    await tester.pump();
    // No signed-in user -> the load fails fast into the error branch; a few
    // small pumps are enough (never pumpAndSettle: the loading spinner is
    // an infinite animation).
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final body = scaffold.body;
    expect(body, isA<Stack>(),
        reason: 'Scaffold body must be a Stack so the busy barrier can sit '
            'above the header');
    final first = (body as Stack).children.first;
    expect(first, isA<Column>());
    expect(
      find.descendant(
          of: find.byWidget(first), matching: find.byType(SubpageHeader)),
      findsOneWidget,
    );
  });

  testWidgets('delete account keeps the deleting barrier above the header',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: DeleteAccountScreen()));
    await tester.pump();
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.body, isA<Stack>(),
        reason: 'Scaffold body must be a Stack so the deleting barrier can '
            'sit above the header');
  });
}
