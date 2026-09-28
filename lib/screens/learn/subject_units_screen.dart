import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Subject units — mirrors app/subjects/units/[subjectId].tsx.
/// Track chips + expandable unit cards; each unit chapter opens the
/// same Practice / Read / Theory bottom sheet.
class SubjectUnitsScreen extends StatefulWidget {
  final String subjectId;
  const SubjectUnitsScreen({super.key, required this.subjectId});

  @override
  State<SubjectUnitsScreen> createState() => _SubjectUnitsScreenState();
}

class _SubjectUnitsScreenState extends State<SubjectUnitsScreen> {
  late Future<_UnitData> _future;
  String? _expandedUnitId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_UnitData> _load() async {
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

    String subjectName = 'Subject';
    try {
      final subjectDoc = await FirestoreRest.getDocument(
          'app_subjects_details/${widget.subjectId}',
          idToken: token);
      subjectName = (subjectDoc?['nameNe'] as String?) ??
          (subjectDoc?['name'] as String?) ??
          subjectName;
    } catch (_) {}

    final allUnits = await FirestoreRest.listDocuments(
        'app_subjects_units_details',
        idToken: token,
        pageSize: 100);
    final units = allUnits.where((u) {
      if (u['isPublished'] == false) return false;
      final subj = (u['subjectId'] as String?) ?? '';
      if (_canon(subj) != _canon(widget.subjectId)) return false;
      final c = u['courseId'] as String?;
      final sc = u['subcourseId'] as String?;
      if (courseId != null && c != null && c != courseId) return false;
      if (subcourseId != null && sc != null && sc != subcourseId) {
        return false;
      }
      return true;
    }).toList();
    units.sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));

    final allUnitChapters = await FirestoreRest.listDocuments(
        'app_subjects_unit-chapters_details',
        idToken: token,
        pageSize: 300);
    final unitChapters = allUnitChapters.where((c) {
      if (c['isPublished'] == false) return false;
      final subj = (c['subjectId'] as String?) ?? '';
      if (_canon(subj) != _canon(widget.subjectId)) return false;
      return true;
    }).toList();
    unitChapters
        .sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));

    return _UnitData(
      subjectName: subjectName,
      courseId: courseId ?? '',
      subcourseId: subcourseId ?? '',
      units: units,
      unitChapters: unitChapters,
    );
  }

  static String _canon(String v) {
    final parts = v.split('__').where((p) => p.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.last : v;
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  void _showModeSheet(Map<String, dynamic> chapter, String unitId,
      String unitName, _UnitData d) {
    final chapterId = chapter['id'] as String;
    final chapterName =
        (chapter['nameNe'] as String?) ?? (chapter['name'] as String?) ?? '';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chapterName,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(unitName, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              _modeTile(
                  context,
                  Icons.quiz_outlined,
                  'Practice',
                  'MCQ questions with explanations',
                  Colors.blue, () {
                _goMode('/subjects/practice', chapterId, chapterName, unitId,
                    unitName, d);
              }),
              _modeTile(
                  context,
                  Icons.menu_book_outlined,
                  'Read',
                  'Question & answer format',
                  Colors.green, () {
                _goMode('/subjects/read', chapterId, chapterName, unitId,
                    unitName, d);
              }),
              _modeTile(
                  context,
                  Icons.description_outlined,
                  'Theory',
                  'Study notes & reference PDF',
                  AppColors.accent, () {
                _goMode('/subjects/theory', chapterId, chapterName, unitId,
                    unitName, d);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeTile(BuildContext context, IconData icon, String title,
      String subtitle, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  void _goMode(String route, String chapterId, String chapterName,
      String unitId, String unitName, _UnitData d) {
    final params = {
      'courseId': d.courseId,
      'subcourseId': d.subcourseId,
      'subjectId': widget.subjectId,
      'chapterId': chapterId,
      'unitId': unitId,
      'subjectName': d.subjectName,
      'chapterName': chapterName,
      'unitName': unitName,
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    context.push('$route?$qs');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Units'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<_UnitData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Failed to load units.'),
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
          if (d.units.isEmpty) {
            return const Center(
                child: Text('No units found.',
                    style: TextStyle(color: Colors.grey)));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(d.subjectName,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${d.units.length} units',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              ...d.units.map((u) {
                final unitId = u['id'] as String;
                final unitName = (u['nameNe'] as String?) ??
                    (u['name'] as String?) ??
                    'Unit';
                final expanded = _expandedUnitId == unitId;
                final chapters = d.unitChapters.where((c) {
                  final cuid = (c['unitId'] as String?) ?? '';
                  return _canon(cuid) == _canon(unitId);
                }).toList();
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.navy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text('${_num(u['order']).toInt()}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navy)),
                        ),
                        title: Text(unitName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${chapters.length} chapters • ${(u['track'] as String?) ?? ''}'),
                        trailing: Icon(
                            expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.grey),
                        onTap: () => setState(() => _expandedUnitId =
                            expanded ? null : unitId),
                      ),
                      if (expanded)
                        ...chapters.map((c) {
                          final name = (c['nameNe'] as String?) ??
                              (c['name'] as String?) ??
                              'Chapter';
                          return ListTile(
                            contentPadding: const EdgeInsets.only(
                                left: 72, right: 16),
                            title: Text(name,
                                style: const TextStyle(fontSize: 14)),
                            trailing: const Icon(Icons.chevron_right,
                                size: 18, color: Colors.grey),
                            onTap: () => _showModeSheet(
                                c, unitId, unitName, d),
                          );
                        }),
                    ],
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

class _UnitData {
  final String subjectName;
  final String courseId;
  final String subcourseId;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> unitChapters;

  const _UnitData({
    required this.subjectName,
    required this.courseId,
    required this.subcourseId,
    this.units = const [],
    this.unitChapters = const [],
  });
}
