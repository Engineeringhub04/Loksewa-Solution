import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/keep_note.dart';
import '../../services/app_language.dart';
import '../../services/keep_notes_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/keep_rich_text.dart';
import '../../widgets/preloading.dart';

/// Keep Notes editor — Google Keep style.
///
/// Top-left back arrow, top-right PIN icon only, bold Title field, rich-text
/// Note body, and a bottom footer with just undo / redo / text-format ("A").
/// Bold, underline and italic apply to the current selection, or — with a
/// collapsed cursor — to subsequently typed text. Everything auto-saves to
/// the phone (local JSON, never Firestore).
class NoteDetailScreen extends StatefulWidget {
  final String id;
  final KeepNotesStore? store;

  const NoteDetailScreen({super.key, required this.id, this.store});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  bool get _isNew => widget.id == 'new';
  KeepNotesStore get _store => widget.store ?? KeepNotesStore.instance;

  final _titleCtrl = TextEditingController();
  late final KeepRichController _bodyCtrl;

  bool _loaded = false;
  bool _preloading = true;
  bool _pinned = false;
  bool _showFormatBar = false;
  String _noteId = '';

  final _history = KeepEditHistory();
  Timer? _historyTimer;
  Timer? _saveTimer;
  bool _applyingSnapshot = false;

