import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:loksewa_solution/theme/app_theme.dart';
import '../../widgets/subpage_header.dart';

/// Constitution index — mirrors app/constitution/index.tsx.
///
/// The constitution content is static JSON hosted at
/// `https://nepal-constitution-json.pages.dev` (manifest.json → index.json →
/// parts/*.json), cached per the Expo service. NP/EN language toggle, search
/// filter, and section cards. Tapping a card opens the section reader.
class ConstitutionScreen extends StatefulWidget {
  const ConstitutionScreen({super.key});

  @override
  State<ConstitutionScreen> createState() => _ConstitutionScreenState();
}

class _ConstitutionScreenState extends State<ConstitutionScreen> {
  static const _base = 'https://nepal-constitution-json.pages.dev';
  late Future<List<Map<String, dynamic>>> _future;
  String _lang = 'np'; // 'np' | 'en'
  String _query = '';
  String _docTitleNp = '';
  String _docTitleEn = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final manifestRes = await http.get(Uri.parse('$_base/manifest.json'));
    if (manifestRes.statusCode != 200) {
      throw Exception('manifest: ${manifestRes.statusCode}');
    }
    final manifest = json.decode(manifestRes.body) as Map<String, dynamic>;
    final indexFile = (manifest['indexFile'] ?? 'index.json').toString();
    final indexRes = await http.get(Uri.parse('$_base/$indexFile'));
    if (indexRes.statusCode != 200) {
      throw Exception('index: ${indexRes.statusCode}');
    }
    final index = json.decode(indexRes.body) as Map<String, dynamic>;
    _docTitleNp = (index['titleNp'] ?? '').toString();
    _docTitleEn = (index['titleEn'] ?? '').toString();
    final files = index['files'];
    final List list = files is List ? files : [];
    final entries = list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    entries.sort((a, b) =>
        ((a['order'] ?? 0) as num).compareTo((b['order'] ?? 0) as num));
    return entries;
  }

  String _sectionLabel(Map<String, dynamic> e) {
    final type = (e['sectionType'] ?? '').toString();
    if (type == 'preamble') return _lang == 'np' ? 'प्रस्तावना' : 'Preamble';
    if (type == 'schedule') {
      final no = e['scheduleNo'];
      return _lang == 'np' ? 'अनुसूची $no' : 'Schedule $no';
    }
    final no = e['partNo'];
    return _lang == 'np' ? 'भाग $no' : 'Part $no';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: _docTitleNp.isNotEmpty && _lang == 'np'
            ? _docTitleNp
            : (_docTitleEn.isNotEmpty ? _docTitleEn : 'Constitution'), actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'np', label: Text('ने')),
                ButtonSegment(value: 'en', label: Text('EN')),
              ],
              selected: {_lang},
              onSelectionChanged: (s) => setState(() => _lang = s.first),
              style: ButtonStyle(
                foregroundColor:
                    WidgetStateProperty.all(Colors.white),
              ),
            ),
          ),
        ]),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load constitution:\n${snap.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final all = snap.data ?? [];
          final q = _query.trim().toLowerCase();
          final items = all.where((e) {
            if (q.isEmpty) return true;
            final np = (e['titleNp'] ?? '').toString().toLowerCase();
            final en = (e['titleEn'] ?? '').toString().toLowerCase();
            return np.contains(q) || en.contains(q);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search parts & schedules…',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text('No sections found.',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final e = items[i];
                          final title = _lang == 'np'
                              ? (e['titleNp'] ?? '').toString()
                              : (e['titleEn'] ?? '').toString();
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.navy
                                    .withValues(alpha: 0.1),
                                child: Text(
                                  '${(e['order'] ?? 0)}',
                                  style: const TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(
                                  title.isEmpty
                                      ? (e['titleEn'] ?? '').toString()
                                      : title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(_sectionLabel(e)),
                              trailing:
                                  const Icon(Icons.chevron_right),
                              onTap: () {
                                final file =
                                    (e['file'] ?? '').toString();
                                if (file.isEmpty) return;
                                final filename =
                                    file.split('/').last;
                                context.push(
                                    '/constitution/${Uri.encodeComponent(filename)}');
                              },
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
}
