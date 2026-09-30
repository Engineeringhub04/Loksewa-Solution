import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/splash_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/tabs_screen.dart';
import '../screens/maintenance_screen.dart';
import '../screens/no_internet_screen.dart';
import '../screens/login_screen.dart';

// Auth / static
import '../screens/auth/signup_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/reset_password_screen.dart';
import '../screens/auth/about_screen.dart';
import '../screens/auth/app_info_screen.dart';
import '../screens/auth/contact_us_screen.dart';
import '../screens/auth/privacy_policy_screen.dart';
import '../screens/auth/terms_conditions_screen.dart';
import '../screens/auth/delete_account_screen.dart';
import '../screens/auth/feedback_screen.dart';
import '../screens/auth/help_center_screen.dart';
import '../screens/auth/report_problem_screen.dart';
import '../screens/auth/under_construction_screen.dart';

// Learn
import '../screens/learn/subjects_screen.dart';
import '../screens/learn/profile_tab.dart';
import '../screens/learn/subject_chapters_screen.dart';
import '../screens/learn/subject_units_screen.dart';
import '../screens/learn/practice_analytics_screen.dart';
import '../screens/learn/subject_practice_screen.dart';
import '../screens/learn/subject_read_screen.dart';
import '../screens/learn/subject_theory_screen.dart';
import '../screens/learn/syllabus_screen.dart';
import '../screens/learn/course_details_screen.dart';
import '../screens/learn/course_setup_screen.dart';
import '../screens/learn/notes_screen.dart';
import '../screens/learn/note_detail_screen.dart';
import '../screens/learn/pdf_screen.dart';

// Exam engine
import '../screens/exam/exam_detail_screen.dart';
import '../screens/exam/exam_quiz_screen.dart';
import '../screens/exam/exam_ranking_screen.dart';
import '../screens/exam/exam_review_screen.dart';
import '../screens/exam/exam_summary_screen.dart';
import '../screens/exam/mock_instructions_screen.dart';
import '../screens/exam/mock_attempt_screen.dart';
import '../screens/exam/daily_test_screen.dart';
import '../screens/exam/daily_test_models_screen.dart';
import '../screens/exam/daily_test_history_screen.dart';
import '../screens/exam/daily_quiz_screen.dart';
import '../screens/exam/daily_review_screen.dart';
import '../screens/exam/daily_summary_screen.dart';
import '../screens/exam/live_exam_waiting_screen.dart';
import '../screens/exam/subject_quiz_screen.dart';
import '../screens/exam/question_of_day_screen.dart';
import '../screens/exam/exam_history_screen.dart';
import '../screens/exam/result_screen.dart';
import '../screens/exam/leaderboard_screen.dart';

// Shop
import '../screens/shop/exam_purchase_screen.dart';
import '../screens/shop/subscription_screen.dart';
import '../screens/shop/subscription_detail_screen.dart';
import '../screens/shop/checkout_screen.dart';
import '../screens/shop/subscription_exam_purchase_screen.dart';
import '../screens/shop/purchase_details_screen.dart';
import '../screens/shop/content_purchase_detail_screen.dart';
import '../screens/shop/achievements_screen.dart';
import '../screens/shop/exam_answer_screen.dart';
import '../screens/shop/my_submissions_screen.dart';
import '../screens/shop/upload_answer_screen.dart';
import '../screens/shop/report_question_screen.dart';
import '../screens/shop/report_history_screen.dart';
import '../screens/shop/report_detail_screen.dart';
import '../screens/shop/additional_gk_screen.dart';
import '../screens/shop/additional_pm_screen.dart';
import '../screens/shop/additional_topic_screen.dart';

