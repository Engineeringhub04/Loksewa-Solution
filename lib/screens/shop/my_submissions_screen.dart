// "My Answer Submissions" — the student's Theory answers, newest first,
// with a Pending/Reviewed badge. One row per exam set (v1.0.125): the
// LATEST submission represents the set; earlier attempts live in the
// detail page's Previous Submissions history. Tapping a row opens its
// details screen (score, reviewer note, edit-window re-upload).
//
// Mirrors app/exam-answer/my-submissions.tsx: summary hero band with
// Submitted / Pending / Passed tallies, per-status tone cards (icon tile,
// course line, status pill + score pill, relative time), empty state,
// pull-to-refresh, error toast.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/cf_api.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/syllabus_entrance.dart';

class MySubmissionsScreen extends StatefulWidget {
  const MySubmissionsScreen({super.key});

  @override
  State<MySubmissionsScreen> createState() => _MySubmissionsScreenState();
}

class _MySubmissionsScreenState extends State<MySubmissionsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The student's own docs from the flat `app_exam_answers` collection,
  /// newest first. Phase-2: GET /exam-answers/mine returns every answer
  /// row in one call (the worker resolves the per-user index
  /// server-side) — the list paints as soon as the rows arrive.
  Future<void> _load({bool refresh = false}) async {
    if (!refresh) setState(() => _loading = true);
    try {
      final all = await CfApi.getMyExamAnswers();
      all.sort((a, b) => _millis(b['createdAt'])
          .compareTo(_millis(a['createdAt'])));
      // v1.0.125: ONE row per exam set — the LATEST submission. A
      // re-applied set used to list every attempt as its own card;
      // the older ones now live in the detail page's Previous
      // Submissions history instead.
      final mine = latestSubmissionsBySet(all);
      if (!mounted) return;
      // Render FIRST with the names already stored on the docs (v1.0.120):
      // the list paints as soon as the answers arrive instead of waiting
      // for every missing name to resolve.
      setState(() {
        _items = mine;
        _loading = false;
      });
      // Older submissions saved blank course/subcourse names (copied from
      // the set doc, which only carries IDs) — resolve them from the parent
      // exam set, one set-doc load per unique set, and patch each card in
      // as its names land. Best-effort: failures leave the names blank
      // and the card falls back to '—'.
      final setCache = <String, Map<String, dynamic>?>{};
      for (var i = 0; i < mine.length; i++) {
        final doc = mine[i];
        final blank = (doc['courseName'] ?? '').toString().trim().isEmpty ||
            (doc['subcourseName'] ?? '').toString().trim().isEmpty;
        if (!blank) continue;
        final names = await resolveAnswerDisplayNames(doc,
            nepali: AppLanguage.isNepali, examSetCache: setCache);
        if (!mounted) return;
        if (names.courseName.isEmpty && names.subcourseName.isEmpty) {
          continue;
        }
        final merged = Map<String, dynamic>.from(doc);
        if ((merged['courseName'] ?? '').toString().trim().isEmpty &&
            names.courseName.isNotEmpty) {
          merged['courseName'] = names.courseName;
        }
        if ((merged['subcourseName'] ?? '').toString().trim().isEmpty &&
            names.subcourseName.isNotEmpty) {
          merged['subcourseName'] = names.subcourseName;
        }
        mine[i] = merged;
        // Patch the visible list (same order — resolution never re-sorts).
        setState(() => _items = List.of(mine));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(
          context,
          AppLanguage.tr('Could not load your submissions.',
              'तपाईंका उत्तरहरू लोड हुन सकेन।'),
          ToastVariant.error);
    }
  }

  int _millis(dynamic raw) {
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  String _docId(Map<String, dynamic> d) => d['id']?.toString() ?? '';

  String _timeAgo(dynamic raw) {
    final ms = _millis(raw);
    if (ms == 0) return '';
    final diffMin =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms))
            .inMinutes
            .clamp(0, 1 << 30);
    if (diffMin < 1) return AppLanguage.tr('just now', 'भर्खरै');
    if (diffMin < 60) {
      return AppLanguage.tr('$diffMin m ago', '$diffMin मिनेट अघि');
    }
    final diffHr = (diffMin / 60).round();
    if (diffHr < 24) {
      return AppLanguage.tr('$diffHr h ago', '$diffHr घण्टा अघि');
    }
    final diffDay = (diffHr / 24).round();
    return AppLanguage.tr('$diffDay d ago', '$diffDay दिन अघि');
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: pal.background,
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr(
                  'My Answer Submissions', 'मेरा उत्तर पेशहरू')),
          Expanded(
            child: _loading
                ? PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
                    hint: AppLanguage.tr('Fetching your submissions',
                        'तपाईंका उत्तरहरू ल्याउँदै'),
                  )
                : RefreshIndicator.adaptive(
                    onRefresh: () => _load(refresh: true),
                    color: pal.primary,
                    child: _items.isEmpty
                        ? SyllabusEntrance(
                            delayMs: 100, child: _emptyBody(pal))
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                            children: [
                              SyllabusEntrance(
                                  delayMs: 0, child: _hero(pal)),
                              const SizedBox(height: 12),
                              for (var i = 0; i < _items.length; i++) ...[
                                if (i > 0) const SizedBox(height: 10),
                                SyllabusEntrance(
                                  delayMs: (i.clamp(0, 8) + 1) * 60,
                                  child: _SubmissionCard(
                                    key: ValueKey(_docId(_items[i])),
                                    answer: _items[i],
                                    pal: pal,
                                    timeAgo: _timeAgo(_items[i]['createdAt']),
                                    onTap: () => context.push(
                                        '/exam-answer/${_docId(_items[i])}'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Summary band — icon + title + subtitle, with the three tally tiles.
  Widget _hero(ExpoPalette pal) {
    final reviewed =
        _items.where((d) => d['status']?.toString() == 'reviewed');
    final pending = _items.length - reviewed.length;
    final passed = reviewed.where((d) => d['passed'] == true).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pal.primary, const Color(0xFF1E40AF)],
        ),
        boxShadow: [
          BoxShadow(
            color: pal.primary.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned(
              right: -34,
              top: -34,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              right: 24,
              bottom: -48,
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                      child: const Icon(Icons.cloud_done_outlined,
                          size: 23, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLanguage.tr('My Answer Submissions',
                                'मेरा उत्तर पेशहरू'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLanguage.tr(
                                'Every Theory answer you have uploaded, newest first.',
                                'तपाईंले अपलोड गर्नुभएका सबै थ्योरी उत्तरहरू, नयाँ पहिले।'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.80),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _StatTile(
                      value: '${_items.length}',
                      label: AppLanguage.tr('Submitted', 'पेश गरिएको'),
                      icon: Icons.description_outlined,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    _StatTile(
                      value: '$pending',
                      label: AppLanguage.tr('Pending', 'बाँकी'),
                      icon: Icons.schedule_outlined,
                      color: const Color(0xFFFCD34D),
                    ),
                    const SizedBox(width: 8),
                    _StatTile(
                      value: '$passed',
                      label: AppLanguage.tr('Passed', 'उत्तीर्ण'),
                      icon: Icons.emoji_events_outlined,
                      color: const Color(0xFF6EE7B7),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBody(ExpoPalette pal) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      children: [
        Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: pal.primary.withValues(alpha: 0.08),
                border: Border.all(
                    color: pal.primary.withValues(alpha: 0.20), width: 1),
              ),
              child: Icon(Icons.cloud_upload_outlined,
                  size: 32, color: pal.primary),
            ),
            const SizedBox(height: 18),
            Text(
              AppLanguage.tr('No submissions yet', 'अहिलेसम्म कुनै उत्तर छैन'),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: pal.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              AppLanguage.tr(
                  'Answers you upload for Theory Desk papers will appear here.',
                  'थ्योरी डेस्क पेपरका लागि अपलोड गरेका उत्तरहरू यहाँ देखिनेछन्।'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: pal.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _StatTile(
      {required this.value,
      required this.label,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.80),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmissionCard extends StatefulWidget {
  final Map<String, dynamic> answer;
  final ExpoPalette pal;
  final String timeAgo;
  final VoidCallback onTap;
  const _SubmissionCard(
      {super.key,
      required this.answer,
      required this.pal,
      required this.timeAgo,
      required this.onTap});

  @override
  State<_SubmissionCard> createState() => _SubmissionCardState();
}

class _SubmissionCardState extends State<_SubmissionCard> {
  bool _pressed = false;

  String _num(dynamic v) {
    final n = v is num ? v : num.tryParse('$v') ?? 0;
    return n % 1 == 0 ? n.toInt().toString() : n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final a = widget.answer;
    final reviewed = a['status']?.toString() == 'reviewed';
    // Rejected at the grading desk: reviewed, but the admin saved a
    // rejection reason instead of a result (passed stays null). Same
    // test as the detail page — the card shows the reason, never a
    // "Not passed" verdict or a score.
    final rejected = reviewed &&
        (a['rejectionReason']?.toString().trim().isNotEmpty ?? false);
    final passed = a['passed'] == true;
    final tone =
        reviewed ? (passed ? pal.success : pal.danger) : pal.warning;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = dark ? 0.15 : 0.08;
    final courseLine = [
      (a['courseName'] ?? '').toString(),
      (a['subcourseName'] ?? '').toString()
    ].where((s) => s.isNotEmpty).join(' · ');

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _pressed ? tone.withValues(alpha: tint) : pal.surface,
          border: Border.all(
              color: _pressed
                  ? tone.withValues(alpha: dark ? 0.35 : 0.25)
                  : pal.border,
              width: 0.5),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tone.withValues(alpha: tint + 0.06),
                        tone.withValues(alpha: tint),
                      ],
                    ),
                    border: Border.all(
                      color: tone.withValues(alpha: dark ? 0.33 : 0.20),
                      width: 0.75,
                    ),
                  ),
                  child: Icon(
                    reviewed
                        ? (passed
                            ? Icons.done_all_outlined
                            : Icons.error_outline)
                        : Icons.hourglass_top_outlined,
                    size: 21,
                    color: tone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ((a['examSetTitle'] ?? '').toString().isNotEmpty)
                            ? a['examSetTitle'].toString()
                            : AppLanguage.tr(
                                'Theory Answer', 'थ्योरी उत्तर'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: pal.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        courseLine.isNotEmpty ? courseLine : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: pal.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 18, color: pal.textDisabled),
              ],
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusPill(
                        label: rejected
                            ? (a['rejectionReason']?.toString().trim() ?? '')
                            : reviewed
                                ? (passed
                                    ? AppLanguage.tr('Passed', 'उत्तीर्ण')
                                    : AppLanguage.tr(
                                        'Not passed', 'अनुत्तीर्ण'))
                                : AppLanguage.tr('Pending', 'बाँकी'),
                        color: tone,
                        icon: reviewed
                            ? (passed
                                ? Icons.check_circle_outline
                                : Icons.cancel_outlined)
                            : Icons.schedule_outlined,
                      ),
                      // A rejected answer has no score to show.
                      if (reviewed && !rejected)
                        StatusPill(
                          label:
                              '${_num(a['score'])}/${_num(a['fullMarks'])}',
                          color: tone,
                          icon: Icons.emoji_events_outlined,
                        ),
                    ],
                  ),
                ),
                if (widget.timeAgo.isNotEmpty)
                  Text(
                    widget.timeAgo,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 12, color: pal.textSecondary),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
