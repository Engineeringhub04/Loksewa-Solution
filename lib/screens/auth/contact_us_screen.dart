import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../services/app_language.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/syllabus_entrance.dart';

/// Contact Us — mirrors app/contact-us.tsx.
///
/// Hero (with "Replies within 1 working day" pill), Reach us rows,
/// Follow us brand circles, and a message form. External links are
/// display-only (no url_launcher): tapping a channel or social copies its
/// value/URL to the clipboard. The message posts to the team's Google Form
/// via [ReportService.submitContactMessage] — the same pipeline as React.
class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _message = TextEditingController();
  bool _sending = false;
  bool? _offline;

  static const _email = 'contact@kbr.com.np';
  static const _phone = '+977-9810768297';
  static const _websiteUrl = 'https://kbr.com.np';
  static const _websiteDisplay = 'kbr.com.np';

  @override
  void initState() {
    super.initState();
    _checkOnline();
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
    final socials = [
      for (final s in _socials)
        s.$2 == 'X (Twitter)'
            ? (s.$1, s.$2, isDark ? const Color(0xFFE7E9EA) : s.$3, s.$4)
            : s,
    ];
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Contact Us', 'सम्पर्क गर्नुहोस्')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SyllabusEntrance(
                  delayMs: 0,
                  child: Card(
                    color: AppColors.navy,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white
                                      .withValues(alpha: 0x1F / 0xFF),
                                ),
                                child: const Icon(Icons.chat_bubble_outline,
                                    color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppLanguage.tr(
                                      'Contact Us', 'सम्पर्क गर्नुहोस्'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppLanguage.tr(
                              'We usually reply within one working day. Pick whichever channel suits you.',
                              'हामी सामान्यतया एक कार्यदिनभित्र जवाफ दिन्छौं। तपाईंलाई उपयुक्त च्यानल छान्नुहोस्।',
                            ),
                            style: const TextStyle(
                                color: Color(0xFFD7E3FF), height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          StatusPill(
                            label: AppLanguage.tr(
                                'Replies within 1 working day',
                                '१ कार्यदिनभित्र जवाफ'),
                            color: const Color(0xFF4ADE80),
                            icon: Icons.schedule_outlined,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SyllabusEntrance(
                  delayMs: 60,
                  child: _sectionCard(
                    icon: Icons.headset_mic_outlined,
                    tone: AppColors.navy,
                    title: AppLanguage.tr('Reach us', 'सम्पर्क'),
                    children: [
                      _channelRow(
                        icon: Icons.mail_outline,
                        tone: AppColors.navy,
                        label: AppLanguage.tr('Email us', 'इमेल गर्नुहोस्'),
                        value: _email,
                        copyValue: _email,
                      ),
                      _channelRow(
                        icon: Icons.call_outlined,
                        tone: const Color(0xFF16A34A),
                        label: AppLanguage.tr('Call us', 'फोन गर्नुहोस्'),
                        value: _phone,
                        copyValue: _phone,
                      ),
                      _channelRow(
                        icon: Icons.language_outlined,
                        tone: const Color(0xFF0EA5E9),
                        label: AppLanguage.tr('Website', 'वेबसाइट'),
                        value: _websiteDisplay,
                        copyValue: _websiteUrl,
                        last: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SyllabusEntrance(
                  delayMs: 120,
                  child: _sectionCard(
                    icon: Icons.share_outlined,
                    tone: const Color(0xFF8B5CF6),
                    title: AppLanguage.tr(
                        'Follow us', 'हामीलाई फलो गर्नुहोस्'),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final s in socials)
                            Expanded(
                              child: _socialItem(
                                icon: s.$1,
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
                const SizedBox(height: 12),
                if (offline)
                  SyllabusEntrance(
                    delayMs: 180,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0x14 / 0xFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.orange
                                .withValues(alpha: 0x55 / 0xFF)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.cloud_off_outlined,
                              size: 22, color: Colors.orange),
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
                                      fontSize: 13,
                                      color: Colors.orange),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppLanguage.tr(
                                      'This requires an internet connection',
                                      'यसका लागि इन्टरनेट जडान आवश्यक छ'),
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.orange),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SyllabusEntrance(
                    delayMs: 180,
                    child: _sectionCard(
                      icon: Icons.send_outlined,
                      tone: const Color(0xFF0EA5E9),
                      title: AppLanguage.tr('Send Message', 'सन्देश पठाउनुहोस्'),
                      subtitle: AppLanguage.tr(
                          'Reach out to our support team',
                          'हाम्रो सहायता टोलीलाई सम्पर्क गर्नुहोस्'),
                      children: [
                        TextField(
                          controller: _message,
                          maxLines: 4,
                          minLines: 4,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            hintText: AppLanguage.tr(
                                'Write your message…', 'आफ्नो सन्देश लेख्नुहोस्…'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
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
                                borderRadius: BorderRadius.circular(12),
                              ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required Color tone,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone.withValues(alpha: 0x14 / 0xFF),
                  ),
                  child: Icon(icon, size: 18, color: tone),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 13)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  /// One contact channel — display-only (no url_launcher); tapping copies
  /// the value to the clipboard.
  Widget _channelRow({
    required IconData icon,
    required Color tone,
    required String label,
    required String value,
    required String copyValue,
    bool last = false,
  }) {
    return InkWell(
      onTap: () => _copy(copyValue),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.only(
            top: 8, bottom: last ? 4 : 8, left: 4, right: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tone.withValues(alpha: 0x14 / 0xFF),
              ),
              child: Icon(icon, size: 19, color: tone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(value,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.copy_outlined,
                size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  /// One social in its brand colour — display-only; tapping copies the URL.
  Widget _socialItem({
    required IconData icon,
    required String label,
    required Color color,
    required String url,
  }) {
    return InkWell(
      onTap: () => _copy(url),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0x1A / 0xFF),
                border: Border.all(
                    color: color.withValues(alpha: 0x55 / 0xFF)),
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(height: 6),
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
}

/// (icon, label, brand colour, url) — mirrors the React socials list.
/// X flips with the theme in React; Flutter's Material theme handles the
/// same case via brightness.
const _socials = [
  (
    Icons.facebook,
    'Facebook',
    Color(0xFF1877F2),
    'https://www.facebook.com/profile.php?id=61580182268110',
  ),
  (
    Icons.camera_alt_outlined,
    'Instagram',
    Color(0xFFE4405F),
    'https://www.instagram.com/loksewasolution?igsh=dmtlc3Zza2F1Y2xr&utm_source=qr',
  ),
  (
    Icons.play_circle_outline,
    'YouTube',
    Color(0xFFFF0000),
    'https://www.youtube.com/loksewasolution0',
  ),
  (
    Icons.close,
    'X (Twitter)',
    Color(0xFF0F1419),
    'https://x.com/loksewa_soln',
  ),
];
