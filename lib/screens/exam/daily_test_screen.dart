import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/daily_test_card.dart';
import '../../widgets/subpage_header.dart';

/// Daily test landing — mirrors app/daily-test/index.tsx.
///
/// Up to four slides: a reserved upcoming slot (the first model of the next
/// scheduled date, or a "…New Set" demo card dated tomorrow when nothing is
/// queued), today's models ("Test X of Y"), at most one missed model, then
/// recent completions to fill the strip.
class DailyTestScreen extends StatefulWidget {
  const DailyTestScreen({super.key});

  @override
  State<DailyTestScreen> createState() => _DailyTestScreenState();
}

class _Slide {
  final DailyTestModel model;
  final DailyTestSlot slot;
  final bool completed;
  final int? indexInDay;
  final int? totalInDay;

  const _Slide(
      {required this.model,
      required this.slot,
      this.completed = false,
      this.indexInDay,
      this.totalInDay});
}

class _DailyTestScreenState extends State<DailyTestScreen> {
  bool _loading = true;
  bool _noCourse = false;
  String? _error;

  UserProfile? _profile;
  String _courseName = '';
  String _subcourseName = '';
  List<DailyTestModel> _models = const [];
  Map<String, DailyTestResult> _resultsById = const {};
  List<DailyTestActivity> _activities = const [];
  List<_Slide> _slides = const [];
  String _dayKey = '';

  int _slideIndex = 0;
  PageController? _pageController;
  Timer? _autoSlideTimer;
  Timer? _resumeTimer;
  Timer? _midnightTimer;
  Timer? _tickTimer;
  String _countdown = '';

