// Report detail — what the reporter sees after filing a report.
//
// Mirrors app/report-history/[id].tsx: status hero with source/reason/date
// pills, the reported-content card (target title / preview / author,
// target kind, report ID), the report message (reason, explanation,
// submitted date), reporter details (avatar, email, course, sub-course),
// and the admin-response list (per-status tones, spine on the latest) —
// or the pending-review hint when nothing has arrived yet.
import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/syllabus_entrance.dart';
import 'report_visuals.dart';

class ReportDetailScreen extends StatefulWidget {
  final String id;
  const ReportDetailScreen({super.key, required this.id});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  Map<String, dynamic>? _record;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Mirrors `fetchReportHistory`.
  Future<void> _load({bool refresh = false}) async {
    if (!refresh) setState(() => _loading = true);
    try {
      final idToken = await AuthService.getValidIdToken();
      final doc = await FirestoreRest.getDocument(
          'app_report_history/${widget.id}',
          idToken: idToken);
      if (!mounted) return;
      setState(() {
        _record = doc;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(
          context,
          AppLanguage.tr('Could not load the report.',
              'रिपोर्ट लोड हुन सकेन।'),
          ToastVariant.error);
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _fmtDate(dynamic raw) {
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw;
    } else if (raw is num) {
      dt = DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    } else if (raw is String) {
      dt = DateTime.tryParse(raw);
    }
    if (dt == null) return '—';
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: pal.background,
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Report Details', 'रिपोर्ट विवरण')),
          Expanded(
            child: _loading
                ? PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
                    hint: AppLanguage.tr(
                        'Fetching your content', 'सामग्री ल्याउँदै'),
                  )
                : _record == null
                    ? _errorBody(pal)
                    : RefreshIndicator.adaptive(
                        onRefresh: () => _load(refresh: true),
                        color: pal.primary,
                        child: _body(pal, _record!),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _errorBody(ExpoPalette pal) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      children: [
        Column(
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 44, color: pal.textDisabled),
            const SizedBox(height: 12),
            Text(
              AppLanguage.tr(
                  'Report not found.', 'रिपोर्ट भेटिएन।'),
              style: TextStyle(fontSize: 14, color: pal.textPrimary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: Text(AppLanguage.tr('Retry', 'पुनः प्रयास')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _body(ExpoPalette pal, Map<String, dynamic> r) {
    final statusKey = (r['status'] ?? 'pending').toString();
    final status = reportStatusVisual(statusKey);
    final statusColor = reportToneColor(pal, status.tone);
    final sourceKey = (r['source'] ?? 'other').toString();
    final source = reportSourceVisual(sourceKey);
    final sourceColor = reportToneColor(pal, source.tone);
    final targetType = (r['targetType'] ?? 'question').toString();
    final target = reportTargetVisual(targetType);
    final responses =
        (r['adminResponses'] as List?)?.whereType<Map>().toList() ?? [];
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = dark ? 0x26 / 0xFF : 0x14 / 0xFF;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Status hero.
        SyllabusEntrance(
          delayMs: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  statusColor,
                  Color.lerp(statusColor, Colors.black, 0.18)!,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0x1A / 0xFF),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color:
                            Colors.white.withValues(alpha: 0x29 / 0xFF),
                      ),
                      child: Icon(status.icon,
                          size: 24, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLanguage.tr(
                                status.labelEn, status.labelNe),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ((r['contextLabel'] ?? '').toString().isNotEmpty)
                                ? r['contextLabel'].toString()
                                : AppLanguage.tr(
                                    source.labelEn, source.labelNe),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white
                                  .withValues(alpha: 0xCC / 0xFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _HeroPill(
                      icon: source.icon,
                      label: AppLanguage.tr(
                          source.labelEn, source.labelNe),
                    ),
                    _HeroPill(
                      icon: Icons.flag_outlined,
                      label: (r['reason'] ?? '').toString(),
                    ),
                    _HeroPill(
                      icon: Icons.calendar_month_outlined,
                      label: _fmtDate(r['createdAt']),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Reported content.
        SyllabusEntrance(
          delayMs: 60,
          child: _SectionCard(
            pal: pal,
            icon: target.icon,
            tone: sourceColor,
            title: AppLanguage.tr(
                'Reported content', 'रिपोर्ट गरिएको सामग्री'),
            trailing: StatusPill(
              label: AppLanguage.tr(target.labelEn, target.labelNe),
              color: sourceColor,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: tint),
                    border: Border(
                      left: BorderSide(color: sourceColor, width: 3),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _avatar(
                              pal,
                              (r['targetAuthorPhoto'] ?? '')
                                  .toString(),
                              target.icon,
                              38),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ((r['targetTitle'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                      ? r['targetTitle'].toString()
                                      : AppLanguage.tr(target.labelEn,
                                          target.labelNe),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: pal.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${((r['targetAuthorName'] ?? '').toString().isNotEmpty) ? r['targetAuthorName'].toString() : AppLanguage.tr(source.labelEn, source.labelNe)} · ${_fmtDate(r['createdAt'])}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: pal.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ((r['targetPreview'] ?? '').toString().isNotEmpty)
                            ? r['targetPreview'].toString()
                            : '—',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: pal.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _InfoRow(
                  pal: pal,
                  icon: Icons.sell_outlined,
                  label: AppLanguage.tr('Target', 'लक्ष्य'),
                  value: AppLanguage.tr(
                      target.labelEn, target.labelNe),
                ),
                _InfoRow(
                  pal: pal,
                  icon: Icons.fingerprint_outlined,
                  label: AppLanguage.tr('Report ID', 'रिपोर्ट आईडी'),
                  value: (r['targetId'] ?? '').toString().isNotEmpty
                      ? r['targetId'].toString()
                      : '—',
                  last: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Report message.
        SyllabusEntrance(
          delayMs: 120,
          child: _SectionCard(
            pal: pal,
            icon: Icons.info_outline,
            tone: pal.warning,
            title: AppLanguage.tr(
                'Report information', 'रिपोर्ट जानकारी'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  pal: pal,
                  icon: Icons.flag_outlined,
                  label: AppLanguage.tr('Reason', 'कारण'),
                  value: (r['reason'] ?? '').toString(),
                  tone: pal.warning,
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLanguage.tr('Explanation', 'व्याख्या'),
                        style: TextStyle(
                            fontSize: 12,
                            color: pal.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ((r['description'] ?? '').toString().isNotEmpty)
                            ? r['description'].toString()
                            : '—',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: pal.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                    height: 0.75, color: pal.divider),
                _InfoRow(
                  pal: pal,
                  icon: Icons.schedule_outlined,
                  label: AppLanguage.tr(
                      'Submitted on', 'पठाइएको मिति'),
                  value: _fmtDate(r['createdAt']),
                  last: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Reporter details.
        SyllabusEntrance(
          delayMs: 180,
          child: _SectionCard(
            pal: pal,
            icon: Icons.person_outline,
            tone: pal.info,
            title: AppLanguage.tr(
                'Reporter details', 'रिपोर्टकर्ताको विवरण'),
            child: Column(
              children: [
                Row(
                  children: [
                    _avatar(
                        pal,
                        (r['reporterPhoto'] ?? '').toString(),
                        Icons.person,
                        52),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            ((r['reporterName'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                ? r['reporterName'].toString()
                                : '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: pal.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(999),
                              color: pal.info.withValues(
                                  alpha:
                                      dark ? 0x26 / 0xFF : 0x14 / 0xFF),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.mail_outline,
                                    size: 12, color: pal.info),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    ((r['reporterEmail'] ?? '')
                                                .toString()
                                                .isNotEmpty)
                                        ? r['reporterEmail']
                                            .toString()
                                        : '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: pal.info,
                                    ),
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
                const SizedBox(height: 6),
                _InfoRow(
                  pal: pal,
                  icon: Icons.school_outlined,
                  label: AppLanguage.tr('Course', 'कोर्स'),
                  value: ((r['reporterCourseId'] ?? '').toString().isNotEmpty)
                      ? r['reporterCourseId'].toString()
                      : '—',
                ),
                _InfoRow(
                  pal: pal,
                  icon: Icons.layers_outlined,
                  label: AppLanguage.tr('Sub-course', 'सब-कोर्स'),
                  value: ((r['reporterSubcourseId'] ?? '')
                          .toString()
                          .isNotEmpty)
                      ? r['reporterSubcourseId'].toString()
                      : '—',
                  last: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Admin responses — or the pending hint.
        if (responses.isNotEmpty)
          SyllabusEntrance(
            delayMs: 240,
            child: _SectionCard(
              pal: pal,
              icon: Icons.admin_panel_settings_outlined,
              tone: pal.success,
              title: AppLanguage.tr(
                  'Admin response', 'एडमिन प्रतिक्रिया'),
              subtitle: AppLanguage.tr(
                  'Response history', 'जवाफ इतिहास'),
              child: Column(
                children: [
                  for (var i = 0; i < responses.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _ResponsePanel(
                      pal: pal,
                      response: responses[i],
                      latest: i == responses.length - 1,
                      date: _fmtDate(responses[i]['createdAt']),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          SyllabusEntrance(
            delayMs: 240,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: pal.surfaceAlt,
                border: Border.all(color: pal.border, width: 0.75),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_top_outlined,
                      size: 20, color: pal.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppLanguage.tr(
                          'Your report is waiting for admin review. A response will appear here once it is reviewed.',
                          'तपाईंको रिपोर्ट एडमिन समीक्षाको प्रतीक्षामा छ। समीक्षा भएपछि प्रतिक्रिया यहाँ देखिनेछ।'),
                      style: TextStyle(
                          fontSize: 13, color: pal.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _avatar(
      ExpoPalette pal, String photoUrl, IconData fallback, double size) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (photoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(
              pal, dark, fallback, size),
        ),
      );
    }
    return _avatarFallback(pal, dark, fallback, size);
  }

  Widget _avatarFallback(
      ExpoPalette pal, bool dark, IconData fallback, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pal.primary
            .withValues(alpha: dark ? 0x26 / 0xFF : 0x14 / 0xFF),
        border: Border.all(
          color: pal.primary
              .withValues(alpha: dark ? 0x55 / 0xFF : 0x33 / 0xFF),
          width: 0.75,
        ),
      ),
      child: Icon(fallback, size: size * 0.45, color: pal.primary),
    );
  }
}

/// White-on-tint pill used in the status hero.
class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeroPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0x29 / 0xFF),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0x38 / 0xFF),
          width: 0.75,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final ExpoPalette pal;
  final IconData icon;
  final Color tone;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  const _SectionCard({
    required this.pal,
    required this.icon,
    required this.tone,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border.all(color: pal.border, width: 0.75),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: tone.withValues(
                      alpha: dark ? 0x26 / 0xFF : 0x14 / 0xFF),
                ),
                child: Icon(icon, size: 17, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: pal.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                            fontSize: 11, color: pal.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final ExpoPalette pal;
  final IconData? icon;
  final String label;
  final String value;
  final Color? tone;
  final bool last;
  const _InfoRow({
    required this.pal,
    this.icon,
    required this.label,
    required this.value,
    this.tone,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: tone ?? pal.textSecondary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: pal.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tone ?? pal.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    if (last) return content;
    return Column(
      children: [
        content,
        Container(height: 0.75, color: pal.divider),
      ],
    );
  }
}

/// One admin response — tone panel, spine on the latest, status caption.
class _ResponsePanel extends StatelessWidget {
  final ExpoPalette pal;
  final Map response;
  final bool latest;
  final String date;
  const _ResponsePanel({
    required this.pal,
    required this.response,
    required this.latest,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final status =
        reportStatusVisual((response['status'] ?? 'reviewed').toString());
    final color = reportToneColor(pal, status.tone);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0x26 / 0xFF : 0x14 / 0xFF),
        border: Border(
          left: BorderSide(
              color: color, width: latest ? 3 : 0.75),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(status.icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                AppLanguage.tr(status.labelEn, status.labelNe),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: pal.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            (response['message'] ?? '').toString(),
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: pal.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
