import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Global search — mirrors app/search.tsx.
///
/// Debounced (350ms) search across subjects, discussions and questions with
/// grouped results; recent searches persist in SharedPreferences.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _recentKey = 'loksewa:recentSearches';
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  bool _searched = false;
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _discussions = [];
  List<Map<String, dynamic>> _questions = [];
  List<String> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final raw = await PrefsService.getString(_recentKey);
      final List list = raw == null || raw.isEmpty ? [] : json.decode(raw);
      setState(() => _recent =
          list.map((e) => e.toString()).take(10).toList());
    } catch (_) {}
  }

  Future<void> _saveRecent(String q) async {
    final next = [q, ..._recent.where((e) => e != q)].take(10).toList();
    setState(() => _recent = next);
    await PrefsService.setString(_recentKey, json.encode(next));
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _searched = false;
        _subjects = [];
        _discussions = [];
        _questions = [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _searched = true;
    });
    try {
      final idToken = await AuthService.getValidIdToken() ?? '';
      final results = await Future.wait([
        FirestoreRest.listDocuments('subjects', idToken: idToken),
        FirestoreRest.listDocuments('discussions',
            idToken: idToken, pageSize: 50),
        FirestoreRest.listDocuments('questions',
            idToken: idToken, pageSize: 100),
      ]);
      if (!mounted) return;
      setState(() {
        _subjects = results[0]
            .where((s) =>
                (s['name'] ?? '').toString().toLowerCase().contains(q))
            .toList();
        _discussions = results[1]
            .where((d) =>
                (d['title'] ?? '').toString().toLowerCase().contains(q) ||
                (d['body'] ?? '').toString().toLowerCase().contains(q))
            .toList();
        _questions = results[2]
            .where((x) =>
                (x['text'] ?? '').toString().toLowerCase().contains(q))
            .toList();
        _searching = false;
      });
      await _saveRecent(query.trim());
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total =
        _subjects.length + _discussions.length + _questions.length;
    return Scaffold(
      body: Column(
        children: [
          const SubpageHeader(title: 'Search'),
          Expanded(
            child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search subjects, discussions, questions…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctrl.clear();
                          _onChanged('');
                          setState(() {});
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onChanged,
              onSubmitted: _search,
            ),
          ),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : !_searched
                    ? _recentView()
                    : total == 0
                        ? Center(
                            child: Text(
                              'No results for "${_ctrl.text.trim()}".',
                              style:
                                  const TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.all(12),
                            children: [
                              if (_subjects.isNotEmpty) ...[
                                _groupHeader('Subjects', _subjects.length),
                                for (final s in _subjects)
                                  _tile(
                                    Icons.book,
                                    (s['name'] ?? '').toString(),
                                    (s['description'] ?? '').toString(),
                                    () {},
                                  ),
                              ],
                              if (_discussions.isNotEmpty) ...[
                                _groupHeader('Discussions',
                                    _discussions.length),
                                for (final d in _discussions)
                                  _tile(
                                    Icons.forum,
                                    (d['title'] ?? '').toString(),
                                    (d['body'] ?? '').toString(),
                                    () {
                                      final id = (d['docId'] ??
                                              d['id'] ??
                                              '')
                                          .toString();
                                      if (id.isNotEmpty) {
                                        context.push('/discussion/$id',
                                            extra: d);
                                      }
                                    },
                                  ),
                              ],
                              if (_questions.isNotEmpty) ...[
                                _groupHeader('Questions',
                                    _questions.length),
                                for (final x in _questions)
                                  _tile(
                                    Icons.quiz,
                                    (x['text'] ?? '').toString(),
                                    '',
                                    () {},
                                  ),
                              ],
                            ],
                          ),
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }

  Widget _recentView() {
    if (_recent.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Search across subjects, discussions and questions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('Recent searches',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final r in _recent)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(r),
            onTap: () {
              _ctrl.text = r;
              _search(r);
            },
          ),
      ],
    );
  }

  Widget _groupHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text('$title ($count)',
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: AppColors.navy)),
    );
  }

  Widget _tile(
      IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.navy),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
    );
  }
}
