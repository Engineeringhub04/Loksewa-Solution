// Achievements.
// Mirrors app/achievements.tsx: a 3-column badge grid; earned badges are
// full-colour, locked ones dimmed. Tapping a badge opens a bottom sheet with
// its title and description (or the unlocked-on date).
import 'package:flutter/material.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

class _Badge {
  final String id;
  final String title;
  final String description;
  final String icon;
  final bool unlocked;
  final String? unlockedAt;
  _Badge(this.id, this.title, this.description, this.icon, this.unlocked,
      this.unlockedAt);
}

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late final Future<List<_Badge>> _future = _load();

  Future<List<_Badge>> _load() async {
    final token = await AuthService.getValidIdToken();
    final uid = AuthService.currentUser?.uid;
    final results = await Future.wait([
      FirestoreRest.listDocuments('achievements',
          idToken: token, pageSize: 100),
      FirestoreRest.getDocument('users/$uid', idToken: token),
    ]);
    final catalog = results[0] as List<Map<String, dynamic>>;
    final userDoc = results[1] as Map<String, dynamic>?;
    final unlockedMap =
        (userDoc?['unlockedAchievements'] as Map?)?.cast<String, dynamic>() ??
            {};
    return catalog
        .map((a) => _Badge(
              a['id']?.toString() ?? '',
              a['title']?.toString() ?? 'Achievement',
              a['description']?.toString() ?? '',
              a['icon']?.toString() ?? 'emoji_events',
              unlockedMap[a['id']?.toString()] != null,
              unlockedMap[a['id']?.toString()]?.toString(),
            ))
        .toList();
  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'military_tech':
        return Icons.military_tech;
      case 'star':
        return Icons.star;
      case 'bolt':
        return Icons.bolt;
      case 'school':
        return Icons.school;
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'workspace_premium':
        return Icons.workspace_premium;
      default:
        return Icons.emoji_events;
    }
  }

  void _showSheet(_Badge b) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(b.icon),
                size: 56,
                color: b.unlocked ? AppColors.accent : Colors.grey),
            const SizedBox(height: 12),
            Text(b.title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              b.description.isNotEmpty
                  ? b.description
                  : (b.unlocked && b.unlockedAt != null
                      ? 'Unlocked on ${_fmtDate(b.unlockedAt)}'
                      : 'Keep learning to unlock this badge.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            if (b.unlocked && b.unlockedAt != null) ...[
              const SizedBox(height: 8),
              Text('Unlocked on ${_fmtDate(b.unlockedAt)}',
                  style: const TextStyle(
                      color: Colors.green, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Achievements'),
          Expanded(
            child: FutureBuilder<List<_Badge>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load achievements.\n${snap.error}',
                        textAlign: TextAlign.center)));
          }
          final badges = snap.data!;
          if (badges.isEmpty) {
            return const Center(child: Text('No achievements yet.'));
          }
          final earned = badges.where((b) => b.unlocked).length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('$earned of ${badges.length} unlocked',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: badges.length,
                  itemBuilder: (_, i) {
                    final b = badges[i];
                    return Opacity(
                      opacity: b.unlocked ? 1.0 : 0.45,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _showSheet(b),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: b.unlocked
                                    ? AppColors.accent
                                    : Colors.black12,
                                width: b.unlocked ? 2 : 1),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_iconFor(b.icon),
                                  size: 40,
                                  color: b.unlocked
                                      ? AppColors.accent
                                      : Colors.grey),
                              const SizedBox(height: 8),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(b.title,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                              if (!b.unlocked)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Icon(Icons.lock,
                                      size: 16, color: Colors.grey),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
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

  String _fmtDate(String? v) {
    final dt = v == null ? null : DateTime.tryParse(v);
    if (dt == null) return '—';
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }
}
