import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';
import '../../widgets/app_modal_shell.dart';
import '../../widgets/trash_icon.dart';
import 'bookmark_tracks.dart';
import 'bookmark_remove_dialog.dart';

/// Bookmark detail — premium redesign.
///
/// Renders the saved snapshot payload: a track hero card (track identity +
/// saved date), meta rows, the question with staggered premium option tiles
/// (correct option + explanation revealed only via the Reveal toggle), and a
/// premium article layout for article/Gorkhapatra bookmarks. Remove deletes
/// the bookmark document behind the shared AppModalShell confirm modal.
class BookmarkDetailScreen extends StatefulWidget {
  final String id;

  /// Test seams — production code never passes these. [loadBookmark]
  /// replaces the Firestore/auth load; [deleteBookmark] replaces the
  /// Firestore delete (receives the bookmark id and the loaded doc).
  final Future<Map<String, dynamic>?> Function()? loadBookmark;
  final Future<void> Function(String id, Map<String, dynamic> bookmark)?
      deleteBookmark;

  const BookmarkDetailScreen({
    super.key,
    required this.id,
    this.loadBookmark,
    this.deleteBookmark,
  });

  @override
  State<BookmarkDetailScreen> createState() => _BookmarkDetailScreenState();
}

class _BookmarkDetailScreenState extends State<BookmarkDetailScreen> {
  late Future<Map<String, dynamic>?> _future;
  bool _removing = false;
  Map<String, dynamic>? _loaded;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Rebuild (in particular the header above the FutureBuilder) once the
    // bookmark arrives. The header's delete action is disabled until
    // _loaded is set; the FutureBuilder's own rebuild does NOT rebuild the
    // header, so without this the delete icon's onTap would stay null
    // forever and tapping it would do nothing.
    _future.then((b) {
      if (mounted) setState(() => _loaded = b);
    }, onError: (_) {});
  }

  Future<Map<String, dynamic>?> _load() async {
    final loader = widget.loadBookmark;
    if (loader != null) return loader();
    final uid = AuthService.currentUser?.uid;
    if (uid == null) {
      throw Exception(AppLanguage.tr('Not signed in.', 'साइन इन गरिएको छैन।'));
    }
    final idToken = await AuthService.getValidIdToken();
    return FirestoreRest.getDocument('users/$uid/bookmarks/${widget.id}',
        idToken: idToken);
  }

  Future<void> _remove(Map<String, dynamic> b) async {
    final ok = await AppModalShell.show<bool>(
      context: context,
      builder: (c) => BookmarkRemoveDialog(item: b),
    );
    if (ok != true) return;
    setState(() => _removing = true);
    try {
      final deleter = widget.deleteBookmark;
      if (deleter != null) {
        await deleter(widget.id, b);
      } else {
        final uid = AuthService.currentUser?.uid;
        if (uid == null) {
          throw Exception(
              AppLanguage.tr('Not signed in.', 'साइन इन गरिएको छैन।'));
        }
        final idToken = await AuthService.getValidIdToken();
        await FirestoreRest.deleteDocument(
            'users/$uid/bookmarks/${widget.id}',
            idToken: idToken);
      }
      if (mounted) {
        showToast(
            context,
            AppLanguage.tr('Removed from bookmarks', 'बुकमार्कबाट हटाइयो'),
            ToastVariant.info);
        context.pop();
      }
    } catch (e) {
      setState(() => _removing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLanguage.tr(
                'Remove failed: $e', 'हटाउन असफल भयो: $e'))));
      }
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _savedDate(dynamic raw) {
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw;
    } else if (raw is num) {
      dt = DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    } else if (raw is String) {
      dt = DateTime.tryParse(raw);
    }
    if (dt == null) return '';
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SubpageHeader(title: AppLanguage.tr('Bookmark', 'बुकमार्क'), actions: [
            GestureDetector(
              onTap: (_loaded == null || _removing)
                  ? null
                  : () => _remove(_loaded!),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _removing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const TrashIcon(size: 20, color: Colors.white),
              ),
            ),
          ]),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return PreloadingWidget(
                    tinted: false,
                    label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
                  );
                }
                if (snap.hasError || snap.data == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        snap.hasError
                            ? '${AppLanguage.tr('Failed to load bookmark:',
                                    'बुकमार्क लोड हुन असफल भयो:')}\n${snap.error}'
                            : AppLanguage.tr(
                                'Bookmark not found.', 'बुकमार्क भेटिएन।'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final b = snap.data!;
                return BookmarkDetailBody(
                  bookmark: b,
                  savedDate: _savedDate(b['createdAt']),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Loaded-state body of the bookmark detail screen. Public so widget tests
/// can drive it directly with a fake bookmark map (no Firestore/auth).
class BookmarkDetailBody extends StatefulWidget {
  final Map<String, dynamic> bookmark;
  final String savedDate;
  const BookmarkDetailBody(
      {super.key, required this.bookmark, this.savedDate = ''});

  @override
  State<BookmarkDetailBody> createState() => _BookmarkDetailBodyState();
}

class _BookmarkDetailBodyState extends State<BookmarkDetailBody> {
  bool _revealAnswer = false;

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final b = widget.bookmark;
    final track = bookmarkTrackOf(b);
    final payload = b['payload'];
    final Map<String, dynamic> p =
        payload is Map ? Map<String, dynamic>.from(payload) : {};
    final meta = p['meta'];
    final List metaRows = meta is List ? meta : [];
    final question = (p['question'] ?? '').toString();
    final options = p['options'];
    final List optionList = options is List ? options : [];
    final answerIndex =
        p['answerIndex'] is int ? p['answerIndex'] as int : -1;
    final explanation = (p['explanation'] ?? '').toString();
    final bodyText = (p['body'] ?? '').toString();
    final preview = (b['preview'] ?? '').toString();
    final isQuestion = question.isNotEmpty;
    final isArticle = !isQuestion &&
        (track.key == 'article' ||
            bodyText.isNotEmpty ||
            preview.isNotEmpty);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _EntranceOnce(
          delayMs: 0,
          child: _TrackHero(
            track: track,
            subject: _subjectOf(p),
            sourceLabel: (b['sourceLabel'] ?? '').toString(),
            savedDate: widget.savedDate,
          ),
        ),
        const SizedBox(height: 14),
        _EntranceOnce(
          delayMs: 60,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: pal.border, width: 1),
            ),
            child: Text(
              isQuestion ? question : (b['title'] ?? '').toString(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.35,
                color: pal.textPrimary,
              ),
            ),
          ),
        ),
        if (metaRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          _EntranceOnce(
            delayMs: 120,
            child: _MetaCard(rows: metaRows, pal: pal),
          ),
        ],
        if (isQuestion) ...[
          const SizedBox(height: 14),
          for (var i = 0; i < optionList.length; i++)
            _Stagger(
              index: i,
              child: _OptionTile(
                index: i,
                text: optionList[i].toString(),
                answerIndex: answerIndex,
                revealed: _revealAnswer,
                pal: pal,
              ),
            ),
          const SizedBox(height: 10),
          _EntranceOnce(
            delayMs: 200,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () =>
                    setState(() => _revealAnswer = !_revealAnswer),
                icon: Icon(_revealAnswer
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                label: Text(AppLanguage.tr(
                    _revealAnswer ? 'Hide answer' : 'Reveal answer',
                    _revealAnswer ? 'उत्तर लुकाउनुहोस्' : 'उत्तर देखाउनुहोस्')),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
          // The explanation is gated on the reveal toggle — it must never
          // show before the user taps "Reveal answer".
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: _revealAnswer && explanation.isNotEmpty
                ? _ExplanationCard(text: explanation, pal: pal)
                : const SizedBox.shrink(),
          ),
        ] else if (isArticle) ...[
          const SizedBox(height: 14),
          _EntranceOnce(
            delayMs: 120,
            child: _ArticleCard(
              body: bodyText.isNotEmpty ? bodyText : preview,
              pal: pal,
            ),
          ),
        ],
      ],
    );
  }
}

