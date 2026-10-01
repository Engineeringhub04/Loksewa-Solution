// Widget + unit tests for the edit profile screen
// (lib/screens/user/edit_profile_screen.dart).
//
// The screen is exercised through its constructor seams (debugUid, loadProfile,
// saveProfile, uploadPhoto, pickPhoto) so no test touches AuthService,
// Firestore, Cloudinary or the real photo picker.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/screens/user/edit_profile_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/profile_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _doc = <String, dynamic>{
  'firstName': 'Ram',
  'lastName': 'Bahadur',
  'dob': '2001-05-09',
  'gender': 'male',
  'photoURL': null,
};

const _docWithPhoto = <String, dynamic>{
  'firstName': 'Ram',
  'lastName': 'Bahadur',
  'dob': '2001-05-09',
  'gender': 'male',
  'photoURL': 'https://res.cloudinary.com/x/old.jpg',
};

/// A real 1x1 PNG — the image codec rejects arbitrary bytes.
final _pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

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

/// Opens the photo sheet via the camera badge on the photo.
Future<void> _openPhotoSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.camera_alt));
  await tester.pump(const Duration(milliseconds: 300));
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

    testWidgets('photo sheet offers camera and gallery', (tester) async {
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1', loadProfile: (_) async => _doc));

      await _openPhotoSheet(tester);
      expect(find.text('Change Photo'), findsWidgets);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // No photo yet → no Remove option.
      expect(find.text('Remove Photo'), findsNothing);
    });

    testWidgets('picking a photo uploads IMMEDIATELY with a progress ring',
        (tester) async {
      const uploadedUrl = 'https://res.cloudinary.com/x/photo.jpg';
      final progressSeen = <double>[];
      final uploadGate = Completer<String>();
      var uploadCalls = 0;
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1',
              loadProfile: (_) async => _doc,
              pickPhoto: () async => _pngBytes,
              uploadPhoto: (picked, onProgress) {
                uploadCalls++;
                expect(picked, _pngBytes);
                onProgress(0.5);
                progressSeen.add(0.5);
                return uploadGate.future;
              }));

      await _openPhotoSheet(tester);
      await tester.tap(find.text('Gallery'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The upload started at pick time — no save was ever pressed.
      expect(uploadCalls, 1);
      expect(progressSeen, isNotEmpty);
      // The determinate ring is drawn on the photo's border (no full-screen
      // overlay covers it), with the live percent caption.
      expect(find.byType(AvatarProgressRing), findsOneWidget);
      expect(find.textContaining('Uploading your photo...'), findsOneWidget);
      expect(find.text('Saving your profile...'), findsNothing);
      // The picked photo previews from memory inside the ring.
      expect(find.byType(Image), findsWidgets);

      // The done beat: full green ring + "Photo uploaded" caption, the face
      // fully visible (no checkmark overlay covering it).
      uploadGate.complete(uploadedUrl);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Photo uploaded'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);

      // The completed upload makes the form dirty → save enables.
      await tester.pump(const Duration(milliseconds: 900));
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save Changes'))
              .onPressed,
          isNotNull);

      // Let the toast's auto-dismiss timer fire so no Timer is pending at
      // teardown.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('save is disabled while an upload is in flight',
        (tester) async {
      final uploadGate = Completer<String>();
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1',
              loadProfile: (_) async => _doc,
              pickPhoto: () async => _pngBytes,
              uploadPhoto: (picked, onProgress) => uploadGate.future));

      await _openPhotoSheet(tester);
      await tester.tap(find.text('Gallery'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Bytes still going out: saving now would risk persisting a half-known
      // photoURL, so the button stays inert.
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save Changes'))
              .onPressed,
          isNull);

      uploadGate.complete('https://res.cloudinary.com/x/photo.jpg');
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save Changes'))
              .onPressed,
          isNotNull);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('failed upload toasts and reverts to the previous photo',
        (tester) async {
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1',
              loadProfile: (_) async => _docWithPhoto,
              pickPhoto: () async => _pngBytes,
              uploadPhoto: (picked, onProgress) async {
                throw Exception('CLOUDINARY_UPLOAD_FAILED_500');
              }));

      await _openPhotoSheet(tester);
      // A photo exists → the Remove option is offered too.
      expect(find.text('Remove Photo'), findsOneWidget);
      await tester.tap(find.text('Gallery'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Error toast; the photoURL was never assigned so the old photo is
      // back on its own and the ring is gone.
      expect(
          find.text('Photo upload failed. Please try again.'), findsOneWidget);
      expect(find.byType(AvatarProgressRing), findsNothing);
      expect(find.text('Click On Photo To Change'), findsOneWidget);
      // Nothing changed → save stays disabled.
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save Changes'))
              .onPressed,
          isNull);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('save after an immediate upload persists the hosted URL and '
        'patches the shared store', (tester) async {
      const uploadedUrl = 'https://res.cloudinary.com/x/photo.jpg';
      final saveGate = Completer<void>();
      String? savedPhotoURL;
      String? savedSource;

      // Seed the shared store so the post-save patch has something to merge
      // into (and so we can observe it).
      ProfileStore.instance.profile = const UserProfile(
        uid: 'u1',
        name: 'Ram Bahadur',
        firstName: 'Ram',
        lastName: 'Bahadur',
        photoURLSource: 'none',
      );
      addTearDown(ProfileStore.instance.clear);

      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1',
              loadProfile: (_) async => _doc,
              pickPhoto: () async => _pngBytes,
              uploadPhoto: (picked, onProgress) async {
                onProgress(1);
                return uploadedUrl;
              },
              saveProfile: (
                      {required uid,
                      required firstName,
                      required lastName,
                      dob,
                      gender,
                      photoURL,
                      photoURLSource}) async {
                savedPhotoURL = photoURL;
                savedSource = photoURLSource;
                await saveGate.future;
              }));

      // Pick → the upload completes immediately (before any save). The form
      // is dirty because the new photoURL landed, so save is enabled.
      await _openPhotoSheet(tester);
      await tester.tap(find.text('Gallery'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save Changes'))
              .onPressed,
          isNotNull);

      // Save now only does the Firestore write — no second upload. The
      // "Photo uploaded" toast floats over the save button, so let it
      // auto-dismiss first. Small pumps here: one big pump leaves the
      // SnackBar in the tree and the tap misses (AGENTS.md test lesson).
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.tap(find.text('Save Changes'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Saving your profile...'), findsOneWidget);

      saveGate.complete();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The hosted URL was persisted and the shared store patched, so Home
      // and Profile re-render with the new photo without any refresh.
      expect(savedPhotoURL, uploadedUrl);
      expect(savedSource, 'manual');
      expect(ProfileStore.instance.profile?.photoURL, uploadedUrl);
      expect(ProfileStore.instance.profile?.name, 'Ram Bahadur');
      expect(find.text('Profile updated successfully'), findsOneWidget);
      expect(find.text('home-marker'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('remove photo marks the form dirty and saves null',
        (tester) async {
      String? savedPhotoURL = 'sentinel';
      String? savedSource = 'sentinel';
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1',
              loadProfile: (_) async => _docWithPhoto,
              saveProfile: (
                      {required uid,
                      required firstName,
                      required lastName,
                      dob,
                      gender,
                      photoURL,
                      photoURLSource}) async {
                savedPhotoURL = photoURL;
                savedSource = photoURLSource;
              }));

      await _openPhotoSheet(tester);
      await tester.tap(find.text('Remove Photo'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save Changes'))
              .onPressed,
          isNotNull);

      await tester.tap(find.text('Save Changes'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(savedPhotoURL, isNull);
      expect(savedSource, 'none');
      expect(find.text('home-marker'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
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

    testWidgets('save is disabled until the form is dirty', (tester) async {
      await _pumpScreen(
          tester,
          EditProfileScreen(
              debugUid: 'u1', loadProfile: (_) async => _doc));

      // Mirrors React's disabled={!isDirty || isOffline || saving}: nothing
      // changed yet, so the button is inert.
      final saveButton = find.widgetWithText(FilledButton, 'Save Changes');
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

      await tester.enterText(find.byType(TextField).at(0), 'Shyam');
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    });

    testWidgets('ProfileStore.applyLocalPatch notifies listeners',
        (tester) async {
      ProfileStore.instance.profile = const UserProfile(
        uid: 'u9',
        name: 'Old Name',
        firstName: 'Old',
        lastName: 'Name',
      );
      addTearDown(ProfileStore.instance.clear);

      var notified = 0;
      void listener() => notified++;
      ProfileStore.instance.addListener(listener);
      ProfileStore.instance
          .applyLocalPatch((p) => p.copyWith(firstName: 'New'));
      expect(ProfileStore.instance.profile?.firstName, 'New');
      expect(notified, 1);
      ProfileStore.instance.removeListener(listener);
    });

    group('floating label colour parity (React focusAnim/colorAnim split)',
        () {
      /// Exact-equality is brittle across Color.lerp's float rounding, so
      /// compare channel-wise with a tight tolerance.
      void expectColor(Color actual, Color expected) {
        final diffs = [
          (actual.r - expected.r).abs(),
          (actual.g - expected.g).abs(),
          (actual.b - expected.b).abs(),
          (actual.a - expected.a).abs(),
        ];
        expect(diffs.every((d) => d < 0.01), isTrue,
            reason: 'actual $actual differs from expected $expected');
      }

      Color labelColorOf(WidgetTester tester, String label) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.style?.color, isNotNull);
        return text.style!.color!;
      }

      /// The field's outer bordered Container, found by walking up from its
      /// floating label.
      Border fieldBorder(WidgetTester tester, String label) {
        final box = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).border is Border),
        );
        expect(box, findsOneWidget);
        final decoration = (tester.widget<Container>(box).decoration
            as BoxDecoration);
        return decoration.border as Border;
      }

      testWidgets(
          'unfocused field WITH a value keeps a neutral label and border',
          (tester) async {
        await _pumpScreen(
            tester,
            EditProfileScreen(
                debugUid: 'u1', loadProfile: (_) async => _doc));

        final palette =
            ExpoPalette.of(tester.element(find.text('First Name')));
        final focusMix =
            Color.lerp(palette.primary, palette.textSecondary, 0.6)!;

        // The First Name field holds 'Ram' but has no focus: the label
        // floats (position anim) yet keeps the neutral tone — NOT the blue
        // focus mix that the old single-anim logic rendered for every
        // pre-filled field.
        expectColor(labelColorOf(tester, 'First Name'),
            palette.textSecondary);
        expect(
            (labelColorOf(tester, 'First Name').r - focusMix.r).abs() < 0.01 &&
                (labelColorOf(tester, 'First Name').g - focusMix.g).abs() <
                    0.01,
            isFalse,
            reason: 'label must not sit at the focus tint while unfocused');
        expectColor(fieldBorder(tester, 'First Name').top.color,
            palette.border);
      });

      testWidgets('focus tints the label to the softened focus mix',
          (tester) async {
        await _pumpScreen(
            tester,
            EditProfileScreen(
                debugUid: 'u1', loadProfile: (_) async => _doc));

        final palette =
            ExpoPalette.of(tester.element(find.text('First Name')));
        final focusMix =
            Color.lerp(palette.primary, palette.textSecondary, 0.6)!;

        // Sanity: starts neutral.
        expectColor(labelColorOf(tester, 'First Name'),
            palette.textSecondary);

        await tester.tap(find.byType(TextField).at(0));
        // Small pumps so the tap registers and the 240ms colour wash runs
        // to completion.
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        final after = labelColorOf(tester, 'First Name');
        expectColor(after, focusMix);
        expectColor(fieldBorder(tester, 'First Name').top.color, focusMix);
        // The harsh full-strength blue stays gone.
        expect(
            (after.r - palette.primary.r).abs() < 0.01 &&
                (after.g - palette.primary.g).abs() < 0.01 &&
                (after.b - palette.primary.b).abs() < 0.01,
            isFalse,
            reason: 'label must use the softened mix, not full primary');
      });
    });
  });
}
