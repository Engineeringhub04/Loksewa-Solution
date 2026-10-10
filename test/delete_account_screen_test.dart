import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/auth/delete_account_screen.dart';

/// Advances past the 1s preloading plus every SyllabusEntrance delay
/// (≤240ms) and its 380ms animation — many SMALL pumps: a single big pump
/// can leave taps unregistered by the gesture arena (hit test reaches the
/// widget but onTap never fires). Never pumpAndSettle (PreloadingWidget's
/// spinner never settles).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Harness {
  final List<Map<String, dynamic>> posts = [];
  final List<Map<String, dynamic>> savedRecords = [];
  String? webhookUrl = 'https://discord.test/webhook';
  bool throwOnPost = false;
  bool throwOnSave = false;

  /// Existing app_deleterequest/{uid} doc, or null for a first-time request.
  Map<String, dynamic>? existingRequest;

  DeleteAccountScreen screen() => DeleteAccountScreen(
        fetchWebhookUrl: () async => webhookUrl,
        postToDiscord: (url, body) async {
          if (throwOnPost) throw Exception('boom');
          posts.add({'url': url, 'body': body});
        },
        fetchDeleteRequest: () async => existingRequest,
        saveDeleteRequest: (fields) async {
          if (throwOnSave) throw Exception('save failed');
          savedRecords.add(fields);
        },
      );
}

Future<GoRouter> _pump(WidgetTester tester, _Harness h) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
          path: '/',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('home-marker')))),
      GoRoute(path: '/delete', builder: (_, __) => h.screen()),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  // push (like the real app) so pop() can return here.
  router.push('/delete');
  await tester.pump();
  await _settle(tester);
  return router;
}

