import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Home tab — mirrors app/(tabs)/index.tsx.
/// Banner carousel, QOTD card, subjects rail, quick links, additional
/// features, recent notices, app guide, developer card.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final token = await AuthService.getValidIdToken();
    final user = AuthService.currentUser;

    String? courseId;
    String? subcourseId;
    if (user != null) {
      try {
        final userDoc =
            await FirestoreRest.getDocument('users/${user.uid}', idToken: token);
        courseId = userDoc?['courseId'] as String?;
        subcourseId = userDoc?['subcourseId'] as String?;
      } catch (_) {}
    }

    List<Map<String, dynamic>> banners = [];
    List<Map<String, dynamic>> notices = [];
    Map<String, dynamic>? qotd;
    Map<String, dynamic>? developer;
    try {
      banners = await FirestoreRest.listDocuments('app_home_banners',
          idToken: token, pageSize: 20);
    } catch (_) {}
    try {
      final allNotices = await FirestoreRest.listDocuments('app_notices',
          idToken: token, pageSize: 10);
      allNotices
          .sort((a, b) => _num(b['createdAt']).compareTo(_num(a['createdAt'])));
      notices = allNotices.take(3).toList();
    } catch (_) {}
    try {
      qotd = await FirestoreRest.getDocument('app_question_of_the_day/today',
          idToken: token);
    } catch (_) {}
    try {
      final devs = await FirestoreRest.listDocuments('app_developers',
          idToken: token, pageSize: 5);
      if (devs.isNotEmpty) developer = devs.first;
    } catch (_) {}

    List<Map<String, dynamic>> subjects = [];
    try {
      final all = await FirestoreRest.listDocuments('app_subjects_details',
          idToken: token, pageSize: 100);
      subjects = all.where((s) {
        final c = s['courseId'] as String?;
        final sc = s['subcourseId'] as String?;
        if (s['isPublished'] == false) return false;
        if (courseId != null && c != null && c != courseId) return false;
        if (subcourseId != null && sc != null && sc != subcourseId) {
          return false;
        }
        return true;
      }).toList();
      subjects.sort((a, b) => _num(a['order']).compareTo(_num(b['order'])));
    } catch (_) {}

    return _HomeData(
      courseId: courseId,
      subcourseId: subcourseId,
      banners: banners,
      notices: notices,
      qotd: qotd,
      subjects: subjects,
      developer: developer,
    );
  }

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loksewa Solution'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<_HomeData>(
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
                  const Text('Failed to load home.'),
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
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _greeting(d),
                const SizedBox(height: 16),
                _bannerCarousel(d),
                const SizedBox(height: 16),
                _qotdCard(d),
                const SizedBox(height: 20),
                _sectionHeader(context, 'Subjects', '/subjects'),
                const SizedBox(height: 8),
                _subjectsRail(d),
                const SizedBox(height: 20),
                _sectionHeader(context, 'Quick Links', null),
                const SizedBox(height: 8),
                _quickLinks(),
                const SizedBox(height: 20),
                _sectionHeader(context, 'Additional Features', null),
                const SizedBox(height: 8),
                _featureGrid(),
                const SizedBox(height: 20),
                _sectionHeader(context, 'Recent Notices', '/notice-board'),
                const SizedBox(height: 8),
                _noticesList(d),
                const SizedBox(height: 20),
                _sectionHeader(context, 'App Guide', null),
                const SizedBox(height: 8),
                _guideGrid(),
                const SizedBox(height: 20),
                _developerCard(d),
                const SizedBox(height: 12),
                const Center(
                  child: Text('Made with ❤ by Loksewa Solution',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _greeting(_HomeData d) {
    final name = AuthService.currentUser?.displayName ??
        AuthService.currentUser?.email ??
        'Student';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Namaste 🙏',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text('Welcome back, $name',
            style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _bannerCarousel(_HomeData d) {
    if (d.banners.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 150,
      child: PageView.builder(
        itemCount: d.banners.length,
        itemBuilder: (context, i) {
          final b = d.banners[i];
          final url = b['imageUrl'] as String? ?? b['image'] as String?;
          return Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppColors.navy.withOpacity(0.08),
            ),
            clipBehavior: Clip.antiAlias,
            child: url != null && url.isNotEmpty
                ? Image.network(url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _bannerFallback(b))
                : _bannerFallback(b),
          );
        },
      ),
    );
  }

  Widget _bannerFallback(Map<String, dynamic> b) => Container(
        color: AppColors.navy,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Text(
          (b['title'] as String?) ?? 'Loksewa Solution',
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      );

  Widget _qotdCard(_HomeData d) {
    final q = d.qotd;
    if (q == null) return const SizedBox.shrink();
    return Card(
      color: AppColors.navy,
      child: InkWell(
        onTap: () => context.push('/question-of-the-day'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.lightbulb_outline,
                      color: Colors.amber, size: 20),
                  SizedBox(width: 6),
                  Text('Question of the Day',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                (q['questionNe'] as String?) ??
                    (q['question'] as String?) ??
                    '',
                style: const TextStyle(color: Colors.white, fontSize: 15),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              const Text('Tap to answer →',
                  style: TextStyle(color: Colors.amber, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, String? route) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        if (route != null)
          TextButton(
            onPressed: () => context.push(route),
            child: const Text('See all'),
          ),
      ],
    );
  }

  Widget _subjectsRail(_HomeData d) {
    if (d.subjects.isEmpty) {
      return const Text('No subjects yet.',
          style: TextStyle(color: Colors.grey));
    }
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: d.subjects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final s = d.subjects[i];
          final name =
              (s['nameNe'] as String?) ?? (s['name'] as String?) ?? 'Subject';
          return InkWell(
            onTap: () {
              final id = s['id'] as String;
              final isTech = s['technical'] == true ||
                  (s['category'] as String? ?? '').contains('प्राविधिक') ||
                  (s['category'] as String? ?? '')
                      .toLowerCase()
                      .contains('technical');
              context.push(isTech
                  ? '/subjects/units/$id'
                  : '/subjects/chapters/$id');
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 110,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.navy.withOpacity(0.06),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.navy,
                    child: Text(name.isNotEmpty ? name[0] : 'S',
                        style: const TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(height: 8),
                  Text(name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _quickLinks() {
    final items = [
      (_IconData(Icons.menu_book, 'Subjects'), '/subjects'),
      (_IconData(Icons.description, 'Syllabus'), '/syllabus'),
      (_IconData(Icons.note_alt, 'Notes'), '/notes'),
      (_IconData(Icons.notifications, 'Notices'), '/notice-board'),
    ];
    return _linkRow(items);
  }

  Widget _featureGrid() {
    final items = [
      (_IconData(Icons.newspaper, 'Current\nAffairs'), '/current-affairs'),
      (_IconData(Icons.quiz, 'Mock Tests'), '/mock-tests'),
      (_IconData(Icons.bookmark, 'Saved'), '/saved'),
      (_IconData(Icons.history, 'Old Papers'), '/old-papers'),
      (_IconData(Icons.notifications_active, 'Alerts'), '/notifications'),
      (_IconData(Icons.help_outline, 'Help'), '/help-center'),
      (_IconData(Icons.settings, 'Settings'), '/settings'),
      (_IconData(Icons.info_outline, 'About'), '/about'),
      (_IconData(Icons.star, 'Premium'), '/premium'),
    ];
    return _linkGrid(items);
  }

  Widget _guideGrid() {
    final items = [
      (_IconData(Icons.play_circle, 'How to\nUse'), '/how-to-use'),
      (_IconData(Icons.question_answer, 'FAQ'), '/help-center'),
      (_IconData(Icons.contact_support, 'Contact'), '/contact-us'),
      (_IconData(Icons.privacy_tip, 'Privacy'), '/privacy-policy'),
      (_IconData(Icons.article, 'Terms'), '/terms-of-service'),
      (_IconData(Icons.share, 'Share'), null),
      (_IconData(Icons.thumb_up, 'Rate'), null),
      (_IconData(Icons.feedback, 'Feedback'), '/contact-us'),
      (_IconData(Icons.school, 'Course'), '/course-details'),
    ];
    return _linkGrid(items);
  }

  Widget _linkRow(List<(_IconData, String?)> items) {
    return Row(
      children: items
          .map((e) => Expanded(child: _linkTile(e.$1, e.$2)))
          .toList(),
    );
  }

  Widget _linkGrid(List<(_IconData, String?)> items) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: items.map((e) => _linkTile(e.$1, e.$2)).toList(),
    );
  }

  Widget _linkTile(_IconData item, String? route) {
    return InkWell(
      onTap: route == null
          ? null
          : () => context.push(route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, color: AppColors.navy, size: 26),
            const SizedBox(height: 6),
            Text(item.label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _noticesList(_HomeData d) {
    if (d.notices.isEmpty) {
      return const Text('No notices yet.',
          style: TextStyle(color: Colors.grey));
    }
    return Column(
      children: d.notices.map((n) {
        final title = (n['title'] as String?) ?? 'Notice';
        return Card(
          child: ListTile(
            leading:
                const Icon(Icons.campaign, color: AppColors.accent),
            title: Text(title,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text((n['date'] as String?) ?? ''),
            onTap: () => context.push('/notice-board'),
          ),
        );
      }).toList(),
    );
  }

  Widget _developerCard(_HomeData d) {
    final dev = d.developer;
    if (dev == null) return const SizedBox.shrink();
    final name = (dev['name'] as String?) ?? 'Developer';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.navy,
          child: Text(name.isNotEmpty ? name[0] : 'D',
              style: const TextStyle(color: Colors.white)),
        ),
        title: const Text('About Developer',
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$name\n${(dev['role'] as String?) ?? ''}'),
        isThreeLine: true,
      ),
    );
  }
}

class _HomeData {
  final String? courseId;
  final String? subcourseId;
  final List<Map<String, dynamic>> banners;
  final List<Map<String, dynamic>> notices;
  final Map<String, dynamic>? qotd;
  final List<Map<String, dynamic>> subjects;
  final Map<String, dynamic>? developer;

  const _HomeData({
    this.courseId,
    this.subcourseId,
    this.banners = const [],
    this.notices = const [],
    this.qotd,
    this.subjects = const [],
    this.developer,
  });
}

class _IconData {
  final IconData icon;
  final String label;
  const _IconData(this.icon, this.label);
}
