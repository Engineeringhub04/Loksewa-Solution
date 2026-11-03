import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/screens/settings/change_password_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/change_password_service.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/auth/floating_label_field.dart';
import 'package:loksewa_solution/widgets/syllabus_entrance.dart';

/// Widget tests for Security Settings → Change Password.
///
/// The screen's network seam is injected ([ChangePasswordScreen.debugEmail]
/// etc.), so no API calls happen. NEVER pumpAndSettle — the
/// confirmation popup's 200ms transitions are finite but the entrance
/// animations need small pumps.

Widget _screen({
  Future<PasswordChangeOutcome> Function(String, String)? change,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ChangePasswordScreen(
        debugEmail: 'user@example.com',
        changePassword: change,
      ),
    ),
  );
}


/// Pumps the SyllabusEntrance animations through (380ms + up to 140ms delay)
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
    var changeCalls = 0;
    await tester.pumpWidget(_screen(
      change: (_, __) async {
        changeCalls++;
        return PasswordChangeOutcome.ok;
      },
    ));
    await _pumpEntered(tester);

    await _fillValid(tester);
    await _tapUpdate(tester);

    // The confirmation popup — never a raw dialog.
    expect(find.text('Change your password?'), findsOneWidget);
    expect(find.byType(AppModalShell), findsOneWidget);
    // Nothing submitted yet — the change happens on Confirm.
    expect(changeCalls, 0);
  });

  testWidgets('cancel dismisses the popup without submitting', (tester) async {
    var changeCalls = 0;
    await tester.pumpWidget(_screen(
      change: (_, __) async {
        changeCalls++;
        return PasswordChangeOutcome.ok;
      },
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
    expect(changeCalls, 0);
    expect(find.text('Update Password'), findsOneWidget);
  });

  testWidgets('wrong old password → inline error after confirm', (tester) async {
    await tester.pumpWidget(_screen(
      change: (_, __) async => PasswordChangeOutcome.wrongPassword,
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
    String? seenOld;
    String? seenNew;
    await tester.pumpWidget(_screen(
      change: (old, newPw) async {
        seenOld = old;
        seenNew = newPw;
        return PasswordChangeOutcome.ok;
      },
    ));
    await _pumpEntered(tester);

    await _fillValid(tester);
    await _tapUpdate(tester);
    await tester.tap(find.text('Confirm'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    // The single change call carries the typed old + new passwords.
    expect(seenOld, 'oldpass1');
    expect(seenNew, 'newpass2');
    expect(find.text('Password changed successfully'), findsOneWidget);
  });

  testWidgets('change failure → error toast, no success state', (tester) async {
    await tester.pumpWidget(_screen(
      change: (_, __) async => PasswordChangeOutcome.error,
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

  testWidgets('premium treatment: smooth form + password tips card',
      (tester) async {
    await tester.pumpWidget(_screen());
    await _pumpEntered(tester);

    // Form card + tips card enter smoothly (NOTE-24).
    expect(find.byType(SyllabusEntrance), findsNWidgets(2));
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
          builder: (_, state) =>
              Scaffold(body: Text('forgot-stub ${state.extra ?? ''}')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _pumpEntered(tester);

    await tester.tap(find.text('Forgot Password?'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('forgot-stub user@example.com'), findsOneWidget);
  });

  testWidgets('dark mode: cards follow the theme, fields go dark (NOTE-23)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: const Scaffold(
        body: ChangePasswordScreen(debugEmail: 'user@example.com'),
      ),
    ));
    await _pumpEntered(tester);

    // The form card is the dark palette surface — not the old white.
    final card = tester.widget<Container>(find
        .ancestor(
          of: find.text('Choose a new password'),
          matching: find.byType(Container),
        )
        .first);
    expect((card.decoration as BoxDecoration).color,
        ExpoPalette.dark.surface);
    // Every field takes the dark variant.
    final fields =
        tester.widgetList<FloatingLabelField>(find.byType(FloatingLabelField));
    expect(fields.length, 3);
    expect(fields.every((f) => f.dark), isTrue);
  });

  testWidgets('light mode: fields stay in the light variant', (tester) async {
    await tester.pumpWidget(_screen());
    await _pumpEntered(tester);

    final card = tester.widget<Container>(find
        .ancestor(
          of: find.text('Choose a new password'),
          matching: find.byType(Container),
        )
        .first);
    expect((card.decoration as BoxDecoration).color,
        ExpoPalette.light.surface);
    final fields =
        tester.widgetList<FloatingLabelField>(find.byType(FloatingLabelField));
    expect(fields.length, 3);
    expect(fields.every((f) => !f.dark), isTrue);
  });
}
