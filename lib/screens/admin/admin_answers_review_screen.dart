import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/syllabus_entrance.dart';

/// Admin "Answers Review" desk — the NEW page opened from
/// Profile > Admin > Answer Review. Mirrors React's AdminAnswerDesk
/// (which lived inline on the Exam tab): track tabs narrow the list to a
/// specific desk, each card opens the full grading screen
/// (/admin/exam-answer/:id).
class AdminAnswersReviewScreen extends StatefulWidget {
  const AdminAnswersReviewScreen({super.key});

  @override
  State<AdminAnswersReviewScreen> createState() =>
      _AdminAnswersReviewScreenState();
}

class _Denied implements Exception {}

class _AdminAnswersReviewScreenState extends State<AdminAnswersReviewScreen> {
  String _track = 'all';
  List<ExamAnswer> _answers = [];
  bool _loading = true;
  String? _error;

  static const _newWindowMs = 24 * 60 * 60 * 1000;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = AuthService.currentUser;
      if (user == null) throw _Denied();
      final token = await AuthService.getValidIdToken();
      final profile =
          await FirestoreRest.getDocument('users/${user.uid}', idToken: token);
      if (profile?['isAdmin'] != true) throw _Denied();
      final answers = await fetchAllExamAnswers();
      if (!mounted) return;
      setState(() {
        _answers = answers;
        _loading = false;
      });
    } on _Denied {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Admin access only.', 'प्रशासक पहुँच मात्र।');
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLanguage.tr(
            'Could not load submissions. Pull to retry.',
            'उत्तरहरू लोड हुन सकेन। पुनः प्रयास गर्न तल तान्नुहोस्।');
        _loading = false;
      });
    }
  }

  String _classify(String sectionName) {
    final n = sectionName.toLowerCase();
    if (n.contains('theory')) return 'theory';
    if (n.contains('past')) return 'pastqns';
    return 'other';
  }

  String _timeAgo(int millis) {
    if (millis <= 0) return '';
    final diffMin =
        ((DateTime.now().millisecondsSinceEpoch - millis) / 60000).round();
    if (diffMin < 1) return AppLanguage.tr('just now', 'भर्खरै');
    if (diffMin < 60) return '$diffMin${AppLanguage.tr('m ago', 'मि. अघि')}';
    final diffHr = (diffMin / 60).round();
    if (diffHr < 24) return '$diffHr${AppLanguage.tr('h ago', 'घ. अघि')}';
    return '${(diffHr / 24).round()}${AppLanguage.tr('d ago', 'दि. अघि')}';
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final tracks = ['all', 'theory', 'pastqns', 'other'];
    final counts = <String, int>{'all': _answers.length};
    for (final t in ['theory', 'pastqns', 'other']) {
      counts[t] = _answers.where((a) => _classify(a.sectionName) == t).length;
    }
    final filtered = _track == 'all'
        ? _answers
        : _answers.where((a) => _classify(a.sectionName) == _track).toList();
    final pendingCount = filtered.where((a) => a.status == 'pending').length;

    return Scaffold(
      backgroundColor: pal.background,
      body: Column(
        children: [
          SubpageHeader(
              title: AppLanguage.tr('Answers Review', 'उत्तर समीक्षा')),
          Expanded(
            child: _loading
                ? PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading submissions...',
                        'उत्तरहरू लोड हुँदैछ...'),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_outlined,
                                  size: 48, color: pal.textDisabled),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: pal.textSecondary)),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                          children: [
                            // Track tabs.
                            SyllabusEntrance(
                              delayMs: 0,
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: tracks.map((t) {
                                  final active = _track == t;
                                  final label = t == 'all'
                                      ? AppLanguage.tr('All', 'सबै')
                                      : t == 'theory'
                                          ? AppLanguage.tr(
                                              'Theory Desk', 'थियरी डेस्क')
                                          : t == 'pastqns'
                                              ? AppLanguage.tr('Past Qns Desk',
                                                  'पुराना प्रश्न डेस्क')
                                              : AppLanguage.tr(
                                                  'Other', 'अन्य');
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => _track = t),
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 9),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? pal.primary
                                            : pal.surfaceAlt,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(
                                          color: active
                                              ? pal.primary
                                              : pal.border,
                                          width: 0.75,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(label,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  color: active
                                                      ? Colors.white
                                                      : pal.textPrimary)),
                                          if ((counts[t] ?? 0) > 0) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: active
                                                    ? Colors.white
                                                        .withValues(
                                                            alpha: 0.25)
                                                    : pal.surface,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        999),
                                              ),
                                              child: Text('${counts[t]}',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: active
                                                          ? Colors.white
                                                          : pal.textSecondary)),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Pending banner.
                            if (pendingCount > 0)
                              SyllabusEntrance(
                                delayMs: 60,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD97706)
                                        .withValues(alpha: 0.10),
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    border: Border.all(
                                        color: const Color(0xFFD97706)
                                            .withValues(alpha: 0.25),
                                        width: 0.75),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.schedule_outlined,
                                          size: 16,
                                          color: Color(0xFFD97706)),
                                      const SizedBox(width: 8),
                                      Text(
                                        AppLanguage.tr(
                                            '$pendingCount submission${pendingCount == 1 ? '' : 's'} waiting for review',
                                            'समीक्षाका लागि $pendingCount उत्तर बाँकी'),
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFD97706)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (pendingCount > 0)
                              const SizedBox(height: 12),
                            if (filtered.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 48),
                                child: Column(
                                  children: [
                                    Icon(
                                        Icons
                                            .document_scanner_outlined,
                                        size: 48,
                                        color: pal.textDisabled),
                                    const SizedBox(height: 12),
                                    Text(
                                      AppLanguage.tr('No submissions',
                                          'कुनै उत्तर छैन'),
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: pal.textPrimary),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      AppLanguage.tr(
                                          'Answers submitted from this track will show up here.',
                                          'यस डेस्कबाट पेश गरिएका उत्तरहरू यहाँ देखिनेछन्।'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: pal.textSecondary),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ...filtered.asMap().entries.map((e) {
                                final i = e.key;
                                final a = e.value;
                                final isNew = a.status == 'pending' &&
                                    a.createdAtMillis > 0 &&
                                    DateTime.now()
                                                .millisecondsSinceEpoch -
                                            a.createdAtMillis <
                                        _newWindowMs;
                                // If the student typed a different name than
                                // their profile at submission time, show both.
                                final nameLabel = a.profileName.isNotEmpty &&
                                        a.profileName != a.studentName
                                    ? '${a.studentName} (${a.profileName})'
                                    : a.studentName.isNotEmpty
                                        ? a.studentName
                                        : AppLanguage.tr('Unnamed student',
                                            'नाम नभएको विद्यार्थी');
                                return SyllabusEntrance(
                                  delayMs: (i.clamp(0, 8)) * 60,
                                  child: _AnswerCard(
                                    answer: a,
                                    nameLabel: nameLabel,
                                    timeAgo:
                                        _timeAgo(a.createdAtMillis),
                                    isNew: isNew,
                                    onTap: () => context.push(
                                        '/admin/exam-answer/${a.id}'),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  final ExamAnswer answer;
  final String nameLabel;
  final String timeAgo;
  final bool isNew;
  final VoidCallback onTap;

  const _AnswerCard({
    required this.answer,
    required this.nameLabel,
    required this.timeAgo,
    required this.isNew,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final pending = answer.status == 'pending';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: pal.border, width: 0.75),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (pending
                        ? const Color(0xFFD97706)
                        : const Color(0xFF16A34A))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.description_outlined,
                size: 21,
                color: pending
                    ? const Color(0xFFD97706)
                    : const Color(0xFF16A34A),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          nameLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: pal.textPrimary),
                        ),
                      ),
                      if (isNew)
                        Container(
                          margin:
                              const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius:
                                BorderRadius.circular(999),
                          ),
                          child: Text(
                            AppLanguage.tr('NEW', 'नयाँ'),
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    answer.examSetTitle.isNotEmpty
                        ? answer.examSetTitle
                        : AppLanguage.tr(
                            'Untitled paper', 'शीर्षक नभएको पेपर'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5, color: pal.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: (pending
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF16A34A))
                              .withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(999),
                        ),
                        child: Text(
                          pending
                              ? AppLanguage.tr(
                                  'Pending', 'बाँकी')
                              : AppLanguage.tr(
                                  'Reviewed', 'समीक्षा भयो'),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: pending
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF16A34A)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (timeAgo.isNotEmpty)
                        Text(timeAgo,
                            style: TextStyle(
                                fontSize: 11,
                                color: pal.textDisabled)),
                      const Spacer(),
                      Icon(Icons.chevron_right,
                          size: 18, color: pal.textDisabled),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