/// Subject/topic name pulled from the saved payload's meta rows
/// (labels like Subject / Chapter / Topic), or '' when absent.
String _subjectOf(Map<String, dynamic> p) {
  final meta = p['meta'];
  if (meta is List) {
    for (final row in meta) {
      if (row is Map) {
        final label = (row['label'] ?? '').toString().toLowerCase();
        if (label.contains('subject') ||
            label.contains('chapter') ||
            label.contains('topic')) {
          final v = (row['value'] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
      }
    }
  }
  return '';
}

/// Topic-wise hero icon: matched from the bookmark's subject/topic name
/// (English or Devanagari keywords); falls back to the track icon when
/// nothing matches.
IconData _subjectIcon(String subject, BookmarkTrack track) {
  final s = subject.toLowerCase();
  bool has(List<String> keys) => keys.any(s.contains);
  if (has(['civil', 'engineering', 'इन्जिनियर', 'प्राविधिक'])) {
    return Icons.engineering_outlined;
  }
  if (has(['medical', 'health', 'nurse', 'स्वास्थ्य', 'चिकित्सा'])) {
    return Icons.medical_services_outlined;
  }
  if (has(['computer', 'ict', 'कम्प्युटर', 'सूचना'])) {
    return Icons.computer_outlined;
  }
  if (has(['math', 'गणित'])) return Icons.calculate_outlined;
  if (has(['english', 'अंग्रेजी', 'अङ्ग्रेजी'])) return Icons.translate_outlined;
  if (has(['nepali', 'नेपाली'])) return Icons.language_outlined;
  if (has(['science', 'विज्ञान'])) return Icons.science_outlined;
  if (has(['history', 'इतिहास'])) return Icons.history_edu_outlined;
  if (has(['geography', 'भूगोल'])) return Icons.map_outlined;
  if (has(['constitution', 'संविधान', 'law', 'कानुन', 'कानून'])) {
    return Icons.account_balance_outlined;
  }
  if (has(['econom', 'अर्थ'])) return Icons.trending_up_outlined;
  if (has(['agricultur', 'कृषि'])) return Icons.agriculture_outlined;
  if (has(['current', 'समसामयिक', 'समाचार'])) return Icons.newspaper_outlined;
  return track.icon;
}

/// Premium track hero: layered track-color gradient, a large topic-wise
/// watermark icon, a glossy gradient icon tile, and a "saved" pill.
class _TrackHero extends StatelessWidget {
  final BookmarkTrack track;
  final String subject;
  final String sourceLabel;
  final String savedDate;
  const _TrackHero(
      {required this.track,
      this.subject = '',
      required this.sourceLabel,
      required this.savedDate});

  @override
  Widget build(BuildContext context) {
    final pal = ExpoPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final icon = _subjectIcon(subject, track);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            track.color.withValues(alpha: dark ? 0x66 / 0xFF : 0x38 / 0xFF),
            track.color.withValues(alpha: dark ? 0x33 / 0xFF : 0x16 / 0xFF),
          ],
        ),
        border: Border.all(
          color: track.color.withValues(alpha: dark ? 0x77 / 0xFF : 0x4D / 0xFF),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: track.color.withValues(alpha: 0x1F / 0xFF),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // Decorative oversized watermark of the topic icon.
            Positioned(
              right: -16,
              bottom: -16,
              child: Icon(
                icon,
                size: 104,
                color:
                    track.color.withValues(alpha: dark ? 0x2E / 0xFF : 0x22 / 0xFF),
              ),
            ),
            // Soft top sheen for depth.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white
                          .withValues(alpha: dark ? 0x0A / 0xFF : 0x14 / 0xFF),
                      Colors.white.withValues(alpha: 0x00 / 0xFF),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          track.color,
                          Color.lerp(track.color, Colors.black, 0.18)!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: track.color.withValues(alpha: 0x55 / 0xFF),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 27, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLanguage.tr(track.label, track.labelNe)
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: track.color,
                          ),
                        ),
                        if (subject.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: pal.textPrimary,
                            ),
                          ),
                        ],
                        if (sourceLabel.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            sourceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: pal.textSecondary,
                            ),
                          ),
                        ],
                        if (savedDate.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: track.color.withValues(
                                  alpha: dark ? 0x2E / 0xFF : 0x1A / 0xFF),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_month_outlined,
                                  size: 12,
                                  color: track.color,
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    AppLanguage.tr(
                                        'Saved on $savedDate',
                                        '$savedDate मा सेभ गरियो'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: track.color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
      ),
    );
  }
}

