// Widget tests for the course details screen
// (lib/screens/learn/course_details_screen.dart).
//
// The screen is exercised through its constructor seams (debugUid + loadInfo)
// so no test ever touches AuthService or Firestore.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/learn/course_details_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/widgets/preloading.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _info = CourseDetailsInfo(
  courseId: 'c1',
  subcourseId: 's1',
  courseName: 'GK & Current Affairs',
  subcourseName: 'GK Basics',
);

Widget _wrap(CourseDetailsScreen screen) =>
    MaterialApp(home: Scaffold(body: screen));

Future<void> _pumpScreen(WidgetTester tester, CourseDetailsScreen screen) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrap(screen));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  group('CourseDetailsScreen', () {
    testWidgets('shows resolved course and subcourse names', (tester) async {
      await _pumpScreen(
          tester,
          CourseDetailsScreen(
              debugUid: 'u1', loadInfo: (_) async => _info));

      expect(find.text('Course Details'), findsOneWidget);
      // The course name shows both in the gradient hero headline and in the
      // info card's Course row.
      expect(find.text('GK & Current Affairs'), findsNWidgets(2));
      expect(find.text('GK Basics'), findsOneWidget);
      expect(find.text('Not selected yet'), findsNothing);
      expect(
          find.text(
              'This is the course your study content, mock tests and daily questions are based on.'),
          findsOneWidget);
      expect(find.text('Change Course'), findsOneWidget);
    });

    testWidgets('null names fall back to not-selected', (tester) async {
      await _pumpScreen(
          tester,
          CourseDetailsScreen(
              debugUid: 'u1',
              loadInfo: (_) async => const CourseDetailsInfo()));

      // 'Not selected yet' shows in the hero headline plus both info rows.
      expect(find.text('Not selected yet'), findsNWidgets(3));
    });

    testWidgets('loading shows the preloader with label and hint',
        (tester) async {
      final gate = Completer<CourseDetailsInfo>();
      await tester.pumpWidget(_wrap(CourseDetailsScreen(
          debugUid: 'u1', loadInfo: (_) => gate.future)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(PreloadingWidget), findsOneWidget);
      expect(find.text('Loading Course Details...'), findsOneWidget);
      expect(find.text('Fetching your course information'), findsOneWidget);

      gate.complete(_info);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('GK Basics'), findsOneWidget);
    });

    testWidgets('failure shows the DataNotFound gate with retry',
        (tester) async {
      var calls = 0;
      Future<CourseDetailsInfo> fail(String uid) async {
        calls++;
        throw Exception('nope');
      }

      await _pumpScreen(
          tester, CourseDetailsScreen(debugUid: 'u1', loadInfo: fail));

      expect(find.text('Data Not Found'), findsOneWidget);
      expect(find.text("We couldn't load this content. Please try again."),
          findsOneWidget);
      expect(calls, 1);

      await tester.tap(find.text('Try Again'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 2);
      expect(find.text('Data Not Found'), findsOneWidget);
    });

    testWidgets('pull to refresh reloads the info', (tester) async {
      var calls = 0;
      await _pumpScreen(
          tester,
          CourseDetailsScreen(
              debugUid: 'u1',
              loadInfo: (_) async {
                calls++;
                return _info;
              }));

      expect(calls, 1);
      // A slow drag (not a fast fling) reliably produces the overscroll that
      // arms the RefreshIndicator in tests.
      await tester.timedDrag(
          find.byType(ListView), const Offset(0, 600), const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 2);
      expect(find.text('GK Basics'), findsOneWidget);
    });

    testWidgets('Nepali language renders Nepali strings', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppLanguage.setLanguage('ne');
      addTearDown(() => AppLanguage.setLanguage('en'));
      await _pumpScreen(
          tester,
          CourseDetailsScreen(
              debugUid: 'u1', loadInfo: (_) async => _info));

      expect(find.text('कोर्स विवरण'), findsOneWidget);
      expect(find.text('कोर्स परिवर्तन गर्नुहोस्'), findsOneWidget);
      expect(find.text('Change Course'), findsNothing);
    });
  });
}
