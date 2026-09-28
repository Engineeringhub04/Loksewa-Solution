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

/// Slide-in page transition shared by every route: the new page slides in
/// from the right (300ms, ease-out) on push/go, and slides back on pop.
CustomTransitionPage<void> _slidePage(ValueKey<String> key, Widget child) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOut));
      return SlideTransition(
        position: animation.drive(tween),
        child: child,
      );
    },
  );
}

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', pageBuilder: (_, state) => _slidePage(state.pageKey, const SplashScreen())),
    GoRoute(path: '/', pageBuilder: (_, state) => _slidePage(state.pageKey, const TabsScreen())),
    GoRoute(
        path: '/onboarding', pageBuilder: (_, state) => _slidePage(state.pageKey, const OnboardingScreen())),

    // ---- Auth ----
    GoRoute(path: '/login', pageBuilder: (_, state) => _slidePage(state.pageKey, const LoginScreen())),
    GoRoute(path: '/signup', pageBuilder: (_, state) => _slidePage(state.pageKey, const SignupScreen())),
    GoRoute(
        path: '/forgot-password', pageBuilder: (_, state) => _slidePage(state.pageKey, const ForgotPasswordScreen())),
    GoRoute(
        path: '/reset-password', pageBuilder: (_, state) => _slidePage(state.pageKey, const ResetPasswordScreen())),
    GoRoute(
        path: '/blocking/maintenance', pageBuilder: (_, state) => _slidePage(state.pageKey, const MaintenanceScreen())),
    GoRoute(
        path: '/blocking/no-internet', pageBuilder: (_, state) => _slidePage(state.pageKey, const NoInternetScreen())),

    // ---- Static / info ----
    GoRoute(path: '/about', pageBuilder: (_, state) => _slidePage(state.pageKey, const AboutScreen())),
    GoRoute(path: '/app-info', pageBuilder: (_, state) => _slidePage(state.pageKey, const AppInfoScreen())),
    GoRoute(
        path: '/contact-us', pageBuilder: (_, state) => _slidePage(state.pageKey, const ContactUsScreen())),
    GoRoute(
        path: '/privacy-policy', pageBuilder: (_, state) => _slidePage(state.pageKey, const PrivacyPolicyScreen())),
    GoRoute(
        path: '/terms-conditions', pageBuilder: (_, state) => _slidePage(state.pageKey, const TermsConditionsScreen())),
    GoRoute(
        path: '/terms-of-service',
        redirect: (_, __) => '/terms-conditions'),
    GoRoute(
        path: '/delete-account', pageBuilder: (_, state) => _slidePage(state.pageKey, const DeleteAccountScreen())),
    GoRoute(path: '/feedback', pageBuilder: (_, state) => _slidePage(state.pageKey, const FeedbackScreen())),
    GoRoute(
        path: '/settings/help-center', pageBuilder: (_, state) => _slidePage(state.pageKey, const HelpCenterScreen())),
    GoRoute(
        path: '/help-center', pageBuilder: (_, state) => _slidePage(state.pageKey, const HelpCenterScreen())),
    GoRoute(path: '/help', pageBuilder: (_, state) => _slidePage(state.pageKey, const HelpCenterScreen())),
    GoRoute(
        path: '/settings/report-problem', pageBuilder: (_, state) => _slidePage(state.pageKey, const ReportProblemScreen())),
    GoRoute(
        path: '/under-construction', pageBuilder: (_, state) => _slidePage(state.pageKey, const UnderConstructionScreen())),
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
    GoRoute(path: '/profile', pageBuilder: (_, state) => _slidePage(state.pageKey, const Scaffold(body: ProfileTab()))),
    GoRoute(path: '/subjects', pageBuilder: (_, state) => _slidePage(state.pageKey, const SubjectsScreen())),
    GoRoute(
      path: '/subjects/chapters/:subjectId', pageBuilder: (_, s) => _slidePage(s.pageKey, SubjectChaptersScreen(subjectId: s.pathParameters['subjectId']!)),
    ),
    GoRoute(
      path: '/subjects/units/:subjectId', pageBuilder: (_, s) => _slidePage(s.pageKey, SubjectUnitsScreen(subjectId: s.pathParameters['subjectId']!)),
    ),
    GoRoute(
      path: '/subjects/practice', pageBuilder: (_, s) => _slidePage(s.pageKey, SubjectPracticeScreen(
        courseId: _qp(s, 'courseId') ?? '',
        subcourseId: _qp(s, 'subcourseId') ?? '',
        subjectId: _qp(s, 'subjectId') ?? '',
        chapterId: _qp(s, 'chapterId') ?? '',
        unitId: _qp(s, 'unitId'),
        subjectName: _qp(s, 'subjectName'),
        chapterName: _qp(s, 'chapterName'),
        unitName: _qp(s, 'unitName'),
      )),
    ),
    GoRoute(
      path: '/subjects/read', pageBuilder: (_, s) => _slidePage(s.pageKey, SubjectReadScreen(
        courseId: _qp(s, 'courseId') ?? '',
        subcourseId: _qp(s, 'subcourseId') ?? '',
        subjectId: _qp(s, 'subjectId') ?? '',
        chapterId: _qp(s, 'chapterId') ?? '',
        unitId: _qp(s, 'unitId'),
        subjectName: _qp(s, 'subjectName'),
        chapterName: _qp(s, 'chapterName'),
        unitName: _qp(s, 'unitName'),
      )),
    ),
    GoRoute(
      path: '/subjects/theory', pageBuilder: (_, s) => _slidePage(s.pageKey, SubjectTheoryScreen(
        courseId: _qp(s, 'courseId') ?? '',
        subcourseId: _qp(s, 'subcourseId') ?? '',
        subjectId: _qp(s, 'subjectId') ?? '',
        chapterId: _qp(s, 'chapterId') ?? '',
        unitId: _qp(s, 'unitId'),
        subjectName: _qp(s, 'subjectName'),
        chapterName: _qp(s, 'chapterName'),
        unitName: _qp(s, 'unitName'),
      )),
    ),
    GoRoute(path: '/syllabus', pageBuilder: (_, state) => _slidePage(state.pageKey, const SyllabusScreen())),
    GoRoute(
        path: '/course-details', pageBuilder: (_, state) => _slidePage(state.pageKey, const CourseDetailsScreen())),
    GoRoute(
      path: '/course-setup', pageBuilder: (_, s) => _slidePage(s.pageKey, CourseSetupScreen(mode: _qp(s, 'mode'))),
    ),
    GoRoute(path: '/notes', pageBuilder: (_, state) => _slidePage(state.pageKey, const NotesScreen())),
    GoRoute(
        path: '/notes/new', pageBuilder: (_, state) => _slidePage(state.pageKey, const NoteDetailScreen(id: 'new'))),
    GoRoute(
      path: '/notes/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, NoteDetailScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/pdf/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, PdfScreen(
        id: s.pathParameters['id']!,
        uri: _qp(s, 'uri'),
        title: _qp(s, 'title'),
      )),
    ),

    // ---- Exam engine ----
    GoRoute(
      path: '/exam/:setId', pageBuilder: (_, s) => _slidePage(s.pageKey, ExamDetailScreen(setId: s.pathParameters['setId']!)),
    ),
    GoRoute(
      path: '/exam/:setId/quiz', pageBuilder: (_, s) => _slidePage(s.pageKey, ExamQuizScreen(setId: s.pathParameters['setId']!)),
    ),
    GoRoute(
      path: '/exam/:setId/ranking', pageBuilder: (_, s) => _slidePage(s.pageKey, ExamRankingScreen(setId: s.pathParameters['setId']!)),
    ),
    GoRoute(
      path: '/exam/:setId/review', pageBuilder: (_, s) => _slidePage(s.pageKey, ExamReviewScreen(setId: s.pathParameters['setId']!)),
    ),
    GoRoute(
      path: '/exam/:setId/summary', pageBuilder: (_, s) => _slidePage(s.pageKey, ExamSummaryScreen(setId: s.pathParameters['setId']!)),
    ),
    GoRoute(
      path: '/mock-test/:id/instructions', pageBuilder: (_, s) => _slidePage(s.pageKey, MockInstructionsScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/mock-test/:id/attempt', pageBuilder: (_, s) => _slidePage(s.pageKey, MockAttemptScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(path: '/daily-test', pageBuilder: (_, state) => _slidePage(state.pageKey, const DailyTestScreen())),
    GoRoute(
        path: '/daily-test/models', pageBuilder: (_, state) => _slidePage(state.pageKey, const DailyTestModelsScreen())),
    GoRoute(
        path: '/daily-test/history', pageBuilder: (_, state) => _slidePage(state.pageKey, const DailyTestHistoryScreen())),
    GoRoute(
      path: '/daily-test/:modelId/quiz', pageBuilder: (_, s) => _slidePage(s.pageKey, DailyQuizScreen(modelId: s.pathParameters['modelId']!)),
    ),
    GoRoute(
      path: '/daily-test/:modelId/review', pageBuilder: (_, s) => _slidePage(s.pageKey, DailyReviewScreen(modelId: s.pathParameters['modelId']!)),
    ),
    GoRoute(
      path: '/daily-test/:modelId/summary', pageBuilder: (_, s) => _slidePage(s.pageKey, DailySummaryScreen(modelId: s.pathParameters['modelId']!)),
    ),
    GoRoute(
      path: '/live-exam/:id/waiting', pageBuilder: (_, s) => _slidePage(s.pageKey, LiveExamWaitingScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/quiz/:subjectId', pageBuilder: (_, s) => _slidePage(s.pageKey, SubjectQuizScreen(subjectId: s.pathParameters['subjectId']!)),
    ),
    GoRoute(
        path: '/question-of-the-day', pageBuilder: (_, state) => _slidePage(state.pageKey, const QuestionOfDayScreen())),
    GoRoute(
        path: '/exam-history', pageBuilder: (_, state) => _slidePage(state.pageKey, const ExamHistoryScreen())),
    GoRoute(path: '/exam-results', redirect: (_, __) => '/exam-history'),
    GoRoute(
      path: '/result/:attemptId', pageBuilder: (_, s) => _slidePage(s.pageKey, ResultScreen(attemptId: s.pathParameters['attemptId']!)),
    ),
    GoRoute(path: '/leaderboard', pageBuilder: (_, state) => _slidePage(state.pageKey, const LeaderboardScreen())),

    // ---- Shop ----
    GoRoute(
      path: '/exam-purchase/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, ExamPurchaseScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
        path: '/subscription', pageBuilder: (_, state) => _slidePage(state.pageKey, const SubscriptionScreen())),
    GoRoute(path: '/premium', redirect: (_, __) => '/subscription'),
    GoRoute(
      path: '/subscription/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, SubscriptionDetailScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(path: '/checkout', pageBuilder: (_, state) => _slidePage(state.pageKey, const CheckoutScreen())),
    GoRoute(
      path: '/subscription/exam-purchase/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, SubscriptionExamPurchaseScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
        path: '/purchase-details', pageBuilder: (_, state) => _slidePage(state.pageKey, const PurchaseDetailsScreen())),
    GoRoute(
      path: '/purchase-details/content/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, ContentPurchaseDetailScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
        path: '/achievements', pageBuilder: (_, state) => _slidePage(state.pageKey, const AchievementsScreen())),
    // literal routes before the :id param route
    GoRoute(
        path: '/exam-answer/upload', pageBuilder: (_, state) => _slidePage(state.pageKey, const UploadAnswerScreen())),
    GoRoute(
        path: '/exam-answer/my-submissions', pageBuilder: (_, state) => _slidePage(state.pageKey, const MySubmissionsScreen())),
    GoRoute(
      path: '/exam-answer/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, ExamAnswerScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
        path: '/report-question', pageBuilder: (_, state) => _slidePage(state.pageKey, const ReportQuestionScreen())),
    GoRoute(
        path: '/report-history', pageBuilder: (_, state) => _slidePage(state.pageKey, const ReportHistoryScreen())),
    GoRoute(
      path: '/report-history/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, ReportDetailScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
        path: '/additional-features/gk', pageBuilder: (_, state) => _slidePage(state.pageKey, const AdditionalGkScreen())),
    GoRoute(
        path: '/additional-features/pm', pageBuilder: (_, state) => _slidePage(state.pageKey, const AdditionalPmScreen())),
    GoRoute(
      path: '/additional-features/:featureId/:topicId', pageBuilder: (_, s) => _slidePage(s.pageKey, AdditionalTopicScreen(
        featureId: s.pathParameters['featureId']!,
        topicId: s.pathParameters['topicId']!,
      )),
    ),

    // ---- User ----
    GoRoute(
        path: '/edit-profile', pageBuilder: (_, state) => _slidePage(state.pageKey, const EditProfileScreen())),
    GoRoute(path: '/bookmarks', pageBuilder: (_, state) => _slidePage(state.pageKey, const BookmarksScreen())),
    GoRoute(path: '/saved', redirect: (_, __) => '/bookmarks'),
    GoRoute(
      path: '/bookmarks/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, BookmarkDetailScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(path: '/downloads', pageBuilder: (_, state) => _slidePage(state.pageKey, const DownloadsScreen())),
    GoRoute(
        path: '/notifications', pageBuilder: (_, state) => _slidePage(state.pageKey, const NotificationsScreen())),
    GoRoute(
      path: '/notification/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, NotificationDetailScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(path: '/notices', pageBuilder: (_, state) => _slidePage(state.pageKey, const NoticesScreen())),
    GoRoute(path: '/notice-board', redirect: (_, __) => '/notices'),
    GoRoute(
      path: '/notice/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, NoticeDetailScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(path: '/gorkhapatra', pageBuilder: (_, state) => _slidePage(state.pageKey, const GorkhapatraScreen())),
    GoRoute(
      path: '/gorkhapatra/:slug', pageBuilder: (_, s) => _slidePage(s.pageKey, GorkhapatraDetailScreen(slug: s.pathParameters['slug']!)),
    ),
    GoRoute(
        path: '/constitution', pageBuilder: (_, state) => _slidePage(state.pageKey, const ConstitutionScreen())),
    GoRoute(
      path: '/constitution/:sectionId', pageBuilder: (_, s) => _slidePage(s.pageKey, ConstitutionSectionScreen(sectionId: s.pathParameters['sectionId']!)),
    ),
    GoRoute(path: '/search', pageBuilder: (_, state) => _slidePage(state.pageKey, const SearchScreen())),
    GoRoute(
        path: '/discussion/create', pageBuilder: (_, s) => _slidePage(s.pageKey, DiscussionCreateScreen(editId: _qp(s, 'editId')))),
    GoRoute(
      path: '/discussion/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, DiscussionDetailScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(path: '/analytics', pageBuilder: (_, state) => _slidePage(state.pageKey, const AnalyticsScreen())),

    // ---- Admin ----
    GoRoute(path: '/admin', pageBuilder: (_, state) => _slidePage(state.pageKey, const AdminHomeScreen())),
    GoRoute(
        path: '/admin/exam-purchases', pageBuilder: (_, state) => _slidePage(state.pageKey, const AdminExamPurchasesScreen())),
    GoRoute(
      path: '/admin/exam-purchases/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, AdminExamPurchaseDetailScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/admin/content-purchases/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, AdminContentPurchaseDetailScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/admin/exam-answer/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, AdminExamAnswerScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
        path: '/admin/purchase-details', pageBuilder: (_, state) => _slidePage(state.pageKey, const AdminPurchaseDetailsScreen())),
    GoRoute(
        path: '/admin/report-history', pageBuilder: (_, state) => _slidePage(state.pageKey, const AdminReportHistoryScreen())),
    GoRoute(
      path: '/admin/report-history/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, AdminReportDetailScreen(id: s.pathParameters['id']!)),
    ),
    GoRoute(
        path: '/admin/subscriptions', pageBuilder: (_, state) => _slidePage(state.pageKey, const AdminSubscriptionsScreen())),
    GoRoute(
      path: '/admin/subscriptions/:id', pageBuilder: (_, s) => _slidePage(s.pageKey, AdminSubscriptionDetailScreen(id: s.pathParameters['id']!)),
    ),
  ],
  errorBuilder: (_, s) => Scaffold(
    body: Center(
      child: Text('Page not found: ${s.uri.toString()}'),
    ),
  ),
);
