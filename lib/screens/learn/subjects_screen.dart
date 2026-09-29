import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_rest.dart';
import '../../services/exam_service.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/home/subject_card_colored.dart';

/// Subjects list — exact port of app/subjects/index.tsx.
/// Journey gradient card + measured 2-column grid of SubjectCardColored.
class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  late Future<_SubjectPage> _future;
  Map<String, dynamic>? _premiumSubject;

  static const _colors = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFEA580C),
  ];
  static const _icons = [
    Icons.public_outlined,
    Icons.work_outline,
    Icons.build_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SubjectPage> _load() async {
    final user = AuthService.currentUser;
    final token = await AuthService.getValidIdToken();
    var courseId = 'civil-engineering';
    var subcourseId = 'civil-assistant-sub-engineer';
    var courseName = 'Civil Engineering';
    var subcourseName = 'Civil Assistant Sub Engineer';
    bool isPremium = false;
    if (user != null) {
      try {
        final doc = await FirestoreRest.getDocument('users/${user.uid}',
            idToken: token);
        courseId = (doc?['courseId'] as String?) ?? courseId;
        subcourseId = (doc?['subcourseId'] as String?) ?? subcourseId;
        isPremium = _hasActivePremium(doc);
      } catch (_) {}
    }
    // The two name lookups and the subject catalogue are independent — fetch
    // them concurrently instead of one after another.
    Future<Map<String, dynamic>?> safeDoc(String path) async {
      try {
        return await FirestoreRest.getDocument(path, idToken: token);
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      safeDoc('app_courses/$courseId'),
      safeDoc('app_courses/$courseId/subcourses/$subcourseId'),
      fetchSubjectDetails(courseId, subcourseId),
    ]);
    final cDoc = results[0] as Map<String, dynamic>?;
    final scDoc = results[1] as Map<String, dynamic>?;
    final subjects = results[2] as List<Map<String, dynamic>>;
    courseName = (cDoc?['name'] as String?) ?? courseName;
    subcourseName = (scDoc?['name'] as String?) ?? subcourseName;
    SubjectLearningStats stats =
        const SubjectLearningStats(complete: 0, inProgress: 0);
    if (user != null && subjects.isNotEmpty) {
      try {
        stats = await fetchSubjectLearningStats(
          uid: user.uid,
          courseId: courseId,
          subcourseId: subcourseId,
          subjectIds: subjects.map((s) => '${s['id']}').toList(),
        );
      } catch (_) {}
    }
    return _SubjectPage(
      courseId: courseId,
      subcourseId: subcourseId,
      courseName: courseName,
      subcourseName: subcourseName,
      subjects: subjects,
      complete: stats.complete,
      inProgress: stats.inProgress,
      isPremium: isPremium,
    );
  }

  static bool _hasActivePremium(Map<String, dynamic>? userDoc) {
    final pro = userDoc?['pro'];
    if (pro is bool) return pro;
    if (pro is Map) {
      final active = pro['active'];
      if (active is bool) return active;
      final exp = pro['expiresAt'];
      if (exp is String) {
        final dt = DateTime.tryParse(exp);
        if (dt != null) return dt.isAfter(DateTime.now());
      }
    }
    return false;
  }

  void _handleSubjectAction(Map<String, dynamic> s, _SubjectPage d) {
    final id = '${s['id']}';
    final name = '${s['name'] ?? 'Subject'}';
    final key = '$id $name'.toLowerCase();
    final hasUnits =
        key.contains('technical') || key.contains('प्राविधिक');
    final pro = s['pro'] == true;
    if (pro && !d.isPremium && !hasUnits) {
      setState(() => _premiumSubject = s);
      return;
    }
    context.push(hasUnits
        ? '/subjects/units/$id'
        : '/subjects/chapters/$id');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'All Subjects'),
          Expanded(
            child: FutureBuilder<_SubjectPage>(
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
                          onPressed: () =>
                              setState(() => _future = _load()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final d = snap.data!;
                final premiumCount =
                    d.subjects.where((s) => s['pro'] == true).length;
                return Stack(
                  children: [
                    RefreshIndicator(
                      onRefresh: () async =>
                          setState(() => _future = _load()),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _journeyCard(d, premiumCount),
                          const SizedBox(height: 16),
                          if (d.subjects.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                  child: Text('Content coming soon',
                                      style:
                                          TextStyle(color: Colors.grey))),
                            )
                          else
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final cardWidth =
                                    ((constraints.maxWidth - 12) / 2)
                                        .floorToDouble();
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    for (var i = 0;
                                        i < d.subjects.length;
                                        i++)
                                      SubjectCardColored(
                                        name:
                                            '${d.subjects[i]['name'] ?? 'Subject'}',
                                        icon: _icons[i % _icons.length],
                                        backgroundColor:
                                            _colors[i % _colors.length],
                                        premium:
                                            d.subjects[i]['pro'] == true,
                                        premiumLabel: 'Premium',
                                        purchased:
                                            d.subjects[i]['pro'] == true &&
                                                d.isPremium,
                                        purchasedLabel:
                                            'Purchased (Active)',
                                        footerLabel: 'View Chapter',
                                        width: cardWidth,
                                        height: 150,
                                        onPress: () =>
                                            _handleSubjectAction(
                                                d.subjects[i], d),
                                        onFooterPress: () =>
                                            _handleSubjectAction(
                                                d.subjects[i], d),
                                      ),
                                  ],
                                );
                              },
                            ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                    if (_premiumSubject != null)
                      _PremiumGateDialog(
                        itemName:
                            '${_premiumSubject!['name'] ?? 'Subject'}',
                        title: 'Premium Subject',
                        message:
                            'A subscription is required to access this premium subject.',
                        onConfirm: () {
                          setState(() => _premiumSubject = null);
                          context.push('/subscription');
                        },
                        onCancel: () =>
                            setState(() => _premiumSubject = null),
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

  Widget _journeyCard(_SubjectPage d, int premiumCount) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF153DB8), Color(0xFF0C2D91)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x470C2D91),
              blurRadius: 16,
              offset: Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -40,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF5A8CFF).withValues(alpha: 0.22),
              ),
            ),
          ),
          Positioned(
            bottom: -125,
            left: -70,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00002D).withValues(alpha: 0.16),
              ),
            ),
          ),
          Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your Progress Overview',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${d.subjects.length} subjects available',
                          style: const TextStyle(
                              color: Color(0xFFD6E2FF), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 168),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF9A3412),
                    ),
                    child: Text(
                      '${d.courseName} • ${d.subcourseName}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _JourneyStat(
                      icon: Icons.check_circle,
                      label: 'Complete',
                      value: d.complete,
                      accent: const Color(0xFFC7D9FF)),
                  const SizedBox(width: 10),
                  _JourneyStat(
                      icon: Icons.show_chart,
                      label: 'In Progress',
                      value: d.inProgress,
                      accent: const Color(0xFFB8E1FF)),
                  const SizedBox(width: 10),
                  _JourneyStat(
                      icon: Icons.diamond,
                      label: 'Premium',
                      value: premiumCount,
                      accent: const Color(0xFFFFD2A6)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JourneyStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color accent;

  const _JourneyStat(
      {required this.icon,
      required this.label,
      required this.value,
      required this.accent});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          color: const Color(0xFF6984CC).withValues(alpha: 0.58),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.09)),
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                border: Border.all(
                    color: accent.withValues(alpha: 0.8), width: 2),
              ),
              child:
                  Icon(icon, size: 21, color: const Color(0xFF0C2D91)),
            ),
            const SizedBox(height: 6),
            Text('$value',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.7)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFFE2EAFF), fontSize: 11),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _PremiumGateDialog extends StatelessWidget {
  final String? itemName;
  final String title;
  final String message;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _PremiumGateDialog(
      {this.itemName,
      required this.title,
      required this.message,
      required this.onConfirm,
      required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 40, color: Color(0xFF9A3412)),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (itemName != null) ...[
                const SizedBox(height: 6),
                Text(itemName!,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D4ED8),
                      foregroundColor: Colors.white),
                  onPressed: onConfirm,
                  child: const Text('Go To Subscription Plan'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onCancel, child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectPage {
  final String courseId;
  final String subcourseId;
  final String courseName;
  final String subcourseName;
  final List<Map<String, dynamic>> subjects;
  final int complete;
  final int inProgress;
  final bool isPremium;

  const _SubjectPage({
    required this.courseId,
    required this.subcourseId,
    required this.courseName,
    required this.subcourseName,
    required this.subjects,
    required this.complete,
    required this.inProgress,
    required this.isPremium,
  });
}