/// Premium meta rows card.
class _MetaCard extends StatelessWidget {
  final List rows;
  final ExpoPalette pal;
  const _MetaCard({required this.rows, required this.pal});

  @override
  Widget build(BuildContext context) {
    final items =
        rows.whereType<Map>().toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: pal.border, width: 1),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: pal.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      (items[i]['label'] ?? '').toString(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: pal.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      (items[i]['value'] ?? '').toString(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: pal.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Premium option tile: letter badge, highlight + check only when revealed.
class _OptionTile extends StatelessWidget {
  final int index;
  final String text;
  final int answerIndex;
  final bool revealed;
  final ExpoPalette pal;
  const _OptionTile({
    required this.index,
    required this.text,
    required this.answerIndex,
    required this.revealed,
    required this.pal,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isCorrect = revealed && index == answerIndex;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: isCorrect
            ? const Color(0xFF16A34A).withValues(alpha: dark ? 0x26 / 0xFF : 0x14 / 0xFF)
            : pal.surface,
        border: Border.all(
          color: isCorrect
              ? const Color(0xFF16A34A).withValues(alpha: 0x66 / 0xFF)
              : pal.border,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCorrect
                  ? const Color(0xFF16A34A)
                  : pal.primary.withValues(alpha: dark ? 0x2E / 0xFF : 0x14 / 0xFF),
            ),
            child: Text(
              String.fromCharCode(65 + index),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isCorrect ? Colors.white : pal.primary,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: pal.textPrimary,
              ),
            ),
          ),
          if (isCorrect) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.check_circle,
              color: Color(0xFF16A34A),
              size: 20,
            ),
          ],
        ],
      ),
    );
  }
}

