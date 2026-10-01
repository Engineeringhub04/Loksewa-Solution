import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/auth/contact_us_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/preloading.dart';
import 'package:loksewa_solution/widgets/x_logo_icon.dart';

GoRouter _router() {
  return GoRouter(
    initialLocation: '/contact-us',
    routes: [
      GoRoute(
          path: '/contact-us',
          builder: (_, __) => const ContactUsScreen()),
    ],
  );
}

/// Mocks the native "loksewa_solution/media" channel: openUrl records its
/// argument, then waits on [gate] so the popup's loading state is fully
/// deterministic. Installed on the tester's own binding INSIDE the test
/// body (an orphan TestDefaultBinaryMessengerBinding never fires).
void _mockMediaChannel(
    WidgetTester tester, List<String> openedUrls, Completer<bool> gate) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('loksewa_solution/media'),
    (MethodCall call) async {
      if (call.method == 'openUrl') {
        openedUrls.add((call.arguments as Map)['url'] as String);
        return gate.future;
      }
      return null;
    },
  );
}

/// The shimmer shows first (~1.2s), then the content reveals; afterwards
/// several small pumps settle every SyllabusEntrance delay (≤120ms) plus
/// its 380ms animation. NEVER pumpAndSettle — the preloading spinner is an
/// infinite animation.
Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.byType(PreloadingWidget), findsOneWidget);
  await tester.pump(const Duration(milliseconds: 1300)); // reveal fires
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Taps a channel row and waits for the confirm popup to fade in.
Future<void> _openPopup(WidgetTester tester, String rowText) async {
  await tester.tap(find.text(rowText));
  await tester.pump(const Duration(milliseconds: 300)); // dialog fade-in
  expect(find.byType(AppModalShell), findsOneWidget);
}

/// Taps Confirm, observes the loading state on the button (and asserts the
/// exact URL already reached openUrl), then releases the native side and
/// asserts the popup closes.
Future<void> _confirmPopup(
    WidgetTester tester,
    List<String> openedUrls,
    Completer<bool> gate,
    String expectedUrl) async {
  await tester.tap(find.text('Confirm'));
  await tester.pump(const Duration(milliseconds: 50));
  // Loading shows on the confirm button while the native side works, and
  // the URL has already been handed to openUrl.
  expect(find.text('Opening…'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsWidgets);
  expect(openedUrls, [expectedUrl]);

  gate.complete(true);
  // Several small pumps (not one big pump): the gate release, the channel
  // future, the pop, and the shell's 200ms fade-out each need their own
  // frame to flush in order.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.byType(AppModalShell), findsNothing);
}

void main() {
  setUp(() => AppLanguage.current.value = 'en');
  tearDown(() => AppLanguage.current.value = 'en');

  group('ContactUsScreen', () {
    testWidgets('shimmer shows first, then content reveals', (tester) async {
      await _pumpScreen(tester);
      expect(find.text('Reach us'), findsOneWidget);
      expect(find.text('Email us'), findsOneWidget);
      expect(find.text('contact@kbr.com.np'), findsOneWidget);
      expect(find.text('Call us'), findsOneWidget);
      expect(find.text('+977-9810768297'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
      expect(find.text('kbr.com.np'), findsOneWidget);
      expect(find.text('Follow us'), findsOneWidget);
      // The message form sits below the fold and a lazy ListView only
      // builds visible children — drag up until the form materialises.
      for (var i = 0;
          i < 10 && find.text('Send Message').evaluate().isEmpty;
          i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Send Message'), findsWidgets); // heading + button
    });

    testWidgets('reach-us rows have no copy icons', (tester) async {
      await _pumpScreen(tester);
      expect(find.byIcon(Icons.copy), findsNothing);
      expect(find.byIcon(Icons.content_copy), findsNothing);
      expect(find.byIcon(Icons.copy_outlined), findsNothing);
    });

    testWidgets('email row confirm popup opens mailto: via openUrl',
        (tester) async {
      final openedUrls = <String>[];
      final gate = Completer<bool>();
      _mockMediaChannel(tester, openedUrls, gate);
      await _pumpScreen(tester);

      await _openPopup(tester, 'contact@kbr.com.np');
      expect(find.text('Send an email?'), findsOneWidget);
      expect(find.text('contact@kbr.com.np'), findsWidgets); // row + popup

      await _confirmPopup(tester, openedUrls, gate, 'mailto:contact@kbr.com.np');
    });

    testWidgets('call row confirm popup opens tel: via openUrl',
        (tester) async {
      final openedUrls = <String>[];
      final gate = Completer<bool>();
      _mockMediaChannel(tester, openedUrls, gate);
      await _pumpScreen(tester);

      await _openPopup(tester, '+977-9810768297');
      expect(find.text('Make a call?'), findsOneWidget);

      await _confirmPopup(tester, openedUrls, gate, 'tel:+977-9810768297');
    });

    testWidgets('website row confirm popup opens https: via openUrl',
        (tester) async {
      final openedUrls = <String>[];
      final gate = Completer<bool>();
      _mockMediaChannel(tester, openedUrls, gate);
      await _pumpScreen(tester);

      await _openPopup(tester, 'kbr.com.np');
      expect(find.text('Open the website?'), findsOneWidget);

      await _confirmPopup(tester, openedUrls, gate, 'https://kbr.com.np');
    });

    testWidgets('cancel dismisses the popup without opening anything',
        (tester) async {
      final openedUrls = <String>[];
      final gate = Completer<bool>();
      _mockMediaChannel(tester, openedUrls, gate);
      await _pumpScreen(tester);

      await _openPopup(tester, 'contact@kbr.com.np');

      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AppModalShell), findsNothing);
      expect(openedUrls, isEmpty);
    });

    testWidgets('X brand mark renders via XLogoIcon', (tester) async {
      await _pumpScreen(tester);
      expect(find.byType(XLogoIcon), findsOneWidget);
      expect(find.text('X (Twitter)'), findsOneWidget);
    });
  });
}
