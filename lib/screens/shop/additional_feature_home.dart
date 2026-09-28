import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/prefs_service.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';

/// Shared home screen for the two "additional feature" hubs (GK and PM) —
/// mirrors `src/components/additional/AdditionalFeatureScreen.tsx`.
///
/// Data:
/// - page doc: `app_additional_feature_pages/{featureId}__all__all`
/// - per-topic practice progress: local JSON key
///   `af_practice_{featureId}_{topicId}` =
///   `{ dailyDate, attemptedQuestionIds: [...], selectedAnswerIds: {...} }`
/// - offline flags: `af_offline_{featureId}_complete` = 'true' and
///   `af_offline_{featureId}_date` = yyyy-MM-dd
///
/// Logic matches React exactly:
/// - topics filtered to `isPublished !== false`, sorted by `order`
/// - per-topic percent = min(100, round(attempted / questionCount * 100))
/// - overall percent = QUESTIONCOUNT-WEIGHTED mean of topic percents
/// - offline download fetches every topic's bank, then marks complete
class AdditionalFeatureHomeScreen extends StatefulWidget {
  final String featureId;
  final IconData heroIcon;
  final String reactSubtitle;

  const AdditionalFeatureHomeScreen({
    super.key,
    required this.featureId,
    required this.heroIcon,
    this.reactSubtitle = 'GK & Current Affairs',
  });

  @override
  State<AdditionalFeatureHomeScreen> createState() =>
      _AdditionalFeatureHomeScreenState();
}

class _Topic {
  final String topicId;
  final String titleEn;
  final String titleNp;
  final int order;
  final int questionCount;
  final String questionBankId;
  int attempted = 0;
  _Topic({
    required this.topicId,
    required this.titleEn,
    required this.titleNp,
    required this.order,
    required this.questionCount,
    required this.questionBankId,
  });
}

