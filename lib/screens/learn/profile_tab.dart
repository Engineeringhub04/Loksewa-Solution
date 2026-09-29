import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';

/// Profile tab — mirrors app/(tabs)/profile.tsx.
/// Collapsing header, stats card, Account / Admin / App Settings /
/// Support / More sections, logout with confirm.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadUserDoc();
  }

  Future<Map<String, dynamic>?> _loadUserDoc() async {
    final user = AuthService.currentUser;
    if (user == null) return null;
    try {
      final token = await AuthService.getValidIdToken();
      return await FirestoreRest.getDocument('users/${user.uid}',
          idToken: token);
    } catch (_) {
      return null;
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content:
            const Text('Are you sure you want to log out of your account?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Log out', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    await AuthService.logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final name = user?.displayName ?? user?.email ?? 'Student';
    final email = user?.email ?? '';
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        final doc = snap.data;
        final isAdmin = doc?['role'] == 'admin' || doc?['isAdmin'] == true;
        final stats = <_Stat>[
          _Stat('XP', '${doc?['xp'] ?? 0}', Icons.bolt),
          _Stat('Streak', '${doc?['streak'] ?? 0} days', Icons.local_fire_department),
          _Stat('Badges', '${doc?['badgeCount'] ?? 0}', Icons.emoji_events),
          _Stat('Notes', '${doc?['noteCount'] ?? 0}', Icons.note_alt),
        ];
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.navy, AppColors.deepNavy],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    // 26px bottom curve, like React's tab headers.
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(26),
                      bottomRight: Radius.circular(26),
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.white,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'S',
                              style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navy),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          if (email.isNotEmpty)
                            Text(email,
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statsCard(stats),
                    const SizedBox(height: 16),
                    _section('Account', [
                      _row(Icons.school_outlined, 'My Course',
                          () => context.push('/course-details')),
                      _row(Icons.card_membership_outlined, 'Certificates',
                          () => context.push('/exam-results')),
                      _row(Icons.notifications_outlined, 'Notifications',
                          () => context.push('/notifications')),
                    ]),
                    if (isAdmin) ...[
                      const SizedBox(height: 12),
                      _section('Admin', [
                        _row(Icons.dashboard_outlined, 'Admin Dashboard',
                            () => context.push('/admin')),
                        _row(Icons.receipt_long_outlined, 'Purchase Requests',
                            () => context.push('/admin/purchase-details')),
                        _row(Icons.subscriptions_outlined, 'Subscriptions',
                            () => context.push('/admin/subscriptions')),
                        _row(Icons.report_outlined, 'Report Review',
                            () => context.push('/admin/report-history')),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    _section('App Settings', [
                      _row(Icons.palette_outlined, 'Theme',
                          () => _themeDialog()),
                      _row(Icons.language_outlined, 'Language',
                          () => _languageDialog()),
                    ]),
                    const SizedBox(height: 12),
                    _section('Support', [
                      _row(Icons.help_outline, 'Help Center',
                          () => context.push('/help-center')),
                      _row(Icons.contact_support_outlined, 'Contact Us',
                          () => context.push('/contact-us')),
                    ]),
                    const SizedBox(height: 12),
                    _section('More', [
                      _row(Icons.share_outlined, 'Share App', () {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Share coming soon.')));
                      }),
                      _row(Icons.star_outline, 'Rate App', () {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Rate coming soon.')));
                      }),
                      _row(Icons.logout, 'Log out', _logout,
                          danger: true),
                    ]),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statsCard(List<_Stat> stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: stats
              .map((s) => Expanded(
                    child: Column(
                      children: [
                        Icon(s.icon, color: AppColors.navy, size: 22),
                        const SizedBox(height: 4),
                        Text(s.value,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(s.label,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: rows),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    return ListTile(
      leading: Icon(icon,
          color: danger ? Colors.red : AppColors.navy),
      title: Text(label,
          style: TextStyle(color: danger ? Colors.red : null)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _themeDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Theme'),
        children: ['Light', 'Dark', 'System']
            .map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t),
                ))
            .toList(),
      ),
    );
  }

  void _languageDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Language'),
        children: ['English', 'नेपाली']
            .map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t),
                ))
            .toList(),
      ),
    );
  }
}

class _Stat {
  final String label;
  final String value;
  final IconData icon;
  const _Stat(this.label, this.value, this.icon);
}
