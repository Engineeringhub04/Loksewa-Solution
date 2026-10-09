import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Syllabus — mirrors app/syllabus/index.tsx.
///
/// Premium blue-gradient "Active Course" banner, then one card per syllabus
/// level with a staggered fade/slide entrance (FadeInDown.delay(index*60)).
/// Reads `app_syllabusdata` where courseId == the user's enrolled course,
/// client filter `active !== false`, sorted by `order`.
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
  String _courseId = '';
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
      if (mounted) context.go('/login');
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
          final doc = await ExamRest.getDoc('app_courses/$courseId');
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
            subcourseName = '${doc?['name'] ?? doc?['title'] ?? ''}';
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
        _courseId = courseId;
        _courseName = courseName;
        _subcourseName = subcourseName;
        _items = items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'error';
      });
    }
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  void _openPdf(Map<String, dynamic> s) {
    final uri = '${s['pdfLink'] ?? ''}';
    if (uri.isEmpty) return;
    final id = '${s['id'] ?? ''}';
    // React: language === 'ne' ? nameNe || name : name || nameNe
    // (Flutter app is English-only → name first).
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
        // SubpageHeader paints behind the status bar itself
        // (React parity) — no top inset here or the header gets pushed down.
        top: false,
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
      return const PreloadingWidget(
        tinted: false,
        label: 'Loading Syllabus...',
        hint: 'Fetching your syllabus',
      );
    }
    if (_error != null) {
      final secondary =
          isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 46, color: secondary),
              const SizedBox(height: 14),
              const Text("Couldn't load syllabus",
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Please check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: secondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB)),
                child: const Text('Retry',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
    final divider =
        isDark ? const Color(0xFF263349) : const Color(0xFFE5EAF4);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final textPrimary =
        isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final primary =
        isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);

    // No course enrolled — steer to Course Setup (React EmptyState).
    if (_courseId.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 46, color: secondary),
              const SizedBox(height: 14),
              const Text('No course selected',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Choose a course to see its syllabus.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: secondary)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.push('/course-setup'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB)),
                icon: const Icon(Icons.arrow_forward,
                    color: Colors.white, size: 18),
                label: const Text('Select a course',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator.adaptive(
      onRefresh: () async => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          // Active Course banner — premium blue gradient.
          _activeCourseBanner(),
          const SizedBox(height: 20),
          // Section row: title + count pill.
          Row(
            children: [
              Text('Available Syllabus',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: textPrimary)),
              const SizedBox(width: 8),
              Container(
                constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 22),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text('${_items.length}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.description_outlined,
                        size: 46, color: secondary),
                    const SizedBox(height: 12),
                    const Text('No syllabus available yet',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      'Syllabus papers for your course will appear here soon.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: secondary),
                    ),
                  ],
                ),
              ),
            )
          else
            for (var i = 0; i < _items.length; i++)
              Padding(
                padding: EdgeInsets.only(
                    bottom: i == _items.length - 1 ? 0 : 12),
                child: _Entrance(
                  delayMs: i * 60,
                  child: _card(_items[i], surface, divider,
                      secondary, textPrimary, primary),
                ),
              ),
        ],
      ),
    );
  }

  /// Premium blue-gradient "Active Course" banner (React activeCard).
  Widget _activeCourseBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2563EB),
            Color(0xFF1D4ED8),
            Color(0xFF0B1F5B)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Glow circle.
            Positioned(
              top: -30,
              right: -20,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.school,
                      size: 26, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text('Active Course',
                          style: TextStyle(
                              color: Color(0xC6FFFFFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3)),
                      const SizedBox(height: 3),
                      Text(
                        _courseName.isNotEmpty
                            ? _courseName
                            : '—',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
                      if (_subcourseName.isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 2),
                          child: Text(_subcourseName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Color(0xB8FFFFFF),
                                  fontSize: 13)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.trending_up,
                      size: 22, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(
      Map<String, dynamic> s,
      Color surface,
      Color divider,
      Color secondary,
      Color textPrimary,
      Color primary) {
    final isPro = s['isPro'] == true;
    final name = '${s['name'] ?? s['nameNe'] ?? 'Syllabus'}';
    final hasPdf = '${s['pdfLink'] ?? ''}'.isNotEmpty;
    final badgeBg =
        isPro ? const Color(0x22F59E0B) : const Color(0x2222C55E);
    final badgeFg =
        isPro ? const Color(0xFFD97706) : const Color(0xFF16A34A);
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: hasPdf ? () => _openPdf(s) : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: divider, width: 0.5),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.description,
                    size: 24, color: primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimary)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius:
                                BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                  isPro
                                      ? Icons.star
                                      : Icons.check_circle,
                                  size: 11,
                                  color: badgeFg),
                              const SizedBox(width: 4),
                              Text(isPro ? 'PRO' : 'FREE',
                                  style: TextStyle(
                                      color: badgeFg,
                                      fontSize: 11,
                                      fontWeight:
                                          FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('Tap to open PDF',
                            style: TextStyle(
                                fontSize: 12,
                                color: secondary)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right,
                  size: 20, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Staggered entrance — mirrors `FadeInDown.delay(i * 60).springify()`.
class _Entrance extends StatefulWidget {
  final int delayMs;
  final Widget child;

  const _Entrance({required this.delayMs, required this.child});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _opacity;
  late final Animation<double> _dy;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _opacity = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _dy = Tween<double>(begin: 24, end: 0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.translate(
            offset: Offset(0, _dy.value), child: child),
      ),
      child: widget.child,
    );
  }
}