class _AdditionalFeatureHomeScreenState
    extends State<AdditionalFeatureHomeScreen> {
  Map<String, dynamic>? _page;
  List<_Topic> _topics = [];
  bool _loading = true;
  String? _error;
  bool _offlineComplete = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _fid => widget.featureId;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final idToken = await AuthService.getValidIdToken();
      final page = await FirestoreRest.getDocument(
        'app_additional_feature_pages/${_fid}__all__all',
        idToken: idToken,
      );
      final rawTopics = page?['topics'];
      final list = rawTopics is List ? rawTopics : const [];
      final topics = <_Topic>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        if (m['isPublished'] == false) continue;
        topics.add(_Topic(
          topicId: (m['topicId'] ?? '').toString(),
          titleEn: (m['titleEn'] ?? '').toString(),
          titleNp: (m['titleNp'] ?? '').toString(),
          order: (m['order'] is num) ? (m['order'] as num).toInt() : 0,
          questionCount:
              (m['questionCount'] is num) ? (m['questionCount'] as num).toInt() : 0,
          questionBankId: (m['questionBankId'] ?? '').toString(),
        ));
      }
      topics.sort((a, b) => a.order.compareTo(b.order));

      // Per-topic attempted counts from local practice cache.
      for (final t in topics) {
        final raw = await PrefsService.getString(
            'af_practice_${_fid}_${t.topicId}');
        if (raw == null || raw.isEmpty) continue;
        try {
          final saved = json.decode(raw) as Map<String, dynamic>;
          final ids = saved['attemptedQuestionIds'];
          if (ids is List) t.attempted = ids.length;
        } catch (_) {}
      }

      final completeFlag =
          await PrefsService.getString('af_offline_${_fid}_complete');
      final completeDate =
          await PrefsService.getString('af_offline_${_fid}_date');
      final today = _dateKey(DateTime.now());
      setState(() {
        _page = page;
        _topics = topics;
        _offlineComplete = completeFlag == 'true' && completeDate == today;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load topics. Pull down to retry.';
        _loading = false;
      });
    }
  }

  static String _dateKey(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  int _topicPercent(_Topic t) {
    if (t.questionCount <= 0) return 0;
    final p = (t.attempted / t.questionCount * 100).round();
    return p.clamp(0, 100);
  }

  /// Overall progress = QUESTIONCOUNT-WEIGHTED mean (matches React).
  int get _overallPercent {
    final total =
        _topics.fold<int>(0, (sum, t) => sum + t.questionCount);
    if (total == 0) return 0;
    final weighted = _topics.fold<double>(
        0, (sum, t) => sum + t.questionCount * _topicPercent(t));
    return (weighted / total).round();
  }

  IconData _topicIcon(_Topic t) {
    final name = '${t.titleEn} ${t.titleNp}'.toLowerCase();
    if (name.contains('geograph')) return Icons.public;
    if (name.contains('history') || name.contains('histor')) return Icons.history;
    if (name.contains('science') || name.contains('technology')) {
      return Icons.science;
    }
    if (name.contains('constitution') || name.contains('law')) {
      return Icons.shield_outlined;
    }
    if (name.contains('econom')) return Icons.trending_up;
    if (name.contains('environment') || name.contains('climate')) {
      return Icons.eco;
    }
    if (name.contains('administ') || name.contains('govern')) {
      return Icons.business;
    }
    if (name.contains('management') || name.contains('leadership')) {
      return Icons.work_outline;
    }
    if (name.contains('planning') || name.contains('development')) {
      return Icons.map_outlined;
    }
    if (name.contains('finance') || name.contains('budget')) {
      return Icons.account_balance_wallet_outlined;
    }
    if (name.contains('service') || name.contains('delivery')) {
      return Icons.people_outline;
    }
    return Icons.auto_awesome;
  }

  Future<void> _downloadOffline() async {
    if (_downloading || _topics.isEmpty) return;
    setState(() => _downloading = true);
    try {
      final idToken = await AuthService.getValidIdToken();
      for (final t in _topics) {
        final docId = '${_fid}__all__all__${t.topicId}';
        await FirestoreRest.getDocument(
          'app_additional_feature_question_banks/$docId',
          idToken: idToken,
        );
      }
      await PrefsService.setString('af_offline_${_fid}_complete', 'true');
      await PrefsService.setString(
          'af_offline_${_fid}_date', _dateKey(DateTime.now()));
      if (mounted) {
        setState(() => _offlineComplete = true);
        showToast(context, 'All topics saved for offline access.',
            ToastVariant.success);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'Offline download failed. Please try again.',
            ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleEn = (_page?['titleEn'] as String?) ?? widget.reactSubtitle;
    final titleNp = (_page?['titleNp'] as String?) ?? '';
    final theme = Theme.of(context);
    final onCard = theme.colorScheme.onSurface;

    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: titleEn),
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                            color: theme.colorScheme.primary),
                        const SizedBox(height: 8),
                        Text('Loading topics...',
                            style: TextStyle(
                                fontSize: 15,
                                color: onCard.withValues(alpha: 0.6))),
                      ],
                    ),
                  )
                : _error != null
                    ? RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          children: [
                            const SizedBox(height: 60),
                            Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(_error!,
                                    textAlign: TextAlign.center,
                                    style:
                                        TextStyle(color: onCard.withValues(alpha: 0.6))),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _heroCard(titleEn, titleNp),
                            const SizedBox(height: 12),
                            _infoCard(),
                            const SizedBox(height: 20),
                            if (_topics.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 40),
                                  child: Text(
                                    'Topics are coming soon.',
                                    style: TextStyle(
                                        color: onCard.withValues(alpha: 0.6)),
                                  ),
                                ),
                              )
                            else
                              for (final t in _topics) ...[
                                _topicCard(t, onCard),
                                const SizedBox(height: 10),
                              ],
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// Hero card — mirrors React AdditionalFeatureScreen exactly:
  /// theme-aware surface (NOT hardcoded navy), primary icon tile,
  /// count badge, weighted progress, and the Offline Access button.
  Widget _heroCard(String titleEn, String titleNp) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF151D2E) : Colors.white;
    final divider =
        isDark ? const Color(0xFF263349) : const Color(0xFFE5EAF4);
    final track =
        isDark ? const Color(0xFF26314B) : const Color(0xFFE2E8F0);
    final textPrimary =
        isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final primary =
        isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);
    final success =
        isDark ? const Color(0xFF22C55E) : const Color(0xFF16A34A);
    final overall = _overallPercent;
    final disabled =
        _downloading || _offlineComplete || _topics.isEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: divider, width: 1),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(widget.heroIcon,
                    size: 28, color: primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleEn,
                      style: TextStyle(
                          color: primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      titleEn,
                      style: TextStyle(
                          color: textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    if (titleNp.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(top: 3),
                        child: Text(
                          titleNp,
                          style: TextStyle(
                              color: secondary, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints:
                    const BoxConstraints(minWidth: 48),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$_topics.length',
                        style: TextStyle(
                            color: primary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    Text('Topics',
                        style: TextStyle(
                            color: secondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overall Practice Progress',
                style: TextStyle(
                    color: secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '$overall%',
                style: TextStyle(
                    color: success,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: overall / 100,
              minHeight: 6,
              backgroundColor: track,
              valueColor:
                  AlwaysStoppedAnimation<Color>(success),
            ),
          ),
          const SizedBox(height: 17),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: _offlineComplete
                  ? success.withValues(alpha: 0.15)
                  : primary,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: disabled ? null : _downloadOffline,
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: 47),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: _offlineComplete
                            ? success.withValues(alpha: 0.55)
                            : primary,
                        width: 1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      if (_downloading)
                        const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white),
                        )
                      else
                        Icon(
                            _offlineComplete
                                ? Icons.check_circle_outline
                                : Icons.download_outlined,
                            size: 19,
                            color: _offlineComplete
                                ? success
                                : Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _offlineComplete
                              ? 'Saved for offline access'
                              : 'Offline Access',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _offlineComplete
                                  ? success
                                  : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (!_offlineComplete &&
                          !_downloading) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward,
                            size: 17, color: Colors.white),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);
    final textPrimary =
        isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.047),
        border: Border.all(
            color: primary.withValues(alpha: 0.21), width: 1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.info_outline,
                size: 22, color: primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'New questions are added from time to time. If new questions are available, please connect to the internet after 12:00 AM and tap \u201cOffline Access\u201d to update your offline questions.',
              style: TextStyle(
                  fontSize: 12,
                  height: 19 / 12,
                  color: textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topicCard(_Topic t, Color onCard) {
    final pct = _topicPercent(t);
    final icon = _topicIcon(t);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8);
    final secondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(
          '/additional-features/${_fid}/${t.topicId}',
          extra: {
            'featureId': _fid,
            'topicId': t.topicId,
            'topicTitleEn': t.titleEn,
            'topicTitleNp': t.titleNp,
            'questionBankId': t.questionBankId,
          },
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    size: 24, color: primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOPIC ${t.order.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.titleEn.isNotEmpty ? t.titleEn : t.titleNp,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    if (t.titleNp.isNotEmpty)
                      Text(
                        t.titleNp,
                        style: TextStyle(
                            fontSize: 12,
                            color: onCard.withValues(alpha: 0.6)),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: pct / 100,
                              minHeight: 6,
                              backgroundColor:
                                  onCard.withValues(alpha: 0.1),
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(
                                      Color(0xFF22C55E)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$pct%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: onCard.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}