Future<void> _fillForm(WidgetTester tester,
    {String reason = 'Too many notifications', String message = 'Please delete my account now.'}) async {
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), reason);
  await tester.enterText(fields.at(1), message);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('DeleteAccountScreen request form', () {
    testWidgets('submit is disabled until both fields are filled',
        (tester) async {
      final h = _Harness();
      await _pump(tester, h);

      final submit = find.widgetWithText(ElevatedButton, 'Submit Request');
      expect(submit, findsOneWidget);
      // Disabled: onPressed null.
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);

      // Reason only -> still disabled.
      await tester.enterText(find.byType(TextField).at(0), 'some reason');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);

      // Both filled -> enabled.
      await tester.enterText(
          find.byType(TextField).at(1), 'full message here');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);
    });

    testWidgets(
        'confirm popup saves the record, posts the Discord embed, and shows the already-requested state',
        (tester) async {
      final h = _Harness();
      final router = await _pump(tester, h);
      await _fillForm(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Request'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Confirm popup is showing.
      expect(find.text('Submit deletion request?'), findsOneWidget);

      // Tap the popup's confirm button (the last Submit Request in the tree
      // is the dialog's — the overlay renders above the page).
      await tester.tap(
          find.widgetWithText(ElevatedButton, 'Submit Request').last);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The request record was saved to app_deleterequest/{uid} first.
      expect(h.savedRecords, hasLength(1));
      final record = h.savedRecords.single;
      expect(record['reason'], 'Too many notifications');
      expect(record['message'], 'Please delete my account now.');
      expect(record['status'], 'pending');
      expect(record['requestedAt'], isNotNull);
      expect(record['appVersion'], '1.0.83');
      expect(record.containsKey('uid'), isTrue);

      // One Discord post with the red deletion-request embed.
      expect(h.posts, hasLength(1));
      expect(h.posts.single['url'], 'https://discord.test/webhook');
      final body = h.posts.single['body'] as Map<String, dynamic>;
      final embeds = body['embeds'] as List;
      expect(embeds.single['title'], 'Account Deletion Request');
      expect(embeds.single['color'], 15158332);
      final fields = {
        for (final f in (embeds.single['fields'] as List))
          (f as Map)['name']: f['value']
      };
      expect(fields['Reason'], 'Too many notifications');
      expect(fields['Message'], 'Please delete my account now.');
      expect(fields['Requested At'], contains('NPT'));

      // Popup closed, success toast shown, and the page refreshed into the
      // already-requested state instead of popping back.
      expect(find.text('Submit deletion request?'), findsNothing);
      expect(find.text('Your request has been submitted'), findsOneWidget);
      expect(find.text('Request received'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Submit Request'),
          findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('home-marker'), findsNothing);
      expect(router.state.uri.path, '/delete');
    });

    testWidgets('missing webhook shows an error and posts nothing',
        (tester) async {
      final h = _Harness()..webhookUrl = null;
      await _pump(tester, h);
      await _fillForm(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Request'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(
          find.widgetWithText(ElevatedButton, 'Submit Request').last);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(h.posts, isEmpty);
      expect(find.text('Request service is unavailable right now.'),
          findsOneWidget);
    });

    testWidgets('failed Discord post still records the request and blocks '
        'duplicates', (tester) async {
      final h = _Harness()..throwOnPost = true;
      await _pump(tester, h);
      await _fillForm(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Request'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(
          find.widgetWithText(ElevatedButton, 'Submit Request').last);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The record was saved even though Discord failed.
      expect(h.savedRecords, hasLength(1));
      expect(h.posts, isEmpty);
      expect(find.text('Submit deletion request?'), findsNothing);
      expect(
          find.text(
              'Request saved, but the team notification failed. We will still review it.'),
          findsOneWidget);
      // The page shows the already-requested state: no second submission.
      expect(find.text('Request received'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('failed save posts nothing and keeps the form open',
        (tester) async {
      final h = _Harness()..throwOnSave = true;
      await _pump(tester, h);
      await _fillForm(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Request'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(
          find.widgetWithText(ElevatedButton, 'Submit Request').last);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Nothing reached Discord, and the form is still there for a retry.
      expect(h.posts, isEmpty);
      expect(find.text('Submit deletion request?'), findsNothing);
      expect(find.text('Could not submit your request. Please try again.'),
          findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('existing request on load replaces the form with the '
        'already-requested state', (tester) async {
      final h = _Harness()
        ..existingRequest = {
          'uid': 'u1',
          'status': 'pending',
          'reason': 'old',
          'message': 'old message',
        };
      await _pump(tester, h);

      // No form, no submit button — just the status card.
      expect(find.byType(TextField), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Submit Request'),
          findsNothing);
      expect(find.text('Request received'), findsOneWidget);
      expect(
          find.text(
              'We have received your account deletion request. You will get a response on your email within 24–48 working hours.'),
          findsOneWidget);
      // The informational cards above the form are untouched.
      expect(find.text('What you will lose'), findsOneWidget);

      // "I understand" acknowledges the card and goes back.
      final understand =
          find.widgetWithText(ElevatedButton, 'I understand');
      expect(understand, findsOneWidget);
      await tester.tap(understand);
      // Many small pumps: lets the pop's reverse route transition finish.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('home-marker'), findsOneWidget);
      expect(find.text('Request received'), findsNothing);
    });
  });

  group('buildDiscordPayload', () {
    test('truncates the message to Discord\'s 1024-char field limit', () {
      final long = 'x' * 2000;
      final payload = DeleteAccountScreen.buildDiscordPayload(
        uid: 'u1',
        name: 'n',
        email: 'e',
        reason: 'r',
        message: long,
        requestedAt: 't',
        appVersion: '1.0.73',
      );
      final fields =
          (payload['embeds'] as List).single['fields'] as List;
      final message =
          (fields.firstWhere((f) => f['name'] == 'Message') as Map)['value']
              as String;
      expect(message.length, lessThanOrEqualTo(1024));
      expect(message.endsWith('...'), isTrue);
    });

    test('nptTimestamp formats Kathmandu time', () {
      // 2026-10-01 18:30 UTC == 2026-10-02 00:15 NPT.
      final s = DeleteAccountScreen.nptTimestamp(
          DateTime.utc(2026, 10, 1, 18, 30));
      expect(s, '2026-10-02 00:15 NPT');
    });
  });
}