/// Explanation card — only rendered when the answer is revealed.
class _ExplanationCard extends StatelessWidget {
  final String text;
  final ExpoPalette pal;
  const _ExplanationCard({required this.text, required this.pal});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB)
            .withValues(alpha: dark ? 0x22 / 0xFF : 0x0D / 0xFF),
        border: Border.all(
          color: const Color(0xFF2563EB)
              .withValues(alpha: dark ? 0x55 / 0xFF : 0x2E / 0xFF),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(width: 6),
              Text(
                AppLanguage.tr('Explanation', 'व्याख्या'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: pal.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Premium article layout for article/Gorkhapatra bookmarks: readable
/// long-form typography inside a soft card.
class _ArticleCard extends StatelessWidget {
  final String body;
  final ExpoPalette pal;
  const _ArticleCard({required this.body, required this.pal});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0x08 / 0xFF),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            body,
            style: TextStyle(
              fontSize: 15,
              height: 1.7,
              color: pal.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One-shot staggered entrance: fade + rise, finite (no loops).
class _Stagger extends StatefulWidget {
  final int index;
  final Widget child;
  const _Stagger({required this.index, required this.child});

  @override
  State<_Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<_Stagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.index * 70), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// One-shot entrance wrapper: fade + slight rise on first build.
class _EntranceOnce extends StatefulWidget {
  final int delayMs;
  final Widget child;
  const _EntranceOnce({required this.delayMs, required this.child});

  @override
  State<_EntranceOnce> createState() => _EntranceOnceState();
}

class _EntranceOnceState extends State<_EntranceOnce> {
  bool _go = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _go = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _go ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _go ? Offset.zero : const Offset(0, 0.06),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
