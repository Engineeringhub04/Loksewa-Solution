import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Course setup — mirrors app/course-setup.tsx.
/// Shown after login/signup when the user has no course yet, and from
/// Profile → My Course in update mode (?mode=update).
/// Select Course (blue) → Subcourse (red) → Save.
class CourseSetupScreen extends StatefulWidget {
  final String? mode;
  const CourseSetupScreen({super.key, this.mode});

  @override
  State<CourseSetupScreen> createState() => _CourseSetupScreenState();
}

class _CourseSetupScreenState extends State<CourseSetupScreen> {
  bool get _isUpdate => widget.mode == 'update';

  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _subcourses = [];
  String? _selectedCourse;
  String? _selectedSubcourse;
  String? _savedCourseId;
  String? _savedSubcourseId;
  bool _loadingCourses = true;
  bool _loadingSub = false;
  bool _subError = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCourses();
    _loadSaved();
  }

  Future<void> _loadCourses() async {
    setState(() => _loadingCourses = true);
    try {
      final token = await AuthService.getValidIdToken();
      final docs = await FirestoreRest.listDocuments('courses',
          idToken: token, pageSize: 50);
      docs.sort(
          (a, b) => _num(a['order']).compareTo(_num(b['order'])));
      if (mounted) setState(() => _courses = docs);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load courses')));
      }
    } finally {
      if (mounted) setState(() => _loadingCourses = false);
    }
  }

  Future<void> _loadSaved() async {
    final user = AuthService.currentUser;
    if (user == null) return;
    try {
      final token = await AuthService.getValidIdToken();
      final userDoc = await FirestoreRest.getDocument('users/${user.uid}',
          idToken: token);
      final courseId = userDoc?['courseId'] as String?;
      final subcourseId = userDoc?['subcourseId'] as String?;
      if (courseId == null || !mounted) return;
      setState(() {
        _savedCourseId = courseId;
        _savedSubcourseId = subcourseId;
        _selectedCourse ??= courseId;
        _selectedSubcourse ??= subcourseId;
      });
      _loadSubcourses(courseId);
    } catch (_) {}
  }

  Future<void> _loadSubcourses(String courseId) async {
    setState(() {
      _loadingSub = true;
      _subError = false;
      _subcourses = [];
    });
    try {
      final token = await AuthService.getValidIdToken();
      var docs = await FirestoreRest.listDocuments(
          'courses/$courseId/subcourses',
          idToken: token,
          pageSize: 100);
      if (docs.isEmpty) {
        // Legacy flat collection fallback, filtered client-side.
        final legacy = await FirestoreRest.listDocuments('app_subcourses',
            idToken: token, pageSize: 100);
        docs =
            legacy.where((d) => d['courseId'] == courseId).toList();
      }
      docs.sort(
          (a, b) => _num(a['order']).compareTo(_num(b['order'])));
      if (mounted) setState(() => _subcourses = docs);
      if (docs.isEmpty && mounted) setState(() => _subError = true);
    } catch (_) {
      if (mounted) setState(() => _subError = true);
    } finally {
      if (mounted) setState(() => _loadingSub = false);
    }
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  void _selectCourse(String courseId) {
    if (courseId == _selectedCourse) return;
    setState(() {
      _selectedCourse = courseId;
      _selectedSubcourse =
          courseId == _savedCourseId ? _savedSubcourseId : null;
    });
    _loadSubcourses(courseId);
  }

  Future<void> _save() async {
    final user = AuthService.currentUser;
    if (user == null || _selectedCourse == null || _selectedSubcourse == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final token = await AuthService.getValidIdToken();
      await FirestoreRest.setDocument(
        'users/${user.uid}',
        {
          'courseId': _selectedCourse!,
          'subcourseId': _selectedSubcourse!,
          'courseSetupComplete': true,
        },
        idToken: token,
        merge: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isUpdate
              ? 'Course updated successfully'
              : 'Course setup complete')));
      if (_isUpdate) {
        context.pop();
      } else {
        context.go('/');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 150,
            pinned: true,
            automaticallyImplyLeading: _isUpdate,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.navy, AppColors.deepNavy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                            _isUpdate
                                ? 'Update Your Course'
                                : 'Setup Your Course',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                        Text(
                            _isUpdate
                                ? 'Change your course or subcourse anytime'
                                : 'Choose a course to start learning',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                      Icons.school, 'Select Course', Colors.blue),
                  const SizedBox(height: 10),
                  _loadingCourses
                      ? const Center(child: CircularProgressIndicator())
                      : Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _courses.map((c) {
                            final id = c['id'] as String;
                            final selected = _selectedCourse == id;
                            return ChoiceChip(
                              label: Text((c['name'] as String?) ?? ''),
                              selected: selected,
                              selectedColor: Colors.blue,
                              labelStyle: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.black87),
                              avatar: selected
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.white, size: 18)
                                  : null,
                              onSelected: (_) => _selectCourse(id),
                            );
                          }).toList(),
                        ),
                  if (_selectedCourse != null) ...[
                    const SizedBox(height: 24),
                    _sectionHeader(
                        Icons.book, 'Select Subcourse', Colors.red),
                    const SizedBox(height: 10),
                    if (_loadingSub)
                      const Center(child: CircularProgressIndicator())
                    else if (_subError)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.red.shade200),
                        ),
                        child: const Text(
                          'No subcourses found for this course yet. Please contact support or try again later.',
                          style: TextStyle(color: Colors.red),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _subcourses.map((s) {
                          final id = s['id'] as String;
                          final selected = _selectedSubcourse == id;
                          final isEnrolled = selected &&
                              id == _savedSubcourseId &&
                              _selectedCourse == _savedCourseId;
                          return ChoiceChip(
                            label: Text(
                                '${(s['name'] as String?) ?? ''} (${(s['level'] as String?) ?? ''})'),
                            selected: selected,
                            selectedColor:
                                isEnrolled ? Colors.blue : Colors.red,
                            labelStyle: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : Colors.black87),
                            avatar: selected
                                ? const Icon(Icons.check_circle,
                                    color: Colors.white, size: 18)
                                : null,
                            onSelected: (_) => setState(
                                () => _selectedSubcourse = id),
                          );
                        }).toList(),
                      ),
                  ],
                  if (_savedCourseId != null) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: const [
                        _LegendDot(color: Colors.blue, label: 'Currently enrolled'),
                        SizedBox(width: 16),
                        _LegendDot(color: Colors.red, label: 'New selection'),
                      ],
                    ),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed:
                (_selectedCourse != null && _selectedSubcourse != null && !_saving)
                    ? _save
                    : null,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(_isUpdate ? 'Update Course' : 'Save Course'),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold)),
      ],
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
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
