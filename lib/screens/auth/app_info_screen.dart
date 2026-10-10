import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../theme/app_theme.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/x_logo_icon.dart';

/// App Info — mirrors app/app-info.tsx.
/// Identity block, About section, "What you get" highlights, Reach us,
/// Follow us, Legal. No build/package internals — only the app version.
///
/// NOTE: no package_info_plus is available in this project, so the displayed
/// version is a hand-maintained constant. Bump it with every release
/// (reminder recorded in ~/AGENTS.md).
class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({super.key});

  /// Displayed app version. BUMP WITH EVERY RELEASE — see ~/AGENTS.md.
  static const _appVersion = '1.0.89';

  /// Public read of the app version for other screens
  /// (e.g. the account-deletion-request Discord embed).
  static String get appVersion => _appVersion;

  static String _devanagariDigits(String s) => s.replaceAllMapped(
        RegExp(r'[0-9]'),
        (m) => '०१२३४५६७८९'[int.parse(m[0]!)],
      );

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  bool _preloading = true;

  @override
  void initState() {
    super.initState();
    // 1s premium preloading shimmer: this page has no database fetch, so the
    // content would pop in instantly without it.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _preloading = false);
    });
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

  @override
  Widget build(BuildContext context) {
    final versionLabel = AppLanguage.tr(
      'Version ${AppInfoScreen._appVersion}',
      'संस्करण ${AppInfoScreen._devanagariDigits(AppInfoScreen._appVersion)}',
    );
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('App Info', 'एप जानकारी')),
          Expanded(
            child: _preloading
                ? _preloadingBody()
                : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                SyllabusEntrance(
                  delayMs: 0,
                  child: _IdentityBlock(versionLabel: versionLabel),
                ),
                const SizedBox(height: 20),
                SyllabusEntrance(
                  delayMs: 60,
                  child: _SectionCard(
                    icon: Icons.info_outline,
                    tone: _Tone.primary,
                    title: AppLanguage.tr('About', 'बारेमा'),
                    body: Text(
                      AppLanguage.tr(
                        "Nepal's trusted digital preparation platform for Loksewa and other competitive government exams.",
                        'लोकसेवा र अन्य प्रतिस्पर्धी सरकारी परीक्षाहरूका लागि नेपालको भरपर्दो डिजिटल तयारी प्लेटफर्म।',
                      ),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: ExpoPalette.of(context).textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // "What you get": header enters at the section base delay;
                // each highlight row cascades syllabus-style (min(i, 8) * 60).
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SyllabusEntrance(
                      delayMs: 120,
                      child: _SectionHeader(
                        icon: Icons.auto_awesome_outlined,
                        tone: _Tone.accent,
                        title: AppLanguage.tr(
                            'What you get', 'तपाईंले पाउने कुरा'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SectionBodyCard(
                      child: Column(
                        children: [
                          for (int i = 0; i < _highlights.length; i++)
                            SyllabusEntrance(
                              delayMs: 120 + min(i, 8) * 60,
                              child: _IconRow(
                                icon: _highlights[i].icon,
                                tone: _highlights[i].tone,
                                title: AppLanguage.tr(
                                    _highlights[i].titleEn,
                                    _highlights[i].titleNe),
                                subtitle: AppLanguage.tr(
                                    _highlights[i].bodyEn,
                                    _highlights[i].bodyNe),
                                showDivider: i < _highlights.length - 1,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SyllabusEntrance(
                  delayMs: 180,
                  child: _SectionCard(
                    icon: Icons.headset_outlined,
                    tone: _Tone.info,
                    title: AppLanguage.tr('Reach us', 'सम्पर्क'),
                    body: Column(
                      children: [
                        _IconRow(
                          icon: Icons.language_outlined,
                          tone: _Tone.info,
                          title: AppLanguage.tr('Website', 'वेबसाइट'),
                          subtitle: 'kbr.com.np',
                          trailing: true,
                          showDivider: true,
                        ),
                        _IconRow(
                          icon: Icons.mail_outline,
                          tone: _Tone.primary,
                          title: AppLanguage.tr('Support', 'सहयोग'),
                          subtitle: 'contact@kbr.com.np',
                          trailing: true,
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SyllabusEntrance(
                  delayMs: 240,
                  child: _SectionCard(
                    icon: Icons.share_outlined,
                    tone: _Tone.success,
                    title: AppLanguage.tr(
                        'Follow Us', 'हामीलाई फलो गर्नुहोस्'),
                    body: const _SocialRow(),
                  ),
                ),
                const SizedBox(height: 20),
                // Legal: header enters at the section base delay; each row
                // cascades syllabus-style (base + i * 60).
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SyllabusEntrance(
                      delayMs: 300,
                      child: _SectionHeader(
                        icon: Icons.lock_outline,
                        tone: _Tone.neutral,
                        title: AppLanguage.tr('Legal', 'कानुनी'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SectionBodyCard(
                      child: Column(
                        children: [
                          SyllabusEntrance(
                            delayMs: 300,
                            child: _IconRow(
                              icon: Icons.shield_outlined,
                              tone: _Tone.neutral,
                              title: AppLanguage.tr(
                                  'Privacy Policy', 'गोपनीयता नीति'),
                              showDivider: true,
                              onTap: () =>
                                  context.push('/privacy-policy'),
                            ),
                          ),
                          SyllabusEntrance(
                            delayMs: 360,
                            child: _IconRow(
                              icon: Icons.description_outlined,
                              tone: _Tone.neutral,
                              title: AppLanguage.tr(
                                  'Terms and Conditions', 'नियम र सर्तहरू'),
                              showDivider: false,
                              onTap: () =>
                                  context.push('/terms-conditions'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SyllabusEntrance(
                  delayMs: 360,
                  child: Text(
                    'Made for Nepali students 🇳🇵',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Tone { primary, danger, warning, info, success, accent, neutral }

Color _toneColor(_Tone tone, ExpoPalette pal) {
  switch (tone) {
    case _Tone.primary:
      return pal.primary;
    case _Tone.danger:
      return pal.danger;
    case _Tone.warning:
      return pal.warning;
    case _Tone.info:
      return pal.info;
    case _Tone.success:
      return pal.success;
    case _Tone.accent:
      return pal.accent;
    case _Tone.neutral:
      return pal.textSecondary;
  }
}

class _Highlight {
  final IconData icon;
  final _Tone tone;
  final String titleEn;
  final String titleNe;
  final String bodyEn;
  final String bodyNe;

  const _Highlight(
      this.icon, this.tone, this.titleEn, this.titleNe, this.bodyEn, this.bodyNe);
}

const _highlights = [
  _Highlight(
    Icons.library_books_outlined,
    _Tone.primary,
    'Complete syllabus',
    'पूर्ण पाठ्यक्रम',
    'Subject-wise notes and chapters mapped to the Loksewa syllabus.',
    'लोकसेवा पाठ्यक्रमअनुसार विषयगत नोट र अध्यायहरू।',
  ),
  _Highlight(
    Icons.timer_outlined,
    _Tone.danger,
    'Mock tests & quizzes',
    'मक टेस्ट र क्विजहरू',
    'Timed practice with instant scoring and detailed explanations.',
    'समयसहितको अभ्यास, तुरुन्त स्कोर र विस्तृत व्याख्यासहित।',
  ),
  _Highlight(
    Icons.newspaper_outlined,
    _Tone.warning,
    'Daily current affairs',
    'दैनिक समसामयिक',
    'Gorkhapatra highlights and a fresh question every day.',
    'गोरखापत्रका मुख्य अंश र हरेक दिन नयाँ प्रश्न।',
  ),
  _Highlight(
    Icons.bar_chart_outlined,
    _Tone.info,
    'Progress analytics',
    'प्रगति विश्लेषण',
    'See your strong and weak subjects as you prepare.',
    'तयारी गर्दै जाँदा आफ्ना बलिया र कमजोर विषय हेर्नुहोस्।',
  ),
  _Highlight(
    Icons.people_outlined,
    _Tone.success,
    'Discussion forum',
    'छलफल मञ्च',
    'Ask questions and learn together with other aspirants.',
    'प्रश्न सोध्नुहोस् र अन्य तयारीकर्तासँग सँगै सिक्नुहोस्।',
  ),
];

/// Identity block: primary-tone → transparent wash, centered logo, app name
/// (always English), tagline and version [StatusPill].
class _IdentityBlock extends StatelessWidget {
  final String versionLabel;

  const _IdentityBlock({required this.versionLabel});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            pal.primary.withValues(alpha: 0x14 / 0xFF),
            pal.surface.withValues(alpha: 0),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: 108,
              height: 108,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Loksewa Solution',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            AppLanguage.tr(
                'Prepare Smarter, Score Higher', 'राम्रो तयारी, उच्च अंक'),
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.textSecondary),
          ),
          const SizedBox(height: 12),
          StatusPill(
            label: versionLabel,
            color: pal.primary,
            icon: Icons.check_circle,
          ),
        ],
      ),
    );
  }
}

/// 36px tone-tinted icon box + bold title row — the header half of a section.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final _Tone tone;
  final String title;

  const _SectionHeader({
    required this.icon,
    required this.tone,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final c = _toneColor(tone, pal);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0x1F / 0xFF),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: c),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// Hairline-bordered surface card (radius 18) — the body half of a section.
class _SectionBodyCard extends StatelessWidget {
  final Widget child;

  const _SectionBodyCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border.all(color: pal.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

/// Premium section: header above a body card.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final _Tone tone;
  final String title;
  final Widget body;

  const _SectionCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: icon, tone: tone, title: title),
        const SizedBox(height: 10),
        _SectionBodyCard(child: body),
      ],
    );
  }
}

/// Tinted 40px icon box + title (semibold) + subtitle (caption, secondary);
/// optional hairline divider; optional trailing open_in_new; optional tap
/// (chevron) for navigation rows.
class _IconRow extends StatelessWidget {
  final IconData icon;
  final _Tone tone;
  final String title;
  final String? subtitle;
  final bool trailing;
  final bool showDivider;
  final VoidCallback? onTap;

  const _IconRow({
    required this.icon,
    required this.tone,
    required this.title,
    this.subtitle,
    this.trailing = false,
    this.showDivider = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final c = _toneColor(tone, pal);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0x1F / 0xFF),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: c),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 13,
                    color: pal.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing)
          Icon(Icons.open_in_new, size: 18, color: pal.textSecondary),
        if (onTap != null) Icon(Icons.chevron_right, color: pal.textSecondary),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onTap != null)
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: row,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: row,
          ),
        if (showDivider) Divider(color: pal.border, height: 1),
      ],
    );
  }
}

class _Social {
  final String label;
  final Color color;
  final Widget icon;

  const _Social(this.label, this.color, this.icon);
}

/// Four brand buttons in one row: tinted bg + hairline brand border,
/// 24px brand icon + brand-coloured label. Display-only (no tap).
class _SocialRow extends StatelessWidget {
  const _SocialRow();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // X's mark flips with the theme (same as Contact Us): the dark mark is
    // all but invisible on a dark surface.
    final xColor = isDark ? const Color(0xFFE7E9EA) : const Color(0xFF0F1419);
    final socials = [
      const _Social('Facebook', Color(0xFF1877F2),
          Icon(Icons.facebook, size: 24, color: Color(0xFF1877F2))),
      const _Social('YouTube', Color(0xFFFF0000),
          CustomPaint(size: Size(24, 24), painter: _YouTubePainter())),
      const _Social('Instagram', Color(0xFFE4405F),
          CustomPaint(size: Size(24, 24), painter: _InstagramPainter())),
      // The real X brand mark via the shared XLogoIcon (same widget as
      // Contact Us) — a plain two-stroke X reads as a close button.
      _Social('X', xColor, XLogoIcon(size: 24, color: xColor)),
    ];
    return Row(
      children: [
        for (int i = 0; i < socials.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: socials[i].color.withValues(alpha: 0x14 / 0xFF),
                border: Border.all(
                    color: socials[i].color.withValues(alpha: 0x55 / 0xFF)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  socials[i].icon,
                  const SizedBox(height: 4),
                  Text(
                    socials[i].label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: socials[i].color,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (i < socials.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// YouTube glyph: rounded red rect + white play triangle.
class _YouTubePainter extends CustomPainter {
  const _YouTubePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final red = Paint()..color = const Color(0xFFFF0000);
    final white = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 5, size.width - 4, size.height - 10),
        const Radius.circular(5),
      ),
      red,
    );
    final triangle = Path()
      ..moveTo(size.width / 2 - 2.5, size.height / 2 - 3.5)
      ..lineTo(size.width / 2 - 2.5, size.height / 2 + 3.5)
      ..lineTo(size.width / 2 + 4, size.height / 2)
      ..close();
    canvas.drawPath(triangle, white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Instagram glyph: rounded square outline + circle + dot.
class _InstagramPainter extends CustomPainter {
  const _InstagramPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final brand = Paint()
      ..color = const Color(0xFFE4405F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3, 3, size.width - 6, size.height - 6),
        const Radius.circular(6),
      ),
      brand,
    );
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), 4.5, brand);
    canvas.drawCircle(
      Offset(size.width - 7, 7),
      1.6,
      Paint()..color = const Color(0xFFE4405F),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
