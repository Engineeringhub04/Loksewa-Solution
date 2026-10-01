// Widget + unit tests for the edit profile screen
// (lib/screens/user/edit_profile_screen.dart).
//
// The screen is exercised through its constructor seams (debugUid, loadProfile,
// saveProfile, uploadPhoto, pickPhoto) so no test touches AuthService,
// Firestore, Cloudinary or the real file picker.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/user/edit_profile_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _doc = <String, dynamic>{
  'firstName': 'Ram',
  'lastName': 'Bahadur',
  'dob': '2001-05-09',
  'gender': 'male',
  'photoURL': null,
};

GoRouter _router(EditProfileScreen screen) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
          path: '/',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('home-marker')))),
      GoRoute(path: '/edit', builder: (_, __) => screen),
    ],
  );
}

Future<void> _pumpScreen(WidgetTester tester, EditProfileScreen screen) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = _router(screen);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  router.push('/edit');
  // Advance past the 650ms minimum loader and every SyllabusEntrance delay
  // (≤240ms) plus its animation — small pumps so taps register.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('profile_service dob helpers', () {
    test('maskDobInput builds the YYYY-MM-DD mask digit by digit', () {
      expect(maskDobInput(''), '');
      expect(maskDobInput('2'), '2');
      expect(maskDobInput('2001'), '2001');
      expect(maskDobInput('20010'), '2001-0');
      expect(maskDobInput('200105'), '2001-05');
      expect(maskDobInput('20010509'), '2001-05-09');
      expect(maskDobInput('20010509123'), '2001-05-09');
      expect(maskDobInput('20ab01-05-09'), '2001-05-09');
    });

    test('isValidDob rejects impossible and future dates', () {
      expect(isValidDob('2001-05-09'), isTrue);
      expect(isValidDob('2001-02-30'), isFalse);
      expect(isValidDob('2001-13-01'), isFalse);
      expect(isValidDob('2001-00-10'), isFalse);
      expect(isValidDob('1899-01-01'), isFalse);
      expect(isValidDob('2999-01-01'), isFalse);
      expect(isValidDob('2001-5-9'), isFalse);
      expect(isValidDob(''), isFalse);
    });

    test('fullNameOf trims and joins', () {
      expect(fullNameOf(' Ram ', ' Bahadur '), 'Ram Bahadur');
      expect(fullNameOf('Ram', ''), 'Ram');
      expect(fullNameOf('', ''), '');
    });
  });

  group('EditProfileScreen', () {
    testWidgets('shows the loader with label and hint before hydration',
        (tester) async {
      final gate = Completer<Map<String, dynamic>?>();
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = _router(EditProfileScreen(
          debugUid: 'u1', loadProfile: (_) => gate.future));
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.push('/edit');
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The load is still gated, so the pre-hydration loader stays up.
      expect(find.text('Loading Your Profile...'), findsOneWidget);
      expect(find.text('Fetching your stats and account'), findsOneWidget);
      gate.complete(_doc);
      await tester.pump();
    });

    testWidgets('hydrates the form from the document', (tester) async {
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1', loadProfile: (_) async => _doc));

      expect(find.text('Edit Profile'), findsOneWidget);
      // TextFields hold the seeded values.
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      expect((tester.widget(fields.at(0)) as TextField).controller?.text,
          'Ram');
      expect((tester.widget(fields.at(1)) as TextField).controller?.text,
          'Bahadur');
      expect((tester.widget(fields.at(2)) as TextField).controller?.text,
          '2001-05-09');
      // Live name preview, gender pill, email row, save button.
      expect(find.text('Ram Bahadur'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text('Click On Photo To Change'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('dirty form asks for confirmation on back', (tester) async {
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1', loadProfile: (_) async => _doc));

      // Make the form dirty.
      await tester.enterText(find.byType(TextField).at(0), 'Shyam');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump(const Duration(milliseconds: 300));

      // AppModalShell renders the tag pill and the title with the same text.
      expect(find.text('Discard changes?'), findsNWidgets(2));
      expect(
          find.text(
              'You have unsaved changes. If you go back now they will be lost.'),
          findsOneWidget);

      // "Keep editing" stays on the page.
      await tester.tap(find.text('Keep editing'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('home-marker'), findsNothing);

      // "Discard" leaves the page.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Discard'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('home-marker'), findsOneWidget);
    });

    testWidgets('clean form backs out without a dialog', (tester) async {
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1', loadProfile: (_) async => _doc));

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('home-marker'), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('invalid DOB blocks save with an inline error', (tester) async {
      var saved = false;
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1',
              loadProfile: (_) async => _doc,
              saveProfile: (
                      {required uid,
                      required firstName,
                      required lastName,
                      dob,
                      gender,
                      photoURL,
                      photoURLSource}) async {
                saved = true;
              }));

      await tester.enterText(find.byType(TextField).at(2), '20010230');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('2001-02-30'), findsOneWidget);

      await tester.tap(find.text('Save Changes'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
          find.text('Enter a valid date (YYYY-MM-DD)'), findsOneWidget);
      expect(saved, isFalse);
      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets('save persists, toasts and pops back', (tester) async {
      final gate = Completer<void>();
      Map<String, dynamic>? captured;
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1',
              loadProfile: (_) async => _doc,
              saveProfile: (
                      {required uid,
                      required firstName,
                      required lastName,
                      dob,
                      gender,
                      photoURL,
                      photoURLSource}) async {
                captured = {
                  'uid': uid,
                  'firstName': firstName,
                  'lastName': lastName,
                  'dob': dob,
                  'gender': gender,
                };
                await gate.future;
              }));

      await tester.enterText(find.byType(TextField).at(0), 'Shyam');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Save Changes'));
      await tester.pump(const Duration(milliseconds: 200));

      // Saving overlay blocks the screen while the write is in flight.
      expect(find.text('Saving your profile...'), findsOneWidget);

      gate.complete();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(captured?['uid'], 'u1');
      expect(captured?['firstName'], 'Shyam');
      expect(captured?['lastName'], 'Bahadur');
      expect(captured?['dob'], '2001-05-09');
      expect(captured?['gender'], 'male');
      expect(find.text('Profile updated successfully'), findsOneWidget);
      expect(find.text('home-marker'), findsOneWidget);
    });

    testWidgets('photo sheet picks from gallery and previews', (tester) async {
      // A real 1x1 PNG — the image codec rejects arbitrary bytes.
      final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1',
              loadProfile: (_) async => _doc,
              pickPhoto: () async => bytes));

      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Gallery'), findsOneWidget);

      await tester.tap(find.text('Gallery'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The freshly picked photo previews from memory.
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('renders Nepali strings after language switch', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppLanguage.setLanguage('ne');
      addTearDown(() => AppLanguage.setLanguage('en'));

      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1', loadProfile: (_) async => _doc));

      expect(find.text('प्रोफाइल सम्पादन गर्नुहोस्'), findsOneWidget);
      expect(find.text('तपाईंको प्रोफाइल लोड हुँदै...'), findsNothing);
      expect(find.text('पहिलो नाम'), findsOneWidget);
      expect(find.text('परिवर्तनहरू सेव गर्नुहोस्'), findsOneWidget);
      expect(find.text('Click On Photo To Change'), findsNothing);
    });
  });
}
