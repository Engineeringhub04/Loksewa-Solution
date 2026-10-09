import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../widgets/leaderboard_podium.dart';
import '../../widgets/preloading.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/syllabus_entrance.dart';

/// Leaderboard for a single exam set — mirrors app/exam/[setId]/ranking.tsx
/// same-to-same.
///
/// Deliberately FIXED to its own dark-blue palette (does not follow the app
/// theme): the podium is a designed surface. The podium is pinned above the
/// list; the list scrolls inside a darker rounded sheet. Only each user's
/// BEST attempt counts, ties broken by faster time. Locked until the exam
/// window closes.
class ExamRankingScreen extends StatefulWidget {
  final String setId;
  const ExamRankingScreen({super.key, required this.setId});

  @override
  State<ExamRankingScreen> createState() => _ExamRankingScreenState();
}

// Fixed palette (React: Podium.tsx).
const _bgTop = Color(0xFF12275C);
const _bgBottom = Color(0xFF1D4ED8);
const _card = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)
const _cardBorder = Color(0x2EFFFFFF); // rgba(255,255,255,0.18)
const _text = Colors.white;
const _textDim = Color(0xB8FFFFFF); // rgba(255,255,255,0.72)


class _ExamRankingScreenState extends State<ExamRankingScreen> {
  ExamSet? _set;
  List<RankingRow> _rows = const [];
  bool _loading = true;
  bool _hardRefreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool hard = false}) async {
    if (hard) setState(() => _hardRefreshing = true);
    if (!hard) setState(() => _loading = true);
    try {
      final set = await fetchExamSet(widget.setId);
      if (set == null) throw Exception('Exam set not found');
      final rows = await fetchExamRanking(widget.setId);
      if (!mounted) return;
      setState(() {
        _set = set;
        _rows = rows;
        _loading = false;
        _hardRefreshing = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hardRefreshing = false;
        _error = AppLanguage.tr(
            'Could not load the ranking.', 'र्याङ्किङ लोड हुन सकेन।');
      });
    }
  }

  bool get _ready => !_loading && !_hardRefreshing;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      // Defensive: no inherited text decoration (underline) can reach any
      // text on this page, whatever its source — merged over the ambient
      // style so nothing else changes.
      child: DefaultTextStyle(
        style: DefaultTextStyle.of(context)
            .style
            .copyWith(decoration: TextDecoration.none),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_bgTop, _bgBottom],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                _header(),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back,
                  size: 20, color: _text),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLanguage.tr(
                      'Overall Leaderboard', 'समग्र लिडरबोर्ड'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _text,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  _set?.title ??
                      AppLanguage.tr(
                          'Loading exam…', 'परीक्षा लोड हुँदै…'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: _textDim, fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _hardRefreshing ? null : () => _load(hard: true),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: _hardRefreshing
                  ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _text),
                    )
                  : const Icon(Icons.refresh,
                      size: 19, color: _text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _text)),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: () => _load(hard: true),
                  child: Text(AppLanguage.tr('Retry', 'पुनः प्रयास'))),
            ],
          ),
        ),
      );
    }
    final set = _set;
    if (set != null && !areResultsUnlocked(set, DateTime.now())) {
      // Same unlock gate as summary and review.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline,
                    size: 32, color: _text),
              ),
              const SizedBox(height: 16),
              Text(
                AppLanguage.tr(
                    'Ranking is locked', 'र्याङ्किङ लक छ'),
                style: const TextStyle(
                    color: _text,
                    fontSize: 17,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                AppLanguage.tr(
                    'Rankings unlock after the exam window closes, so results stay fair for everyone taking it.',
                    'परीक्षा समय सकिएपछि र्याङ्किङ खुल्नेछ, सबैका लागि निष्पक्ष।'),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: _textDim, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: _text,
                    side: const BorderSide(color: _textDim)),
                onPressed: () => context.pop(),
                child: Text(AppLanguage.tr('Go back', 'फर्कनुहोस्')),
              ),
            ],
          ),
        ),
      );
    }
    if (!_ready) {
      return PreloadingWidget(
        tinted: true,
        label: AppLanguage.tr(
            'Loading Ranking...', 'र्याङ्किङ लोड हुँदै...'),
      );
    }
    return Column(
      children: [
        // FIXED podium — pinned above the scrolling list.
        // Shared podium UI with the main leaderboard — same UI, only the
        // data differs (exam ranking rows instead of main board rows).
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 14),
          child: SyllabusEntrance(
            delayMs: 0,
            child: LeaderboardPodium(
              entries: [
                _rows.length > 1 ? _toPodiumEntry(_rows[1]) : null,
                _rows.isNotEmpty ? _toPodiumEntry(_rows[0]) : null,
                _rows.length > 2 ? _toPodiumEntry(_rows[2]) : null,
              ],
              emptyLabel: AppLanguage.tr('Open spot', 'खाली स्थान'),
            ),
          ),
        ),
        // The list scrolls inside a darker rounded sheet.
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0x47081436), // rgba(8,20,54,0.28)
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(26),
                topRight: Radius.circular(26),
              ),
            ),
            child: RefreshIndicator.adaptive(
              onRefresh: () => _load(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SyllabusEntrance(
                      delayMs: 0, child: _myCard()),
                  const SizedBox(height: 14),
                  Text(
                    AppLanguage.tr('Rankings', 'र्याङ्किङहरू'),
                    style: const TextStyle(
                        color: _text,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  if (_rows.length <= 3)
                    _emptyRow()
                  else
                    ..._rows
                        .skip(3)
                        .toList()
                        .asMap()
                        .entries
                        .map((e) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 10),
                              child: SyllabusEntrance(
                                delayMs:
                                    (e.key.clamp(0, 8)) * 60,
                                child:
                                    _row(e.key + 4, e.value),
                              ),
                            )),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  ({int position, RankingRow row})? get _myEntry {
    final uid = AuthService.currentUser?.uid ?? '';
    if (uid.isEmpty) return null;
    final index = _rows.indexWhere((r) => r.uid == uid);
    if (index < 0) return null;
    return (position: index + 1, row: _rows[index]);
  }

  /// Maps an exam ranking row to the shared podium entry.
  /// The exam score IS the percent (e.g. 38 -> "38%"), same as before.
  PodiumEntry _toPodiumEntry(RankingRow row) => PodiumEntry(
        name: row.name,
        photoURL: row.photoURL,
        isPro: row.isPro,
        stat: '${row.score}%',
      );

  Widget _nameWithTick(String name,
      {required bool pro,
      required bool filled,
      bool centered = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          centered ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: filled ? _text : _textDim,
            ),
          ),
        ),
        if (pro) ...[
          const SizedBox(width: 3),
          const Icon(Icons.verified, size: 14, color: Color(0xFF38BDF8)),
        ],
      ],
    );
  }

  Widget _myCard() {
    final me = _myEntry;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder, width: 1),
      ),
      child: me == null
          ? Row(
              children: [
                const Icon(Icons.person_add_outlined,
                    size: 22, color: _textDim),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppLanguage.tr(
                        'You have not appeared in this exam yet — attempt it to claim a rank.',
                        'तपाईंले यो परीक्षा दिनुभएको छैन — र्याङ्कका लागि प्रयास गर्नुहोस्।'),
                    style: const TextStyle(
                        color: _textDim, fontSize: 13),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Row(
                  children: [
                    Container(
                      constraints:
                          const BoxConstraints(minWidth: 48),
                      height: 40,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10),
                      decoration: BoxDecoration(
                        color:
                            Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text('#${me.position}',
                            style: const TextStyle(
                                color: _text,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ProfileAvatar(
                      uri: me.row.photoURL,
                      name: me.row.name,
                      size: 44,
                      pro: me.row.isPro,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text('Your Position',
                              style: TextStyle(
                                  color: _textDim, fontSize: 11)),
                          _nameWithTick(me.row.name,
                              pro: me.row.isPro, filled: true),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color:
                            Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text('${me.row.score}%',
                              style: const TextStyle(
                                  color: _text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                          const Text('score',
                              style: TextStyle(
                                  color: _textDim, fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text('${me.row.score} / 100',
                                style: const TextStyle(
                                    color: _text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            const Text('Marks',
                                style: TextStyle(
                                    color: _textDim, fontSize: 11)),
                          ],
                        ),
                      ),
                      Container(
                          width: 1,
                          height: 36,
                          color: Colors.white
                              .withValues(alpha: 0.25)),
                      Expanded(
                        child: Column(
                          children: [
                            Text('${me.row.score}%',
                                style: const TextStyle(
                                    color: _text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            const Text('Percentage',
                                style: TextStyle(
                                    color: _textDim, fontSize: 11)),
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

  Widget _emptyRow() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_outlined,
              size: 20, color: _textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLanguage.tr(
                  'No results yet. Be the first to complete this exam.',
                  'अहिलेसम्म नतिजा छैन। यो परीक्षा सक्ने पहिलो बन्नुहोस्।'),
              style:
                  const TextStyle(color: _textDim, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(int position, RankingRow row) {
    final uid = AuthService.currentUser?.uid ?? '';
    final isMe = row.uid == uid && uid.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe ? const Color(0xFF34D399) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0x4094A3B8), // rgba(148,163,184,0.25)
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text('$position',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isMe ? _text : const Color(0xFF334155))),
            ),
          ),
          const SizedBox(width: 10),
          ProfileAvatar(
              uri: row.photoURL,
              name: row.name,
              size: 38,
              pro: row.isPro),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _nameWithTick(
                  isMe ? '${row.name} (You)' : row.name,
                  pro: row.isPro,
                  filled: true,
                ),
                Text('Rank #$position',
                    style: TextStyle(
                        fontSize: 11,
                        color: isMe
                            ? _textDim
                            : const Color(0xFF64748B))),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withValues(alpha: 0.2)
                  : const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('${row.score}%',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isMe ? _text : const Color(0xFF15803D))),
          ),
        ],
      ),
    );
  }
}
