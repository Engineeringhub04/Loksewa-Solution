import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/firestore_rest.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

/// Course + subcourse selector — mirrors app/course-setup.tsx exactly.
///
/// - Hand-rolled curved gradient header (26px bottom radius, like React's own
///   header on this screen — NOT the shared SubpageHeader), with a working
///   theme toggle. The system status bar is tinted brand-blue via
///   [AnnotatedRegion] so no light band sits above the header.
/// - Courses from `app_courses` sorted by `order` (client-side, like React).
/// - Subcourses from `app_courses/{courseId}/subcourses`, falling back to the
///   legacy flat `app_subcourses` collection filtered by `courseId`.
/// - Blue = currently-enrolled selection, red = a NEW pick that differs.
/// - Save writes users/{uid} (merge): courseId, subcourseId,
///   courseSetupComplete — with the user's ID token (anonymous reads/writes
///   are rejected by the Firestore rules, which is why the course list used
///   to come back empty).
class CourseSetupScreen extends StatefulWidget {
  final String mode; // 'update' | 'initial'

  const CourseSetupScreen({super.key, this.mode = 'initial'});

  @override
  State<CourseSetupScreen> createState() => _CourseSetupScreenState();
}

class _CourseSetupScreenState extends State<CourseSetupScreen> {
  static const _courseCol = 'app_courses';
  static const _legacySubCol = 'app_subcourses';

  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _subcourses = [];
  String? _selectedCourse;
  String? _selectedSubcourse;
  String? _savedCourseId;
  String? _savedSubcourseId;
  bool _loadingCourses = true;
  bool _loadingSub = false;
  bool _subcourseError = false;
  bool _saving = false;

