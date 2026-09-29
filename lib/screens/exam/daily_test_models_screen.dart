import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/server_clock.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/daily_test_card.dart';
import '../../widgets/subpage_header.dart';

/// All daily test models grouped by release date, newest first.
/// Mirrors app/daily-test/models.tsx.
class DailyTestModelsScreen extends StatefulWidget {
  const DailyTestModelsScreen({super.key});

  @override
  State<DailyTestModelsScreen> createState() => _DailyTestModelsScreenState();
}

class _DailyTestModelsScreenState extends State<DailyTestModelsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  UserProfile? _profile;
  String _subcourseName = '';
  List<DailyTestModel> _models = const [];
  Map<String, DailyTestResult> _resultsById = const {};
  String _dayKey = '';
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dayKey = todayDateKey();
    _load();
    // Recompute the list when the Kathmandu day rolls over at midnight.
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
      // The phone may have slept through midnight: re-sync the clock and
      // refetch only if the Kathmandu day key actually changed.
      _checkDayRollover();
    }
  }

  Future<void> _checkDayRollover() async {
    await ServerClock.ensureSynced();
    if (!mounted) return;
    final key = todayDateKey();
    if (key != _dayKey) {
      setState(() => _dayKey = key);
      _load();
    }
  }

  /// Milliseconds until the next Kathmandu midnight (+2s pad), computed in
  /// the same Kathmandu frame todayDateKey() uses — NOT device-local
  /// midnight, which is a different instant outside Nepal.
  int _msUntilKathmanduMidnight() {
    const offset = Duration(hours: 5, minutes: 45);
    final nowUtc = DateTime.now().toUtc();
    final kath = nowUtc.add(offset);
    // Interpret the Kathmandu wall-clock fields as UTC, then back out the
    // offset: the true UTC instant of the next Kathmandu midnight.
    final nextMidnightUtc =
        DateTime.utc(kath.year, kath.month, kath.day + 1).subtract(offset);
    return nextMidnightUtc.difference(nowUtc).inMilliseconds + 2000;
  }

  void _armMidnightTimer() {
    _midnightTimer?.cancel();
    _midnightTimer =
        Timer(Duration(milliseconds: _msUntilKathmanduMidnight()),
            () async {
      if (!mounted) return;
      await ServerClock.ensureSynced();
      if (!mounted) return;
      final key = todayDateKey();
      if (key != _dayKey) {
        setState(() => _dayKey = key);
        _load();
      }
      _armMidnightTimer();
    });
  }

  Future<void> _load({bool refreshing = false}) async {
    final uid = AuthService.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      context.go('/login');
      return;
    }
    // Server-corrected clock first: the day key — and therefore which models
    // count as "today" — must come from server time, not the device clock.
    await ServerClock.ensureSynced();
    if (!mounted) return;
    _dayKey = todayDateKey();
    if (!refreshing) setState(() => _loading = true);
    setState(() => _error = null);
    try {
      final profile = await fetchUserProfile(uid);
      if (!mounted) return;
      final subcourseId = profile?.subcourseId ?? '';
      if (subcourseId.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'no-course';
        });
        return;
      }
      // These three reads are independent — they go out together, not one
      // after another (that serial chain was what made the page feel slow).
      final fetched = await Future.wait([
        fetchDailyTestModels(subcourseId),
        fetchDailyTestResults(uid),
        _fetchSubcourseName(profile?.courseId ?? '', subcourseId),
      ]);
      final models = fetched[0] as List<DailyTestModel>;
      final results = fetched[1] as List<DailyTestResult>;
      final subcourseName = fetched[2] as String;
      // Newest attempt wins per model: the results list is newest-first, so
      // first-wins keeps the latest score.
      final byId = <String, DailyTestResult>{};
      for (final r in results) {
        byId.putIfAbsent(r.modelId, () => r);
      }
      final session = sessionDailyTestCompletions(uid);
      for (final e in session.entries) {
        byId[e.key] = e.value;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _profile = profile;
        _subcourseName = subcourseName;
        _models = models;
        _resultsById = byId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t load the daily tests. ${_cleanErr('$e')}';
      });
    }
  }

  /// Decorative subcourse name; failures are swallowed so the list still
  /// works when the catalogue read fails.
  Future<String> _fetchSubcourseName(
      String courseId, String subcourseId) async {
    try {
      final sdoc = await ExamRest.getDoc(
          'app_courses/$courseId/subcourses/$subcourseId');
      return '${sdoc?['name'] ?? sdoc?['title'] ?? ''}';
    } catch (_) {
      return '';
    }
  }

  /// Strips raw JSON/API dumps from an error so the UI never shows them.
  String _cleanErr(String raw) {
    var msg = raw.replaceFirst('Exception: ', '');
    final jsonStart = msg.indexOf('{');
    if (jsonStart >= 0) msg = msg.substring(0, jsonStart).trim();
    if (msg.length > 160) msg = '${msg.substring(0, 160).trim()}…';
    return msg.isEmpty ? 'Please try again.' : msg;
  }

  DailyTestSlot _slotFor(DailyTestModel m) {
    // DATE CHECK FIRST — a future-dated model with a saved result is still
    // "upcoming", never "completed" (mirrors models.tsx slotFor).
    if (m.testDate.compareTo(_dayKey) > 0) return DailyTestSlot.upcoming;
    if (m.testDate == _dayKey) return DailyTestSlot.today;
    if (_resultsById.containsKey(m.id)) return DailyTestSlot.completed;
    return DailyTestSlot.missed;
  }

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

  Future<void> _onTapModel(DailyTestModel m) async {
    final slot = _slotFor(m);
    final existing = _resultsById[m.id];
    if (existing != null) {
      _goSummary(m,
          answers: existing.answers,
          timeTakenSeconds: existing.timeTakenSeconds);
      return;
    }
    if (slot == DailyTestSlot.upcoming) {
      showToast(context,
          'This test unlocks on ${relativeDayLabel(m.testDate, _dayKey)}.',
          ToastVariant.info);
      return;
    }
    if (slot == DailyTestSlot.missed) {
      showToast(context, 'This test is closed — its date has passed.',
          ToastVariant.info);
      return;
    }
    if (m.isPro && !(_profile?.hasActivePremium ?? false)) {
      context.push('/subscription');
      return;
    }
    final ok = await showDailyTestRulesDialog(context, m);
    if (!mounted || !ok) return;
    context.push('/daily-test/${m.id}/quiz');
  }

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
            const SubpageHeader(title: 'All Models'),
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
    if (_error == 'no-course') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No course selected',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Choose a course to see its daily tests.',
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
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF6B7280))),
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
    if (_models.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No Daily Test has been added for this course yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
        ),
      );
    }

    // Group by release date, newest first. Unscheduled docs (empty testDate)
    // are never listed — mirrors models.tsx's `if (!model.testDate) continue`.
    final byDate = <String, List<DailyTestModel>>{};
    for (final m in _models) {
      if (m.testDate.isEmpty) continue;
      byDate.putIfAbsent(m.testDate, () => []).add(m);
    }
    final dates = byDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: () => _load(refreshing: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: dates.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _contextStrip(isDark),
            );
          }
          final date = dates[i - 1];
          final items = byDate[date]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dateHeading(date, items.length, isDark),
                const SizedBox(height: 10),
                ...items.map((m) {
                  final slot = _slotFor(m);
                  final existing = _resultsById[m.id];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DailyTestMiniCard(
                      model: m,
                      slot: slot,
                      completed: existing != null,
                      scorePercent: existing?.score,
                      hasPremiumAccess: _profile?.hasActivePremium ?? false,
                      todayKey: _dayKey,
                      onTap: () => _onTapModel(m),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _contextStrip(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151D2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? const Color(0xFF26314B)
                : const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.library_books_outlined,
              size: 18, color: Color(0xFF2563EB)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _subcourseName.isNotEmpty ? _subcourseName : 'Daily Tests',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Text('${_models.length} total',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _dateHeading(String date, int count, bool isDark) {
    final Color tone;
    if (date == _dayKey) {
      tone = const Color(0xFF2563EB);
    } else if (date.compareTo(_dayKey) > 0) {
      tone = const Color(0xFF6366F1);
    } else {
      tone = isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    }
    final rel = relativeDayLabel(date, _dayKey).toUpperCase();
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.08),
                border: Border.all(
                    color: tone.withValues(alpha: 0.25)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 12, color: tone),
                  const SizedBox(width: 5),
                  Text(rel,
                      style: TextStyle(
                          color: tone,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                formatDateKeyLong(date),
                style: TextStyle(
                    color: secondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Text(count == 1 ? '1 test' : '$count tests',
                style:
                    TextStyle(color: secondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 1,
          color: isDark
              ? const Color(0xFF1E293B)
              : const Color(0xFFE5E7EB),
        ),
      ],
    );
  }
}
