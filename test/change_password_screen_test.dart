import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/screens/settings/change_password_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/change_password_service.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/stagger_entrance.dart';

/// Widget tests for Security Settings → Change Password.
///
/// The screen's network seams are injected ([ChangePasswordScreen.debugEmail]
/// etc.), so no Identity Toolkit calls happen. NEVER pumpAndSettle — the
/// confirmation popup's 200ms transitions are finite but the entrance
/// animations need small pumps.

Widget _screen({
  Future<OldPasswordCheck> Function(String, String)? verify,
  Future<bool> Function(String, String)? update,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ChangePasswordScreen(
        debugEmail: 'user@example.com',
        verifyOldPassword: verify,
        updatePassword: update,
      ),
    ),
  );
}


/// Pumps the StaggerEntrance animations through (450ms + up to 140ms delay)
/// in small increments, so buttons are back on screen before taps.
/// Never pumpAndSettle — the entrance delays need the fake clock advanced.
Future<void> _pumpEntered(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _fillValid(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'oldpass1');
  await tester.enterText(fields.at(1), 'newpass2');
  await tester.enterText(fields.at(2), 'newpass2');
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tapUpdate(WidgetTester tester) async {
  await tester.tap(find.text('Update Password'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('empty old password shows the inline prompt', (tester) async {
    await tester.pumpWidget(_screen());
    await _pumpEntered(tester);

    await _tapUpdate(tester);

    expect(find.text('Please enter your old password'), findsOneWidget);
    expect(find.byType(AppModalShell), findsNothing);
  });

  testWidgets('short new password shows the min-length error', (tester) async {
    await tester.pumpWidget(_screen());
    await _pumpEntered(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'oldpass1');
    await tester.enterText(fields.at(1), 'abc');
    await tester.enterText(fields.at(2), 'abc');
    await tester.pump(const Duration(milliseconds: 100));
    await _tapUpdate(tester);

    expect(
        find.text('Password must be at least 6 characters'), findsOneWidget);
    expect(find.byType(AppModalShell), findsNothing);
  });

  testWidgets('new == old shows the must-be-different error', (tester) async {
    await tester.pumpWidget(_screen());
    await _pumpEntered(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'samepass1');
    await tester.enterText(fields.at(1), 'samepass1');
    await tester.enterText(fields.at(2), 'samepass1');
    await tester.pump(const Duration(milliseconds: 100));
    await _tapUpdate(tester);

    expect(find.text('New password must be different from the old password.'),
        findsOneWidget);
    expect(find.byType(AppModalShell), findsNothing);
  });

  testWidgets('mismatched confirm shows the mismatch error', (tester) async {
    await tester.pumpWidget(_screen());
    await _pumpEntered(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'oldpass1');
    await tester.enterText(fields.at(1), 'newpass2');
    await tester.enterText(fields.at(2), 'otherpass3');
    await tester.pump(const Duration(milliseconds: 100));
    await _tapUpdate(tester);

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(find.byType(AppModalShell), findsNothing);
  });

  testWidgets('valid form opens the confirmation popup', (tester) async {
    var verifyCalls = 0;
    await tester.pumpWidget(_screen(
      verify: (_, __) async {
        verifyCalls++;
        return const OldPasswordCheck.ok('fresh-token');
      },
      update: (_, __) async => true,
    ));
    await _pumpEntered(tester);

    await _fillValid(tester);
    await _tapUpdate(tester);

    // The confirmation popup — never a raw dialog.
    expect(find.text('Change your password?'), findsOneWidget);
    expect(find.byType(AppModalShell), findsOneWidget);
    // Nothing verified yet — the verify happens on Confirm.
    expect(verifyCalls, 0);
  });

  testWidgets('cancel dismisses the popup without verifying', (tester) async {
    var verifyCalls = 0;
    await tester.pumpWidget(_screen(
      verify: (_, __) async {
        verifyCalls++;
        return const OldPasswordCheck.ok('fresh-token');
      },
      update: (_, __) async => true,
    ));
    await _pumpEntered(tester);

    await _fillValid(tester);
    await _tapUpdate(tester);
    await tester.tap(find.text('Cancel'));
    // The dialog's reverse transition needs a few frames in the test
    // binding — pump until it is gone rather than a fixed duration.
    for (var i = 0;
        i < 20 && find.byType(AppModalShell).evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(AppModalShell), findsNothing);
    expect(verifyCalls, 0);
    expect(find.text('Update Password'), findsOneWidget);
  });

  testWidgets('wrong old password → inline error after confirm', (tester) async {
    await tester.pumpWidget(_screen(
      verify: (_, __) async => OldPasswordCheck.wrong,
      update: (_, __) async => true,
    ));
    await _pumpEntered(tester);

    await _fillValid(tester);
    await _tapUpdate(tester);
    await tester.tap(find.text('Confirm'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    // Popup dismissed, inline error on the old-password field.
    expect(find.byType(AppModalShell), findsNothing);
    expect(find.text('Old password is incorrect.'), findsOneWidget);
    expect(find.text('Password changed successfully'), findsNothing);
  });

  testWidgets('confirm with correct old password → success state',
      (tester) async {
    String? seenToken;
    String? seenNew;
    await tester.pumpWidget(_screen(
      verify: (email, old) async {
        expect(email, 'user@example.com');
        expect(old, 'oldpass1');
        return const OldPasswordCheck.ok('fresh-token');
      },
      update: (token, newPw) async {
        seenToken = token;
        seenNew = newPw;
        return true;
      },
    ));
    await _pumpEntered(tester);

    await _fillValid(tester);
    await _tapUpdate(tester);
    await tester.tap(find.text('Confirm'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    // The fresh idToken from the sign-in step is used for the update.
    expect(seenToken, 'fresh-token');
    expect(seenNew, 'newpass2');
    expect(find.text('Password changed successfully'), findsOneWidget);
  });

  testWidgets('update failure → error toast, no success state', (tester) async {
    await tester.pumpWidget(_screen(
      verify: (_, __) async => const OldPasswordCheck.ok('fresh-token'),
      update: (_, __) async => false,
    ));
    await _pumpEntered(tester);

    await _fillValid(tester);
    await _tapUpdate(tester);
    await tester.tap(find.text('Confirm'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Password changed successfully'), findsNothing);
    expect(find.text('Something went wrong. Please try again.'),
        findsOneWidget);
  });

  testWidgets('premium treatment: staggered form + password tips card',
      (tester) async {
    await tester.pumpWidget(_screen());
    await _pumpEntered(tester);

    // Form card + tips card stagger in.
    expect(find.byType(StaggerEntrance), findsNWidgets(2));
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.text('Password tips'), findsOneWidget);
    expect(find.text('At least 6 characters'), findsOneWidget);
    expect(find.text('Different from your old password'), findsOneWidget);
    expect(find.text('Never share it with anyone'), findsOneWidget);
    // Core functionality unchanged.
    expect(find.text('Update Password'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
  });

  testWidgets('renders Devanagari strings in Nepali mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.setLanguage('ne');
    addTearDown(() => AppLanguage.setLanguage('en'));

    await tester.pumpWidget(_screen());
    await _pumpEntered(tester);

    expect(find.text('पासवर्ड परिवर्तन'), findsOneWidget);
    expect(find.text('नयाँ पासवर्ड छान्नुहोस्'), findsOneWidget);
    expect(find.text('पासवर्ड अद्यावधिक गर्नुहोस्'), findsOneWidget);
    expect(find.text('पासवर्ड बिर्सनुभयो?'), findsOneWidget);
    expect(find.text('पासवर्ड सुझावहरू'), findsOneWidget);
    expect(find.text('कम्तीमा ६ अक्षर'), findsOneWidget);
    // No English leaking through.
    expect(find.text('Update Password'), findsNothing);
    expect(find.text('Password tips'), findsNothing);
  });

  testWidgets('Forgot Password? navigates to /forgot-password', (tester) async {
    final router = GoRouter(
      initialLocation: '/settings/change-password',
      routes: [
        GoRoute(
          path: '/settings/change-password',
          builder: (_, __) => const ChangePasswordScreen(
            debugEmail: 'user@example.com',
          ),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (_, __) =>
              const Scaffold(body: Text('forgot-stub')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _pumpEntered(tester);

    await tester.tap(find.text('Forgot Password?'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('forgot-stub'), findsOneWidget);
  });
}
