// Widget tests for the profile double-label menu rows (Part 2).
//
// Every ProfileMenuRow shows a bold title with a smaller gray subtitle below
// it (the reference settings-screen pattern). The subtitle must stay a
// readable gray in BOTH themes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/profile_rows.dart';

Widget _wrap(Widget child, {bool dark = false}) {
  return MaterialApp(
    theme: dark ? ThemeData.dark() : ThemeData.light(),
    home: Scaffold(body: child),
  );
}

ProfileMenuRow _row({String? subtitle, bool destructive = false}) {
  return ProfileMenuRow(
    icon: const Icon(Icons.bookmark_outline),
    label: 'Bookmarks',
    subtitle: subtitle,
    destructive: destructive,
    onPress: () {},
  );
}

Future<void> _pumpRow(WidgetTester tester, ProfileMenuRow row,
    {bool dark = false}) async {
  await tester.pumpWidget(_wrap(row, dark: dark));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('ProfileMenuRow double label', () {
    testWidgets('title is bold, subtitle is smaller gray text below it',
        (tester) async {
      await _pumpRow(
          tester, _row(subtitle: 'Your saved questions & notes'));

      final title = tester.widget<Text>(find.text('Bookmarks'));
      expect(title.style?.fontWeight, FontWeight.bold);
      expect(title.style?.fontSize, 16);

      final subtitle =
          tester.widget<Text>(find.text('Your saved questions & notes'));
      expect(subtitle.style?.fontSize, 12);
      expect(subtitle.style?.color, ExpoPalette.light.textSecondary);
      expect(subtitle.style?.fontWeight, isNot(FontWeight.bold));
    });

    testWidgets('subtitle stays readable gray in dark theme',
        (tester) async {
      await _pumpRow(
          tester, _row(subtitle: 'Your saved questions & notes'),
          dark: true);

      final subtitle =
          tester.widget<Text>(find.text('Your saved questions & notes'));
      expect(subtitle.style?.color, ExpoPalette.dark.textSecondary);
      // Not the dark danger tint and not near-black: a real readable gray.
      expect(subtitle.style?.color, isNot(ExpoPalette.dark.danger));
    });

    testWidgets('row without a subtitle still renders one line',
        (tester) async {
      await _pumpRow(tester, _row());

      expect(find.text('Bookmarks'), findsOneWidget);
      // Only the title text and the chevron icon are in the row.
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('destructive row keeps a gray subtitle, red title',
        (tester) async {
      await _pumpRow(
          tester,
          _row(
              subtitle: 'Permanently remove your account',
              destructive: true));

      final title = tester.widget<Text>(find.text('Bookmarks'));
      expect(title.style?.color, ExpoPalette.light.danger);
      expect(title.style?.fontWeight, FontWeight.bold);

      final subtitle =
          tester.widget<Text>(find.text('Permanently remove your account'));
      expect(subtitle.style?.color, ExpoPalette.light.textSecondary);
    });

    testWidgets('subtitle follows the app language (pure EN / pure NE)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppLanguage.setLanguage('en');

      await _pumpRow(
          tester,
          _row(
              subtitle: AppLanguage.tr(
                  'Your saved questions & notes',
                  'तपाईंले सेभ गरेका प्रश्न र नोटहरू')));
      expect(find.text('Your saved questions & notes'), findsOneWidget);

      await AppLanguage.setLanguage('ne');
      await tester.pumpWidget(_wrap(_row(
          subtitle: AppLanguage.tr('Your saved questions & notes',
              'तपाईंले सेभ गरेका प्रश्न र नोटहरू'))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          find.text('तपाईंले सेभ गरेका प्रश्न र नोटहरू'), findsOneWidget);
      expect(find.text('Your saved questions & notes'), findsNothing);

      addTearDown(() => AppLanguage.setLanguage('en'));
    });
  });
}
