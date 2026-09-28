import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Global search — mirrors app/search.tsx +
/// src/core/firebase/services/search.ts.
///
/// Client-side filtering over the full `subjects` collection, the latest 50
/// `discussions`, and the first 100 `questions` (lowercased substring on
/// name / title+body / text). 350ms debounce. Recent searches persist under
/// `loksewa:recentSearches` (max 8), the exact key/cap the Expo settings
/// store uses.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _recentKey = 'loksewa:recentSearches';
  static const _maxRecent = 8;
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  String _query = '';
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _discussions = [];
  List<Map<String, dynamic>> _questions = [];
  List<String> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _ctrl.addListener(() => setState(() {}));
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
      if (mounted) {
        setState(() => _recent =
            list.map((e) => e.toString()).take(_maxRecent).toList());
      }
    } catch (_) {}
  }

  Future<void> _saveRecent(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    final next =
        [trimmed, ..._recent.where((e) => e != trimmed)].take(_maxRecent).toList();
    setState(() => _recent = next);
    await PrefsService.setString(_recentKey, json.encode(next));
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = []);
    await PrefsService.setString(_recentKey, json.encode([]));
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  void _runQueryNow(String text) {
    _ctrl.text = text;
    _ctrl.selection =
        TextSelection.collapsed(offset: _ctrl.text.length);
    _search(text);
  }

  Future<void> _search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _searching = false;
        _subjects = [];
        _discussions = [];
        _questions = [];
      });
      return;
    }
    setState(() {
      _query = query.trim();
      _searching = true;
    });
    try {
      final idToken = await AuthService.getValidIdToken();
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
      await _saveRecent(query);
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final showingResults = _query.isNotEmpty;
    final hasResults = _subjects.isNotEmpty ||
        _discussions.isNotEmpty ||
        _questions.isNotEmpty;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          const SubpageHeader(title: 'Search'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ExpoSpacing.screenPadding, 12, ExpoSpacing.screenPadding, 8),
            child: _searchBar(palette),
          ),
          Expanded(
            child: !showingResults
                ? _recentView(palette)
                : _searching
                    ? Center(
                        child: CircularProgressIndicator(
                            color: palette.primary))
                    : !hasResults
                        ? _emptyResults(palette)
                        : _resultsList(palette),
          ),
        ],
      ),
    );
  }

  /// Mirrors src/components/inputs/SearchBar.tsx: surfaceAlt pill, 44 tall,
  /// search icon left, clear (close-circle) right while text is present.
  Widget _searchBar(ExpoPalette palette) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(ExpoRadius.pill),
      ),
      child: Row(
        children: [
          Icon(Icons.search,
              size: 18, color: palette.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              onChanged: _onChanged,
              style: TextStyle(
                  fontSize: ExpoType.body,
                  color: palette.textPrimary),
              decoration: InputDecoration(
                hintText:
                    'Search subjects, questions, discussions...',
                hintStyle:
                    TextStyle(color: palette.textDisabled),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _ctrl.clear();
                _onChanged('');
              },
              child: Icon(Icons.cancel,
                  size: 18, color: palette.textDisabled),
            ),
        ],
      ),
    );
  }

  Widget _recentView(ExpoPalette palette) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: ExpoSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Searches',
                  style: TextStyle(
                      fontSize: ExpoType.bodySmall,
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary)),
              if (_recent.isNotEmpty)
                GestureDetector(
                  onTap: _clearRecent,
                  child: Text('Close',
                      style: TextStyle(
                          fontSize: ExpoType.bodySmall,
                          color: palette.primary)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Mirrors src/components/misc/Chip.tsx.
          Wrap(
            children: [
              for (final q in _recent)
                GestureDetector(
                  onTap: () => _runQueryNow(q),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8, bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius:
                          BorderRadius.circular(ExpoRadius.pill),
                    ),
                    child: Text(q,
                        style: TextStyle(
                            fontSize: ExpoType.bodySmall,
                            fontWeight: FontWeight.w500,
                            color: palette.textSecondary)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Mirrors EmptyState: centred tray icon + h3 semibold title.
  Widget _emptyResults(ExpoPalette palette) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 64, color: palette.textDisabled),
            const SizedBox(height: 12),
            Text('No results found for "$_query"',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: ExpoType.h3,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _resultsList(ExpoPalette palette) {
    return ListView(
      padding: const EdgeInsets.all(ExpoSpacing.screenPadding),
      children: [
        if (_subjects.isNotEmpty) ...[
          _groupHeader(palette, 'All Subjects'),
          const SizedBox(height: 8),
          for (final s in _subjects)
            _resultCard(
              context,
              text: (s['name'] ?? '').toString(),
              onTap: () => context.push('/subjects'),
            ),
          const SizedBox(height: 16),
        ],
        if (_discussions.isNotEmpty) ...[
          _groupHeader(palette, 'Discussion'),
          const SizedBox(height: 8),
          for (final d in _discussions)
            _resultCard(
              context,
              text: (d['title'] ?? '').toString(),
              onTap: () {
                final id =
                    (d['id'] ?? '').toString();
                if (id.isNotEmpty) {
                  context.push('/discussion/$id', extra: d);
                }
              },
            ),
          const SizedBox(height: 16),
        ],
        if (_questions.isNotEmpty) ...[
          _groupHeader(palette, 'Questions'),
          const SizedBox(height: 8),
          for (final q in _questions)
            _resultCard(
              context,
              text: (q['text'] ?? '').toString(),
              maxLines: 2,
            ),
        ],
      ],
    );
  }

  Widget _groupHeader(ExpoPalette palette, String title) {
    return Text(title,
        style: TextStyle(
            fontSize: ExpoType.bodySmall,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary));
  }

  /// Mirrors the search result rows: a plain Card with body text.
  /// Subjects open the subjects list; discussions open the discussion;
  /// questions have no action — exactly like app/search.tsx.
  Widget _resultCard(BuildContext context,
      {required String text, VoidCallback? onTap, int? maxLines}) {
    final palette = ExpoPalette.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Text(text,
          maxLines: maxLines,
          overflow:
              maxLines != null ? TextOverflow.ellipsis : null,
          style: TextStyle(
              fontSize: ExpoType.body,
              color: palette.textPrimary)),
    );
    return Card(
      color: palette.surface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ExpoRadius.md),
      ),
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius:
                  BorderRadius.circular(ExpoRadius.md),
              child: content,
            ),
    );
  }
}