  @override
  void initState() {
    super.initState();
    _bodyCtrl = KeepRichController();
    _bodyCtrl.addListener(_onBodyChanged);
    _titleCtrl.addListener(_onTitleChanged);
    _boot();
    // 1s premium preloading shimmer: this page has no database fetch, so the
    // content would pop in instantly without it.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _preloading = false);
    });
  }

  Future<void> _boot() async {
    await _store.ensureInit();
    if (!mounted) return;
    if (!_isNew) {
      final note = _store.getById(widget.id);
      if (note != null) {
        _noteId = note.id;
        _titleCtrl.text = note.title;
        final rich = KeepRichController.fromRuns(
            note.runs.map((r) => r.toJson()).toList());
        _bodyCtrl.setRichText(rich.text, rich.ranges);
        _pinned = note.pinned;
      }
    }
    if (_isNew) _noteId = KeepNote.newId();
    _pushHistory();
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _saveTimer?.cancel();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ edits

  void _onTitleChanged() {
    if (_applyingSnapshot || !_loaded) return;
    _scheduleHistory();
    _scheduleSave();
  }

  void _onBodyChanged() {
    if (_applyingSnapshot || !_loaded) return;
    _scheduleHistory();
    _scheduleSave();
    if (mounted) setState(() {}); // refresh undo/redo + format active states
  }

  void _scheduleHistory() {
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(milliseconds: 900), _pushHistory);
  }

  void _pushHistory() {
    if (!_loaded || _applyingSnapshot) return;
    _history.push(_snapshot());
    if (mounted) setState(() {});
  }

  KeepEditSnapshot _snapshot() {
    final ts = _titleCtrl.selection;
    final bs = _bodyCtrl.selection;
    return KeepEditSnapshot(
      title: _titleCtrl.text,
      bodyText: _bodyCtrl.text,
      ranges: _bodyCtrl.ranges,
      titleBase: ts.isValid ? ts.baseOffset : -1,
      titleExtent: ts.isValid ? ts.extentOffset : -1,
      bodyBase: bs.isValid ? bs.baseOffset : -1,
      bodyExtent: bs.isValid ? bs.extentOffset : -1,
    );
  }

  void _applySnapshot(KeepEditSnapshot s) {
    _applyingSnapshot = true;
    _historyTimer?.cancel();
    _titleCtrl.value = TextEditingValue(
      text: s.title,
      selection: s.titleBase >= 0
          ? TextSelection(
              baseOffset: s.titleBase.clamp(0, s.title.length),
              extentOffset: s.titleExtent.clamp(0, s.title.length))
          : TextSelection.collapsed(offset: s.title.length),
    );
    _bodyCtrl.setRichText(s.bodyText, s.ranges);
    _bodyCtrl.selection = s.bodyBase >= 0
        ? TextSelection(
            baseOffset: s.bodyBase.clamp(0, s.bodyText.length),
            extentOffset: s.bodyExtent.clamp(0, s.bodyText.length))
        : TextSelection.collapsed(offset: s.bodyText.length);
    _applyingSnapshot = false;
    _scheduleSave();
    setState(() {});
  }

  void _undo() {
    final s = _history.undo();
    if (s != null) _applySnapshot(s);
  }

  void _redo() {
    final s = _history.redo();
    if (s != null) _applySnapshot(s);
  }

  // ------------------------------------------------------------------- save

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveNow);
  }

  /// Synchronous final save — the store is initialized before [_loaded].
  void _saveNow() {
    if (!_loaded || !_store.isReady) return;
    final title = _titleCtrl.text;
    final runs = _bodyCtrl.toRuns();
    final empty =
        title.trim().isEmpty && runs.every((r) => '${r['t']}'.trim().isEmpty);
    if (empty) {
      if (!_isNew) _store.delete(_noteId);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _isNew ? null : _store.getById(_noteId);
    _store.upsert(KeepNote(
      id: _noteId,
      title: title,
      runs: runs.map((m) => KeepTextRun.fromJson(m)).toList(),
      pinned: _pinned,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    ));
  }

  void _onBack() {
    _saveNow();
    if (mounted) context.pop();
  }

  void _togglePin() {
    setState(() => _pinned = !_pinned);
    _scheduleSave();
  }

  void _toggleFormat(KeepTextStyle style) {
    _historyTimer?.cancel();
    _bodyCtrl.toggleStyle(style);
    _pushHistory();
  }

  // -------------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    final bg = palette.background;
    final textPrimary = palette.textPrimary;
    final textDisabled = palette.textDisabled;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveNow();
      },
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: _preloading
              ? _preloadingBody()
              : (_loaded
                  ? Column(
                      children: [
                        _topBar(textPrimary),
                        _titleField(textPrimary, textDisabled),
                        Expanded(child: _bodyField(textPrimary, textDisabled)),
                        if (_showFormatBar) _formatBar(palette),
                        _footer(palette),
                      ],
                    )
                  : const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )),
        ),
      ),
    );
  }

  /// 1s preloading shimmer shown on first build before the page content.
  Widget _preloadingBody() {
    return Center(
      child: PreloadingWidget(
        // Theme-coloured page: theme-grey spokes, not white.
        tinted: false,
        label: AppLanguage.tr('Loading...', 'लोड हुँदैछ...'),
      ),
    );
  }

  /// Keep-style top bar: back arrow left, PIN icon only on the right.
  Widget _topBar(Color iconColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            color: iconColor,
            onPressed: _onBack,
            tooltip: AppLanguage.tr('Back', 'फर्कनुहोस्'),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
            color: iconColor,
            onPressed: _togglePin,
            tooltip: _pinned
                ? AppLanguage.tr('Unpin', 'पिन हटाउनुहोस्')
                : AppLanguage.tr('Pin', 'पिन गर्नुहोस्'),
          ),
        ],
      ),
    );
  }

  /// Title is ALWAYS bold (requirement 5).
  Widget _titleField(Color textColor, Color hintColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: TextField(
        controller: _titleCtrl,
        style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.bold, color: textColor),
        decoration: InputDecoration(
          hintText: AppLanguage.tr('Title', 'शीर्षक'),
          hintStyle: TextStyle(color: hintColor, fontWeight: FontWeight.bold),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        textCapitalization: TextCapitalization.sentences,
      ),
    );
  }

  /// Body is normal weight by default (requirement 6) — bold only where the
  /// user applied it via the format toolbar.
  Widget _bodyField(Color textColor, Color hintColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextField(
        controller: _bodyCtrl,
        style: TextStyle(fontSize: 16, color: textColor),
        decoration: InputDecoration(
          hintText: AppLanguage.tr('Note', 'नोट'),
          hintStyle: TextStyle(color: hintColor),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        keyboardType: TextInputType.multiline,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        textCapitalization: TextCapitalization.sentences,
      ),
    );
  }

  /// Popup toolbar opened by the "A" button: Bold / Underline / Italic.
  Widget _formatBar(ExpoPalette palette) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _formatButton(KeepTextStyle.bold, Icons.format_bold,
              AppLanguage.tr('Bold', 'बोल्ड'), palette),
          _formatButton(KeepTextStyle.underline, Icons.format_underline,
              AppLanguage.tr('Underline', 'अन्डरलाइन'), palette),
          _formatButton(KeepTextStyle.italic, Icons.format_italic,
              AppLanguage.tr('Italic', 'इटालिक'), palette),
        ],
      ),
    );
  }

  Widget _formatButton(
      KeepTextStyle style, IconData icon, String tip, ExpoPalette palette) {
    final active =
        _bodyCtrl.typingStyles.contains(style) || _selectionHas(style);
    return IconButton(
      icon: Icon(icon),
      color: active ? palette.primary : palette.textSecondary,
      style: IconButton.styleFrom(
        backgroundColor:
            active ? palette.primary.withValues(alpha: 0.14) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () => _toggleFormat(style),
      tooltip: tip,
    );
  }

  bool _selectionHas(KeepTextStyle style) {
    final sel = _bodyCtrl.selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    final a = sel.start.clamp(0, _bodyCtrl.text.length);
    final b = sel.end.clamp(0, _bodyCtrl.text.length);
    for (final r in _bodyCtrl.ranges) {
      if (r.start <= a && r.end >= b && r.styles.contains(style)) {
        return true;
      }
    }
    return false;
  }

  /// Footer holds ONLY undo, redo and the "A" format button (requirement 7).
  Widget _footer(ExpoPalette palette) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.undo),
            color: palette.textPrimary,
            disabledColor: palette.textDisabled,
            onPressed: _history.canUndo ? _undo : null,
            tooltip: AppLanguage.tr('Undo', 'अनडु'),
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            color: palette.textPrimary,
            disabledColor: palette.textDisabled,
            onPressed: _history.canRedo ? _redo : null,
            tooltip: AppLanguage.tr('Redo', 'रिडु'),
          ),
          IconButton(
            icon: Text(
              'A',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _showFormatBar ? palette.primary : palette.textPrimary,
                decoration: TextDecoration.underline,
              ),
            ),
            onPressed: () => setState(() => _showFormatBar = !_showFormatBar),
            tooltip: AppLanguage.tr('Text formatting', 'टेक्स्ट फर्म्याटिङ'),
          ),
        ],
      ),
    );
  }
}
