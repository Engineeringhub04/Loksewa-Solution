import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/daily_test_card.dart';
import '../../widgets/subpage_header.dart';

/// Daily test attempt history — mirrors app/daily-test/history.tsx.
///
/// On-device only: SharedPreferences key
/// `@loksewa/daily-test/recent-activities/{uid}`, max 20, newest first.
class DailyTestHistoryScreen extends StatefulWidget {
  const DailyTestHistoryScreen({super.key});

  @override
  State<DailyTestHistoryScreen> createState() =>
      _DailyTestHistoryScreenState();
}

class _DailyTestHistoryScreenState extends State<DailyTestHistoryScreen> {
  bool _loading = true;
  List<DailyTestActivity> _activities = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = AuthService.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      context.go('/login');
      return;
    }
    final activities = await getRecentDailyTestActivities(uid);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _activities = activities;
    });
  }

  void _openActivity(DailyTestActivity a) {
    if (a.answers == null) {
      showToast(context,
          'Full details are not saved for this older attempt.',
          ToastVariant.info);
      return;
    }
    final uri = Uri(
      path: '/daily-test/${a.modelId}/summary',
      queryParameters: {
        'answers': jsonEncode(a.answers),
        'timeTaken': '${a.timeTakenSeconds}',
      },
    );
    context.push(uri.toString());
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
            const SubpageHeader(title: 'Daily Test History'),
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
    if (_activities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 26),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: isDark
                          ? const Color(0xFF26314B)
                          : const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.history,
                        size: 26, color: Color(0xFF9CA3AF)),
                    SizedBox(height: 10),
                    Text('Your finished daily tests will show up here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B7280))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final attempts = _activities.length;
    final passed = _activities.where((a) => a.isPassed).length;
    final avg = attempts > 0
        ? (_activities.map((a) => a.score).reduce((a, b) => a + b) /
                attempts)
            .round()
        : 0;
    final best = _activities
        .map((a) => a.score)
        .reduce((a, b) => a > b ? a : b);
    final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
    final border =
        isDark ? const Color(0xFF26314B) : const Color(0xFFE5E7EB);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

    return RefreshIndicator(
      onRefresh: () async => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // Lifetime totals strip.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                    child: _lifeStat('Attempts', '$attempts',
                        Icons.layers_outlined,
                        const Color(0xFF2563EB), secondary)),
                Expanded(
                    child: _lifeStat('Passed', '$passed',
                        Icons.emoji_events,
                        const Color(0xFF16A34A), secondary)),
                Expanded(
                    child: _lifeStat('Average', '$avg%',
                        Icons.bar_chart,
                        const Color(0xFF2563EB), secondary)),
                Expanded(
                    child: _lifeStat('Best', '$best%',
                        Icons.local_fire_department,
                        const Color(0xFFD97706), secondary)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._activities.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DailyTestHistoryCard(
                  activity: a,
                  onTap: () => _openActivity(a),
                ),
              )),
        ],
      ),
    );
  }

  Widget _lifeStat(String label, String value, IconData icon,
      Color color, Color secondary) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 6),
        Text(value,
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 11, color: secondary)),
      ],
    );
  }
}
