import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Edit profile — mirrors app/edit-profile.tsx.
///
/// Reads `users/{uid}` (firstName, lastName, dob, gender, photoURL; email is
/// locked/display-only). Save is disabled until the form is dirty; navigating
/// back with unsaved changes asks for confirmation. Photo upload is not
/// available in this build (no image-picker dependency) — the current photoURL
/// is shown read-only.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  String _gender = '';
  String _email = '';
  String? _photoUrl;

  String _origFirst = '';
  String _origLast = '';
  String _origDob = '';
  String _origGender = '';

  @override
  void initState() {
    super.initState();
    _load();
    for (final c in [_firstCtrl, _lastCtrl, _dobCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _firstCtrl.text.trim() != _origFirst ||
      _lastCtrl.text.trim() != _origLast ||
      _dobCtrl.text.trim() != _origDob ||
      _gender != _origGender;

  String? get _dobError {
    final v = _dobCtrl.text.trim();
    if (v.isEmpty) return null;
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(v);
    if (m == null) return 'Use DD/MM/YYYY';
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return 'Invalid date';
    final now = DateTime.now().year;
    if (y < 1900 || y > now) return 'Invalid year';
    return null;
  }

  Future<void> _load() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    try {
      final idToken = await AuthService.getValidIdToken() ?? '';
      final doc = await FirestoreRest.getDocument('users/$uid', idToken: idToken);
      final d = doc ?? {};
      _firstCtrl.text = _origFirst = (d['firstName'] ?? '').toString();
      _lastCtrl.text = _origLast = (d['lastName'] ?? '').toString();
      _dobCtrl.text = _origDob = (d['dob'] ?? '').toString();
      _gender = _origGender = (d['gender'] ?? '').toString();
      _email = (d['email'] ?? AuthService.currentUser?.email ?? '').toString();
      final p = (d['photoURL'] ?? '').toString();
      _photoUrl = p.isEmpty ? null : p;
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load profile: $e';
      });
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Discard them?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard')),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _save() async {
    if (_dobError != null) return;
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      final idToken = await AuthService.getValidIdToken() ?? '';
      await FirestoreRest.setDocument(
        'users/$uid',
        {
          'firstName': _firstCtrl.text.trim(),
          'lastName': _lastCtrl.text.trim(),
          'dob': _dobCtrl.text.trim(),
          'gender': _gender,
        },
        idToken: idToken,
        merge: true,
      );
      _origFirst = _firstCtrl.text.trim();
      _origLast = _lastCtrl.text.trim();
      _origDob = _dobCtrl.text.trim();
      _origGender = _gender;
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved')),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) context.pop();
      },
      child: Scaffold(
        body: Column(
          children: [
            const SubpageHeader(title: 'Edit Profile'),
            Expanded(
              child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton(
                              onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 44,
                          backgroundColor: AppColors.navy.withValues(alpha: 0.1),
                          backgroundImage: _photoUrl != null
                              ? NetworkImage(_photoUrl!)
                              : null,
                          child: _photoUrl == null
                              ? Text(
                                  (_firstCtrl.text.isNotEmpty
                                          ? _firstCtrl.text[0]
                                          : 'U')
                                      .toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 32, color: AppColors.navy),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _field('First name', _firstCtrl),
                      const SizedBox(height: 12),
                      _field('Last name', _lastCtrl),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _dobCtrl,
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          labelText: 'Date of birth (DD/MM/YYYY)',
                          border: const OutlineInputBorder(),
                          errorText: _dobError,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _gender.isEmpty ? null : _gender,
                        decoration: const InputDecoration(
                          labelText: 'Gender',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'male', child: Text('Male')),
                          DropdownMenuItem(
                              value: 'female', child: Text('Female')),
                          DropdownMenuItem(
                              value: 'other', child: Text('Other')),
                        ],
                        onChanged: (v) =>
                            setState(() => _gender = v ?? ''),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: TextEditingController(text: _email),
                        readOnly: true,
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Email (cannot be changed)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: (_dirty && !_saving && _dobError == null)
                              ? _save
                              : null,
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Save changes'),
                        ),
                      ),
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