// User
import '../screens/user/edit_profile_screen.dart';
import '../screens/user/bookmarks_screen.dart';
import '../screens/user/bookmark_detail_screen.dart';
import '../screens/user/downloads_screen.dart';
import '../screens/user/notifications_screen.dart';
import '../screens/user/notification_detail_screen.dart';
import '../screens/user/notices_screen.dart';
import '../screens/user/notice_detail_screen.dart';
import '../screens/user/gorkhapatra_screen.dart';
import '../screens/user/gorkhapatra_detail_screen.dart';
import '../screens/user/constitution_screen.dart';
import '../screens/user/constitution_section_screen.dart';
import '../screens/user/search_screen.dart';
import '../screens/user/discussion_detail_screen.dart';
import '../screens/user/discussion_create_screen.dart';
import '../screens/user/analytics_screen.dart';

// Admin
import '../screens/admin/admin_home_screen.dart';
import '../screens/admin/admin_exam_purchases_screen.dart';
import '../screens/admin/admin_exam_purchase_detail_screen.dart';
import '../screens/admin/admin_content_purchase_detail_screen.dart';
import '../screens/admin/admin_exam_answer_screen.dart';
import '../screens/admin/admin_purchase_details_screen.dart';
import '../screens/admin/admin_report_history_screen.dart';
import '../screens/admin/admin_report_detail_screen.dart';
import '../screens/admin/admin_subscriptions_screen.dart';
import '../screens/admin/admin_subscription_detail_screen.dart';

String? _qp(GoRouterState s, String key) => s.uri.queryParameters[key];

