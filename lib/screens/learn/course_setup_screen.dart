import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_rest.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/app_toast.dart';

/// Course + subcourse selector. Mirrors app/course-setup.tsx exactly:
/// - Courses from `app_courses` (NOT `courses`), sorted by `order`.
/// - Subcourses from `app_courses/{courseId}/subcourses`, with the legacy
///   flat `app_subcourses` collection as fallback.
/// - Currently-enrolled selections shown in blue, new selections in red.
/// - Save writes users/{uid} (merge): courseId, subcourseId, courseSetupComplete.
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
  String? _enrolledCourse;
  String? _enrolledSubcourse;
  bool _loadingCourses = true;
  bool _loadingSubcourses = false;
  bool _saving = false;
  String? _subcourseError;

  bool get _updateMode => widget.mode == 'update';

  bool _canSave() =>
      _selectedCourse != null && _selectedSubcourse != null && !_saving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _loadSaved();
    await _loadCourses();
  }

  Future<void> _loadSaved() async {
    try {
      final user = AuthService.currentUser;
      if (user == null) return;
      final doc =
          await FirestoreRest.getDocument('users/${user.uid}');
      if (!mounted) return;
      if (doc == null) return;
      final courseId = doc['courseId'];
      final subcourseId = doc['subcourseId'];
      setState(() {
        _selectedCourse = courseId is String && courseId.isNotEmpty ? courseId : null;
        _selectedSubcourse =
            subcourseId is String && subcourseId.isNotEmpty ? subcourseId : null;
        _enrolledCourse = _selectedCourse;
        _enrolledSubcourse = _selectedSubcourse;
      });
      if (_selectedCourse != null) {
        await _loadSubcourses(_selectedCourse!);
      }
    } catch (_) {
      // non-fatal: user can still pick manually
    }
  }

  Future<void> _loadCourses() async {
    setState(() => _loadingCourses = true);
    try {
      final docs = await FirestoreRest.listDocuments(_courseCol,
          pageSize: 100);
      final list = docs
          .where((d) => d['active'] != false)
          .toList()
        ..sort((a, b) => _ord(a).compareTo(_ord(b)));
      if (!mounted) return;
      setState(() {
        _courses = list;
        _loadingCourses = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCourses = false);
      showToast(context, 'Could not load courses. Please try again.',
          ToastVariant.error);
    }
  }

  int _ord(Map<String, dynamic> d) {
    final o = d['order'];
    return o is num ? o.toInt() : 999999;
  }

  Future<void> _loadSubcourses(String courseId) async {
    setState(() {
      _loadingSubcourses = true;
      _subcourseError = null;
    });
    try {
      // Modern layout first: app_courses/{courseId}/subcourses.
      var docs = await FirestoreRest.listDocuments(
          '$_courseCol/$courseId/subcourses',
          pageSize: 200);
      var list = docs
          .where((d) => d['active'] != false)
          .toList()
        ..sort((a, b) => _ord(a).compareTo(_ord(b)));

      if (list.isEmpty) {
        // Legacy layout: flat `app_subcourses` filtered client-side.
        try {
          final legacy = await FirestoreRest.listDocuments(_legacySubCol,
              pageSize: 200);
          list = legacy
              .where((d) =>
                  d['active'] != false && d['courseId'] == courseId)
              .toList()
            ..sort((a, b) => _ord(a).compareTo(_ord(b)));
        } catch (_) {
          // ignore — keep empty, the error below explains
        }
      }

      if (!mounted) return;
      setState(() {
        _subcourses = list;
        _loadingSubcourses = false;
        _subcourseError =
            list.isEmpty ? 'No subcourses found for this course yet.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSubcourses = false;
        _subcourseError = 'Could not load subcourses. Please try again.';
      });
    }
  }

  void _selectCourse(String id) {
    if (id == _selectedCourse) return;
    setState(() {
      _selectedCourse = id;
      _selectedSubcourse = null;
      _subcourses = [];
      _subcourseError = null;
    });
    _loadSubcourses(id);
  }

  Future<void> _save() async {
    if (!_canSave()) return;
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
        idToken: '',
        merge: true,
      );
      if (!mounted) return;
      showToast(
          context,
          _updateMode ? 'Course updated.' : 'Course saved.',
          ToastVariant.success);
      if (_updateMode) {
        context.pop();
      } else {
        context.go('/');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, 'Could not save. Please try again.', ToastVariant.error);
    }
  }

  String _courseLabel(Map<String, dynamic> d) {
    final n = d['name'];
    if (n is String && n.isNotEmpty) return n;
    return d['id']?.toString() ?? 'Course';
  }

  String _subLabel(Map<String, dynamic> d) {
    final t = d['title'] ?? d['name'];
    if (t is String && t.isNotEmpty) return t;
    return d['id']?.toString() ?? 'Subcourse';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            SubpageHeader(
              title: _updateMode ? 'Update Course' : 'Select Your Course',
              showBack: _updateMode,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Courses section
                    const Text('Choose Course',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 12),
                    if (_loadingCourses)
                      const Center(
                          child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(),
                      ))
                    else if (_courses.isEmpty)
                      _emptyCard('No courses found.')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _courses
                            .map((c) => _Chip(
                                  label: _courseLabel(c),
                                  enrolled: c['id'] == _enrolledCourse,
                                  selected: c['id'] == _selectedCourse,
                                  onTap: () => _selectCourse('${c['id']}'),
                                ))
                            .toList(),
                      ),

                    const SizedBox(height: 24),

                    // Subcourses section
                    const Text('Choose Subcourse',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 12),
                    if (_selectedCourse == null)
                      _emptyCard('Select a course first to see its subcourses.')
                    else if (_loadingSubcourses)
                      const Center(
                          child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(),
                      ))
                    else if (_subcourseError != null)
                      _emptyCard(_subcourseError!)
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _subcourses
                            .map((s) => _Chip(
                                  label: _subLabel(s),
                                  enrolled: s['id'] == _enrolledSubcourse,
                                  selected: s['id'] == _selectedSubcourse,
                                  red: true,
                                  onTap: () => setState(() =>
                                      _selectedSubcourse = '${s['id']}'),
                                ))
                            .toList(),
                      ),

                    const SizedBox(height: 24),

                    // Legend
                    if (_enrolledCourse != null)
                      const Row(
                        children: [
                          _LegendDot(
                              color: Color(0xFF2563EB),
                              label: 'Currently enrolled'),
                          SizedBox(width: 16),
                          _LegendDot(
                              color: Color(0xFFDC2626), label: 'New selection'),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canSave() ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    disabledBackgroundColor: const Color(0xFF93C5FD),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(
                          _updateMode ? 'Update Course' : 'Save and Continue',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Text(message,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool enrolled;
  final bool selected;
  final bool red;
  final VoidCallback onTap;

  const _Chip(
      {required this.label,
      required this.enrolled,
      required this.selected,
      required this.onTap,
      this.red = false});

  @override
  Widget build(BuildContext context) {
    // Blue = already-enrolled selection, red = new selection — mirrors RN.
    final color =
        red ? const Color(0xFFDC2626) : const Color(0xFF2563EB);
    final isOn = selected || enrolled;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOn ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isOn ? color : const Color(0xFFD1D5DB), width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isOn ? Colors.white : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
      ],
    );
  }
}