  bool get _updateMode => widget.mode == 'update';
  bool get _canSave =>
      _selectedCourse != null && _selectedSubcourse != null && !_saving;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _loadSaved();
    await _loadCourses();
  }

  Future<String> _token() => AuthService.getValidIdToken();

  /// Seeds the working selection from the user's enrolled course, like React's
  /// applySaved(): only fills in while nothing is chosen yet, so a late fetch
  /// never overwrites a tap the user already made.
  Future<void> _loadSaved() async {
    try {
      final user = AuthService.currentUser;
      if (user == null) return;
      final doc = await FirestoreRest.getDocument('users/${user.uid}',
          idToken: await _token());
      if (!mounted) return;
      final cid = _str(doc?['courseId']);
      final scid = _str(doc?['subcourseId']);
      if (cid == null) return;
      setState(() {
        _savedCourseId = cid;
        _savedSubcourseId = scid;
        _selectedCourse ??= cid;
        _selectedSubcourse ??= scid;
      });
      if (_selectedCourse != null) {
        await _loadSubcourses(_selectedCourse!);
      }
    } catch (_) {
      // Non-fatal — the screen still works as a fresh setup.
    }
  }

  String? _str(dynamic v) =>
      (v is String && v.isNotEmpty) ? v : null;

  int _ord(Map<String, dynamic> d) {
    final o = d['order'];
    return o is num ? o.toInt() : 0;
  }

  /// Mirrors React's fetchCourses: one direct read, client-side order sort.
  /// Pull-to-refresh re-runs this; it never shows the full-page spinner.
  Future<void> _loadCourses() async {
    try {
      final docs = await FirestoreRest.listDocuments(_courseCol,
          idToken: await _token(), pageSize: 100);
      docs.sort((a, b) => _ord(a).compareTo(_ord(b)));
      if (!mounted) return;
      setState(() {
        _courses = docs;
        _loadingCourses = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCourses = false);
      showToast(context, 'Failed to load courses', ToastVariant.error);
    }
  }

  Future<void> _loadSubcourses(String courseId) async {
    setState(() {
      _loadingSub = true;
      _subcourseError = false;
    });
    try {
      final token = await _token();
      var docs = await FirestoreRest.listDocuments(
          '$_courseCol/$courseId/subcourses',
          idToken: token,
          pageSize: 200);
      if (docs.isEmpty) {
        // Legacy layout: flat `app_subcourses` filtered client-side.
        try {
          final legacy = await FirestoreRest.listDocuments(_legacySubCol,
              idToken: token, pageSize: 200);
          docs = legacy
              .where((d) => d['courseId'] == courseId)
              .toList();
        } catch (_) {
          // keep empty — the error state below explains
        }
      }
      docs.sort((a, b) => _ord(a).compareTo(_ord(b)));
      if (!mounted) return;
      setState(() {
        _subcourses = docs;
        _loadingSub = false;
        _subcourseError = docs.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSub = false;
        _subcourseError = true;
      });
      showToast(context, 'Failed to load subcourses', ToastVariant.error);
    }
  }

  /// The ONLY place the subcourse selection is reset, like React's
  /// handleSelectCourse: tapping back onto the enrolled course restores its
  /// subcourse instead of wiping it.
  void _selectCourse(String id) {
    if (id == _selectedCourse) return;
    setState(() {
      _selectedCourse = id;
      _selectedSubcourse =
          (id == _savedCourseId) ? _savedSubcourseId : null;
      _subcourses = [];
      _subcourseError = false;
    });
    _loadSubcourses(id);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final user = AuthService.currentUser;
    if (user == null) {
      context.go('/login');
      return;
    }
    setState(() => _saving = true);
    try {
      await FirestoreRest.setDocument(
        'users/${user.uid}',
        {
          'courseId': _selectedCourse,
          'subcourseId': _selectedSubcourse,
          'courseSetupComplete': true,
        },
        idToken: await _token(),
        merge: true,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (_updateMode) {
        showToast(context, 'Course updated successfully', ToastVariant.success);
        context.pop();
      } else {
        showToast(context, 'Course setup complete', ToastVariant.success);
        context.go('/');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, 'Failed to save. Please try again.', ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Brand-blue status bar so no light band sits above the header; the
      // header gradient starts immediately below it, like React's
      // edge-to-edge header (paddingTop: insets.top + 12).
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF2563EB),
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: pal.background,
        body: Column(
          children: [
            _header(topPad),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadCourses,
                color: const Color(0xFF2563EB),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.fromLTRB(20, 24, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Entrance(
                        delayMs: 0,
                        slide: _Slide.up,
                        child: _titleSection(pal),
                      ),
                      const SizedBox(height: 24),
                      _Entrance(
                        delayMs: 200,
                        slide: _Slide.down,
                        child: _courseSection(pal),
                      ),
                      if (_selectedCourse != null) ...[
                        const SizedBox(height: 24),
                        _Entrance(
                          delayMs: 0,
                          slide: _Slide.down,
                          child: _subcourseSection(pal),
                        ),
                      ],
                      if (_savedCourseId != null) ...[
                        const SizedBox(height: 24),
                        _Entrance(
                          delayMs: 0,
                          slide: _Slide.none,
                          child: _legend(pal),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _bottomBar(pal, bottomPad),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header(double topPad) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF2563EB),
            Color(0xFF1D4ED8),
            Color(0xFF0B1F5B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
      ),
      padding: EdgeInsets.only(top: topPad + 12, bottom: 20),
      child: _Entrance(
        delayMs: 0,
        slide: _Slide.none,
        durationMs: 400,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Update mode: back button. Initial mode: static school icon.
              _updateMode
                  ? GestureDetector(
                      onTap: () => context.pop(),
                      child: _iconBox(const Icon(Icons.arrow_back,
                          size: 20, color: Colors.white)),
                    )
                  : _iconBox(const Icon(Icons.school,
                      size: 22, color: Colors.white)),
              Expanded(
                child: Text(
                  _updateMode ? 'Update Your Course' : 'Setup Your Course',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _themeToggle(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBox(Widget child) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _themeToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => ThemeService.toggle(context),
      child: _iconBox(Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 20,
        color: Colors.white,
      )),
    );
  }

  // ------------------------------------------------------------- sections

  Widget _titleSection(ExpoPalette pal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _updateMode ? 'Update Your Course' : 'Setup Your New Course',
          style: TextStyle(
            color: pal.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _updateMode
              ? 'Change your selected course or subcourse anytime'
              : 'Choose a course to start your learning journey',
          style: TextStyle(color: pal.textSecondary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _sectionHeader(ExpoPalette pal,
      {required IconData icon,
      required Color iconColor,
      required String title}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: pal.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              color: pal.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _courseSection(ExpoPalette pal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(pal,
            icon: Icons.school,
            iconColor: const Color(0xFF2563EB),
            title: 'Select Course'),
        if (_loadingCourses)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF2563EB)),
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (int i = 0; i < _courses.length; i++)
                _Entrance(
                  delayMs: 250 + i * 80,
                  durationMs: 350,
                  slide: _Slide.down,
                  child: _chip(
                    pal,
                    label: _label(_courses[i]),
                    selected: _courses[i]['id'] == _selectedCourse,
                    color: const Color(0xFF2563EB),
                    onTap: () =>
                        _selectCourse('${_courses[i]['id']}'),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _subcourseSection(ExpoPalette pal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(pal,
            icon: Icons.book,
            iconColor: const Color(0xFFDC2626),
            title: 'Select Subcourse'),
        if (_loadingSub)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(
                  color: Color(0xFFDC2626)),
            ),
          )
        else if (_subcourseError)
          _Entrance(
            delayMs: 0,
            durationMs: 300,
            slide: _Slide.none,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 20, color: Color(0xFFDC2626)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No subcourses found for this course yet. Please contact support or try again later.',
                      style: TextStyle(
                        color: Color(0xFF991B1B),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (int i = 0; i < _subcourses.length; i++)
                _Entrance(
                  delayMs: i * 80,
                  durationMs: 350,
                  slide: _Slide.down,
                  child: Builder(builder: (context) {
                    final sub = _subcourses[i];
                    final isSelected =
                        sub['id'] == _selectedSubcourse;
                    // Blue = the subcourse you're already enrolled in.
                    // Red  = a NEW pick that differs from what's saved.
                    final isEnrolled = isSelected &&
                        sub['id'] == _savedSubcourseId &&
                        _selectedCourse == _savedCourseId;
                    return _chip(
                      pal,
                      label: _subLabel(sub),
                      selected: isSelected,
                      color: isEnrolled
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFDC2626),
                      onTap: () => setState(() =>
                          _selectedSubcourse = '${sub['id']}'),
                    );
                  }),
                ),
            ],
          ),
      ],
    );
  }

  Widget _legend(ExpoPalette pal) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pal.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _legendItem(pal,
              color: const Color(0xFF2563EB),
              label: 'Currently enrolled'),
          const SizedBox(width: 16),
          _legendItem(pal,
              color: const Color(0xFFDC2626),
              label: 'New selection'),
        ],
      ),
    );
  }

  Widget _legendItem(ExpoPalette pal,
      {required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: pal.textSecondary, fontSize: 12)),
      ],
    );
  }

  Widget _chip(ExpoPalette pal,
      {required String label,
      required bool selected,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color : pal.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? color : pal.border, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_circle,
                  size: 18, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.w500,
                color:
                    selected ? Colors.white : pal.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(Map<String, dynamic> d) {
    final n = d['name'];
    if (n is String && n.isNotEmpty) return n;
    return d['id']?.toString() ?? 'Course';
  }

  String _subLabel(Map<String, dynamic> d) {
    final n = _label(d);
    final level = d['level'];
    if (level is String && level.isNotEmpty) return '$n ($level)';
    return n;
  }

  // ------------------------------------------------------------ bottom bar

  Widget _bottomBar(ExpoPalette pal, double bottomPad) {
    return Container(
      padding:
          EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 16),
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border(top: BorderSide(color: pal.divider)),
      ),
      child: _Entrance(
        delayMs: 0,
        slide: _Slide.up,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _canSave ? _save : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              disabledBackgroundColor: const Color(0xFF9CA3AF),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 4,
              shadowColor:
                  const Color(0xFF2563EB).withValues(alpha: 0.3),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(
                    _updateMode ? 'Update Course' : 'Save Course',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
          ),
        ),
      ),
    );
  }
}

enum _Slide { none, down, up }

/// Entrance animation mirroring react-native-reanimated's FadeIn / FadeInDown
/// / FadeInUp used across the Expo app.
class _Entrance extends StatefulWidget {
  final int delayMs;
  final int durationMs;
  final _Slide slide;
  final Widget child;

  const _Entrance({
    required this.delayMs,
    required this.child,
    this.durationMs = 400,
    this.slide = _Slide.none,
  });

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  bool _go = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _go = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final offset = switch (widget.slide) {
      _Slide.down => const Offset(0, -0.12),
      _Slide.up => const Offset(0, 0.12),
      _Slide.none => Offset.zero,
    };
    return AnimatedOpacity(
      opacity: _go ? 1 : 0,
      duration: Duration(milliseconds: widget.durationMs),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _go ? Offset.zero : offset,
        duration: Duration(milliseconds: widget.durationMs),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
