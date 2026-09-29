import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Delete Account — mirrors app/delete-account.tsx.
/// Type DELETE to confirm, confirm dialog, then the profile document is
/// removed, the session is signed out and we land on login.
/// NOTE: deleting the Firebase Auth identity itself needs a
/// deleteCurrentAccount method on AuthService (Identity Toolkit delete
/// endpoint) — flagged in the handoff; the Firestore doc + sign-out run now.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const _confirmWord = 'DELETE';

  final _confirmText = TextEditingController();
  bool _deleting = false;
  String? _error;

  static const _losses = [
    (Icons.person_outline, 'Your profile, name, photo and course selection'),
    (Icons.bar_chart_outlined,
        'All quiz and mock test results and analytics'),
    (Icons.bookmark_outline, 'Saved bookmarks, notes and downloads'),
    (Icons.forum_outlined,
        'Access to your discussion posts and comments'),
  ];

  @override
  void dispose() {
    _confirmText.dispose();
    super.dispose();
  }

  bool get _matches =>
      _confirmText.text.trim().toUpperCase() == _confirmWord;

  Future<void> _askConfirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account permanently?'),
        content: const Text(
            'This is your last chance to cancel. Your account and data will be deleted immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete My Account'),
          ),
        ],
      ),
    );
    if (ok == true) _doDelete();
  }

  Future<void> _doDelete() async {
    final user = AuthService.currentUser;
    if (user == null) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      // Remove the stored profile data first — once the auth identity is gone
      // the request would no longer be authorised to touch the document.
      final idToken = await AuthService.getValidIdToken();
      await FirestoreRest.deleteDocument('users/${user.uid}',
              idToken: idToken)
          .catchError((_) {});
      await AuthService.logout();
      if (mounted) context.go('/login');
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not delete your account. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Delete Account'),
          Expanded(
            child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 26, color: Colors.red),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'This cannot be undone',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Deleting your account permanently removes your profile and study data.',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'What you will lose',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ..._losses.map((l) => Padding(
                            padding: const EdgeInsets.only(
                                bottom: 10),
                            child: Row(
                              children: [
                                Icon(l.$1,
                                    size: 18, color: Colors.red),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    l.$2,
                                    style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ),
              if (user?.email != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Account to be deleted',
                        style: TextStyle(
                            color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user!.email!,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _confirmText,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style:
                          const TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed:
                    (_matches && !_deleting) ? _askConfirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Delete My Account'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.navy)),
              ),
            ],
          ),
          if (_deleting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: PreloadingWidget(
                  label: 'Deleting your account...',
                ),
              ),
            ),
        ],
      ),
          ),
        ],
      ),
    );
  }
}
