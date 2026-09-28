import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import '../../widgets/subpage_header.dart';

/// Course details — mirrors app/course-details.tsx.
/// Reads the user's enrolled course/subcourse from users/{uid} and
/// resolves the display names from the courses collections.
class CourseDetailsScreen extends StatefulWidget {
  const CourseDetailsScreen({super.key});

  @override
  State<CourseDetailsScreen> createState() => _CourseDetailsScreenState();
}

class _CourseDetailsScreenState extends State<CourseDetailsScreen> {
  late Future<_CourseInfo> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_CourseInfo> _load() async {
    final user = AuthService.currentUser;
    if (user == null) {
      return const _CourseInfo(courseName: null, subcourseName: null);
    }
    final token = await AuthService.getValidIdToken();
    final userDoc =
        await FirestoreRest.getDocument('users/${user.uid}', idToken: token);
    final courseId = userDoc?['courseId'] as String?;
    final subcourseId = userDoc?['subcourseId'] as String?;

    String? courseName;
    String? subcourseName;
    if (courseId != null) {
      try {
        final courseDoc = await FirestoreRest.getDocument('courses/$courseId',
            idToken: token);
        courseName = courseDoc?['name'] as String?;
      } catch (_) {}
    }
    if (courseId != null && subcourseId != null) {
      try {
        final subDoc = await FirestoreRest.getDocument(
            'courses/$courseId/subcourses/$subcourseId',
            idToken: token);
        subcourseName = subDoc?['name'] as String?;
      } catch (_) {
        try {
          final legacy = await FirestoreRest.getDocument(
              'app_subcourses/$subcourseId',
              idToken: token);
          subcourseName = legacy?['name'] as String?;
        } catch (_) {}
      }
    }
    return _CourseInfo(courseName: courseName, subcourseName: subcourseName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Course Details'),
          Expanded(
            child: FutureBuilder<_CourseInfo>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Failed to load course details.'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final d = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.school, color: AppColors.navy),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This is the course you are enrolled in. You can change it anytime.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.school_outlined,
                            color: AppColors.navy),
                      ),
                      title: const Text('Course',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey)),
                      subtitle: Text(d.courseName ?? 'Not selected',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.layers_outlined,
                            color: AppColors.navy),
                      ),
                      title: const Text('Subcourse',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey)),
                      subtitle: Text(d.subcourseName ?? 'Not selected',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: Colors.grey),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Changing your course will switch the subjects, syllabus and exam sets shown to you.',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () =>
                      context.push('/course-setup?mode=update'),
                  child: const Text('Change Course'),
                ),
              ),
            ],
          );
        },
      ),
          ),
        ],
      ),
    );
  }
}

class _CourseInfo {
  final String? courseName;
  final String? subcourseName;

  const _CourseInfo({this.courseName, this.subcourseName});
}
