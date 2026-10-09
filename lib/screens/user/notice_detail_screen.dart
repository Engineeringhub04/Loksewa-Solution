import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/home/notice_date.dart';
import 'package:loksewa_solution/widgets/home/notice_visual.dart';
import 'package:loksewa_solution/widgets/status_pill.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/subpage_header.dart';
import '../../widgets/preloading.dart';

/// Individual notice detail page — mirrors app/notice/[id].tsx.
///
/// One direct `app_notices/{id}` read (the list screen passes the document
/// along as `extra`, so usually zero reads). Renders the HeroBand (kind
/// medallion + title + kind/date pills), the optional download row (opens
/// the stored link — shown in a dialog since url_launcher is not a
/// dependency), and the ordered content blocks inside a SectionCard:
/// headings, paragraphs with `**bold**` spans + tappable URLs, images
/// (tappable into a full-screen viewer), and `[img:KEY]` inline tokens
/// placed in the flow of the text.
class NoticeDetailScreen extends StatefulWidget {
  final String id;
  const NoticeDetailScreen({super.key, required this.id});

  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    final extra = GoRouterState.of(context).extra;
    if (extra is Map<String, dynamic> && extra.isNotEmpty) {
      _future = Future.value(extra);
    } else if (extra is Map && extra.isNotEmpty) {
      _future = Future.value(Map<String, dynamic>.from(extra));
    } else {
      _future = _load();
    }
  }

  Future<Map<String, dynamic>?> _load() async {
    final idToken = await AuthService.getValidIdToken();
    return FirestoreRest.getDocument('app_notices/${widget.id}',
        idToken: idToken);
  }

  void _showLinkDialog(String url) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Link'),
        content: SelectableText(url),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _showImage(String url, String caption) {
    showImageViewer(context, NetworkImage(url));
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          const SubpageHeader(title: 'Notices'),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _loadingState(palette);
                }
                if (snap.hasError) {
                  return _errorState(
                      context, palette, () => setState(() {
                            _future = _load();
                          }));
                }
                final n = snap.data;
                if (n == null) {
                  return _notFoundState(context, palette);
                }
                return _body(context, palette, n);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ExpoPalette palette,
      Map<String, dynamic> n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kind = (n['kind'] as String?);
    final visual = noticeVisual(kind, palette);
    final tone = visual.color;
    final label = (n['dateLabel'] ?? '').toString().trim();
    final p = n['publishedAt'];
    final date = label.isNotEmpty
        ? label
        : (p is DateTime ? noticeNeDate(p) : '');
    final downloadEnabled = n['downloadEnabled'] == true;
    final downloadUrl = (n['downloadUrl'] ?? '').toString();
    final rawLabel = (n['downloadLabel'] ?? '').toString().trim();
    final downloadLabel = rawLabel.isEmpty ? 'Download' : rawLabel;
    final blocks = n['blocks'];
    final List blockList = blocks is List ? blocks : [];
    final images = n['images'];
    final Map<String, dynamic> imageMap =
        images is Map ? Map<String, dynamic>.from(images) : {};

    return RefreshIndicator.adaptive(
      onRefresh: () async {
        final next = _load();
        setState(() => _future = next);
        await next;
      },
      child: ListView(
        padding:
            const EdgeInsets.all(ExpoSpacing.screenPadding),
        children: [
          _heroBand(context, palette, isDark, n, visual, date),
          if (downloadEnabled && downloadUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            _downloadRow(
                context, palette, isDark, tone, downloadLabel,
                () => _showLinkDialog(downloadUrl)),
          ],
          const SizedBox(height: 16),
          _sectionCard(context, palette, isDark, tone, blockList,
              imageMap),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Mirrors HeroBand: surface card with a top-heavy tone tint, 54px
  /// medallion, h2 title, and the kind + date pills in the footer.
  Widget _heroBand(
      BuildContext context,
      ExpoPalette palette,
      bool isDark,
      Map<String, dynamic> n,
      NoticeVisual visual,
      String date) {
    final tone = visual.color;
    final bgAlpha = isDark ? 0x26 / 0xFF : 0x14 / 0xFF;
    final borderAlpha = isDark ? 0x55 / 0xFF : 0x33 / 0xFF;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        border: Border.all(
            color: tone.withValues(alpha: borderAlpha), width: 0.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Vertical, top-heavy tint fading out before the text.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tone.withValues(alpha: bgAlpha),
                    palette.surface.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color:
                            tone.withValues(alpha: bgAlpha),
                        borderRadius: BorderRadius.circular(
                            ExpoRadius.lg),
                        border: Border.all(
                            color: tone.withValues(
                                alpha: borderAlpha),
                            width: 0.5),
                      ),
                      alignment: Alignment.center,
                      child: Icon(visual.icon,
                          size: 26, color: tone),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        (n['title'] ?? 'Notice').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: ExpoType.h2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusPill(
                        label: visual.label, color: tone),
                    // Always rendered, like the Expo HeroBand footer.
                    StatusPill(
                      label: date,
                      color: palette.textSecondary,
                      icon: Icons.access_time,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Mirrors the download CTA row: tone-tinted pressable with open icon,
  /// label, and chevron — NOT a filled button. Pressed: the fill deepens to
  /// tone.border at 0.92 opacity.
  Widget _downloadRow(
      BuildContext context,
      ExpoPalette palette,
      bool isDark,
      Color tone,
      String label,
      VoidCallback onTap) {
    final bgAlpha = isDark ? 0x26 / 0xFF : 0x14 / 0xFF;
    final borderAlpha = isDark ? 0x55 / 0xFF : 0x33 / 0xFF;
    return _PressedRow(
      onTap: onTap,
      builder: (pressed) => Opacity(
        opacity: pressed ? 0.92 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: pressed
                ? tone.withValues(alpha: borderAlpha)
                : tone.withValues(alpha: bgAlpha),
            borderRadius:
                BorderRadius.circular(ExpoRadius.lg),
            border: Border.all(
                color: tone.withValues(alpha: borderAlpha),
                width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.open_in_new_outlined,
                  size: 17, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: tone,
                        fontSize: ExpoType.bodySmall,
                        fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.chevron_right, size: 16, color: tone),
            ],
          ),
        ),
      ),
    );
  }

  /// Mirrors SectionCard: titled block with a 38px icon medallion and the
  /// ordered content blocks as its body.
  Widget _sectionCard(
      BuildContext context,
      ExpoPalette palette,
      bool isDark,
      Color tone,
      List blockList,
      Map<String, dynamic> imageMap) {
    final bgAlpha = isDark ? 0x26 / 0xFF : 0x14 / 0xFF;
    final borderAlpha = isDark ? 0x55 / 0xFF : 0x33 / 0xFF;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(ExpoRadius.lg),
        border:
            Border.all(color: palette.border, width: 0.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: bgAlpha),
                  borderRadius:
                      BorderRadius.circular(ExpoRadius.md),
                  border: Border.all(
                      color: tone.withValues(alpha: borderAlpha),
                      width: 0.5),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.description_outlined,
                    size: 19, color: tone),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text('Details',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: ExpoType.h3,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < blockList.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            if (blockList[i] is Map)
              _block(context, palette,
                  blockList[i] as Map, imageMap),
          ],
        ],
      ),
    );
  }

  Widget _block(BuildContext context, ExpoPalette palette, Map b,
      Map<String, dynamic> images) {
    final type = (b['type'] ?? 'text').toString();
    if (type == 'image') {
      final url = (b['url'] ?? '').toString();
      if (url.isEmpty) return const SizedBox.shrink();
      return _noticeImage(
          context, url, (b['caption'] ?? '').toString());
    }
    if (type == 'heading') {
      final text = (b['text'] ?? '').toString();
      if (text.isEmpty) return const SizedBox.shrink();
      return Text(text,
          style: TextStyle(
              color: palette.textPrimary,
              fontSize: ExpoType.h3,
              fontWeight: FontWeight.bold));
    }
    // text — split [img:KEY] tokens into flowing pieces.
    return _textBlock(
        context, palette, (b['text'] ?? '').toString(), images);
  }

  /// A text block whose `[img:KEY]` tokens split the paragraph: text before
  /// the token renders as a rich paragraph, then the inline image appears in
  /// the flow, then the remaining text carries on — mirrors TextBlock.
  Widget _textBlock(BuildContext context, ExpoPalette palette,
      String text, Map<String, dynamic> images) {
    final tokenRe = RegExp(r'\[img:([A-Za-z0-9_-]+)\]');
    final pieces = <Widget>[];
    int cursor = 0;
    for (final m in tokenRe.allMatches(text)) {
      final key = m.group(1)!;
      final entry = images[key];
      final url =
          entry is Map ? (entry['url'] ?? '').toString() : '';
      if (m.start > cursor) {
        pieces.add(_richParagraph(context, palette,
            text.substring(cursor, m.start)));
      }
      if (url.isNotEmpty) {
        pieces.add(_noticeImage(context, url,
            entry is Map ? (entry['caption'] ?? '').toString() : ''));
      }
      cursor = m.end;
    }
    if (cursor < text.length) {
      pieces.add(
          _richParagraph(context, palette, text.substring(cursor)));
    }
    if (pieces.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < pieces.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          pieces[i],
        ],
      ],
    );
  }

  /// One paragraph with `**bold**` spans and plain-text URLs turned into
  /// tappable links — mirrors RichParagraph.
  Widget _richParagraph(
      BuildContext context, ExpoPalette palette, String text) {
    final base = TextStyle(
        color: palette.textPrimary,
        fontSize: ExpoType.body,
        height: 25 / 14);
    final spans = <InlineSpan>[];
    final boldRe = RegExp(r'(\*\*[^*]+\*\*)');
    int si = 0;
    for (final m in boldRe.allMatches(text)) {
      if (m.start > si) {
        _linkify(spans, text.substring(si, m.start), base,
            palette, bold: false);
      }
      final content =
          m.group(0)!.substring(2, m.group(0)!.length - 2);
      _linkify(spans, content, base, palette, bold: true);
      si = m.end;
    }
    if (si < text.length) {
      _linkify(spans, text.substring(si), base, palette,
          bold: false);
    }
    return RichText(text: TextSpan(children: spans));
  }

  void _linkify(List<InlineSpan> spans, String segment,
      TextStyle base, ExpoPalette palette,
      {required bool bold}) {
    final urlRe = RegExp(r'(https?://[^\s<>()]+)');
    int ri = 0;
    for (final m in urlRe.allMatches(segment)) {
      if (m.start > ri) {
        spans.add(TextSpan(
            text: segment.substring(ri, m.start),
            style: base.copyWith(
                fontWeight:
                    bold ? FontWeight.bold : null)));
      }
      final url = m.group(0)!;
      spans.add(WidgetSpan(
        child: GestureDetector(
          onTap: () => _showLinkDialog(url),
          child: Text(url,
              style: base.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.primary,
                  decoration: TextDecoration.underline)),
        ),
      ));
      ri = m.end;
    }
    if (ri < segment.length) {
      spans.add(TextSpan(
          text: segment.substring(ri),
          style: base.copyWith(
              fontWeight: bold ? FontWeight.bold : null)));
    }
  }

  /// Content image — radius 12, centred caption, pressable (0.9 opacity)
  /// into the full-screen viewer. Mirrors NoticeImage (contentFit contain,
  /// #E5E7EB backdrop).
  Widget _noticeImage(
      BuildContext context, String url, String caption) {
    final palette = ExpoPalette.of(context);
    return _PressedRow(
      onTap: () => _showImage(url, caption),
      builder: (pressed) => Opacity(
        opacity: pressed ? 0.9 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: const Color(0xFFE5E7EB),
                child: Image.network(
                  url,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
            if (caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(caption,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: ExpoType.caption)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _loadingState(ExpoPalette palette) {
    return const PreloadingWidget(
      tinted: false,
      label: 'Loading Notice...',
      hint: 'Fetching your content',
    );
  }

  /// Mirrors DataNotFound with a retry action.
  Widget _errorState(BuildContext context, ExpoPalette palette,
      VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: palette.textDisabled),
            const SizedBox(height: 12),
            Text('Data Not Found',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text("We couldn't load this content. Please try again.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textSecondary, fontSize: 14)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh,
                        size: 15, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Try Again',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mirrors DataNotFound with the notFound copy (no retry — the notice is
  /// gone, not failing to load).
  Widget _notFoundState(
      BuildContext context, ExpoPalette palette) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: palette.textDisabled),
            const SizedBox(height: 12),
            Text('Notice not found',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('This notice may have been removed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textSecondary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

/// Pressable wrapper reporting the pressed state to its builder —
/// used for the download row's pressed styling.
class _PressedRow extends StatefulWidget {
  final VoidCallback onTap;
  final Widget Function(bool pressed) builder;

  const _PressedRow({required this.onTap, required this.builder});

  @override
  State<_PressedRow> createState() => _PressedRowState();
}

class _PressedRowState extends State<_PressedRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: widget.builder(_pressed),
    );
  }
}


