import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';

/// Constitution index — mirrors app/constitution/index.tsx.
///
/// The constitution content is static JSON hosted at
/// `https://nepal-constitution-json.pages.dev` (manifest.json → index.json →
/// parts/*.json), cached per the Expo service. NP/EN language toggle, manual
/// refresh limited to once per day, search filter, intro card, and 02-padded
/// order badges on section cards. Tapping a card opens the section reader.
class ConstitutionScreen extends StatefulWidget {
  const ConstitutionScreen({super.key});

  @override
  State<ConstitutionScreen> createState() => _ConstitutionScreenState();
}

class _ConstitutionScreenState extends State<ConstitutionScreen> {
  static const _base = 'https://nepal-constitution-json.pages.dev';
  static const _manualRefreshKey = 'constitution/manual-refresh-date';

  late Future<List<Map<String, dynamic>>> _future;
  String _lang = 'np'; // 'np' | 'en'
  String _query = '';
  String _docTitleNp = '';
  String _docTitleEn = '';
  int _totalContentFiles = 0;
  bool _canManualRefresh = true;
  bool _manualRefreshing = false;

  bool get _np => _lang == 'np';

  @override
  void initState() {
    super.initState();
    _future = _load();
    _readManualRefreshState();
  }

  static String _localDateKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _readManualRefreshState() async {
    try {
      final last = await PrefsService.getString(_manualRefreshKey);
      if (!mounted) return;
      setState(() => _canManualRefresh = last != _localDateKey());
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _load({bool bustCache = false}) async {
    final cacheBust =
        bustCache ? '?t=${DateTime.now().millisecondsSinceEpoch}' : '';
    final manifestRes =
        await http.get(Uri.parse('$_base/manifest.json$cacheBust'));
    if (manifestRes.statusCode != 200) {
      throw Exception('manifest: ${manifestRes.statusCode}');
    }
    final manifest = json.decode(manifestRes.body) as Map<String, dynamic>;
    final indexFile = (manifest['indexFile'] ?? 'index.json').toString();
    final indexRes =
        await http.get(Uri.parse('$_base/$indexFile$cacheBust'));
    if (indexRes.statusCode != 200) {
      throw Exception('index: ${indexRes.statusCode}');
    }
    final index = json.decode(indexRes.body) as Map<String, dynamic>;
    _docTitleNp = (index['titleNp'] ?? '').toString();
    _docTitleEn = (index['titleEn'] ?? '').toString();
    _totalContentFiles =
        (index['totalContentFiles'] as num?)?.toInt() ?? 0;
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

  /// Mirrors `refreshConstitutionManually` — one forced remote re-fetch per
  /// local day, then the part cache is invalidated (each part re-downloads
  /// on next open in the reader).
  Future<void> _manualRefresh() async {
    if (_manualRefreshing) return;
    if (!_canManualRefresh) {
      showToast(
        context,
        _np
            ? 'आजको manual refresh प्रयोग भइसकेको छ। भोलि फेरि प्रयास गर्नुहोस्।'
            : 'Today\u2019s manual refresh has already been used. Please try again tomorrow.',
        ToastVariant.warning,
      );
      return;
    }
    setState(() => _manualRefreshing = true);
    try {
      final fresh = await _load(bustCache: true);
      await PrefsService.setString(_manualRefreshKey, _localDateKey());
      if (!mounted) return;
      setState(() {
        _future = Future.value(fresh);
        _canManualRefresh = false;
      });
      showToast(
        context,
        _np ? 'नयाँ संविधान डेटा डाउनलोड भयो।' : 'New Constitution data downloaded.',
        ToastVariant.success,
      );
    } catch (_) {
      if (!mounted) return;
      showToast(
        context,
        _np
            ? 'नयाँ डेटा डाउनलोड हुन सकेन। फेरि प्रयास गर्नुहोस्।'
            : 'New data could not be downloaded. Please try again.',
        ToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _manualRefreshing = false);
    }
  }

  static const _npDigits = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];

  String _npNum(dynamic v) => v
      .toString()
      .replaceAllMapped(RegExp(r'[0-9]'), (m) => _npDigits[int.parse(m[0]!)]);

  String _sectionLabel(Map<String, dynamic> e, String lang) {
    final type = (e['sectionType'] ?? '').toString();
    if (type == 'preamble') return lang == 'np' ? 'प्रस्तावना' : 'Preamble';
    if (type == 'schedule') {
      final no = e['scheduleNo'];
      return lang == 'np'
          ? 'अनुसूची ${_npNum(no)}'
          : 'Schedule $no';
    }
    final no = e['partNo'];
    return lang == 'np' ? 'भाग ${_npNum(no)}' : 'Part $no';
  }

  @override
  Widget build(BuildContext context) {
    final headerTitle = _np
        ? (_docTitleNp.isNotEmpty ? _docTitleNp : 'नेपालको संविधान')
        : (_docTitleEn.isNotEmpty ? _docTitleEn : 'The Constitution of Nepal');
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: headerTitle, actions: [
            IconButton(
              tooltip: _np
                  ? 'नयाँ डेटा refresh गर्नुहोस्'
                  : 'Refresh Constitution data',
              icon: _manualRefreshing
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(Icons.refresh,
                      color: _canManualRefresh
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.45)),
              onPressed: _manualRefreshing ? null : _manualRefresh,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => setState(
                    () => _lang = _np ? 'en' : 'np'),
                child: Text(
                  _np ? 'EN' : 'ने',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ]),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(_np
                            ? 'संविधान सामग्री तयार हुँदैछ...'
                            : 'Loading Constitution content...'),
                      ],
                    ),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off,
                              size: 46, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(
                              _np
                                  ? 'सामग्री उपलब्ध छैन'
                                  : 'Content unavailable',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(
                            _np
                                ? 'यो खण्ड खोल्न इन्टरनेट जडान आवश्यक छ।'
                                : 'An internet connection is required to open this section.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () =>
                                setState(() => _future = _load()),
                            child: Text(_np
                                ? 'पुनः प्रयास गर्नुहोस्'
                                : 'Retry'),
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
                  final haystack = [
                    (e['titleNp'] ?? '').toString(),
                    (e['titleEn'] ?? '').toString(),
                    _sectionLabel(e, 'np'),
                    _sectionLabel(e, 'en'),
                    (e['order'] ?? '').toString(),
                    (e['partNo'] ?? '').toString(),
                    (e['scheduleNo'] ?? '').toString(),
                  ].join(' ').toLowerCase();
                  return haystack.contains(q);
                }).toList();
                final count = _totalContentFiles > 0
                    ? _totalContentFiles
                    : all.length;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _introCard(count),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        hintText: _np
                            ? 'संविधानका खण्डहरू खोज्नुहोस्'
                            : 'Search Constitution sections',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _np ? 'भागहरू र अनुसूचीहरू' : 'Parts and Schedules',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (items.isEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            const Icon(Icons.search_off,
                                size: 40, color: Colors.grey),
                            const SizedBox(height: 8),
                            Text(
                                _np
                                    ? 'कुनै मिल्दो खण्ड भेटिएन'
                                    : 'No matching section',
                                style: const TextStyle(
                                    color: Colors.grey)),
                            Text(
                                _np
                                    ? 'अर्को भाग वा अनुसूची खोज्नुहोस्।'
                                    : 'Search for another Part or Schedule.',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      )
                    else
                      for (final e in items) _partCard(e),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _introCard(int count) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.library_books_outlined,
                  size: 26, color: AppColors.navy),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _np ? 'संविधानका खण्डहरू' : 'Constitution Sections',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _np
                        ? '${_npNum(count)} वटा खण्ड'
                        : '$count sections',
                    style: TextStyle(
                        fontSize: 12,
                        color: onSurface.withValues(alpha: 0.55)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _partCard(Map<String, dynamic> e) {
    final title = _np
        ? (e['titleNp'] ?? '').toString()
        : (e['titleEn'] ?? '').toString();
    final order = (e['order'] ?? 0).toString().padLeft(2, '0');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final file = (e['file'] ?? '').toString();
          if (file.isEmpty) return;
          final filename = file.split('/').last;
          context
              .push('/constitution/${Uri.encodeComponent(filename)}');
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  order,
                  style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sectionLabel(e, _lang),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title.isEmpty
                          ? (e['titleEn'] ?? '').toString()
                          : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
