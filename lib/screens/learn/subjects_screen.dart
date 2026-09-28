import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import '../../widgets/subpage_header.dart';

/// Subjects list — mirrors app/subjects/index.tsx.
/// Journey gradient card + 2-column subject grid, filtered by the
/// user's enrolled course/subcourse.
class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final token = await AuthService.getValidIdToken();
    String? courseId;
    String? subcourseId;
    final user = AuthService.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirestoreRest.getDocument('users/${user.uid}',
            idToken: token);
        courseId = userDoc?['courseId'] as String?;
        subcourseId = userDoc?['subcourseId'] as String?;
      } catch (_) {}
    }
    final all = await FirestoreRest.listDocuments('app_subjects_details',
        idToken: token, pageSize: 100);
    final filtered = all.where((s) {
      if (s['isPublished'] == false) return false;
      final c = s['courseId'] as String?;
      final sc = s['subcourseId'] as String?;
      if (courseId != null && c != null && c != courseId) return false;
      if (subcourseId != null && sc != null && sc != subcourseId) {
        return false;
      }
      return true;
    }).toList();
    filtered.sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));
    return filtered;
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  bool _isTechnical(Map<String, dynamic> s) =>
      s['technical'] == true ||
      (s['category'] as String? ?? '').contains('प्राविधिक') ||
      (s['category'] as String? ?? '').toLowerCase().contains('technical');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Subjects'),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
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
                  const Text('Failed to load subjects.'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final subjects = snap.data ?? [];
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.navy, AppColors.deepNavy],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your Learning Journey',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text(
                          'Pick a subject and start practicing, reading or studying theory.',
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (subjects.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                        child: Text('No subjects found for your course.',
                            style: TextStyle(color: Colors.grey))),
                  )
                else
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.1,
                    children: subjects.map((s) {
                      final name = (s['nameNe'] as String?) ??
                          (s['name'] as String?) ??
                          'Subject';
                      return InkWell(
                        onTap: () {
                          final id = s['id'] as String;
                          context.push(_isTechnical(s)
                              ? '/subjects/units/$id'
                              : '/subjects/chapters/$id');
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: Colors.grey.shade300),
                            color: Colors.white,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor:
                                    AppColors.navy.withValues(alpha: 0.1),
                                child: Text(
                                  name.isNotEmpty ? name[0] : 'S',
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.navy),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          );
        },
      ),
          ),
        ],
      ),
    );
  }
}