  @override
  void initState() {
    super.initState();
    _dayKey = todayDateKey();
    _countdown = _formatCountdown();
    _load();
    // Recompute the feed when the local day rolls over at midnight.
    _armMidnightTimer();
    // Live "unlocks in" countdown on the no-test strip.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _countdown = _formatCountdown());
    });
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _resumeTimer?.cancel();
    _midnightTimer?.cancel();
    _tickTimer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  void _armMidnightTimer() {
    _midnightTimer?.cancel();
    _midnightTimer =
        Timer(Duration(milliseconds: msUntilNextLocalMidnight()), () {
      if (!mounted) return;
      setState(() => _dayKey = todayDateKey());
      _load();
      _armMidnightTimer();
    });
  }

  String _formatCountdown() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    final diff = next.difference(now);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  // -- auto-sliding carousel ----------------------------------------------
  void _setupCarousel() {
    _autoSlideTimer?.cancel();
    _resumeTimer?.cancel();
    _pageController?.dispose();
    _slideIndex = 0;
    if (_slides.length < 2) {
      _pageController = PageController();
      return;
    }
    _pageController = PageController();
    _autoSlideTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _advanceSlide());
  }

  void _advanceSlide() {
    final c = _pageController;
    if (c == null || !c.hasClients || _slides.length < 2) return;
    final next = (_slideIndex + 1) % _slides.length;
    _slideIndex = next;
    c.animateToPage(next,
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    if (mounted) setState(() {});
  }

  void _pauseCarousel() {
    _autoSlideTimer?.cancel();
    _resumeTimer?.cancel();
  }

  void _scheduleResume() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _slides.length < 2) return;
      _autoSlideTimer?.cancel();
      _autoSlideTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _advanceSlide());
    });
  }

  // -- data ---------------------------------------------------------------

  /// Strips raw JSON/API dumps from an error so the UI never shows them.
  String _sanitizeError(String raw) {
    var msg = raw.replaceFirst('Exception: ', '');
    final jsonStart = msg.indexOf('{');
    if (jsonStart >= 0) msg = msg.substring(0, jsonStart).trim();
    if (msg.length > 160) msg = '${msg.substring(0, 160).trim()}…';
    return msg.isEmpty ? 'Please try again.' : msg;
  }

  Future<void> _load({bool refreshing = false}) async {
    final uid = AuthService.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      context.go('/login');
      return;
    }
    setState(() {
      if (!refreshing) {
        _loading = true;
      }
      _error = null;
    });
    try {
      final profile = await fetchUserProfile(uid);
      if (!mounted) return;
      final subcourseId = profile?.subcourseId ?? '';
      final courseId = profile?.courseId ?? '';
      if (subcourseId.isEmpty) {
        setState(() {
          _loading = false;
          _noCourse = true;
        });
        return;
      }
      final models = await fetchDailyTestModels(subcourseId);
      final results = await fetchDailyTestResults(uid);
      final activities = await getRecentDailyTestActivities(uid);
      final session = sessionDailyTestCompletions(uid);
      final byId = {for (final r in results) r.modelId: r};
      for (final e in session.entries) {
        byId[e.key] = e.value;
      }

      String courseName = '';
      String subcourseName = '';
      try {
        final cdoc = await ExamRest.getDoc('app_courses/$courseId');
        final sdoc = await ExamRest.getDoc(
            'app_courses/$courseId/subcourses/$subcourseId');
        courseName = '${cdoc?['name'] ?? ''}';
        subcourseName = '${sdoc?['name'] ?? sdoc?['title'] ?? ''}';
        if (subcourseName.isEmpty) {
          final legacy = await ExamRest.getDoc('app_subcourses/$subcourseId');
          subcourseName = '${legacy?['name'] ?? legacy?['title'] ?? ''}';
        }
      } catch (_) {
        // names are decorative; the feed works without them
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _noCourse = false;
        _profile = profile;
        _courseName = courseName;
        _subcourseName = subcourseName;
        _models = models;
        _resultsById = byId;
        _activities = activities;
      });
      _buildSlides();
    } catch (e) {
      if (!mounted) return;
      // Never blame the connection for a query failure: the phone is online
      // (home loads fine). Show what actually failed, sanitized — never a raw
      // JSON/API dump.
      setState(() {
        _loading = false;
        _error = 'Couldn\'t load the daily tests. ${_sanitizeError('$e')}';
      });
    }
  }

  void _buildSlides() {
    final dayKey = _dayKey;
    final doneIds = _resultsById.keys.toSet();
    final todayModels = modelsForDate(_models, dayKey);
    final nextDate = nextScheduledDate(_models, dayKey);
    DailyTestModel? reserved;
    if (nextDate != null) {
      final first = modelsForDate(_models, nextDate);
      if (first.isNotEmpty) reserved = first.first;
    }
    final missed = missedDailyTestModels(_models, doneIds, dayKey);
    final recent = _resultsById.values.toList()
      ..sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));

    final slides = <_Slide>[];
    final taken = <String>{};
    void push(DailyTestModel m, DailyTestSlot slot,
        {bool completed = false, int? indexInDay, int? totalInDay}) {
      if (taken.contains(m.id)) return;
      taken.add(m.id);
      slides.add(_Slide(
          model: m,
          slot: slot,
          completed: completed,
          indexInDay: indexInDay,
          totalInDay: totalInDay));
    }

    // 1 — reserved upcoming slot: the next scheduled model, else the demo card.
    if (reserved != null) {
      push(reserved, DailyTestSlot.upcoming);
    } else {
      push(
          buildDemoUpcomingModel(
            courseId: _profile?.courseId ?? '',
            subcourseId: _profile?.subcourseId ?? '',
            dateKey: addDaysToKey(dayKey, 1),
            subcourseName: _subcourseName,
          ),
          DailyTestSlot.upcoming);
    }
    // 2 — today's models.
    for (var i = 0; i < todayModels.length; i++) {
      final m = todayModels[i];
      push(m, DailyTestSlot.today,
          completed: doneIds.contains(m.id),
          indexInDay: i + 1,
          totalInDay: todayModels.length);
    }
    // 3 — at most one missed model.
    if (missed.isNotEmpty) {
      push(missed.first, DailyTestSlot.missed);
    }
    // 4 — recent completions fill the strip.
    for (final r in recent) {
      if (slides.length >= 4) break;
      DailyTestModel? m;
      for (final x in _models) {
        if (x.id == r.modelId) {
          m = x;
          break;
        }
      }
      if (m != null) push(m, DailyTestSlot.today, completed: true);
    }

    setState(() => _slides = slides);
    _setupCarousel();
  }

  // -- navigation ----------------------------------------------------------
  void _goSummary(DailyTestModel m,
      {List<int>? answers, int? timeTakenSeconds}) {
    final qp = <String, String>{};
    if (answers != null) qp['answers'] = jsonEncode(answers);
    if (timeTakenSeconds != null) qp['timeTaken'] = '$timeTakenSeconds';
    final uri = Uri(
        path: '/daily-test/${m.id}/summary',
        queryParameters: qp.isEmpty ? null : qp);
    context.push(uri.toString());
  }

  Future<void> _openModel(DailyTestModel m) async {
    if (isDailyTestDemo(m)) {
      showToast(
          context, 'Demo preview — real test will appear here.',
          ToastVariant.info);
      return;
    }
    final existing = _resultsById[m.id];
    if (existing != null) {
      _goSummary(m,
          answers: existing.answers,
          timeTakenSeconds: existing.timeTakenSeconds);
      return;
    }
    final ok = await showDailyTestRulesDialog(context, m);
    if (!mounted || !ok) return;
    context.push('/daily-test/${m.id}/quiz');
  }

  // -- build ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B1120) : const Color(0xFFF5F6FA),
      body: SafeArea(
        // SubpageHeader paints behind the status bar itself
        // (React parity) — no top inset here or the header gets pushed down.
        top: false,
        child: Column(
          children: [
            const SubpageHeader(title: 'Daily Test'),
            Expanded(child: _body(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _body(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 44, color: Color(0xFF9CA3AF)),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _load(),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB)),
                child: const Text('Try again',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    if (_noCourse) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.school_outlined,
                  size: 44, color: Color(0xFF9CA3AF)),
              const SizedBox(height: 12),
              const Text('No course selected',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Choose a course to get your daily test.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => context.push('/course-setup'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB)),
                child: const Text('Select a course',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final todayModels = modelsForDate(_models, _dayKey);

    return RefreshIndicator(
      onRefresh: () => _load(refreshing: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _activeCourseBanner(),
            const SizedBox(height: 20),
            _sectionHeader(
              title: "Today's Tests",
              actionLabel: 'View All',
              onAction: () => context.push('/daily-test/models'),
            ),
            const SizedBox(height: 12),
            if (todayModels.isEmpty)
              DailyTestNoTestStrip(countdown: _countdown),
            if (_slides.isNotEmpty) ...[
              if (todayModels.isEmpty) const SizedBox(height: 12),
              _carousel(),
            ] else if (todayModels.isNotEmpty)
              _emptyCard(
                  'A new daily test will appear here soon.'),
            if (_activities.isNotEmpty) ...[
              const SizedBox(height: 24),
              _sectionHeader(
                title: 'Your History',
                actionLabel: 'View All',
                onAction: () => context.push('/daily-test/history'),
              ),
              const SizedBox(height: 12),
              ..._activities.take(3).map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DailyTestHistoryCard(
                      activity: a,
                      onTap: () => _openHistoryActivity(a),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _activeCourseBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF0B1F5B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.school, size: 22, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ACTIVE COURSE',
                    style: TextStyle(
                        color: Color.fromRGBO(255, 255, 255, 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
                const SizedBox(height: 2),
                Text(
                  _courseName.isNotEmpty ? _courseName : 'Daily Test',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
                if (_subcourseName.isNotEmpty)
                  Text(
                    _subcourseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color.fromRGBO(255, 255, 255, 0.8),
                        fontSize: 13),
                  ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.trending_up,
                size: 18, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
      {required String title,
      required String actionLabel,
      required VoidCallback onAction}) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800)),
        const Spacer(),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(actionLabel,
                  style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right,
                  size: 15, color: Color(0xFF2563EB)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _carousel() {
    return Column(
      children: [
        Listener(
          onPointerDown: (_) => _pauseCarousel(),
          onPointerUp: (_) => _scheduleResume(),
          onPointerCancel: (_) => _scheduleResume(),
          child: SizedBox(
            height: 372,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _slides.length,
              onPageChanged: (i) =>
                  setState(() => _slideIndex = i),
              itemBuilder: (ctx, i) {
                final s = _slides[i];
                final existing = _resultsById[s.model.id];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: DailyTestCard(
                    model: s.model,
                    slot: s.slot,
                    completed: s.completed,
                    scorePercent: existing?.score,
                    hasPremiumAccess:
                        _profile?.isPro ?? false,
                    demo: isDailyTestDemo(s.model),
                    indexInDay: s.indexInDay,
                    totalInDay: s.totalInDay,
                    todayKey: _dayKey,
                    onPrimaryPress: () => _openModel(s.model),
                    onSubscribePress: () =>
                        context.push('/subscription'),
                  ),
                );
              },
            ),
          ),
        ),
        if (_slides.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _slides.length; i++)
                Container(
                  width: i == _slideIndex ? 20 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _slideIndex
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _openHistoryActivity(DailyTestActivity a) {
    if (a.answers == null) {
      showToast(
          context,
          'Full details are not saved for this older attempt.',
          ToastVariant.info);
      return;
    }
    DailyTestModel? m;
    for (final x in _models) {
      if (x.id == a.modelId) {
        m = x;
        break;
      }
    }
    final model = m ??
        DailyTestModel(
          id: a.modelId,
          name: a.modelName,
          modelName: a.modelName,
          courseId: '',
          subcourseId: '',
          testDate: '',
          questions: const [],
          category: 'medium',
          perQuestionTimeSeconds: 30,
          negativeMarking: false,
          negativeMarkPercent: 0.2,
          marksPerQuestion: 1,
          passPercent: a.passPercent ?? 40,
          rules: const [],
          isPro: false,
          subscriptionType: 'off',
          price: 0,
          active: true,
          order: 0,
        );
    _goSummary(model,
        answers: a.answers, timeTakenSeconds: a.timeTakenSeconds);
  }

  Widget _emptyCard(String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151D2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark
                ? const Color(0xFF26314B)
                : const Color(0xFFE5E7EB)),
      ),
      child: Text(message,
          style:
              const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
    );
  }
}
