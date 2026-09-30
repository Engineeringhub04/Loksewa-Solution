import 'dart:math';

import 'package:flutter/material.dart';

/// Inline text styles supported by the Keep Notes editor.
enum KeepTextStyle { bold, underline, italic }

/// A styled range `[start, end)` over the controller's plain text.
/// Ranges are kept sorted, non-overlapping and merged by [_normalize].
class KeepStyleRange {
  int start;
  int end;
  final Set<KeepTextStyle> styles;

  KeepStyleRange(this.start, this.end, [Set<KeepTextStyle>? styles])
      : styles = styles != null ? Set.of(styles) : <KeepTextStyle>{};

  KeepStyleRange copy() => KeepStyleRange(start, end, styles);

  @override
  String toString() => 'KeepStyleRange($start,$end,$styles)';
}

/// A [TextEditingController] that renders inline bold/underline/italic
/// WITHOUT any rich-text package.
///
/// The plain [text] stays the source of truth; styling lives in [ranges].
/// [buildTextSpan] is overridden so the single body TextField paints styled
/// spans while keeping fully native editing (keyboard, selection, cursor).
/// The [value] setter diffs old vs new text and mechanically shifts / splits /
/// clips ranges, so typing and deleting never corrupt styling.
///
/// Formatting model (Google Keep-like):
/// * non-collapsed selection + toggle → the style is flipped on that range;
/// * collapsed cursor + toggle → flips the "typing style" applied to text
///   typed next (moving the cursor re-derives it from the text under it).
class KeepRichController extends TextEditingController {
  List<KeepStyleRange> ranges = [];
  final Set<KeepTextStyle> typingStyles = {};

  bool _suspend = false;

  KeepRichController({String? text, List<KeepStyleRange>? ranges}) {
    if (ranges != null) {
      this.ranges = _normalize(ranges.map((r) => r.copy()).toList());
    }
    if (text != null) {
      _suspend = true;
      value = TextEditingValue(text: text);
      _suspend = false;
    }
  }

  // ------------------------------------------------------------------ value

  @override
  set value(TextEditingValue newValue) {
    final oldText = value.text;
    super.value = newValue; // notifies listeners synchronously
    if (_suspend) return;
    if (oldText != newValue.text) {
      _remapRanges(oldText, newValue.text);
    }
    _refreshTypingStyles(newValue.selection);
  }

