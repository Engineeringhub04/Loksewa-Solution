import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/subpage_header.dart';

/// Syllabus — mirrors app/syllabus/index.tsx.
///
/// Reads `app_syllabusdata` where courseId == the user's enrolled course,
/// filters client-side `active !== false`, sorts by `order`.
///
/// Tap ALWAYS opens the PDF — no paywall gate.
class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({super.key});

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  bool _loading = true;
  String? _error;
  String _courseName = '';
  String _subcourseName = '';
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = AuthService.currentUser;
    if (user == null) {
      context.go('/login');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await fetchUserProfile(user.uid);
      final courseId = profile?.courseId ?? '';
      final subcourseId = profile?.subcourseId ?? '';
      String courseName = '';
      String subcourseName = '';
      if (courseId.isNotEmpty) {
        try {
          final doc =
              await ExamRest.getDoc('app_courses/$courseId');
          courseName = '${doc?['name'] ?? doc?['title'] ?? ''}';
        } catch (_) {}
      }
      if (courseId.isNotEmpty && subcourseId.isNotEmpty) {
        try {
          final doc = await ExamRest.getDoc(
              'app_courses/$courseId/subcourses/$subcourseId');
          subcourseName = '${doc?['name'] ?? doc?['title'] ?? ''}';
        } catch (_) {
          try {
            final doc =
                await ExamRest.getDoc('app_subcourses/$subcourseId');
            subcourseName =
                '${doc?['name'] ?? doc?['title'] ?? ''}';
          } catch (_) {}
        }
      }

      List<Map<String, dynamic>> items = const [];
      if (courseId.isNotEmpty) {
        final all = await ExamRest.runQuery('app_syllabusdata',
            where: ExamRest.fieldFilter('courseId', 'EQUAL', courseId),
            limit: 200);
        items = all
            .where((s) => s['active'] != false)
            .toList()
          ..sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _courseName = courseName;
        _subcourseName = subcourseName;
        _items = items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load syllabus.';
      });
    }
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  void _openPdf(Map<String, dynamic> s) {
    final uri = '${s['pdfLink'] ?? ''}';
    if (uri.isEmpty) return;
    final id = '${s['id'] ?? ''}';
    final title = '${s['name'] ?? s['nameNe'] ?? 'Syllabus'}';
    context.push(Uri(
      path: '/pdf/${Uri.encodeComponent(id)}',
      queryParameters: {'uri': uri, 'title': title},
    ).toString());
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
            const SubpageHeader(title: 'Syllabus'),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB)),
              child: const Text('Retry',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
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
          // Active-course banner.
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ACTIVE COURSE',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6)),
                      const SizedBox(height: 4),
                      Text(
                        _courseName.isNotEmpty
                            ? _courseName
                            : 'No course selected',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800),
                      ),
                      if (_subcourseName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(_subcourseName,
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13)),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${_items.length} PDF${_items.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'No syllabus PDFs have been added for your course yet. Please check back soon.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 14, color: secondary),
                ),
              ),
            )
          else
            ..._items.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _card(s, surface, border, secondary, isDark),
                )),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> s, Color surface, Color border,
      Color secondary, bool isDark) {
    final isPro = s['isPro'] == true;
    final name = '${s['name'] ?? s['nameNe'] ?? 'Syllabus'}';
    final nameNe = '${s['nameNe'] ?? ''}';
    final hasPdf = '${s['pdfLink'] ?? ''}'.isNotEmpty;
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: hasPdf ? () => _openPdf(s) : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.picture_as_pdf,
                    size: 26, color: Color(0xFFDC2626)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    if (nameNe.isNotEmpty && nameNe != name)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(nameNe,
                            style: TextStyle(
                                fontSize: 12, color: secondary)),
                      ),
                    const SizedBox(height: 6),
                    isPro
                        ? Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0x22F59E0B),
                              borderRadius:
                                  BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star,
                                    size: 11,
                                    color: Color(0xFFD97706)),
                                SizedBox(width: 3),
                                Text('Pro',
                                    style: TextStyle(
                                        color:
                                            Color(0xFFD97706),
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight.w700)),
                              ],
                            ),
                          )
                        : Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0x2222C55E),
                              borderRadius:
                                  BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle,
                                    size: 11,
                                    color: Color(0xFF16A34A)),
                                SizedBox(width: 3),
                                Text('Free',
                                    style: TextStyle(
                                        color:
                                            Color(0xFF16A34A),
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight.w700)),
                              ],
                            ),
                          ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20,
                  color:
                      isDark ? const Color(0xFF475569) : secondary),
            ],
          ),
        ),
      ),
    );
  }
}
