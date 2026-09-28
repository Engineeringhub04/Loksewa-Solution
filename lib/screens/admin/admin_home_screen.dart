import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

/// Admin home — dashboard menu linking to every admin tool. Admin-only
/// (users/{uid}.isAdmin == true), mirroring the Admin section of the Expo
/// profile tab.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _Denied implements Exception {}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  Future<bool>? _future;

  @override
  void initState() {
    super.initState();
    _future = _checkAdmin();
  }

  Future<bool> _checkAdmin() async {
    final user = AuthService.currentUser;
    if (user == null) throw _Denied();
    final token = await AuthService.getValidIdToken();
    final profile =
        await FirestoreRest.getDocument('users/${user.uid}', idToken: token);
    if (profile?['isAdmin'] != true) throw _Denied();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: FutureBuilder<bool>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !(snap.data ?? false)) {
            return const Center(child: Text('Access denied'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Admin tools live here and nowhere else.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              _tile(
                icon: Icons.receipt_long_outlined,
                color: AppColors.navy,
                title: 'Exam Purchase Review',
                subtitle: 'Approve or reject exam purchase requests',
                route: '/admin/exam-purchases',
              ),
              _tile(
                icon: Icons.shield_outlined,
                color: Colors.indigo,
                title: 'Purchase Request Control',
                subtitle: 'Every exam + content purchase request in one list',
                route: '/admin/purchase-details',
              ),
              _tile(
                icon: Icons.flag_outlined,
                color: Colors.orange,
                title: 'Report Review',
                subtitle: 'Review user reports and answer reporters',
                route: '/admin/report-history',
              ),
              _tile(
                icon: Icons.diamond_outlined,
                color: Colors.green,
                title: 'Subscription Review',
                subtitle: 'Approve or reject premium subscription requests',
                route: '/admin/subscriptions',
              ),
              const Card(
                margin: EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(0x1A9C27B0),
                    child:
                        Icon(Icons.edit_note_outlined, color: Colors.purple),
                  ),
                  title: Text('Theory Answer Grading',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Opens from the Theory Desk — each submission has its own grading page.'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String route,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title:
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(route),
      ),
    );
  }
}
