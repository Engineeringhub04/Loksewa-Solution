import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:loksewa_solution/screens/auth/app_info_screen.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import 'package:loksewa_solution/widgets/preloading.dart';
import 'package:loksewa_solution/widgets/subpage_header.dart';
import 'package:loksewa_solution/widgets/syllabus_entrance.dart';

/// Delete Account — mirrors app/delete-account.tsx.
///
/// This page no longer deletes anything itself. It collects a deletion
/// REQUEST (reason + full message) and sends it to the team's Discord
/// webhook for manual review — the admin deletes the account by hand.
///
/// Flow (standing popup-action pattern): fill the form → Submit Request →
/// [AppModalShell] confirm popup → loading state on the popup's confirm
/// button → POST to Discord → success toast → back.
///
/// The Discord webhook URL is read at runtime from the Firestore document
/// `app_applink_details/main` (field `discordWebhookUrl`), so the URL can
/// change without an app update. When offline the form is hidden and only
/// a warning line + Cancel remain (same as React).
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    this.fetchWebhookUrl,
    this.postToDiscord,
  });

  /// Override in tests: resolves the Discord webhook URL.
  @visibleForTesting
  final Future<String?> Function()? fetchWebhookUrl;

  /// Override in tests: posts the payload to Discord.
  @visibleForTesting
  final Future<void> Function(String url, Map<String, dynamic> body)?
      postToDiscord;

  /// Builds the Discord webhook payload (embed with the request details).
  @visibleForTesting
  static Map<String, dynamic> buildDiscordPayload({
    required String uid,
    required String name,
    required String email,
    required String reason,
    required String message,
    required String requestedAt,
    required String appVersion,
  }) {
    // Discord embed field values cap at 1024 characters.
    String cell(String s) {
      final v = s.isEmpty ? '-' : s;
      return v.length > 1024 ? '${v.substring(0, 1021)}...' : v;
    }

    return {
      'embeds': [
        {
          'title': 'Account Deletion Request',
          'color': 15158332, // red
          'fields': [
            {'name': 'Name', 'value': cell(name), 'inline': true},
            {'name': 'User ID', 'value': cell(uid), 'inline': true},
            {'name': 'Email', 'value': cell(email)},
            {'name': 'Reason', 'value': cell(reason)},
            {'name': 'Message', 'value': cell(message)},
            {'name': 'Requested At', 'value': cell(requestedAt)},
            {'name': 'App version', 'value': cell(appVersion), 'inline': true},
          ],
        },
      ],
    };
  }

  /// 'yyyy-MM-dd HH:mm NPT' stamp for the Discord request.
  @visibleForTesting
  static String nptTimestamp([DateTime? now]) {
    final npt = (now ?? DateTime.now())
        .toUtc()
        .add(const Duration(hours: 5, minutes: 45));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${npt.year}-${two(npt.month)}-${two(npt.day)} '
        '${two(npt.hour)}:${two(npt.minute)} NPT';
  }

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _reasonText = TextEditingController();
  final _messageText = TextEditingController();
  bool? _offline;
  bool _preloading = true;

  @override
  void initState() {
    super.initState();
    _checkOnline();
    // 1s premium preloading shimmer: this page has no database fetch, so the
    // content would pop in instantly without it.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _preloading = false);
    });
  }

  Future<void> _checkOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      setState(
          () => _offline = results.every((r) => r == ConnectivityResult.none));
    } catch (_) {
      if (mounted) setState(() => _offline = false);
    }
  }

  @override
  void dispose() {
    _reasonText.dispose();
    _messageText.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _reasonText.text.trim().isNotEmpty &&
      _messageText.text.trim().isNotEmpty;

  /// Reads the Discord webhook URL from `app_applink_details/main`.
  Future<String?> _defaultFetchWebhookUrl() async {
    try {
      String token = '';
      try {
        token = await AuthService.getValidIdToken();
      } catch (_) {}
      final doc = await FirestoreRest.getDocument('app_applink_details/main',
          idToken: token);
      final v = doc?['discordWebhookUrl'];
      return (v is String && v.isNotEmpty) ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// POSTs the embed payload to the Discord webhook.
  Future<void> _defaultPostToDiscord(
      String url, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('discord webhook: ${res.statusCode}');
    }
  }

  /// Sends the request. Returns true on success.
  Future<bool> _submitRequest() async {
    final fetch = widget.fetchWebhookUrl ?? _defaultFetchWebhookUrl;
    final url = await fetch();
    if (!mounted) return false;
    if (url == null || url.isEmpty) {
      showToast(
        context,
        AppLanguage.tr('Request service is unavailable right now.',
            'अनुरोध सेवा अहिले उपलब्ध छैन।'),
        ToastVariant.error,
      );
      return false;
    }
    try {
      final user = AuthService.currentUser;
      final profile = ProfileStore.instance.profile;
      final profileName = profile?.name.trim() ?? '';
      final body = DeleteAccountScreen.buildDiscordPayload(
        uid: user?.uid ?? '',
        name: profileName.isNotEmpty
            ? profileName
            : (user?.displayName ?? ''),
        email: user?.email ?? '',
        reason: _reasonText.text.trim(),
        message: _messageText.text.trim(),
        requestedAt: DeleteAccountScreen.nptTimestamp(),
        appVersion: AppInfoScreen.appVersion,
      );
      final post = widget.postToDiscord ?? _defaultPostToDiscord;
      await post(url, body);
      return true;
    } catch (_) {
      if (!mounted) return false;
      showToast(
        context,
        AppLanguage.tr('Could not submit your request. Please try again.',
            'अनुरोध पठाउन सकिएन। पुनः प्रयास गर्नुहोस्।'),
        ToastVariant.error,
      );
      return false;
    }
  }

  Future<void> _askConfirm() async {
    // Theme-aware danger red (React colors.error: #DC2626 light / #F87171 dark).
    final danger = ExpoPalette.of(context).danger;
    final ok = await AppModalShell.show<bool>(
      context: context,
      builder: (_) {
        var sending = false;
        return StatefulBuilder(
          builder: (modalContext, setModalState) => AppModalShell(
            accent: danger,
            accentMid: const Color(0xFFEF4444),
            accentLight: const Color(0xFFFECACA),
            tagColor: danger,
            tagLabel: AppLanguage.tr('REQUEST', 'अनुरोध'),
            onClose: sending ? null : () => Navigator.of(modalContext).pop(),
            icon: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: danger,
              ),
              child: const Icon(Icons.send_rounded,
                  size: 28, color: Colors.white),
            ),
            title: Text(
              AppLanguage.tr(
                  'Submit deletion request?', 'मेटाउने अनुरोध पठाउने?'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
                height: 1.3,
                decoration: TextDecoration.none,
              ),
            ),
            body: Text(
              AppLanguage.tr(
                'Our team will review your request and contact you. Your account stays active until then.',
                'हाम्रो टोलीले तपाईंको अनुरोध समीक्षा गर्नेछ र सम्पर्क गर्नेछ। त्यतिन्जेल तपाईंको खाता सक्रिय रहन्छ।',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF64748B),
                decoration: TextDecoration.none,
              ),
            ),
            footer: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: sending
                        ? null
                        : () => Navigator.of(modalContext).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: sending
                        ? null
                        : () async {
                            setModalState(() => sending = true);
                            final sent = await _submitRequest();
                            if (!modalContext.mounted) return;
                            Navigator.of(modalContext).pop(sent);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: danger,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: danger,
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(AppLanguage.tr(
                            'Submit Request', 'अनुरोध पठाउनुहोस्')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok == true && mounted) {
      showToast(
        context,
        AppLanguage.tr(
            'Your request has been submitted', 'तपाईंको अनुरोध पठाइयो'),
        ToastVariant.success,
      );
      if (context.canPop()) context.pop();
    }
  }

  /// 1s preloading shimmer shown on first build before the page content.
  Widget _preloadingBody() {
    return Center(
      child: PreloadingWidget(
        // Theme-coloured page: theme-grey spokes, not white.
        tinted: false,
        label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    required Color danger,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: danger),
      alignLabelWithHint: true,
      filled: true,
      fillColor: danger.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: danger, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final offline = _offline == true;
    // Theme-aware palette (React useTheme colors): danger red, secondary
    // text and surfaceAlt all flip correctly between light and dark.
    final palette = ExpoPalette.of(context);
    final danger = palette.danger;
    final primary = palette.primary;
    final enabled = _canSubmit;
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Delete Account', 'खाता मेट्नुहोस्')),
          Expanded(
            child: _preloading
                ? _preloadingBody()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      SyllabusEntrance(
                        delayMs: 0,
                        child: _dangerHero(danger),
                      ),
                      const SizedBox(height: 16),
                      SyllabusEntrance(
                        delayMs: 60,
                        child: _lossesCard(context, palette, danger),
                      ),
                      if (user?.email != null) ...[
                        const SizedBox(height: 16),
                        SyllabusEntrance(
                          delayMs: 120,
                          child: _accountCard(context, palette, user!.email!),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (offline)
                        SyllabusEntrance(
                          delayMs: 180,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              AppLanguage.tr('No internet connection',
                                  'इन्टरनेट जडान छैन'),
                              style: TextStyle(
                                  color: palette.warning, fontSize: 13),
                            ),
                          ),
                        )
                      else ...[
                        SyllabusEntrance(
                          delayMs: 180,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLanguage.tr(
                                    'Request details', 'अनुरोध विवरण'),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: palette.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLanguage.tr(
                                  'Tell us why you want to delete your account. Our team reviews every request.',
                                  'तपाईं खाता किन मेट्न चाहनुहुन्छ बताउनुहोस्। हाम्रो टोलीले हरेक अनुरोध समीक्षा गर्छ।',
                                ),
                                style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 13,
                                    height: 1.5),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _reasonText,
                                textInputAction: TextInputAction.next,
                                decoration: _fieldDecoration(
                                  label: AppLanguage.tr(
                                      'Reason (required)', 'कारण (आवश्यक)'),
                                  icon: Icons.subject_rounded,
                                  danger: danger,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _messageText,
                                minLines: 4,
                                maxLines: 6,
                                textInputAction: TextInputAction.newline,
                                decoration: _fieldDecoration(
                                  label: AppLanguage.tr('Full Message (required)',
                                      'पूर्ण सन्देश (आवश्यक)'),
                                  icon: Icons.message_outlined,
                                  danger: danger,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SyllabusEntrance(
                          delayMs: 240,
                          child: Opacity(
                            opacity: enabled ? 1.0 : 0.5,
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: enabled ? _askConfirm : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: primary,
                                  disabledForegroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  textStyle: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600),
                                ),
                                child: Text(AppLanguage.tr('Submit Request',
                                    'अनुरोध पठाउनुहोस्')),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => context.pop(),
                        child: Text(
                          AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्'),
                          // React's text-variant Button uses colors.primary —
                          // theme-aware, readable on both themes.
                          style: TextStyle(color: palette.primary),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Danger-gradient hero with decorative rings and the irreversible-action
  /// warning.
  Widget _dangerHero(Color danger) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFDC2626),
            Color(0xFFB91C1C),
            Color(0xFF991B1B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -36,
              top: -36,
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              right: 58,
              bottom: -48,
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    child: const Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLanguage.tr('This cannot be undone',
                              'यो फिर्ता गर्न मिल्दैन'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppLanguage.tr(
                            'Deleting your account permanently removes your profile and study data.',
                            'खाता मेट्दा तपाईंको प्रोफाइल र अध्ययन डाटा सधैंको लागि हट्नेछ।',
                          ),
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 14,
                              height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Theme-aware surface card used for the losses list and the account box.
  Widget _surfaceCard(BuildContext context, {required Widget child}) {
    final palette = ExpoPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        border: Border.all(color: palette.border),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: child,
    );
  }

  /// "What you will lose" — the same four losses as React, as divided rows.
  Widget _lossesCard(BuildContext context, ExpoPalette palette, Color danger) {
    return _surfaceCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLanguage.tr('What you will lose', 'तपाईंले गुमाउने कुराहरू'),
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _losses.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: palette.divider, indent: 28),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Icon(_losses[i].$1, size: 19, color: danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppLanguage.tr(_losses[i].$2, _losses[i].$3),
                      style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 14,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The signed-in account the request is about.
  Widget _accountCard(BuildContext context, ExpoPalette palette, String email) {
    return _surfaceCard(
      context,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: palette.primary.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.account_circle_outlined,
                size: 22, color: palette.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLanguage.tr(
                      'Account this request is about', 'अनुरोध गरिएको खाता'),
                  style:
                      TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// (icon, English loss line, Nepali loss line) — same four losses as React.
const _losses = [
  (
    Icons.account_circle_outlined,
    'Your profile, name, photo and course selection',
    'तपाईंको प्रोफाइल, नाम, फोटो र कोर्स छनोट',
  ),
  (
    Icons.bar_chart_outlined,
    'All quiz and mock test results and analytics',
    'सबै क्विज र मक टेस्टका नतिजा र विश्लेषण',
  ),
  (
    Icons.bookmark_outline,
    'Saved bookmarks, notes and downloads',
    'सेभ गरिएका बुकमार्क, नोट र डाउनलोड',
  ),
  (
    Icons.forum_outlined,
    'Access to your discussion posts and comments',
    'तपाईंका छलफल पोस्ट र कमेन्टमा पहुँच',
  ),
];
