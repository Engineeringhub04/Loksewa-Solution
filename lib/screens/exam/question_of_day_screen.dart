import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/exam_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/subpage_header.dart';
import 'package:loksewa_solution/widgets/preloading.dart';

/// Question of the day — exact port of app/question-of-the-day.tsx.
///
/// Data: `app_qotd_daily/{kathmanduDateKey}__{courseId}__{subcourseId}`
/// (published by the admin — no client-side rotation), result at
/// `users/{uid}/questionofdata/{attemptId}`, summary at
/// `users/{uid}/questionofdata/summary`. A timer re-arms for the next
/// Kathmandu midnight so a new question appears at 12AM; resuming the app
/// re-checks when the cached state is stale (>30s).
class QuestionOfDayScreen extends StatefulWidget {
  const QuestionOfDayScreen({super.key});

  @override
  State<QuestionOfDayScreen> createState() => _QuestionOfDayScreenState();
}

class _QuestionOfDayScreenState extends State<QuestionOfDayScreen>
    with WidgetsBindingObserver {
  QotdDay? _day;
  String _courseId = '';
  String _subcourseId = '';
  String _courseName = '';
  String _subcourseName = '';
  bool _opening = true;
  String? _error;
  String? _submitting;
  Timer? _midnightTimer;
  int _checkedAt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
    _armMidnightTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final day = _day;
      final stale = DateTime.now().millisecondsSinceEpoch - _checkedAt >= 30000;
      final shouldCheck = stale && (day?.question == null || day?.result == null);
      if (shouldCheck && _courseId.isNotEmpty && _subcourseId.isNotEmpty) {
        _load(force: true);
      }
    }
  }

  /// Kathmandu midnight delay — mirrors getKathmanduMidnightDelay(): the
  /// first instant whose Kathmandu date key differs from now, +1.5s.
  Duration _midnightDelay() {
    final nowUtc = DateTime.now().toUtc();
    String keyOf(DateTime dt) {
      final k = dt.add(const Duration(hours: 5, minutes: 45));
      return '${k.year}-${k.month}-${k.day}';
    }

    final nowKey = keyOf(nowUtc);
    var probe = nowUtc.add(const Duration(hours: 20));
    while (keyOf(probe) == nowKey) {
      probe = probe.add(const Duration(minutes: 1));
    }
    while (keyOf(probe.subtract(const Duration(minutes: 1))) != nowKey) {
      probe = probe.subtract(const Duration(minutes: 1));
    }
    final delay = probe.difference(nowUtc) + const Duration(milliseconds: 1500);
    return delay.inMilliseconds < 1000
        ? const Duration(seconds: 1)
        : delay;
  }

  void _armMidnightTimer() {
    _midnightTimer?.cancel();
    _midnightTimer = Timer(_midnightDelay(), () {
      if (mounted) {
        _load(force: true);
        _armMidnightTimer();
      }
    });
  }

  Future<void> _boot() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final uid = AuthService.currentUser?.uid ?? '';
      String courseId = '';
      String subcourseId = '';
      String courseName = '';
      String subcourseName = '';
      if (uid.isNotEmpty) {
        final profile = await fetchUserProfile(uid);
        courseId = profile?.courseId ?? '';
        subcourseId = profile?.subcourseId ?? '';
        courseName = courseId;
        subcourseName = subcourseId;
        // Resolve human-readable names like the home header does.
        if (courseId.isNotEmpty) {
          final c =
              await ExamRest.getDoc('app_courses/$courseId').catchError((_) => null);
          final n = (c?['name'] ?? c?['nameNe']) as String?;
          if (n != null && n.trim().isNotEmpty) courseName = n.trim();
        }
        if (courseId.isNotEmpty && subcourseId.isNotEmpty) {
          final sc = await ExamRest.getDoc('app_subcourses/$subcourseId')
              .catchError((_) => null);
          final n = (sc?['name'] ?? sc?['nameNe']) as String?;
          if (n != null && n.trim().isNotEmpty) subcourseName = n.trim();
        }
      }
      if (!mounted) return;
      setState(() {
        _courseId = courseId;
        _subcourseId = subcourseId;
        _courseName = courseName;
        _subcourseName = subcourseName;
      });
      if (uid.isNotEmpty && courseId.isNotEmpty && subcourseId.isNotEmpty) {
        await Future.wait([
          _load(),
          Future.delayed(const Duration(milliseconds: 420)),
        ]);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _load({bool force = false}) async {
    final uid = AuthService.currentUser?.uid ?? '';
    if (uid.isEmpty || _courseId.isEmpty || _subcourseId.isEmpty) return;
    if (!force && _day != null) {
      final d = _day!;
      if (d.dateKey == todayDateKey() &&
          d.courseId == _courseId &&
          d.subcourseId == _subcourseId) {
        return;
      }
    }
    setState(() => _error = null);
    try {
      final day = await fetchQotdDay(uid, _courseId, _subcourseId);
      if (!mounted) return;
      setState(() {
        _day = day;
        _checkedAt = DateTime.now().millisecondsSinceEpoch;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _msg(e));
    }
  }

  String _msg(Object e) => '$e'.replaceFirst('Exception: ', '');

  Future<void> _choose(QotdOption option) async {
    final uid = AuthService.currentUser?.uid;
    final question = _day?.question;
    if (uid == null || question == null || _day?.result != null || _submitting != null) {
      return;
    }
    setState(() => _submitting = option.id);
    try {
      final saved = await Future.wait([
        submitQotdAnswer(uid, question, option.id, _day!.summary),
        Future.delayed(const Duration(milliseconds: 420)),
      ]).then((v) => v[0] as ({QotdResult result, QotdSummary summary}));
      if (!mounted) return;
      setState(() {
        _day = QotdDay(
          dateKey: _day!.dateKey,
          courseId: _day!.courseId,
          subcourseId: _day!.subcourseId,
          question: _day!.question,
          result: saved.result,
          summary: saved.summary,
        );
        _checkedAt = DateTime.now().millisecondsSinceEpoch;
        _submitting = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_msg(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final day = _day;
    final q = day?.result?.snapshot ?? day?.question;
    final validDay = day != null &&
            day.courseId == _courseId &&
            day.subcourseId == _subcourseId
        ? day
        : null;
    final isInitialLoading = _opening ||
        (_courseId.isNotEmpty &&
            _subcourseId.isNotEmpty &&
            validDay == null &&
            _error == null);

    Widget body;
    if (isInitialLoading) {
      body = _loadingView(palette, 'Preparing your daily question\u2026');
    } else if (_courseId.isEmpty || _subcourseId.isEmpty) {
      body = _notFound(
        palette,
        title: 'Course setup required',
        description: 'Select your Course and Sub-course first.',
        onRetry: _boot,
      );
    } else if (_error != null && q == null) {
      body = _notFound(palette, onRetry: () => _load(force: true));
    } else if (q == null) {
      body = RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          padding: const EdgeInsets.all(ExpoSpacing.screenPadding),
          children: [
            _PremiumStats(
              summary: validDay?.summary,
              course: '$_courseName \u00B7 $_subcourseName',
            ),
            const SizedBox(height: 16),
            _notFound(
              palette,
              title: 'No question added for today',
              description:
                  'No question is scheduled today for $_courseName \u00B7 $_subcourseName.',
              onRetry: () => _load(force: true),
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: _questionView(palette, validDay!, q),
      );
    }

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          const SubpageHeader(
              title: 'Question of the Day', showThemeToggle: true),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _loadingView(ExpoPalette palette, String label) => PreloadingWidget(
        tinted: false,
        label: label,
      );

  Widget _notFound(
    ExpoPalette palette, {
    String? title,
    String? description,
    required VoidCallback onRetry,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined,
                  size: 48, color: palette.textDisabled),
              const SizedBox(height: 12),
              if (title != null)
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: ExpoType.bodyLarge,
                        fontWeight: FontWeight.bold)),
              if (description != null) ...[
                const SizedBox(height: 6),
                Text(description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: ExpoType.bodySmall)),
              ],
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _questionView(ExpoPalette palette, QotdDay day, QotdQuestion q) {
    final completed = day.result != null;
    final selected = day.result?.selectedOptionId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const abcd = 'ABCD';
    return ListView(
      padding: const EdgeInsets.only(
          left: ExpoSpacing.screenPadding,
          right: ExpoSpacing.screenPadding,
          top: ExpoSpacing.screenPadding,
          bottom: 48),
      children: [
        _PremiumStats(
          summary: day.summary,
          course: '${q.courseName.isNotEmpty ? q.courseName : _courseName} \u00B7 '
              '${q.subcourseName.isNotEmpty ? q.subcourseName : _subcourseName}',
        ),
        const SizedBox(height: 16),
        // Question card.
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 13, color: palette.primary),
                        const SizedBox(width: 5),
                        Text(
                          q.showingDate.isNotEmpty
                              ? q.showingDate
                              : day.dateKey,
                          style: TextStyle(
                              color: palette.primary,
                              fontSize: ExpoType.caption,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _Tag(
                      label: q.difficulty.toUpperCase(),
                      color: _difficultyColor(q.difficulty),
                      isDark: isDark),
                  IconButton(
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => context.push('/bookmarks'),
                    icon: Icon(Icons.bookmark_border,
                        size: 20, color: palette.textSecondary),
                  ),
                  IconButton(
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => context.push('/report-question'),
                    icon: Icon(Icons.flag_outlined,
                        size: 20, color: palette.textSecondary),
                  ),
                ],
              ),
              if (q.categories.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: q.categories
                      .map((c) => _Tag(
                          label: qotdEn(c.name),
                          color: _hexColor(c.color),
                          isDark: isDark))
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                qotdEn(q.content),
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 19,
                    height: 28 / 19,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text('Choose the best answer',
                  style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: ExpoType.caption)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Options.
        ...List.generate(q.options.length, (i) {
          final o = q.options[i];
          final isSel = selected == o.id;
          final isCorrect = o.id == q.correctOptionId;
          final isSaving = _submitting == o.id;
          Color border = palette.border;
          Color bg = palette.surface;
          Color accent = palette.textSecondary;
          if (completed && isCorrect) {
            border = const Color(0xFF22C55E);
            bg = isDark
                ? const Color(0xFF153526)
                : const Color(0xFFECFDF5);
            accent = isDark
                ? const Color(0xFF86EFAC)
                : const Color(0xFF16A34A);
          } else if (completed && isSel) {
            border = const Color(0xFFEF4444);
            bg = isDark
                ? const Color(0xFF3A1D25)
                : const Color(0xFFFFF1F2);
            accent = isDark
                ? const Color(0xFFFCA5A5)
                : const Color(0xFFDC2626);
          } else if (isSaving) {
            border = palette.primary;
            bg = isDark
                ? const Color(0xFF172554)
                : const Color(0xFFEFF6FF);
            accent =
                isDark ? const Color(0xFF93C5FD) : palette.primary;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(17),
              child: InkWell(
                onTap: completed || _submitting != null
                    ? null
                    : () => _choose(o),
                borderRadius: BorderRadius.circular(17),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 68),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: border, width: 1.3),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: accent.withValues(alpha: 0.08),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.21)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          o.id.isNotEmpty
                              ? o.id
                              : (i < 4 ? abcd[i] : '?'),
                          style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.bold,
                              fontSize: ExpoType.body),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          qotdEn(o.content),
                          style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: ExpoType.bodyLarge,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isSaving)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: palette.primary),
                        )
                      else if (completed && isCorrect)
                        const Icon(Icons.check_circle,
                            size: 24, color: Color(0xFF16A34A))
                      else if (completed && isSel)
                        const Icon(Icons.cancel,
                            size: 24, color: Color(0xFFDC2626))
                      else
                        Icon(Icons.chevron_right,
                            size: 19, color: palette.textDisabled),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        // Result card.
        if (completed) ...[
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: day.result!.isCorrect
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFFF7ED),
              border: Border.all(
                  color: day.result!.isCorrect
                      ? const Color(0xFF86EFAC)
                      : const Color(0xFFFDBA74)),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: day.result!.isCorrect
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFF59E0B),
                  ),
                  child: Icon(
                      day.result!.isCorrect
                          ? Icons.emoji_events
                          : Icons.lightbulb_outline,
                      size: 25,
                      color: Colors.white),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day.result!.isCorrect
                          ? 'CORRECT ANSWER'
                          : 'INCORRECT ANSWER',
                      style: TextStyle(
                          color: day.result!.isCorrect
                              ? const Color(0xFF15803D)
                              : const Color(0xFFC2410C),
                          fontSize: ExpoType.overline,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      qotdEn(day.result!.isCorrect
                          ? (q.correctGreeting.isNotEmpty
                              ? q.correctGreeting
                              : 'Excellent!')
                          : (q.wrongGreeting.isNotEmpty
                              ? q.wrongGreeting
                              : 'Good attempt!')),
                      style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: ExpoType.bodyLarge,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  color: const Color(0x2E64748B),
                ),
                const SizedBox(
                  width: double.infinity,
                  child: Text('Explanation',
                      style: TextStyle(
                          color: Color(0xFF334155),
                          fontSize: ExpoType.bodySmall,
                          fontWeight: FontWeight.bold)),
                ),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    qotdEn(q.explanation),
                    style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: ExpoType.body,
                        height: 21 / 14),
                  ),
                ),
                const SizedBox(
                  width: double.infinity,
                  child: Text(
                    'Completed for today. Come back tomorrow for a new question. Thank you!',
                    style: TextStyle(
                        color: Color(0xFF2563EB),
                        fontSize: ExpoType.bodySmall,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Parse '#RRGGBB' / '#AARRGGBB' (with or without '#'); fallback #2563EB.
  Color _hexColor(String hex) {
    var h = hex.trim().replaceAll('#', '');
    if (h.length == 3) h = h.split('').map((c) => c + c).join();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? const Color(0xFF2563EB) : Color(v);
  }

  Color _difficultyColor(String d) {
    switch (d) {
      case 'easy':
        return const Color(0xFF22C55E);
      case 'hard':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFF59E0B);
    }
  }
}

/// Daily progress stats — mirrors PremiumStats in question-of-the-day.tsx.
class _PremiumStats extends StatelessWidget {
  final QotdSummary? summary;
  final String course;

  const _PremiumStats({required this.summary, required this.course});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1F51), Color(0xFF153E90), Color(0xFF2257C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR DAILY PROGRESS',
                      style: TextStyle(
                          color: Color(0xFF93C5FD),
                          fontSize: ExpoType.overline,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 3),
                    Text(course,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.74),
                            fontSize: ExpoType.bodySmall)),
                  ],
                ),
              ),
              const Icon(Icons.analytics_outlined,
                  size: 23, color: Color(0xFFBFDBFE)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat(Icons.help_outline, '${summary?.totalAttempts ?? 0}',
                  'Total Attempts', const Color(0xFFFBBF24)),
              const SizedBox(width: 10),
              _stat(Icons.check_circle, '${summary?.correct ?? 0}', 'Correct',
                  const Color(0xFF4ADE80)),
              const SizedBox(width: 10),
              _stat(Icons.show_chart, '${summary?.averagePercent ?? 0}%',
                  'Average', const Color(0xFF7DD3FC)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label, Color color) =>
      Expanded(
        child: Container(
          padding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: 0.12),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.14),
                  border: Border.all(
                      color: color.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(height: 6),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      height: 24 / 19,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.74),
                      fontSize: ExpoType.caption,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
}

/// Difficulty/category pill — mirrors Tag() in question-of-the-day.tsx.
class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;

  const _Tag(
      {required this.label, required this.color, required this.isDark});

  Color _mixWithWhite(Color c, [double ratio = 0.55]) {
    int ch(double v) => (v + (255 - v) * ratio).round().clamp(0, 255);
    return Color.fromARGB(255, ch(c.r * 255), ch(c.g * 255), ch(c.b * 255));
  }

  @override
  Widget build(BuildContext context) {
    final display = isDark ? _mixWithWhite(color) : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: display.withValues(alpha: isDark ? 0.12 : 0.09),
        border: Border.all(
            color: display.withValues(alpha: isDark ? 0.4 : 0.27)),
      ),
      child: Text(label,
          style: TextStyle(
              color: display,
              fontSize: ExpoType.overline,
              fontWeight: FontWeight.bold)),
    );
  }
}
