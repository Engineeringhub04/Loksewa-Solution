import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loksewa_solution/screens/auth/contact_us_screen.dart';
import 'package:loksewa_solution/screens/auth/delete_account_screen.dart';
import 'package:loksewa_solution/screens/auth/feedback_screen.dart';
import 'package:loksewa_solution/screens/auth/privacy_policy_screen.dart';
import 'package:loksewa_solution/screens/auth/report_problem_screen.dart';
import 'package:loksewa_solution/screens/auth/terms_conditions_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/widgets/preloading.dart';

// Every screen below carries SyllabusEntrance (delayed AnimationController +
// Future.delayed), so: very tall test surface (all sections build at once,
// no scrolling), settle with many small pumps (one big pump() leaves taps
// unregistered by the gesture arena; pumpAndSettle never settles while the
// entrance timers are pending).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: screen));
  await _settle(tester);
}

void main() {
  tearDown(() => AppLanguage.current.value = 'en');

  group('DeleteAccountScreen', () {
    testWidgets('renders warning, losses, request form and cancel',
        (WidgetTester tester) async {
      await _pump(tester, const DeleteAccountScreen());

      expect(find.text('Delete Account'), findsOneWidget);
      expect(find.text('This cannot be undone'), findsOneWidget);
      expect(find.text('What you will lose'), findsOneWidget);
      expect(find.text('Your profile, name, photo and course selection'),
          findsOneWidget);
      expect(find.text('Reason (required)'), findsOneWidget);
      expect(find.text('Full Message (required)'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Submit stays disabled until both fields are filled.
      final submitBtn =
          find.widgetWithText(ElevatedButton, 'Submit Request');
      expect(submitBtn, findsOneWidget);
      expect(tester.widget<ElevatedButton>(submitBtn).onPressed, isNull);
    });

    testWidgets('filling both fields enables the submit button',
        (WidgetTester tester) async {
      await _pump(tester, const DeleteAccountScreen());

      await tester.enterText(find.byType(TextField).at(0), 'Too many emails');
      await tester.pump();
      await tester.enterText(
          find.byType(TextField).at(1), 'Please delete my account. Thanks.');
      await tester.pump();
      final submitBtn =
          find.widgetWithText(ElevatedButton, 'Submit Request');
      expect(tester.widget<ElevatedButton>(submitBtn).onPressed,
          isNotNull);
    });

    testWidgets('submit opens the confirm dialog, cancel dismisses it',
        (WidgetTester tester) async {
      await _pump(tester, const DeleteAccountScreen());

      await tester.enterText(find.byType(TextField).at(0), 'Too many emails');
      await tester.pump();
      await tester.enterText(
          find.byType(TextField).at(1), 'Please delete my account. Thanks.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Request'));
      await _settle(tester);

      expect(find.text('Submit deletion request?'), findsOneWidget);

      // Cancelling dismisses the dialog without submitting.
      await tester
          .tap(find.widgetWithText(OutlinedButton, 'Cancel').first);
      await _settle(tester);
      expect(find.text('Submit deletion request?'), findsNothing);
    });

    testWidgets('renders Nepali copy when the app language is Nepali',
        (WidgetTester tester) async {
      AppLanguage.current.value = 'ne';
      await _pump(tester, const DeleteAccountScreen());

      expect(find.text('खाता मेट्नुहोस्'), findsWidgets);
      expect(find.text('यो फिर्ता गर्न मिल्दैन'), findsOneWidget);
      expect(find.text('तपाईंले गुमाउने कुराहरू'), findsOneWidget);
      expect(find.text('कारण (आवश्यक)'), findsOneWidget);
      expect(find.text('पूर्ण सन्देश (आवश्यक)'), findsOneWidget);
      expect(find.text('अनुरोध पठाउनुहोस्'), findsOneWidget);
      expect(find.text('रद्द गर्नुहोस्'), findsOneWidget);
    });
  });

  group('ContactUsScreen', () {
    testWidgets('renders hero, channels, socials and the message form',
        (WidgetTester tester) async {
      await _pump(tester, const ContactUsScreen());

      expect(find.text('Contact Us'), findsWidgets);
      expect(
          find.text(
              'We usually reply within one working day. Pick whichever channel suits you.'),
          findsOneWidget);
      expect(find.text('Replies within 1 working day'), findsOneWidget);

      expect(find.text('Reach us'), findsOneWidget);
      expect(find.text('Email us'), findsOneWidget);
      expect(find.text('contact@kbr.com.np'), findsOneWidget);
      expect(find.text('Call us'), findsOneWidget);
      expect(find.text('+977-9810768297'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
      expect(find.text('kbr.com.np'), findsOneWidget);

      expect(find.text('Follow us'), findsOneWidget);
      expect(find.text('Facebook'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('X (Twitter)'), findsOneWidget);

      expect(find.text('Send Message'), findsWidgets);
      expect(find.text('Reach out to our support team'), findsOneWidget);
    });

    testWidgets('send button enables once a message is typed',
        (WidgetTester tester) async {
      await _pump(tester, const ContactUsScreen());

      final sendBtn =
          find.widgetWithText(ElevatedButton, 'Send Message');
      expect(sendBtn, findsOneWidget);
      expect(tester.widget<ElevatedButton>(sendBtn).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Hello support');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(sendBtn).onPressed, isNotNull);
    });

    testWidgets('renders Nepali copy when the app language is Nepali',
        (WidgetTester tester) async {
      AppLanguage.current.value = 'ne';
      await _pump(tester, const ContactUsScreen());

      expect(find.text('सम्पर्क गर्नुहोस्'), findsWidgets);
      expect(find.text('१ कार्यदिनभित्र जवाफ'), findsOneWidget);
      expect(find.text('इमेल गर्नुहोस्'), findsOneWidget);
      expect(find.text('फोन गर्नुहोस्'), findsOneWidget);
      expect(find.text('सन्देश पठाउनुहोस्'), findsWidgets);
      expect(find.text('हाम्रो सहायता टोलीलाई सम्पर्क गर्नुहोस्'),
          findsOneWidget);
    });
  });

  group('ReportProblemScreen', () {
    testWidgets('renders hero, categories, description and drop zone',
        (WidgetTester tester) async {
      await _pump(tester, const ReportProblemScreen());

      expect(find.text('Report a Problem'), findsOneWidget);
      expect(
          find.text(
              'Send us the details and we will look into it.'),
          findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Pick the closest match'), findsOneWidget);
      expect(find.text('Bug or error'), findsOneWidget);
      expect(find.text('Content problem'), findsOneWidget);
      expect(find.text('Payment or access'), findsOneWidget);
      expect(find.text('Something else'), findsOneWidget);
      expect(find.text('Describe the problem'), findsOneWidget);
      expect(find.text('Attach Screenshot (optional)'), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);
    });

    testWidgets('submit enables after category + description are set',
        (WidgetTester tester) async {
      await _pump(tester, const ReportProblemScreen());

      final submitBtn =
          find.widgetWithText(ElevatedButton, 'Submit');
      expect(tester.widget<ElevatedButton>(submitBtn).onPressed, isNull);

      await tester.tap(find.text('Bug or error'));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Describe the problem'),
          'The app crashes on open');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(submitBtn).onPressed,
          isNotNull);
    });

    testWidgets('picking Other reveals the custom-category field',
        (WidgetTester tester) async {
      await _pump(tester, const ReportProblemScreen());

      await tester.tap(find.text('Something else'));
      await _settle(tester);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Describe it below'), findsOneWidget);
    });

    testWidgets('renders Nepali copy when the app language is Nepali',
        (WidgetTester tester) async {
      AppLanguage.current.value = 'ne';
      await _pump(tester, const ReportProblemScreen());

      expect(find.text('समस्या रिपोर्ट गर्नुहोस्'), findsOneWidget);
      expect(find.text('श्रेणी'), findsOneWidget);
      expect(find.text('बग वा त्रुटि'), findsOneWidget);
      expect(find.text('समस्याको वर्णन गर्नुहोस्'), findsOneWidget);
      expect(find.text('पेश गर्नुहोस्'), findsOneWidget);
    });
  });

  group('PrivacyPolicyScreen', () {
    testWidgets('renders all five sections and the full-policy link',
        (WidgetTester tester) async {
      await _pump(tester, const PrivacyPolicyScreen());

      expect(find.text('Privacy Policy'), findsWidgets);
      expect(
          find.text(
              'Your privacy matters. Here is exactly what Loksewa Solution stores and why.'),
          findsOneWidget);
      expect(find.text('No data selling'), findsOneWidget);
      expect(find.text('You can delete it all'), findsOneWidget);
      for (final title in [
        'What we collect',
        'Study data',
        'How it is protected',
        'What we never do',
        'Your control',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Full policy'), findsOneWidget);
      expect(
          find.text('https://www.kbr.com.np/privacy'), findsOneWidget);
      expect(find.text('Read the full policy online'), findsOneWidget);
    });

    testWidgets('title localises to Nepali',
        (WidgetTester tester) async {
      AppLanguage.current.value = 'ne';
      await _pump(tester, const PrivacyPolicyScreen());
      expect(find.text('गोपनीयता नीति'), findsWidgets);
    });
  });

  group('TermsConditionsScreen', () {
    testWidgets('renders all eight clauses with § pills',
        (WidgetTester tester) async {
      await _pump(tester, const TermsConditionsScreen());

      expect(find.text('Terms & Conditions'), findsWidgets);
      expect(
          find.text(
              'Please read these terms before continuing to use Loksewa Solution.'),
          findsOneWidget);
      expect(find.text('8 clauses'), findsOneWidget);
      for (final title in [
        'Using this app',
        'Your account',
        'Study content',
        'No result guarantee',
        'Fair use',
        'Community discussions',
        'Changes',
        'Contact',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      for (var i = 1; i <= 8; i++) {
        expect(find.text('§$i'), findsOneWidget);
      }
      expect(find.text('View online version'), findsOneWidget);
    });

    testWidgets('title localises to Nepali',
        (WidgetTester tester) async {
      AppLanguage.current.value = 'ne';
      await _pump(tester, const TermsConditionsScreen());
      expect(find.text('नियम र सर्तहरू'), findsWidgets);
    });
  });

  group('FeedbackScreen', () {
    testWidgets('renders hero, stars, hint and the message card',
        (WidgetTester tester) async {
      await _pump(tester, const FeedbackScreen());

      expect(find.text('Feedback'), findsWidgets);
      expect(
          find.text(
              'Your feedback directly shapes what we build next. Thank you for taking a moment.'),
          findsOneWidget);
      expect(find.text('How would you rate the app?'), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsNWidgets(5));
      expect(find.text('Tap a star to rate'), findsOneWidget);
      expect(find.text('Tell us more (optional)'), findsOneWidget);
      expect(find.text('What did you like? What should we improve?'),
          findsOneWidget);

      // Submit is gated on a rating.
      final submitBtn =
          find.widgetWithText(ElevatedButton, 'Submit');
      expect(tester.widget<ElevatedButton>(submitBtn).onPressed, isNull);
    });

    testWidgets('tapping a star shows its label pill and enables submit',
        (WidgetTester tester) async {
      await _pump(tester, const FeedbackScreen());

      await tester.tap(find.byIcon(Icons.star_border).last);
      await tester.pump();
      expect(find.byIcon(Icons.star), findsNWidgets(5));
      expect(find.text('Excellent'), findsOneWidget);
      expect(find.text('Tap a star to rate'), findsNothing);

      final submitBtn =
          find.widgetWithText(ElevatedButton, 'Submit');
      expect(tester.widget<ElevatedButton>(submitBtn).onPressed,
          isNotNull);
    });

    testWidgets('renders Nepali copy when the app language is Nepali',
        (WidgetTester tester) async {
      AppLanguage.current.value = 'ne';
      await _pump(tester, const FeedbackScreen());

      expect(find.text('प्रतिक्रिया'), findsWidgets);
      expect(find.text('एपलाई कति नम्बर दिनुहुन्छ?'), findsOneWidget);
      expect(find.text('अझ बताउनुहोस् (वैकल्पिक)'), findsOneWidget);
      expect(
          find.text('तपाईंलाई के मन पर्यो? हामीले के सुधार्नुपर्छ?'),
          findsOneWidget);
      expect(find.text('पेश गर्नुहोस्'), findsOneWidget);
    });
  });

  group('premium preloading shimmer', () {
    // Pump one frame with no settle, so the ~1.5s shimmer is still up.
    Future<void> pumpBare(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();
    }

    // Small pumps only (never pumpAndSettle — the shimmer's animation is
    // infinite). 2.0s: shimmer ends at ~1.5s, revealed SyllabusEntrance
    // delays (up to 240ms) must also fire before the test ends.
    Future<void> pumpPastShimmer(WidgetTester tester) async {
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('ReportProblemScreen shows the shimmer first, then the form',
        (WidgetTester tester) async {
      await pumpBare(tester, const ReportProblemScreen());

      // Shimmer first: the header frame is up, the form not yet built.
      expect(find.byType(PreloadingWidget), findsOneWidget);
      expect(find.text('Report a Problem'), findsOneWidget);
      expect(find.text('Bug or error'), findsNothing);

      await pumpPastShimmer(tester);

      expect(find.byType(PreloadingWidget), findsNothing);
      expect(find.text('Bug or error'), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);
    });

    testWidgets('FeedbackScreen shows the shimmer first, then the content',
        (WidgetTester tester) async {
      await pumpBare(tester, const FeedbackScreen());

      expect(find.byType(PreloadingWidget), findsOneWidget);
      expect(find.text('Feedback'), findsWidgets);
      expect(find.text('How would you rate the app?'), findsNothing);

      await pumpPastShimmer(tester);

      expect(find.byType(PreloadingWidget), findsNothing);
      expect(find.text('How would you rate the app?'), findsOneWidget);
    });
  });
}
