import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Exam tab — mirrors app/(tabs)/exam.tsx.
/// Gradient header, province filter chips, section tabs, exam-set cards,
/// rules bottom sheet before starting.
class ExamTab extends StatefulWidget {
  const ExamTab({super.key});

  @override
  State<ExamTab> createState() => _ExamTabState();
}

class _ExamTabState extends State<ExamTab> {
  late Future<_ExamData> _future;
  String? _provinceId;
  String? _sectionId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ExamData> _load() async {
    final token = await AuthService.getValidIdToken();
    final provinces = await FirestoreRest.listDocuments('app_exam_provinces',
        idToken: token, pageSize: 50);
    provinces.sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));
    final sections = await FirestoreRest.listDocuments('app_exam_sections',
        idToken: token, pageSize: 50);
    sections.sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));
    final sets = await FirestoreRest.listDocuments('app_exam_sets',
        idToken: token, pageSize: 100);
    sets.removeWhere((s) => s['isPublished'] == false);
    sets.sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));
    List<Map<String, dynamic>> rules = [];
    try {
      rules = await FirestoreRest.listDocuments('app_exam_rules',
          idToken: token, pageSize: 50);
    } catch (_) {}
    return _ExamData(
      provinces: provinces,
      sections: sections,
      sets: sets,
      rules: rules,
    );
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  List<Map<String, dynamic>> _filteredSets(_ExamData d) {
    return d.sets.where((s) {
      if (_provinceId != null && s['provinceId'] != _provinceId) {
        return false;
      }
      if (_sectionId != null && s['sectionId'] != _sectionId) {
        return false;
      }
      return true;
    }).toList();
  }

  void _showRulesSheet(Map<String, dynamic> set, _ExamData d) {
    final rules = d.rules
        .where((r) => r['examSetId'] == set['id'] || r['examSetId'] == null)
        .toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((set['title'] as String?) ?? 'Exam Set',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Exam Rules',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: rules.isEmpty
                      ? [
                          const Text(
                              '• Read each question carefully.\n• No negative marking unless stated.\n• Submit before time runs out.')
                        ]
                      : rules
                          .map((r) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                    '• ${(r['text'] as String?) ?? ''}'),
                              ))
                          .toList(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/exam/${set['id']}');
                  },
                  child: const Text('Start Exam'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_ExamData>(
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
                  const Text('Failed to load exams.'),
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
          final sets = _filteredSets(d);
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 150,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.navy, AppColors.deepNavy],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const SafeArea(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('Exam Hub',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)),
                            Text('Mock tests, live exams & results',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (d.provinces.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text('Province',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: d.provinces.length + 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final id =
                                i == 0 ? null : d.provinces[i - 1]['id'] as String?;
                            final label = i == 0
                                ? 'All'
                                : ((d.provinces[i - 1]['nameNe']
                                            as String?) ??
                                        (d.provinces[i - 1]['name']
                                            as String?) ??
                                        '');
                            final selected = _provinceId == id;
                            return ChoiceChip(
                              label: Text(label),
                              selected: selected,
                              selectedColor: AppColors.navy,
                              labelStyle: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.black87),
                              onSelected: (_) =>
                                  setState(() => _provinceId = id),
                            );
                          },
                        ),
                      ),
                    ],
                    if (d.sections.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text('Section',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: d.sections.length + 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final id =
                                i == 0 ? null : d.sections[i - 1]['id'] as String?;
                            final label = i == 0
                                ? 'All'
                                : ((d.sections[i - 1]['title'] as String?) ??
                                    (d.sections[i - 1]['name']
                                        as String?) ??
                                    '');
                            final selected = _sectionId == id;
                            return ChoiceChip(
                              label: Text(label),
                              selected: selected,
                              selectedColor: AppColors.accent,
                              labelStyle: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.black87),
                              onSelected: (_) =>
                                  setState(() => _sectionId = id),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              if (sets.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                      child: Text('No exam sets found.',
                          style: TextStyle(color: Colors.grey))),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final s = sets[i];
                      final title =
                          (s['title'] as String?) ?? 'Exam Set';
                      final isFree = s['isFree'] == true ||
                          _num(s['price']) == 0;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.navy.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.assignment,
                                color: AppColors.navy),
                          ),
                          title: Text(title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${_num(s['totalQuestions']).toInt()} questions • ${_num(s['totalMarks']).toInt()} marks • ${_num(s['durationMinutes']).toInt()} min',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isFree
                                  ? Colors.green.shade100
                                  : AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isFree
                                  ? 'FREE'
                                  : 'Rs. ${_num(s['price']).toInt()}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isFree
                                    ? Colors.green.shade800
                                    : AppColors.accent,
                              ),
                            ),
                          ),
                          onTap: () => _showRulesSheet(s, d),
                        ),
                      );
                    },
                    childCount: sets.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _ExamData {
  final List<Map<String, dynamic>> provinces;
  final List<Map<String, dynamic>> sections;
  final List<Map<String, dynamic>> sets;
  final List<Map<String, dynamic>> rules;

  const _ExamData({
    this.provinces = const [],
    this.sections = const [],
    this.sets = const [],
    this.rules = const [],
  });
}
