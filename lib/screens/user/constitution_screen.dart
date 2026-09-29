import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';

import '../../widgets/preloading.dart';
import '../../widgets/subpage_header.dart';

/// Constitution index — mirrors app/constitution/index.tsx.
///
/// Static JSON hosted at `https://nepal-constitution-json.pages.dev`
/// (manifest.json → index.json → parts/*.json), NP/EN language toggle with a
/// cross-fade, manual refresh limited to once per day, search filter, intro
/// card, and 02-padded order badges on part cards. Tapping a card opens the
/// section reader.
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

  // Language cross-fade: out 100ms / in 180ms.
  double _fadeOpacity = 1.0;

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

  /// Language toggle with the React cross-fade (100ms out / 180ms in).
  void _toggleLanguage() {
    if (_fadeOpacity != 1.0) return;
    setState(() => _fadeOpacity = 0.0);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      setState(() {
        _lang = _np ? 'en' : 'np';
        _fadeOpacity = 1.0;
      });
    });
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerTitle = _np
        ? (_docTitleNp.isNotEmpty ? _docTitleNp : 'नेपालको संविधान')
        : (_docTitleEn.isNotEmpty ? _docTitleEn : 'The Constitution of Nepal');
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B1120) : const Color(0xFFF5F6FA),
      body: SafeArea(
        // SubpageHeader paints behind the status bar itself
        // (React parity) — no top inset here or the header gets pushed down.
        top: false,
        child: Column(
          children: [
            SubpageHeader(
              title: headerTitle,
              actions: [
                // Language button.
                GestureDetector(
                  onTap: _toggleLanguage,
                  child: Container(
                    height: 36,
                    constraints: const BoxConstraints(minWidth: 42),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color:
                          Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.language,
                            size: 17, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(_np ? 'EN' : 'ने',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Refresh button.
                Opacity(
                  opacity: _canManualRefresh ? 1.0 : 0.48,
                  child: GestureDetector(
                    onTap:
                        _manualRefreshing ? null : _manualRefresh,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color:
                            Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: _manualRefreshing
                            ? const SizedBox(
                                width: 19,
                                height: 19,
                                child:
                                    CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                              )
                            : const Icon(Icons.refresh,
                                size: 19,
                                color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState ==
                      ConnectionState.waiting) {
                    return PreloadingWidget(
                      tinted: false,
                      label: _np
                          ? 'संविधान सामग्री तयार हुँदैछ...'
                          : 'Preparing the constitution content...',
                      hint: _np
                          ? 'खण्डहरूको सूची तयार हुँदैछ'
                          : 'Loading the section list',
                    );
                  }
                  if (snap.hasError) {
                    return _errorState(isDark);
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

                  return AnimatedOpacity(
                    duration: Duration(
                        milliseconds:
                            _fadeOpacity == 1.0 ? 180 : 100),
                    opacity: _fadeOpacity,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _introCard(count, isDark),
                        const SizedBox(height: 12),
                        _searchBar(isDark),
                        const SizedBox(height: 12),
                        Text(
                          _np
                              ? 'भागहरू र अनुसूचीहरू'
                              : 'Parts and Schedules',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? const Color(0xFFF1F5F9)
                                  : const Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 8),
                        if (items.isEmpty)
                          _emptyState(isDark)
                        else
                          for (var i = 0; i < items.length; i++)
                            Padding(
                              padding: EdgeInsets.only(
                                  bottom: i == items.length - 1
                                      ? 0
                                      : 8),
                              child: _PartEntrance(
                                delayMs:
                                    math.min(i, 8) * 35,
                                child: _partCard(
                                    items[i], isDark),
                              ),
                            ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(bool isDark) {
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 46, color: secondary),
            const SizedBox(height: 14),
            Text(_np ? 'सामग्री उपलब्ध छैन' : 'Content unavailable',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              _np
                  ? 'यो खण्ड खोल्न इन्टरनेट जडान आवश्यक छ। पहिले सुरक्षित गरिएको खण्ड भए इन्टरनेटबिना पनि खुल्नेछ।'
                  : 'An internet connection is required to open this content. Previously saved sections open offline.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: secondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  setState(() => _future = _load()),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB)),
              child: Text(
                  _np ? 'पुनः प्रयास गर्नुहोस्' : 'Retry',
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(bool isDark) {
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 40, color: secondary),
          const SizedBox(height: 8),
          Text(_np ? 'कुनै मिल्दो खण्ड भेटिएन' : 'No matching section',
              style: TextStyle(fontSize: 14, color: secondary)),
          const SizedBox(height: 4),
          Text(
              _np
                  ? 'अर्को भाग वा अनुसूची खोज्नुहोस्।'
                  : 'Search for another Part or Schedule.',
              style: TextStyle(fontSize: 12, color: secondary)),
        ],
      ),
    );
  }

  /// Intro card — mirrors React introCard.
  Widget _introCard(int count, bool isDark) {
    final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
    final divider =
        isDark ? const Color(0xFF263349) : const Color(0xFFE5EAF4);
    final textPrimary =
        isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final primary =
        isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: divider, width: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.library_books_outlined,
                size: 26, color: primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_np ? 'संविधानका खण्डहरू' : 'Constitution Sections',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: textPrimary)),
                const SizedBox(height: 2),
                Text(
                  _np
                      ? '${_npNum(count)} वटा खण्ड'
                      : '$count sections',
                  style:
                      TextStyle(fontSize: 12, color: secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar(bool isDark) {
    final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
    final divider =
        isDark ? const Color(0xFF263349) : const Color(0xFFE5EAF4);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: divider, width: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: secondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: _np
                    ? 'संविधानका खण्डहरू खोज्नुहोस्'
                    : 'Search Constitution sections',
                hintStyle:
                    TextStyle(fontSize: 14, color: secondary),
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// Part card — mirrors React sectionCard.
  Widget _partCard(Map<String, dynamic> e, bool isDark) {
    final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
    final divider =
        isDark ? const Color(0xFF263349) : const Color(0xFFE5EAF4);
    final textPrimary =
        isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final primary =
        isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);
    final title = _np
        ? (e['titleNp'] ?? '').toString()
        : (e['titleEn'] ?? '').toString();
    final order = (e['order'] ?? 0).toString().padLeft(2, '0');
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          final file = (e['file'] ?? '').toString();
          if (file.isEmpty) return;
          final filename = file.split('/').last;
          context
              .push('/constitution/${Uri.encodeComponent(filename)}');
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: divider, width: 0.5),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(order,
                    style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_sectionLabel(e, _lang),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: secondary)),
                    const SizedBox(height: 3),
                    Text(
                      title.isNotEmpty
                          ? title
                          : (e['titleEn'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right,
                  size: 21, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Staggered entrance — mirrors `FadeInDown.delay(min(index, 8) * 35)`
/// with a 260ms fade+slide.
class _PartEntrance extends StatefulWidget {
  final int delayMs;
  final Widget child;

  const _PartEntrance({required this.delayMs, required this.child});

  @override
  State<_PartEntrance> createState() => _PartEntranceState();
}

class _PartEntranceState extends State<_PartEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved =
        CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - curved.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
