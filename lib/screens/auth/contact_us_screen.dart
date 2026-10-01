import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/preloading.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';
import '../../widgets/x_logo_icon.dart';

/// Contact Us — mirrors app/contact-us.tsx.
///
/// Gradient hero (with "Replies within 1 working day" pill), Reach us rows,
/// Follow us brand circles, and a message form. Tapping a channel row opens
/// a confirm popup (shared AppModalShell) that launches the channel through
/// the native "loksewa_solution/media" channel's openUrl branch
/// (ACTION_VIEW; no url_launcher): mailto: for Email, tel: for Call, https:
/// for Website. Tapping a social copies its URL to the clipboard. The message
/// posts to the team's Google Form via [ReportService.submitContactMessage]
/// — the same pipeline as React.
class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _message = TextEditingController();
  bool _sending = false;
  bool? _offline;
  bool _ready = false;

  static const _email = 'contact@kbr.com.np';
  static const _phone = '+977-9810768297';
  static const _websiteUrl = 'https://kbr.com.np';
  static const _websiteDisplay = 'kbr.com.np';

  /// The native "loksewa_solution/media" channel's openUrl branch
  /// (ACTION_VIEW). No url_launcher in this app on purpose.
  static const _mediaChannel = MethodChannel('loksewa_solution/media');

  /// Tones picked to stay clearly visible on BOTH themes — saturated
  /// mid-tones, never near-black (AppColors.navy is 0xFF03145C: dark-on-dark).
  /// The 'Reach us' section head shares the hero's saturated blue.
  static const _reachTone = Color(0xFF2563EB);
  static const _mailTone = Color(0xFF3B82F6);
  static const _callTone = Color(0xFF22C55E);
  static const _webTone = Color(0xFF0EA5E9);

  @override
  void initState() {
    super.initState();
    _checkOnline();
    // Premium reveal: the shimmer shows for ~1.2s before the content
    // builds, so the page never pops in half-painted.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _ready = true);
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
    _message.dispose();
    super.dispose();
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    showToast(
      context,
      AppLanguage.tr('Copied to clipboard', 'क्लिपबोर्डमा प्रतिलिपि भयो'),
      ToastVariant.success,
    );
  }

  Future<void> _send() async {
    if (_message.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ReportService.submitContactMessage(_message.text.trim());
      if (!mounted) return;
      _message.clear();
      setState(() {});
      showToast(
        context,
        AppLanguage.tr("Message sent, we'll get back to you soon",
            'सन्देश पठाइयो, हामी छिट्टै जवाफ दिनेछौं'),
        ToastVariant.success,
      );
    } catch (_) {
      if (!mounted) return;
      showToast(
        context,
        AppLanguage.tr('Something went wrong', 'केही समस्या भयो'),
        ToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline = _offline == true;
    // X's mark has no single usable colour: the dark mark is all but
    // invisible on a dark surface, so it flips with the theme (React parity).
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = ExpoPalette.of(context);
    final socials = [
      for (final s in _socials)
        s.$1 == 'x'
            ? (s.$1, s.$2, isDark ? const Color(0xFFE7E9EA) : s.$3, s.$4)
            : s,
    ];
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Contact Us', 'सम्पर्क गर्नुहोस्')),
          Expanded(
            child: _ready
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                SyllabusEntrance(
                  delayMs: 0,
                  child: _hero(),
                ),
                const SizedBox(height: 16),
                SyllabusEntrance(
                  delayMs: 60,
                  child: _surfaceCard(
                    context,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHead(
                          context,
                          icon: Icons.headset_mic_outlined,
                          tone: _reachTone,
                          title: AppLanguage.tr('Reach us', 'सम्पर्क'),
                        ),
                        const SizedBox(height: 8),
                        _channelRow(
                          context,
                          icon: Icons.mail_outline,
                          tone: _mailTone,
                          label:
                              AppLanguage.tr('Email us', 'इमेल गर्नुहोस्'),
                          value: _email,
                          openUrl: 'mailto:$_email',
                          confirmTitle: AppLanguage.tr(
                              'Send an email?', 'इमेल पठाउने?'),
                        ),
                        Divider(
                            height: 1, color: palette.divider, indent: 54),
                        _channelRow(
                          context,
                          icon: Icons.call_outlined,
                          tone: _callTone,
                          label: AppLanguage.tr('Call us', 'फोन गर्नुहोस्'),
                          value: _phone,
                          openUrl: 'tel:$_phone',
                          confirmTitle: AppLanguage.tr(
                              'Make a call?', 'फोन गर्ने?'),
                        ),
                        Divider(
                            height: 1, color: palette.divider, indent: 54),
                        _channelRow(
                          context,
                          icon: Icons.language_outlined,
                          tone: _webTone,
                          label: AppLanguage.tr('Website', 'वेबसाइट'),
                          value: _websiteDisplay,
                          openUrl: _websiteUrl,
                          confirmTitle: AppLanguage.tr(
                              'Open the website?', 'वेबसाइट खोल्ने?'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SyllabusEntrance(
                  delayMs: 120,
                  child: _surfaceCard(
                    context,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHead(
                          context,
                          icon: Icons.share_outlined,
                          tone: const Color(0xFF8B5CF6),
                          title: AppLanguage.tr(
                              'Follow us', 'हामीलाई फलो गर्नुहोस्'),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (final s in socials)
                              Expanded(
                                child: _socialItem(
                                  icon: _brandIcon(s.$1, s.$3),
                                  label: s.$2,
                                  color: s.$3,
                                  url: s.$4,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (offline)
                  SyllabusEntrance(
                    delayMs: 180,
                    child: _offlineCard(context),
                  )
                else
                  SyllabusEntrance(
                    delayMs: 180,
                    child: _surfaceCard(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHead(
                            context,
                            icon: Icons.send_outlined,
                            tone: const Color(0xFF0EA5E9),
                            title: AppLanguage.tr(
                                'Send Message', 'सन्देश पठाउनुहोस्'),
                            subtitle: AppLanguage.tr(
                                'Reach out to our support team',
                                'हाम्रो सहायता टोलीलाई सम्पर्क गर्नुहोस्'),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _message,
                            maxLines: 5,
                            minLines: 4,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: InputDecoration(
                              hintText: AppLanguage.tr(
                                  'Write your message…',
                                  'आफ्नो सन्देश लेख्नुहोस्…'),
                              filled: true,
                              fillColor: palette.surfaceAlt,
                              contentPadding: const EdgeInsets.all(14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: (_message.text.trim().isEmpty ||
                                      _sending)
                                  ? null
                                  : _send,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.navy,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                              child: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : Text(AppLanguage.tr(
                                      'Send Message', 'सन्देश पठाउनुहोस्')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                    ],
                  )
                : PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading contact details…',
                        'सम्पर्क विवरण लोड हुँदैछ…'),
                  ),
          ),
        ],
      ),
    );
  }

  /// Gradient hero with decorative rings, glass icon tile, subtitle and the
  /// reply-time pill.
  Widget _hero() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1D4ED8),
            Color(0xFF2563EB),
            Color(0xFF3B82F6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.28),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        child: const Icon(Icons.chat_bubble_outline,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          AppLanguage.tr('Contact Us', 'सम्पर्क गर्नुहोस्'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLanguage.tr(
                      'We usually reply within one working day. Pick whichever channel suits you.',
                      'हामी सामान्यतया एक कार्यदिनभित्र जवाफ दिन्छौं। तपाईंलाई उपयुक्त च्यानल छान्नुहोस्।',
                    ),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        height: 1.55,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 14),
                  StatusPill(
                    label: AppLanguage.tr('Replies within 1 working day',
                        '१ कार्यदिनभित्र जवाफ'),
                    color: const Color(0xFF4ADE80),
                    icon: Icons.schedule_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Theme-aware surface card: white + hairline border + soft shadow in
  /// light, raised surface + border in dark.
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

  /// Tone-coded section heading: rounded icon tile + bold title (+ subtitle).
  Widget _sectionHead(
    BuildContext context, {
    required IconData icon,
    required Color tone,
    required String title,
    String? subtitle,
  }) {
    final palette = ExpoPalette.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: 0.12),
          ),
          child: Icon(icon, size: 20, color: tone),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: palette.textPrimary)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle,
                      style: TextStyle(
                          color: palette.textSecondary, fontSize: 13)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One contact channel — tone-coded icon box (coloured translucent box +
  /// coloured icon, visible in both themes). Tapping opens the confirm
  /// popup, which launches the channel through the native openUrl branch.
  Widget _channelRow(
    BuildContext context, {
    required IconData icon,
    required Color tone,
    required String label,
    required String value,
    required String openUrl,
    required String confirmTitle,
  }) {
    final palette = ExpoPalette.of(context);
    return InkWell(
      onTap: () => _confirmOpenChannel(
        context,
        icon: icon,
        tone: tone,
        title: confirmTitle,
        displayValue: value,
        url: openUrl,
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tone.withValues(alpha: 0.12),
              ),
              child: Icon(icon, size: 20, color: tone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          color: palette.textSecondary, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Channel confirm popup (standing popup-action pattern): tap → shared
  /// AppModalShell confirm showing the value → Confirm shows loading on the
  /// button → native openUrl (ACTION_VIEW) → success closes the popup. If the
  /// native side reports failure, the value is copied with a toast instead.
  Future<void> _confirmOpenChannel(
    BuildContext context, {
    required IconData icon,
    required Color tone,
    required String title,
    required String displayValue,
    required String url,
  }) async {
    var opening = false;
    Future<void> confirm(
        BuildContext modalContext, void Function(void Function()) setModalState) async {
      if (opening) return;
      setModalState(() => opening = true);
      final opened = await _openExternal(url);
      if (!mounted) return;
      if (modalContext.mounted) Navigator.of(modalContext).pop();
      if (opened) return;
      await Clipboard.setData(ClipboardData(text: displayValue));
      if (context.mounted) {
        showToast(
          context,
          AppLanguage.tr('Could not open — value copied',
              'खोल्न सकिएन — मान प्रतिलिपि भयो'),
          ToastVariant.warning,
        );
      }
    }

    await AppModalShell.show(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (modalContext, setModalState) => AppModalShell(
          maxWidth: 360,
          tagLabel: AppLanguage.tr('Contact', 'सम्पर्क'),
          accent: tone,
          accentMid: tone,
          accentLight: tone.withValues(alpha: 0.25),
          tagColor: tone,
          onClose:
              opening ? null : () => Navigator.of(modalContext).pop(),
          icon: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: tone,
            ),
            child: Icon(icon, size: 28, color: Colors.white),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
              height: 1.3,
              decoration: TextDecoration.none,
            ),
          ),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLanguage.tr('This will open:', 'यो खुल्नेछ:'),
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: tone.withValues(alpha: 0.08),
                ),
                child: Text(
                  displayValue,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: tone,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
          footer: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: opening
                      ? null
                      : () => Navigator.of(modalContext).pop(),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: opening
                      ? null
                      : () => confirm(modalContext, setModalState),
                  style: FilledButton.styleFrom(
                    backgroundColor: tone,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: opening
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(AppLanguage.tr(
                                'Opening…', 'खोल्दैछ…')),
                          ],
                        )
                      : Text(
                          AppLanguage.tr('Confirm', 'पुष्टि गर्नुहोस्')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens [url] through the native "loksewa_solution/media" channel
  /// (ACTION_VIEW). The native branch handles mailto:, tel: and https:
  /// schemes via Intent resolution. Returns false on any failure.
  Future<bool> _openExternal(String url) async {
    try {
      final ok = await _mediaChannel.invokeMethod<bool>('openUrl', {'url': url});
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Brand glyph for a social key. X renders the real X logo via
  /// [XLogoIcon] (Material's Icons.close looks like a close button, not the
  /// X brand mark); the rest are the app's Material brand icons.
  Widget _brandIcon(String key, Color color) {
    switch (key) {
      case 'x':
        return XLogoIcon(size: 25, color: color);
      case 'facebook':
        return Icon(Icons.facebook, size: 25, color: color);
      case 'instagram':
        return Icon(Icons.camera_alt_outlined, size: 25, color: color);
      case 'youtube':
        return Icon(Icons.play_circle_outline, size: 25, color: color);
      default:
        return Icon(Icons.link, size: 25, color: color);
    }
  }

  /// One social in its brand colour — display-only; tapping copies the URL.
  Widget _socialItem({
    required Widget icon,
    required String label,
    required Color color,
    required String url,
  }) {
    return InkWell(
      onTap: () => _copy(url),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.10),
                border:
                    Border.all(color: color.withValues(alpha: 0.33)),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(child: icon),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Offline warning panel shown in place of the message form.
  Widget _offlineCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.33)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.orange.withValues(alpha: 0.14),
            ),
            child: const Icon(Icons.cloud_off_outlined,
                size: 20, color: Colors.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLanguage.tr(
                      'You are offline. Check your connection and try again.',
                      'तपाईं अफलाइन हुनुहुन्छ। जडान जाँचेर फेरि प्रयास गर्नुहोस्।'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.orange),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLanguage.tr('This requires an internet connection',
                      'यसका लागि इन्टरनेट जडान आवश्यक छ'),
                  style:
                      const TextStyle(fontSize: 13, color: Colors.orange),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// (iconKey, label, brand colour, url) — mirrors the React socials list.
/// X flips with the theme in React; Flutter's Material theme handles the
/// same case via brightness.
const _socials = [
  (
    'facebook',
    'Facebook',
    Color(0xFF1877F2),
    'https://www.facebook.com/profile.php?id=61580182268110',
  ),
  (
    'instagram',
    'Instagram',
    Color(0xFFE4405F),
    'https://www.instagram.com/loksewasolution?igsh=dmtlc3Zza2F1Y2xr&utm_source=qr',
  ),
  (
    'youtube',
    'YouTube',
    Color(0xFFFF0000),
    'https://www.youtube.com/loksewasolution0',
  ),
  (
    'x',
    'X (Twitter)',
    Color(0xFF0F1419),
    'https://x.com/loksewa_soln',
  ),
];
