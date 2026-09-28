import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Syllabus — mirrors app/syllabus/index.tsx.
/// Active-course banner + syllabus PDF list from `app_syllabusdata`,
/// filtered by the user's enrolled course/subcourse.
class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({super.key});

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  late Future<_SyllabusData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SyllabusData> _load() async {
    final token = await AuthService.getValidIdToken();
    String? courseId;
    String? subcourseId;
    String courseName = '';
    String subcourseName = '';
    final user = AuthService.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirestoreRest.getDocument('users/${user.uid}',
            idToken: token);
        courseId = userDoc?['courseId'] as String?;
        subcourseId = userDoc?['subcourseId'] as String?;
        if (courseId != null) {
          try {
            final courseDoc = await FirestoreRest.getDocument(
                'courses/$courseId',
                idToken: token);
            courseName = (courseDoc?['name'] as String?) ?? '';
          } catch (_) {}
        }
        if (courseId != null && subcourseId != null) {
          try {
            final subDoc = await FirestoreRest.getDocument(
                'courses/$courseId/subcourses/$subcourseId',
                idToken: token);
            subcourseName = (subDoc?['name'] as String?) ?? '';
          } catch (_) {
            try {
              final legacy = await FirestoreRest.getDocument(
                  'app_subcourses/$subcourseId',
                  idToken: token);
              subcourseName = (legacy?['name'] as String?) ?? '';
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    final all = await FirestoreRest.listDocuments('app_syllabusdata',
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

    return _SyllabusData(
      courseName: courseName,
      subcourseName: subcourseName,
      items: filtered,
    );
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Syllabus'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<_SyllabusData>(
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
                  const Text('Failed to load syllabus.'),
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
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.navy, AppColors.deepNavy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Active Course',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      d.courseName.isNotEmpty
                          ? d.courseName
                          : 'No course selected',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    if (d.subcourseName.isNotEmpty)
                      Text(d.subcourseName,
                          style:
                              const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (d.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child: Text('No syllabus PDFs found for your course.',
                          style: TextStyle(color: Colors.grey))),
                )
              else
                ...d.items.map((s) {
                  final title = (s['title'] as String?) ?? 'Syllabus';
                  final pdfUrl = (s['pdfUrl'] as String?) ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.picture_as_pdf,
                            color: Colors.red),
                      ),
                      title: Text(title,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text((s['description'] as String?) ?? ''),
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.grey),
                      onTap: pdfUrl.isEmpty
                          ? null
                          : () {
                              final encoded =
                                  Uri.encodeComponent(pdfUrl);
                              context.push(
                                  '/pdf/$encoded?title=${Uri.encodeComponent(title)}');
                            },
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _SyllabusData {
  final String courseName;
  final String subcourseName;
  final List<Map<String, dynamic>> items;

  const _SyllabusData({
    required this.courseName,
    required this.subcourseName,
    this.items = const [],
  });
}