/// Full route table — mirrors the Expo app/ directory 1:1.
final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/', builder: (_, __) => const TabsScreen()),
    GoRoute(
        path: '/onboarding', builder: (_, __) => const OnboardingScreen()),

    // ---- Auth ----
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
    GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen()),
    GoRoute(
        path: '/reset-password',
        builder: (_, __) => const ResetPasswordScreen()),
    GoRoute(
        path: '/blocking/maintenance',
        builder: (_, __) => const MaintenanceScreen()),
    GoRoute(
        path: '/blocking/no-internet',
        builder: (_, __) => const NoInternetScreen()),

    // ---- Static / info ----
    GoRoute(path: '/about', builder: (_, __) => const AboutScreen()),
    GoRoute(path: '/app-info', builder: (_, __) => const AppInfoScreen()),
    GoRoute(
        path: '/contact-us', builder: (_, __) => const ContactUsScreen()),
    GoRoute(
        path: '/privacy-policy',
        builder: (_, __) => const PrivacyPolicyScreen()),
    GoRoute(
        path: '/terms-conditions',
        builder: (_, __) => const TermsConditionsScreen()),
    GoRoute(
        path: '/terms-of-service',
        redirect: (_, __) => '/terms-conditions'),
    GoRoute(
        path: '/delete-account',
        builder: (_, __) => const DeleteAccountScreen()),
    GoRoute(path: '/feedback', builder: (_, __) => const FeedbackScreen()),
    GoRoute(
        path: '/settings/help-center',
        builder: (_, __) => const HelpCenterScreen()),
    GoRoute(
        path: '/help-center', builder: (_, __) => const HelpCenterScreen()),
    GoRoute(path: '/help', builder: (_, __) => const HelpCenterScreen()),
    GoRoute(
        path: '/settings/report-problem',
        builder: (_, __) => const ReportProblemScreen()),
    GoRoute(
        path: '/under-construction',
        builder: (_, __) => const UnderConstructionScreen()),
    // Home-tab shortcuts that point at the placeholder in the Expo app
    GoRoute(
        path: '/current-affairs',
        redirect: (_, __) =>
            '/under-construction?page=${Uri.encodeComponent('Current Affairs')}'),
    GoRoute(
        path: '/mock-tests',
        redirect: (_, __) =>
            '/under-construction?page=${Uri.encodeComponent('Mock Tests')}'),
    GoRoute(
        path: '/old-papers',
        redirect: (_, __) =>
            '/under-construction?page=${Uri.encodeComponent('Old Papers')}'),
    GoRoute(
        path: '/how-to-use',
        redirect: (_, __) =>
            '/under-construction?page=${Uri.encodeComponent('How to Use')}'),
    GoRoute(path: '/settings', redirect: (_, __) => '/'),

    // ---- Learn ----
    // Standalone profile page for the home header avatar tap (the Profile
    // tab shell is unchanged; this reuses the same tab content).
    GoRoute(path: '/profile', builder: (_, __) => const Scaffold(body: ProfileTab())),
    GoRoute(path: '/subjects', builder: (_, __) => const SubjectsScreen()),
    GoRoute(
      path: '/subjects/chapters/:subjectId',
      builder: (_, s) =>
          SubjectChaptersScreen(subjectId: s.pathParameters['subjectId']!),
    ),
    GoRoute(
      path: '/subjects/units/:subjectId',
      builder: (_, s) =>
          SubjectUnitsScreen(subjectId: s.pathParameters['subjectId']!),
    ),
    GoRoute(
      path: '/practice-analytics',
      builder: (_, s) {
        final extra =
            (s.extra as Map?)?.map((k, v) => MapEntry('$k', '$v'));
        return PracticeAnalyticsScreen(
          subjectSlug: extra?['subjectSlug'],
          subjectTitle: extra?['subjectTitle'],
          unitId: extra?['unitId'],
          unitTitle: extra?['unitTitle'],
          chapterSlug: extra?['chapterSlug'],
          chapterTitle: extra?['chapterTitle'],
        );
      },
    ),
    GoRoute(
      path: '/subjects/practice',
      builder: (_, s) => SubjectPracticeScreen(
        courseId: _qp(s, 'courseId') ?? '',
        subcourseId: _qp(s, 'subcourseId') ?? '',
        subjectId: _qp(s, 'subjectId') ?? '',
        chapterId: _qp(s, 'chapterId') ?? '',
        unitId: _qp(s, 'unitId'),
        subjectName: _qp(s, 'subjectName'),
        chapterName: _qp(s, 'chapterName'),
        unitName: _qp(s, 'unitName'),
      ),
    ),
    GoRoute(
      path: '/subjects/read',
      builder: (_, s) => SubjectReadScreen(
        courseId: _qp(s, 'courseId') ?? '',
        subcourseId: _qp(s, 'subcourseId') ?? '',
        subjectId: _qp(s, 'subjectId') ?? '',
        chapterId: _qp(s, 'chapterId') ?? '',
        unitId: _qp(s, 'unitId'),
        subjectName: _qp(s, 'subjectName'),
        chapterName: _qp(s, 'chapterName'),
        unitName: _qp(s, 'unitName'),
      ),
    ),
    GoRoute(
      path: '/subjects/theory',
      builder: (_, s) => SubjectTheoryScreen(
        courseId: _qp(s, 'courseId') ?? '',
        subcourseId: _qp(s, 'subcourseId') ?? '',
        subjectId: _qp(s, 'subjectId') ?? '',
        chapterId: _qp(s, 'chapterId') ?? '',
        unitId: _qp(s, 'unitId'),
        subjectName: _qp(s, 'subjectName'),
        chapterName: _qp(s, 'chapterName'),
        unitName: _qp(s, 'unitName'),
      ),
    ),
    GoRoute(path: '/syllabus', builder: (_, __) => const SyllabusScreen()),
    GoRoute(
        path: '/course-details',
        builder: (_, __) => const CourseDetailsScreen()),
    GoRoute(
      path: '/course-setup',
      builder: (_, s) => CourseSetupScreen(mode: _qp(s, 'mode') ?? 'initial'),
    ),
    GoRoute(path: '/notes', builder: (_, __) => const NotesScreen()),
    GoRoute(
        path: '/notes/new',
        builder: (_, __) => const NoteDetailScreen(id: 'new')),
    GoRoute(
      path: '/notes/:id',
      builder: (_, s) => NoteDetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/pdf/:id',
      builder: (_, s) => PdfScreen(
        id: s.pathParameters['id']!,
        uri: _qp(s, 'uri'),
        title: _qp(s, 'title'),
      ),
    ),

    // ---- Exam engine ----
    GoRoute(
      path: '/exam/:setId',
      builder: (_, s) => ExamDetailScreen(setId: s.pathParameters['setId']!),
    ),
    GoRoute(
      path: '/exam/:setId/quiz',
      builder: (_, s) => ExamQuizScreen(setId: s.pathParameters['setId']!),
    ),
    GoRoute(
      path: '/exam/:setId/ranking',
      builder: (_, s) => ExamRankingScreen(setId: s.pathParameters['setId']!),
    ),
    GoRoute(
      path: '/exam/:setId/review',
      builder: (_, s) => ExamReviewScreen(setId: s.pathParameters['setId']!),
    ),
    GoRoute(
      path: '/exam/:setId/summary',
      builder: (_, s) => ExamSummaryScreen(setId: s.pathParameters['setId']!),
    ),
    GoRoute(
      path: '/mock-test/:id/instructions',
      builder: (_, s) => MockInstructionsScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/mock-test/:id/attempt',
      builder: (_, s) => MockAttemptScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(path: '/daily-test', builder: (_, __) => const DailyTestScreen()),
    GoRoute(
        path: '/daily-test/models',
        builder: (_, __) => const DailyTestModelsScreen()),
    GoRoute(
        path: '/daily-test/history',
        builder: (_, __) => const DailyTestHistoryScreen()),
    GoRoute(
      path: '/daily-test/:modelId/quiz',
      builder: (_, s) => DailyQuizScreen(modelId: s.pathParameters['modelId']!),
    ),
    GoRoute(
      path: '/daily-test/:modelId/review',
      builder: (_, s) =>
          DailyReviewScreen(modelId: s.pathParameters['modelId']!),
    ),
    GoRoute(
      path: '/daily-test/:modelId/summary',
      builder: (_, s) =>
          DailySummaryScreen(modelId: s.pathParameters['modelId']!),
    ),
    GoRoute(
      path: '/live-exam/:id/waiting',
      builder: (_, s) => LiveExamWaitingScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/quiz/:subjectId',
      builder: (_, s) =>
          SubjectQuizScreen(subjectId: s.pathParameters['subjectId']!),
    ),
    GoRoute(
        path: '/question-of-the-day',
        builder: (_, __) => const QuestionOfDayScreen()),
    GoRoute(
        path: '/exam-history', builder: (_, __) => const ExamHistoryScreen()),
    GoRoute(path: '/exam-results', redirect: (_, __) => '/exam-history'),
    GoRoute(
      path: '/result/:attemptId',
      builder: (_, s) => ResultScreen(attemptId: s.pathParameters['attemptId']!),
    ),
    GoRoute(path: '/leaderboard', builder: (_, __) => const LeaderboardScreen()),

    // ---- Shop ----
    GoRoute(
      path: '/exam-purchase/:id',
      builder: (_, s) => ExamPurchaseScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
        path: '/subscription', builder: (_, __) => const SubscriptionScreen()),
    GoRoute(path: '/premium', redirect: (_, __) => '/subscription'),
    GoRoute(
      path: '/subscription/:id',
      builder: (_, s) => SubscriptionDetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
    GoRoute(
      path: '/subscription/exam-purchase/:id',
      builder: (_, s) =>
          SubscriptionExamPurchaseScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
        path: '/purchase-details',
        builder: (_, __) => const PurchaseDetailsScreen()),
    GoRoute(
      path: '/purchase-details/content/:id',
      builder: (_, s) =>
          ContentPurchaseDetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
        path: '/achievements', builder: (_, __) => const AchievementsScreen()),
    // literal routes before the :id param route
    GoRoute(
        path: '/exam-answer/upload',
        builder: (_, __) => const UploadAnswerScreen()),
    GoRoute(
        path: '/exam-answer/my-submissions',
        builder: (_, __) => const MySubmissionsScreen()),
    GoRoute(
      path: '/exam-answer/:id',
      builder: (_, s) => ExamAnswerScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
        path: '/report-question',
        builder: (_, __) => const ReportQuestionScreen()),
    GoRoute(
        path: '/report-history',
        builder: (_, __) => const ReportHistoryScreen()),
    GoRoute(
      path: '/report-history/:id',
      builder: (_, s) => ReportDetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
        path: '/additional-features/gk',
        builder: (_, __) => const AdditionalGkScreen()),
    GoRoute(
        path: '/additional-features/pm',
        builder: (_, __) => const AdditionalPmScreen()),
    GoRoute(
      path: '/additional-features/:featureId/:topicId',
      builder: (_, s) {
        final extraMap = s.extra is Map ? s.extra as Map : const {};
        return AdditionalTopicScreen(
          featureId: s.pathParameters['featureId']!,
          topicId: s.pathParameters['topicId']!,
          topicTitleEn: extraMap['topicTitleEn']?.toString(),
          topicTitleNp: extraMap['topicTitleNp']?.toString(),
        );
      },
    ),

    // ---- User ----
    GoRoute(
        path: '/edit-profile', builder: (_, __) => const EditProfileScreen()),
    GoRoute(path: '/bookmarks', builder: (_, __) => const BookmarksScreen()),
    GoRoute(path: '/saved', redirect: (_, __) => '/bookmarks'),
    GoRoute(
      path: '/bookmarks/:id',
      builder: (_, s) => BookmarkDetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(path: '/downloads', builder: (_, __) => const DownloadsScreen()),
    GoRoute(
        path: '/notifications', builder: (_, __) => const NotificationsScreen()),
    GoRoute(
      path: '/notification/:id',
      builder: (_, s) =>
          NotificationDetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(path: '/notices', builder: (_, __) => const NoticesScreen()),
    GoRoute(path: '/notice-board', redirect: (_, __) => '/notices'),
    GoRoute(
      path: '/notice/:id',
      builder: (_, s) => NoticeDetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(path: '/gorkhapatra', builder: (_, __) => const GorkhapatraScreen()),
    GoRoute(
      path: '/gorkhapatra/:slug',
      builder: (_, s) => GorkhapatraDetailScreen(slug: s.pathParameters['slug']!),
    ),
    GoRoute(
        path: '/constitution', builder: (_, __) => const ConstitutionScreen()),
    GoRoute(
      path: '/constitution/:sectionId',
      builder: (_, s) =>
          ConstitutionSectionScreen(sectionId: s.pathParameters['sectionId']!),
    ),
    GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
    GoRoute(
        path: '/discussion/create',
        builder: (_, s) => DiscussionCreateScreen(editId: _qp(s, 'editId'))),
    GoRoute(
      path: '/discussion/:id',
      builder: (_, s) => DiscussionDetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen()),

    // ---- Admin ----
    GoRoute(path: '/admin', builder: (_, __) => const AdminHomeScreen()),
    GoRoute(
        path: '/admin/exam-purchases',
        builder: (_, __) => const AdminExamPurchasesScreen()),
    GoRoute(
      path: '/admin/exam-purchases/:id',
      builder: (_, s) =>
          AdminExamPurchaseDetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/admin/content-purchases/:id',
      builder: (_, s) =>
          AdminContentPurchaseDetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/admin/exam-answer/:id',
      builder: (_, s) => AdminExamAnswerScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
        path: '/admin/purchase-details',
        builder: (_, __) => const AdminPurchaseDetailsScreen()),
    GoRoute(
        path: '/admin/report-history',
        builder: (_, __) => const AdminReportHistoryScreen()),
    GoRoute(
      path: '/admin/report-history/:id',
      builder: (_, s) => AdminReportDetailScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(
        path: '/admin/subscriptions',
        builder: (_, __) => const AdminSubscriptionsScreen()),
    GoRoute(
      path: '/admin/subscriptions/:id',
      builder: (_, s) =>
          AdminSubscriptionDetailScreen(id: s.pathParameters['id']!),
    ),
  ],
  errorBuilder: (_, s) => Scaffold(
    body: Center(
      child: Text('Page not found: ${s.uri.toString()}'),
    ),
  ),
);
