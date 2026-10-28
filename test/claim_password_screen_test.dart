import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:loksewa_solution/screens/auth/claim_password_screen.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NOTE-11 claim screen: step 1 (email + Send Code) reveals step 2
/// (code + Set Your Password + confirm) after the worker accepts.
void main() {
  tearDown(() => CfApi.setTestClient(null));

  Future<void> pumpScreen(WidgetTester tester,
      {String? initialEmail}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(MaterialApp(
      home: ClaimPasswordScreen(initialEmail: initialEmail),
    ));
    await tester.pump();
  }

  testWidgets('step 1 shows only the email field and Send Code',
      (tester) async {
    await pumpScreen(tester);
    expect(find.text('Send Code'), findsOneWidget);
    expect(find.text('Verification Code'), findsNothing);
    expect(find.text('Confirm Password'), findsNothing);
  });

  testWidgets('prefilled email + Send Code reveals the password step',
      (tester) async {
    CfApi.setTestClient(
        MockClient((_) async => http.Response('{"ok":true}', 200)));
    await pumpScreen(tester, initialEmail: 'a@b.com');
    expect(find.text('a@b.com'), findsOneWidget);

    await tester.tap(find.text('Send Code'));
    // Worker future resolves, then the AnimatedSwitcher runs.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Verification Code'), findsOneWidget);
    expect(find.text('Set Your Password'), findsWidgets);
    expect(find.text('Confirm Password'), findsOneWidget);
    expect(find.text('Set Password & Login'), findsOneWidget);
  });

  testWidgets('invalid email keeps step 1 (no code step)', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.tap(find.text('Send Code'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Verification Code'), findsNothing);
  });
}