  // -------------------------------------------------------------- rendering

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final base = style ?? const TextStyle();
    final t = text;
    if (ranges.isEmpty || t.isEmpty) {
      return TextSpan(text: t, style: base);
    }
    final children = <TextSpan>[];
    var pos = 0;
    for (final r in ranges) {
      final s = r.start.clamp(0, t.length);
      final e = r.end.clamp(0, t.length);
      if (s > pos) {
        children.add(TextSpan(text: t.substring(pos, s), style: base));
      }
      if (e > s) {
        children.add(TextSpan(
            text: t.substring(s, e), style: _applyFlags(base, r.styles)));
      }
      pos = max(pos, e);
    }
    if (pos < t.length) {
      children.add(TextSpan(text: t.substring(pos), style: base));
    }
    return TextSpan(style: base, children: children);
  }

  static TextStyle _applyFlags(TextStyle base, Set<KeepTextStyle> flags) {
    var s = base;
    if (flags.contains(KeepTextStyle.bold)) {
      s = s.copyWith(fontWeight: FontWeight.bold);
    }
    if (flags.contains(KeepTextStyle.underline)) {
      s = s.copyWith(decoration: TextDecoration.underline);
    }
    if (flags.contains(KeepTextStyle.italic)) {
      s = s.copyWith(fontStyle: FontStyle.italic);
    }
    return s;
  }

  // ------------------------------------------------------- range bookkeeping

  /// Re-ranges after the text changed from [oldT] to [newT].
  /// Insertion at p extends/splits ranges; deletion clips them; a replace
  /// is treated as delete-then-insert. Afterwards [typingStyles] (when
  /// non-empty) claim the freshly inserted characters.
  void _remapRanges(String oldT, String newT) {
    if (ranges.isEmpty && typingStyles.isEmpty) return;

    var prefix = 0;
    final minLen = min(oldT.length, newT.length);
    while (prefix < minLen &&
        oldT.codeUnitAt(prefix) == newT.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < minLen - prefix &&
        oldT.codeUnitAt(oldT.length - 1 - suffix) ==
            newT.codeUnitAt(newT.length - 1 - suffix)) {
      suffix++;
    }
    final delCount = (oldT.length - suffix) - prefix;
    final insCount = (newT.length - suffix) - prefix;
    if (delCount == 0 && insCount == 0) return;

    var rs = ranges;
    if (delCount > 0) rs = _applyDeletion(rs, prefix, delCount);
    if (insCount > 0) {
      rs = _applyInsertion(rs, prefix, insCount);
      if (typingStyles.isNotEmpty) {
        rs = List.of(rs)
          ..add(KeepStyleRange(prefix, prefix + insCount, typingStyles));
      }
    }
    ranges = _normalize(rs);
  }

  /// Deletes [count] chars at [p]: ranges fully inside vanish, overlapping
  /// ones are clipped, later ones shift back.
  static List<KeepStyleRange> _applyDeletion(
      List<KeepStyleRange> rs, int p, int count) {
    final out = <KeepStyleRange>[];
    for (final r in rs) {
      if (r.end <= p) {
        out.add(r.copy());
      } else if (r.start >= p + count) {
        out.add(KeepStyleRange(r.start - count, r.end - count, r.styles));
      } else {
        // Overlaps the deleted span: keep the surviving head/tail pieces.
        if (r.start < p) {
          out.add(KeepStyleRange(r.start, p, r.styles));
        }
        if (r.end > p + count) {
          out.add(KeepStyleRange(p, r.end - count, r.styles));
        }
      }
    }
    return out;
  }

  /// Inserts [count] chars at [p]: ranges split around the insertion and the
  /// tail shifts forward. The inserted characters themselves stay unstyled
  /// here — [_remapRanges] lets [typingStyles] claim them afterwards.
  static List<KeepStyleRange> _applyInsertion(
      List<KeepStyleRange> rs, int p, int count) {
    final out = <KeepStyleRange>[];
    for (final r in rs) {
      if (r.end <= p) {
        out.add(r.copy());
      } else if (r.start >= p) {
        out.add(KeepStyleRange(r.start + count, r.end + count, r.styles));
      } else {
        // Strictly inside: split into head and shifted tail.
        out.add(KeepStyleRange(r.start, p, r.styles));
        out.add(KeepStyleRange(p + count, r.end + count, r.styles));
      }
    }
    return out;
  }

  /// Sorts by start and merges adjacent ranges with identical style sets.
  /// Empty ranges are dropped.
  static List<KeepStyleRange> _normalize(List<KeepStyleRange> rs) {
    final sorted = rs.where((r) => r.end > r.start).toList()
      ..sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.end.compareTo(b.end);
      });
    final out = <KeepStyleRange>[];
    for (final r in sorted) {
      if (out.isNotEmpty &&
          out.last.end >= r.start &&
          _sameStyles(out.last.styles, r.styles)) {
        out.last.end = max(out.last.end, r.end);
      } else {
        out.add(r.copy());
      }
    }
    return out;
  }

  static bool _sameStyles(
      Set<KeepTextStyle> a, Set<KeepTextStyle> b) {
    return a.length == b.length && a.containsAll(b);
  }

  List<KeepStyleRange> _splitAt(List<KeepStyleRange> rs, int p) {
    final out = <KeepStyleRange>[];
    for (final r in rs) {
      if (r.start < p && p < r.end) {
        out.add(KeepStyleRange(r.start, p, r.styles));
        out.add(KeepStyleRange(p, r.end, r.styles));
      } else {
        out.add(r);
      }
    }
    return out;
  }

  // --------------------------------------------------------------- toggling

  /// Toggles [flag] on the current selection, or on the typing style when
  /// the selection is collapsed.
  void toggleStyle(KeepTextStyle flag) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) {
      if (!typingStyles.remove(flag)) typingStyles.add(flag);
      notifyListeners();
      return;
    }
    var a = min(sel.start, sel.end).clamp(0, text.length);
    var b = max(sel.start, sel.end).clamp(0, text.length);
    if (a >= b) return;

    final split = _splitAt(_splitAt(ranges, a), b);

    // Direction: if every covered char already has the flag, remove it;
    // otherwise add it (filling unstyled gaps inside the selection too).
    var pos = a;
    var allHave = true;
    final covered = split
        .where((r) => r.start < b && r.end > a)
        .toList()
      ..sort((x, y) => x.start.compareTo(y.start));
    for (final r in covered) {
      if (r.start > pos || !r.styles.contains(flag)) {
        allHave = false;
        break;
      }
      pos = max(pos, r.end);
    }
    if (pos < b) allHave = false;

    final out = <KeepStyleRange>[];
    var cursor = a;
    for (final r in covered) {
      final rs = max(r.start, a);
      final re = min(r.end, b);
      if (rs > cursor && !allHave) {
        out.add(KeepStyleRange(cursor, rs, {flag}));
      }
      final ns = Set<KeepTextStyle>.of(r.styles);
      if (allHave) {
        ns.remove(flag);
      } else {
        ns.add(flag);
      }
      if (ns.isNotEmpty) out.add(KeepStyleRange(rs, re, ns));
      cursor = max(cursor, re);
    }
    if (cursor < b && !allHave) {
      out.add(KeepStyleRange(cursor, b, {flag}));
    }
    // Ranges outside the selection pass through untouched.
    for (final r in split) {
      if (r.end <= a || r.start >= b) out.add(r);
    }
    ranges = _normalize(out);
    notifyListeners();
  }

  void _refreshTypingStyles(TextSelection sel) {
    if (!sel.isValid || !sel.isCollapsed) return;
    typingStyles.clear();
    final o = sel.baseOffset.clamp(0, text.length);
    KeepStyleRange? pick;
    for (final r in ranges) {
      if (r.start <= o && o <= r.end) {
        if (o > r.start) {
          pick = r;
          break;
        }
        pick ??= r;
      }
    }
    if (pick != null) typingStyles.addAll(pick.styles);
  }

  // ------------------------------------------------------------ serialization

  /// Replaces text + ranges wholesale (loading a note, undo/redo).
  void setRichText(String newText, List<KeepStyleRange> newRanges) {
    _suspend = true;
    value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length));
    _suspend = false;
    ranges = _normalize(newRanges.map((r) => r.copy()).toList());
    typingStyles.clear();
    notifyListeners();
  }

  /// Sweeps text + ranges into storable runs.
  List<Map<String, dynamic>> toRuns() {
    final t = text;
    final out = <Map<String, dynamic>>[];
    var pos = 0;
    final sorted = List.of(ranges)
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final r in sorted) {
      final s = r.start.clamp(0, t.length);
      final e = r.end.clamp(0, t.length);
      if (s > pos) {
        out.add({'t': t.substring(pos, s)});
      }
      if (e > s) {
        final m = <String, dynamic>{'t': t.substring(s, e)};
        if (r.styles.contains(KeepTextStyle.bold)) m['b'] = true;
        if (r.styles.contains(KeepTextStyle.underline)) m['u'] = true;
        if (r.styles.contains(KeepTextStyle.italic)) m['i'] = true;
        out.add(m);
      }
      pos = max(pos, e);
    }
    if (pos < t.length) {
      out.add({'t': t.substring(pos)});
    }
    return out;
  }

  /// Inverse of [toRuns].
  static ({String text, List<KeepStyleRange> ranges}) fromRuns(
      List<Map<String, dynamic>> runs) {
    final buf = StringBuffer();
    final rs = <KeepStyleRange>[];
    for (final m in runs) {
      final chunk = '${m['t'] ?? ''}';
      if (chunk.isEmpty) continue;
      final start = buf.length;
      buf.write(chunk);
      final styles = <KeepTextStyle>{};
      if (m['b'] == true) styles.add(KeepTextStyle.bold);
      if (m['u'] == true) styles.add(KeepTextStyle.underline);
      if (m['i'] == true) styles.add(KeepTextStyle.italic);
      if (styles.isNotEmpty) {
        rs.add(KeepStyleRange(start, start + chunk.length, styles));
      }
    }
    return (text: buf.toString(), ranges: rs);
  }
}

