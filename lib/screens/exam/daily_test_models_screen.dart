import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
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

class _DailyTestModelsScreenState extends State<DailyTestModelsScreen> {
  bool _loading = true;
  String? _error;
  UserProfile? _profile;
  String _subcourseName = '';
  List<DailyTestModel> _models = const [];
  Map<String, DailyTestResult> _resultsById = const {};
  String _dayKey = '';

  @override
  void initState() {
    super.initState();
    _dayKey = todayDateKey();
    _load();
  }

  Future<void> _load({bool refreshing = false}) async {
    final uid = AuthService.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      context.go('/login');
      return;
    }
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
      final models = await fetchDailyTestModels(subcourseId);
      final results = await fetchDailyTestResults(uid);
      final session = sessionDailyTestCompletions(uid);
      final byId = {for (final r in results) r.modelId: r};
      for (final e in session.entries) {
        byId[e.key] = e.value;
      }
      String subcourseName = '';
      try {
        final sdoc = await ExamRest.getDoc(
            'app_courses/${profile?.courseId}/subcourses/$subcourseId');
        subcourseName = '${sdoc?['name'] ?? sdoc?['title'] ?? ''}';
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _loading = false;
        _profile = profile;
        _subcourseName = subcourseName;
        _models = models;
        _resultsById = byId;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Please check your connection and try again.';
      });
    }
  }

  DailyTestSlot _slotFor(DailyTestModel m) {
    if (_resultsById.containsKey(m.id)) return DailyTestSlot.completed;
    if (m.testDate.compareTo(_dayKey) > 0) return DailyTestSlot.upcoming;
    if (m.testDate == _dayKey) return DailyTestSlot.today;
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
    if (m.isPro && !(_profile?.isPro ?? false)) {
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

    // Group by release date, newest first.
    final byDate = <String, List<DailyTestModel>>{};
    for (final m in _models) {
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
                      hasPremiumAccess: _profile?.isPro ?? false,
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
