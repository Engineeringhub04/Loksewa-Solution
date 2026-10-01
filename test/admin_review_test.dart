// Tests for the admin review shared dialogs + language-aware content title:
// - approve confirm pops true/false through the shared AppModalShell modal;
// - reject dialog pops the trimmed reason (or null on cancel);
// - adminContentTitle mirrors React's `language === 'ne'
//   ? contentTitleNe || contentTitle : contentTitle`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loksewa_solution/screens/admin/admin_review_dialogs.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';

Future<void> _pumpHarness(
  WidgetTester tester,
  Future<dynamic> Function(BuildContext) open,
) async {
  tester.view.physicalSize = const Size(720, 1612);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => open(context),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await AppLanguage.setLanguage('en');
  });

  group('adminContentTitle', () {
    test('english returns contentTitle', () async {
      await AppLanguage.setLanguage('en');
      expect(
          adminContentTitle(
              {'contentTitle': 'Algebra', 'contentTitleNe': 'बीजगणित'}),
          'Algebra');
    });

    test('nepali prefers contentTitleNe', () async {
      await AppLanguage.setLanguage('ne');
      expect(
          adminContentTitle(
              {'contentTitle': 'Algebra', 'contentTitleNe': 'बीजगणित'}),
          'बीजगणित');
    });

    test('nepali falls back to contentTitle when Ne missing', () async {
      await AppLanguage.setLanguage('ne');
      expect(adminContentTitle({'contentTitle': 'Algebra'}), 'Algebra');
      expect(
          adminContentTitle(
              {'contentTitle': 'Algebra', 'contentTitleNe': ''}),
          'Algebra');
    });
  });

  group('approve dialog', () {
    testWidgets('renders AppModalShell with title + message',
        (tester) async {
      await _pumpHarness(
          tester,
          (c) => showAdminReviewApproveDialog(c,
              approveMessage: 'Approve this one?'));

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.text('Approve'), findsWidgets);
      expect(find.text('Approve this one?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Approve pops true, Cancel pops false', (tester) async {
      bool? result;
      await _pumpHarness(
          tester,
          (c) async {
            result = await showAdminReviewApproveDialog(c,
                approveMessage: 'msg');
          });

      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('Cancel pops false', (tester) async {
      bool? result;
      var called = false;
      await _pumpHarness(
          tester,
          (c) async {
            called = true;
            result = await showAdminReviewApproveDialog(c,
                approveMessage: 'msg');
          });
      expect(called, isTrue);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });

  group('reject dialog', () {
    testWidgets('renders reason field with placeholder', (tester) async {
      await _pumpHarness(tester, showAdminReviewRejectDialog);

      expect(find.byType(AppModalShell), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(
          find.text('Reason for rejection (shown to the user)'),
          findsOneWidget);
    });

    testWidgets('Reject pops the trimmed reason', (tester) async {
      String? result;
      var sentinel = false;
      await _pumpHarness(
          tester,
          (c) async {
            sentinel = true;
            result = await showAdminReviewRejectDialog(c);
          });
      expect(sentinel, isTrue);

      await tester.enterText(
          find.byType(TextField), '  payment mismatch  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();
      expect(result, 'payment mismatch');
    });

    testWidgets('empty reason pops empty string (caller applies default)',
        (tester) async {
      String? result = 'unset';
      await _pumpHarness(
          tester,
          (c) async {
            result = await showAdminReviewRejectDialog(c);
          });

      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();
      expect(result, '');
    });

    testWidgets('Cancel pops null', (tester) async {
      String? result = 'unset';
      await _pumpHarness(
          tester,
          (c) async {
            result = await showAdminReviewRejectDialog(c);
          });

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('nepali strings render in nepali mode', (tester) async {
      await AppLanguage.setLanguage('ne');
      await _pumpHarness(
          tester,
          (c) => showAdminReviewApproveDialog(c,
              approveMessage: 'सन्देश'));
      expect(find.text('स्वीकृत गर्नुहोस्'), findsWidgets);
      expect(find.text('रद्द गर्नुहोस्'), findsOneWidget);
      expect(find.text('समीक्षा'), findsOneWidget);
    });
  });
}