// ---------------------------------------------------------------------------
// Undo/redo history (pure Dart — unit-tested independently of the editor).
// ---------------------------------------------------------------------------

/// One restorable editor state.
class KeepEditSnapshot {
  final String title;
  final String bodyText;
  final List<KeepStyleRange> ranges;
  final int titleBase;
  final int titleExtent;
  final int bodyBase;
  final int bodyExtent;

  KeepEditSnapshot({
    required this.title,
    required this.bodyText,
    required List<KeepStyleRange> ranges,
    required this.titleBase,
    required this.titleExtent,
    required this.bodyBase,
    required this.bodyExtent,
  }) : ranges = ranges.map((r) => r.copy()).toList();

  @override
  bool operator ==(Object other) {
    if (other is! KeepEditSnapshot) return false;
    if (title != other.title ||
        bodyText != other.bodyText ||
        titleBase != other.titleBase ||
        titleExtent != other.titleExtent ||
        bodyBase != other.bodyBase ||
        bodyExtent != other.bodyExtent ||
        ranges.length != other.ranges.length) {
      return false;
    }
    for (var i = 0; i < ranges.length; i++) {
      final a = ranges[i], b = other.ranges[i];
      if (a.start != b.start ||
          a.end != b.end ||
          a.styles.length != b.styles.length ||
          !a.styles.containsAll(b.styles)) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(title, bodyText, titleBase, bodyBase);
}

/// Bounded undo/redo stack. The top of [_undo] is always the CURRENT state:
/// [push] records a new current state (clearing redo), [undo] steps back,
/// [redo] steps forward.
class KeepEditHistory {
  static const maxDepth = 60;
  final List<KeepEditSnapshot> _undo = [];
  final List<KeepEditSnapshot> _redo = [];

  bool get canUndo => _undo.length > 1;
  bool get canRedo => _redo.isNotEmpty;
  int get depth => _undo.length;

  void push(KeepEditSnapshot s) {
    if (_undo.isNotEmpty && _undo.last == s) return;
    _undo.add(s);
    if (_undo.length > maxDepth) _undo.removeAt(0);
    _redo.clear();
  }

  KeepEditSnapshot? undo() {
    if (!canUndo) return null;
    final cur = _undo.removeLast();
    _redo.add(cur);
    return _undo.last;
  }

  KeepEditSnapshot? redo() {
    if (!canRedo) return null;
    final s = _redo.removeLast();
    _undo.add(s);
    return s;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
