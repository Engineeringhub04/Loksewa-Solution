import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/device_session_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/screens/learn/home_tab.dart';
import 'package:loksewa_solution/screens/learn/exam_tab.dart';
import 'package:loksewa_solution/screens/learn/discussion_tab.dart';
import 'package:loksewa_solution/screens/learn/profile_tab.dart';
import 'package:loksewa_solution/widgets/animated_bottom_nav.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/device_session_dialogs.dart';
import 'package:loksewa_solution/widgets/popup_action_button.dart';

/// Main tab shell — mirrors app/(tabs): Home, Exam, Discussion, Profile.
class TabsScreen extends StatefulWidget {
  const TabsScreen({super.key});

  /// Global tab switch — lets screens outside the tab bar jump to a tab.
  /// Used by the Profile tab's admin "Answer Review" row, which on the Expo
  /// side is `router.push('/(tabs)/exam')` (the exam is tab index 1).
  static final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);

  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> with WidgetsBindingObserver {
  int get _index => TabsScreen.tabIndex.value;
  bool _evictionShowing = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    TabsScreen.tabIndex.addListener(_onTabIndexChanged);
    WidgetsBinding.instance.addObserver(this);
    // Push-triggered recheck (eviction push from the new device).
    DeviceSessionService.onRecheck(_onPushRecheck);
  }

  @override
  void dispose() {
    TabsScreen.tabIndex.removeListener(_onTabIndexChanged);
    WidgetsBinding.instance.removeObserver(this);
    DeviceSessionService.offRecheck(_onPushRecheck);
    super.dispose();
  }

  void _onTabIndexChanged() {
    setState(() {});
    // Route change inside tabs → verify (throttled).
    _verifySession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Foreground return → verify with the shorter throttle.
      _verifySession(
          throttleMs: DeviceSessionService.foregroundVerifyThrottleMs);
    }
  }

  void _onPushRecheck() {
    // Unthrottled: a push naming this very event is evidence the answer
    // changed — a skipped check would waste the only signal we get.
    _verifySession(throttleMs: 0);
  }

  Future<void> _verifySession({int? throttleMs}) async {
    if (_checking || _evictionShowing || !mounted) return;
    final uid = AuthService.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    _checking = true;
    try {
      final result = await DeviceSessionService.verifyDeviceSession(
        uid,
        throttleMs: throttleMs,
      );
      if (!mounted || result.verdict != SessionVerdict.evicted) return;
      _evictionShowing = true;
      // The blocking dialog IS the explanation — it replaces any parked
      // "you were signed out" notice, never duplicates it. Clear first so
      // the notice can never surface on the next login after this path.
      await DeviceSessionService.clearEvictionNotice().catchError((_) {});
      if (!mounted) {
        _evictionShowing = false;
        return;
      }
      await showBlockingEvictionDialog(
        context,
        deviceName: result.deviceName,
        // The button shows its loading spinner until the sign-out finishes
        // (standing popup rule); the dialog dismisses itself afterwards.
        onConfirm: () => AuthService.logout().catchError((_) {}),
      );
      if (!mounted) return;
      context.go('/login');
    } finally {
      _checking = false;
      _evictionShowing = false;
    }
  }

  /// App close confirmation popup (shared AppModalShell design).
  Future<bool?> _confirmExit(BuildContext context) {
    return AppModalShell.show<bool>(
      context: context,
      builder: (dialogContext) => AppModalShell(
        accent: AppColors.navy,
        accentMid: const Color(0xFF1E3A8A),
        accentLight: const Color(0xFFBFDBFE),
        tagColor: AppColors.navy,
        tagLabel: AppLanguage.tr('EXIT', 'बाहिरिनुहोस्'),
        onClose: () => Navigator.of(dialogContext).pop(false),
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: AppColors.navy,
          ),
          child: const Icon(Icons.exit_to_app_rounded,
              size: 28, color: Colors.white),
        ),
        title: Text(
          AppLanguage.tr('Close the app?', 'एप बन्द गर्ने?'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            decoration: TextDecoration.none,
          ),
        ),
        body: Text(
          AppLanguage.tr(
              'Are you sure you want to close Loksewa Solution?',
              'के तपाई पक्का Loksewa Solution बन्द गर्न चाहनुहुन्छ?'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF475569),
              decoration: TextDecoration.none),
        ),
        footer: Row(
          children: [
            Expanded(
              child: PopupCancelButton(
                label: AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्'),
                onTap: () => Navigator.of(dialogContext).pop(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PopupActionButton(
                label: AppLanguage.tr('Exit', 'बाहिरिनुहोस्'),
                backgroundColor: AppColors.navy,
                onTap: () => Navigator.of(dialogContext).pop(true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _tabs = <Widget>[
    HomeTab(),
    ExamTab(),
    DiscussionTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    // Transparent status bar with light icons on the tab shell — every tab
    // header is a dark full-bleed gradient, so it flows under the clock
    // (React's translucent StatusBar), with no white band on top.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      // App close confirmation: back on the main tabs asks before exiting.
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final exit = await _confirmExit(context);
          if (exit == true && context.mounted) {
            SystemNavigator.pop();
          }
        },
        child: Scaffold(
          // Body renders behind the bottom nav so the nav's transparent
          // notch shows the page content through.
          extendBody: true,
          body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: AnimatedBottomNav(
        currentIndex: _index,
        onTap: (i) => TabsScreen.tabIndex.value = i,
      ),
      ),
      ),
    );
  }
}
