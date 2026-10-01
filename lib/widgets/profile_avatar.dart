import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:loksewa_solution/theme/app_theme.dart';

import 'disk_cached_image.dart';

/// Avatar widgets for the Profile (and Home) headers.
///
/// Mirrors `src/components/profile/`:
/// - [ProfileAvatar] — the signed-in user's own avatar wearing whichever ring
///   their account earns (green glow free tier, multi-colour sweep premium).
/// - [ProAvatarRing] — the fixed multi-colour sweep (a conic-gradient
///   equivalent drawn as short SVG-style arcs).
/// - [AvatarProgressRing] — determinate progress ring drawn while a photo
///   uploads (blue uploading, green done, plain ring idle).
/// - [VerifiedTick] — the black premium seal (user-supplied SVG path).
/// - [NameWithTick] — Facebook-style verified name: name + tick beside it.

// ---------------------------------------------------------------------------
// Minimal SVG path parser
// ---------------------------------------------------------------------------

/// Parses the subset of SVG path data used by the seal + pencil glyphs:
/// M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z, implicit lineto pairs, and
/// comma/whitespace-separated numbers (sign-delimited, exponents allowed).
class SvgPathParser {
  static Path parse(String data) {
    final path = Path();
    final tokens = _tokenize(data);
    double cx = 0, cy = 0; // current point
    double sx = 0, sy = 0; // subpath start
    double? lastCx, lastCy; // last cubic control (for S)
    double? lastQx, lastQy; // last quad control (for T)
    String? cmd;
    var i = 0;

    double num() => tokens[i++] as double;
    bool hasNum() => i < tokens.length && tokens[i] is double;

    void lineTo(double x, double y) {
      path.lineTo(x, y);
      cx = x;
      cy = y;
    }

    void curveTo(double x1, double y1, double x2, double y2, double x, double y) {
      path.cubicTo(x1, y1, x2, y2, x, y);
      lastCx = x2;
      lastCy = y2;
      cx = x;
      cy = y;
    }

    while (i < tokens.length) {
      final t = tokens[i];
      if (t is String) {
        cmd = t;
        i++;
        if (cmd == 'Z' || cmd == 'z') {
          path.close();
          cx = sx;
          cy = sy;
          lastCx = lastCy = lastQx = lastQy = null;
          cmd = null;
        } else if (cmd == 'M' || cmd == 'm') {
          final rel = cmd == 'm';
          final x = num(), y = num();
          cx = rel ? cx + x : x;
          cy = rel ? cy + y : y;
          path.moveTo(cx, cy);
          sx = cx;
          sy = cy;
          lastCx = lastCy = lastQx = lastQy = null;
          // Subsequent implicit pairs are linetos.
          cmd = rel ? 'l' : 'L';
        }
        continue;
      }
      if (cmd == null) {
        i++;
        continue;
      }
      switch (cmd) {
        case 'L':
          lineTo(num(), num());
          break;
        case 'l':
          lineTo(cx + num(), cy + num());
          break;
        case 'H':
          lineTo(num(), cy);
          break;
        case 'h':
          lineTo(cx + num(), cy);
          break;
        case 'V':
          lineTo(cx, num());
          break;
        case 'v':
          lineTo(cx, cy + num());
          break;
        case 'C':
          curveTo(num(), num(), num(), num(), num(), num());
          break;
        case 'c':
          {
            final x1 = cx + num(), y1 = cy + num();
            final x2 = cx + num(), y2 = cy + num();
            curveTo(x1, y1, x2, y2, cx + num(), cy + num());
          }
          break;
        case 'S':
          {
            final x1 = lastCx != null ? 2 * cx - lastCx! : cx;
            final y1 = lastCy != null ? 2 * cy - lastCy! : cy;
            curveTo(x1, y1, num(), num(), num(), num());
          }
          break;
        case 's':
          {
            final x1 = lastCx != null ? 2 * cx - lastCx! : cx;
            final y1 = lastCy != null ? 2 * cy - lastCy! : cy;
            final x2 = cx + num(), y2 = cy + num();
            curveTo(x1, y1, x2, y2, cx + num(), cy + num());
          }
          break;
        case 'Q':
          {
            final x1 = num(), y1 = num(), x = num(), y = num();
            path.quadraticBezierTo(x1, y1, x, y);
            lastQx = x1;
            lastQy = y1;
            cx = x;
            cy = y;
          }
          break;
        case 'q':
          {
            final x1 = cx + num(), y1 = cy + num();
            final x = cx + num(), y = cy + num();
            path.quadraticBezierTo(x1, y1, x, y);
            lastQx = x1;
            lastQy = y1;
            cx = x;
            cy = y;
          }
          break;
        case 'T':
          {
            final x1 = lastQx != null ? 2 * cx - lastQx : cx;
            final y1 = lastQy != null ? 2 * cy - lastQy : cy;
            final x = num(), y = num();
            path.quadraticBezierTo(x1, y1, x, y);
            lastQx = x1;
            lastQy = y1;
            cx = x;
            cy = y;
          }
          break;
        case 't':
          {
            final x1 = lastQx != null ? 2 * cx - lastQx : cx;
            final y1 = lastQy != null ? 2 * cy - lastQy : cy;
            final x = cx + num(), y = cy + num();
            path.quadraticBezierTo(x1, y1, x, y);
            lastQx = x1;
            lastQy = y1;
            cx = x;
            cy = y;
          }
          break;
        case 'A':
          {
            final rx = num(), ry = num(), phi = num();
            final laf = num() != 0, sf = num() != 0;
            final x = num(), y = num();
            _arcTo(path, cx, cy, rx, ry, phi, laf, sf, x, y);
            cx = x;
            cy = y;
          }
          break;
        case 'a':
          {
            final rx = num(), ry = num(), phi = num();
            final laf = num() != 0, sf = num() != 0;
            final x = cx + num(), y = cy + num();
            _arcTo(path, cx, cy, rx, ry, phi, laf, sf, x, y);
            cx = x;
            cy = y;
          }
          break;
        default:
          i++;
      }
      if (cmd != 'S' && cmd != 's' && cmd != 'C' && cmd != 'c') {
        lastCx = lastCy = null;
      }
      if (cmd != 'T' && cmd != 't' && cmd != 'Q' && cmd != 'q') {
        lastQx = lastQy = null;
      }
      if (!hasNum()) cmd = null;
    }
    return path;
  }

  static List<Object> _tokenize(String data) {
    final out = <Object>[];
    final numRe = RegExp(
        r'[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');
    var i = 0;
    while (i < data.length) {
      final ch = data[i];
      if (ch == ',' || ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r') {
        i++;
        continue;
      }
      if (RegExp(r'[MmLlHhVvCcSsQqTtAaZz]').hasMatch(ch)) {
        out.add(ch);
        i++;
        continue;
      }
      final m = numRe.matchAsPrefix(data, i);
      if (m != null) {
        out.add(double.parse(m.group(0)!));
        i = m.end;
      } else {
        i++;
      }
    }
    return out;
  }

  /// SVG endpoint-parametrised arc -> cubic beziers (spec F.6.5).
  static void _arcTo(Path path, double x1, double y1, double rx0, double ry0,
      double phiDeg, bool largeArc, bool sweep, double x2, double y2) {
    var rx = rx0.abs(), ry = ry0.abs();
    if (rx == 0 || ry == 0) {
      path.lineTo(x2, y2);
      return;
    }
    final phi = phiDeg * math.pi / 180;
    final cosPhi = math.cos(phi), sinPhi = math.sin(phi);
    final dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
    final x1p = cosPhi * dx + sinPhi * dy;
    final y1p = -sinPhi * dx + cosPhi * dy;

    var lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lambda > 1) {
      final s = math.sqrt(lambda);
      rx *= s;
      ry *= s;
    }
    final num_ = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
    final den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
    var c = den == 0 ? 0.0 : math.sqrt(math.max(0, num_ / den));
    if (largeArc == sweep) c = -c;
    final cxp = c * rx * y1p / ry;
    final cyp = c * -ry * x1p / rx;
    final cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2;
    final cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2;

    double angle(double ux, double uy, double vx, double vy) {
      final dot = ux * vx + uy * vy;
      final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
      var a = len == 0 ? 0.0 : math.acos((dot / len).clamp(-1.0, 1.0));
      if (ux * vy - uy * vx < 0) a = -a;
      return a;
    }

    var t1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
    var dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
        (-x1p - cxp) / rx, (-y1p - cyp) / ry);
    if (!sweep && dTheta > 0) {
      dTheta -= 2 * math.pi;
    } else if (sweep && dTheta < 0) {
      dTheta += 2 * math.pi;
    }

    final segments = math.max(1, (dTheta.abs() / (math.pi / 2)).ceil());
    final step = dTheta / segments;
    for (var s = 0; s < segments; s++) {
      final t2 = t1 + step;
      final k = 4 / 3 * math.tan(step / 4);
      final p1x = cx + rx * math.cos(t1), p1y = cy + ry * math.sin(t1);
      final p2x = cx + rx * math.cos(t2), p2y = cy + ry * math.sin(t2);
      final d1x = -rx * math.sin(t1), d1y = ry * math.cos(t1);
      final d2x = -rx * math.sin(t2), d2y = ry * math.cos(t2);
      // Rotate the points + derivatives by phi.
      double rx_(double x, double y) => cosPhi * x - sinPhi * y;
      double ry_(double x, double y) => sinPhi * x + cosPhi * y;
      path.cubicTo(
        cx + rx_(p1x - cx + k * d1x, p1y - cy + k * d1y),
        cy + ry_(p1x - cx + k * d1x, p1y - cy + k * d1y),
        cx + rx_(p2x - cx - k * d2x, p2y - cy - k * d2y),
        cy + ry_(p2x - cx - k * d2x, p2y - cy - k * d2y),
        cx + rx_(p2x - cx, p2y - cy),
        cy + ry_(p2x - cx, p2y - cy),
      );
      t1 = t2;
    }
  }
}

// ---------------------------------------------------------------------------
// VerifiedTick — the public "this account is premium" mark
// ---------------------------------------------------------------------------

/// The user-supplied SVG seal: starburst with a scalloped edge, drawn in BLACK
/// ("black color hos"). The seal path fills the whole viewBox; its scalloped
/// edge is the design, so the badge never circle-clips it.
class VerifiedTick extends StatelessWidget {
  /// Outer diameter of the badge. Defaults to a standalone 18.
  final double size;

  const VerifiedTick({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final d = math.max(10.0, size);
    return SizedBox(
      width: d,
      height: d,
      child: const CustomPaint(painter: _SealPainter()),
    );
  }
}

/// Smallest badge that still reads as a seal.
const double verifiedTickMinSize = 10;

/// Avatars below this diameter do not get a badge at all.
const double verifiedTickMinAvatar = 22;

/// Badge diameter for an avatar of [avatarSize] — 26% keeps it small on the rim.
double verifiedTickSizeFor(double avatarSize) =>
    math.max(verifiedTickMinSize, (avatarSize * 0.26).roundToDouble());

/// The full user-supplied seal path, INCLUDING the check cut-out (evenodd).
const String _sealPath =
    'M238.738 271.339 210.764 244.4a15 15 0 1 0-20.8 21.6l38.558 37.139a14.965 14.965 0 0 0 21.009-.184l72.719-72.718a15 15 0 0 0-21.215-21.215l-62.294 62.317zM257.03.007a34.56 34.56 0 0 1 23.474 10.1l30.723 30.746a4.21 4.21 0 0 0 4.49 1.214l42-11.249a34.66 34.66 0 0 1 42.43 24.492l11.25 42a4.22 4.22 0 0 0 3.276 3.276l42.018 11.25a34.705 34.705 0 0 1 24.492 42.43l-11.272 42a4.29 4.29 0 0 0 1.214 4.49l30.742 30.744a34.653 34.653 0 0 1 0 48.983l-30.746 30.746a4.29 4.29 0 0 0-1.214 4.491l11.272 42a34.706 34.706 0 0 1-24.492 42.431L414.669 411.4a4.22 4.22 0 0 0-3.276 3.276l-11.25 42a34.66 34.66 0 0 1-42.43 24.491l-42-11.249a4.21 4.21 0 0 0-4.49 1.214L280.5 501.866a34.707 34.707 0 0 1-49.006 0l-30.742-30.746a4.21 4.21 0 0 0-4.468-1.214l-42.007 11.249a34.66 34.66 0 0 1-42.428-24.491l-11.251-42a4.22 4.22 0 0 0-3.281-3.276l-42-11.249a34.7 34.7 0 0 1-24.5-42.431l11.259-41.995a4.22 4.22 0 0 0-1.21-4.491L10.128 280.48a34.664 34.664 0 0 1 0-48.983l30.75-30.746a4.23 4.23 0 0 0 1.2-4.49l-11.259-42a34.7 34.7 0 0 1 24.5-42.43l42-11.25a4.22 4.22 0 0 0 3.281-3.276l11.251-41.995a34.667 34.667 0 0 1 42.428-24.492l42.007 11.249a4.18 4.18 0 0 0 4.468-1.214L231.5 10.111A34.56 34.56 0 0 1 254.971.007z';

/// The check, promoted to a white stroke on top of the black seal.
const String _checkPath =
    'M227.9 281.9 200 255a15 15 0 1 0-20.8 21.6l38.6 37.1a15 15 0 0 0 21-.2l72.7-72.7a15 15 0 0 0-21.2-21.2l-62.4 62.3z';

class _SealPainter extends CustomPainter {
  const _SealPainter();

  static final Path _seal =
      SvgPathParser.parse(_sealPath)..fillType = PathFillType.evenOdd;
  static final Path _check = SvgPathParser.parse(_checkPath);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 512;
    canvas.save();
    canvas.scale(s);
    canvas.drawPath(_seal, Paint()..color = const Color(0xFF111111));
    canvas.drawPath(_check, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// ProAvatarRing — the multi-colour ring worn by a premium member's avatar
// ---------------------------------------------------------------------------

/// IT DOES NOT MOVE, ON PURPOSE: a premium mark should be a mark, not an
/// animation (the old 5s spin read as a loading spinner wrapped around the
/// user's face).
///
/// SIZING CONTRACT: the outer box is exactly `size + ringWidth * 2`, the same
/// box the plain green glow occupies at every avatar size — a premium user and
/// a free user get identically sized headers.
class ProAvatarRing extends StatelessWidget {
  /// Diameter of the avatar being wrapped. The ring adds its own width outside.
  final double size;

  /// The avatar itself. Rendered above the ring.
  final Widget child;

  const ProAvatarRing({super.key, required this.size, required this.child});

  static const _ringColors = [
    Color(0xFF4C7CF0),
    Color(0xFF7B5FE8),
    Color(0xFFE257A6),
    Color(0xFFF6B94E),
  ];

  /// Ring thickness per avatar size, pinned to the green ring it replaces:
  /// 88 -> 7 (4 padding + 3 border), 44 -> 5.5 (3 + 2.5), 30 -> 4 (2 + 2).
  static double ringWidthFor(double size) {
    if (size >= 64) return 7;
    if (size >= 36) return 5.5;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final ringWidth = ringWidthFor(size);
    final outer = size + ringWidth * 2;
    final radius = (outer - ringWidth) / 2;
    // The halo is the same sweep drawn fat and faint — the stand-in for a
    // blur filter. It bleeds inward too, but the avatar is painted over it.
    // Absolutely positioned so its overhang never widens the layout box.
    final haloWidth = ringWidth * 2.6;
    final haloSpread = ((haloWidth - ringWidth) / 2).ceilToDouble();
    final canvasSize = outer + haloSpread * 2;
    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: -haloSpread,
            top: -haloSpread,
            width: canvasSize,
            height: canvasSize,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ProRingPainter(
                  ringWidth: ringWidth,
                  haloWidth: haloWidth,
                  radius: radius,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ProRingPainter extends CustomPainter {
  final double ringWidth;
  final double haloWidth;
  final double radius;

  const _ProRingPainter({
    required this.ringWidth,
    required this.haloWidth,
    required this.radius,
  });

  static const _segments = 36;
  static const _haloSegments = 18;

  static Color _colorAtTurn(double turn) {
    const stops = ProAvatarRing._ringColors;
    final scaled = (((turn % 1) + 1) % 1) * stops.length;
    final index = scaled.floor() % stops.length;
    final t = scaled - scaled.floor();
    final a = stops[index], b = stops[(index + 1) % stops.length];
    int lerp8(int x, int y) => (x + (y - x) * t).round().clamp(0, 255);
    return Color.fromARGB(255, lerp8((a.r * 255.0).round(), (b.r * 255.0).round()),
        lerp8((a.g * 255.0).round(), (b.g * 255.0).round()),
        lerp8((a.b * 255.0).round(), (b.b * 255.0).round()));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    // The quarter turn is the one piece of orientation this needs now that it
    // stands still: the palette begins at the top of the circle, where the eye
    // starts reading it.
    const startBase = -math.pi / 2;
    for (var i = 0; i < _haloSegments; i++) {
      const slot = 2 * math.pi / _haloSegments;
      canvas.drawArc(
        rect,
        startBase + i * slot,
        slot * 1.2,
        false,
        Paint()
          ..color = _colorAtTurn((i + 0.5) / _haloSegments)
              .withValues(alpha: 0.24)
          ..style = PaintingStyle.stroke
          ..strokeWidth = haloWidth,
      );
    }
    for (var i = 0; i < _segments; i++) {
      const slot = 2 * math.pi / _segments;
      canvas.drawArc(
        rect,
        startBase + i * slot,
        slot * 1.2,
        false,
        Paint()
          ..color = _colorAtTurn((i + 0.5) / _segments)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// AvatarProgressRing — determinate ring drawn while a photo uploads
// ---------------------------------------------------------------------------

/// Theme-aware determinate ring drawn while a photo uploads: the theme's info
/// tone while uploading (driven by real upload-progress events), the theme's
/// success tone once the upload completes, and a plain themed ring when idle.
enum UploadState { idle, uploading, done }

class AvatarProgressRing extends StatelessWidget {
  /// Diameter of the inner avatar content.
  final double size;

  /// 0..1
  final double progress;
  final UploadState state;
  final Widget child;

  /// Overrides the uploading arc colour. Defaults to the theme's info tone.
  final Color? activeColor;

  /// Overrides the completed arc colour. Defaults to the theme's success tone.
  final Color? doneColor;

  const AvatarProgressRing({
    super.key,
    required this.size,
    required this.progress,
    required this.state,
    required this.child,
    this.activeColor,
    this.doneColor,
  });

  @override
  Widget build(BuildContext context) {
    const stroke = 4.0;
    const padding = stroke + 2;
    final outer = size + padding * 2;
    final palette = ExpoPalette.of(context);
    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(outer, outer),
            painter: _UploadRingPainter(
              progress: progress,
              state: state,
              trackColor: palette.border,
              activeColor: activeColor ?? palette.info,
              doneColor: doneColor ?? palette.success,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _UploadRingPainter extends CustomPainter {
  final double progress;
  final UploadState state;
  final Color trackColor;
  final Color activeColor;
  final Color doneColor;

  const _UploadRingPainter({
    required this.progress,
    required this.state,
    required this.trackColor,
    required this.activeColor,
    required this.doneColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final showRing = state != UploadState.idle;
    final ringColor = state == UploadState.done ? doneColor : activeColor;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = showRing ? ringColor.withValues(alpha: 0.2) : trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (showRing) {
      // 'done' always draws a full ring even if the last progress event came
      // in slightly under 1.
      final clamped = state == UploadState.done
          ? 1.0
          : progress.clamp(0.0, 1.0);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * clamped,
        false,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UploadRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.state != state ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.doneColor != doneColor;
}

// ---------------------------------------------------------------------------
// ProfileAvatar — the signed-in user's own avatar, wearing its ring
// ---------------------------------------------------------------------------

/// Free-tier ring colour, in both the expanded and collapsed headers.
const Color _glowGreen = Color(0xFF22C55E);

class _GlowStep {
  final double border;
  final double padding;
  final double haloRadius;
  const _GlowStep(this.border, this.padding, this.haloRadius);
}

/// Per-size geometry for the green ring. `border + padding` is the ring's
/// total thickness and must equal ProAvatarRing's width for the same size, or
/// swapping between them moves the layout.
_GlowStep _glowStepFor(double size) {
  if (size >= 64) return const _GlowStep(3, 4, 14);
  if (size >= 36) return const _GlowStep(2.5, 3, 12);
  return const _GlowStep(2, 2, 8);
}

class ProfileAvatar extends StatelessWidget {
  final String? uri;
  final String? name;

  /// Diameter of the photo. Both rings are drawn outside this.
  final double size;

  /// Premium entitlement is active right now — use
  /// [hasActivePremium], not the raw isPremium flag, so a lapsed subscription
  /// stops decorating the avatar even before the next expiry sweep rewrites
  /// the stored field.
  final bool pro;

  const ProfileAvatar({
    super.key,
    this.uri,
    this.name,
    required this.size,
    this.pro = false,
  });

  String _initials() {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last =
        parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  Widget _initialFace(ExpoPalette palette) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.surfaceAlt,
        ),
        alignment: Alignment.center,
        child: Text(
          _initials(),
          style: TextStyle(
            color: palette.primary,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.38,
            height: 1.26,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    Widget face;
    if (uri != null && uri!.isNotEmpty) {
      face = ClipOval(
        child: DiskCachedImage(
          url: uri!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, _, __) => _initialFace(palette),
        ),
      );
    } else {
      face = _initialFace(palette);
    }
    final avatar = SizedBox(width: size, height: size, child: face);

    // The ring used to require a photo — an animated sweep around a grey
    // initials circle read as a loading spinner. Now that it stands still
    // there is nothing to mistake it for, so a premium member without a photo
    // wears it too.
    if (pro) {
      return ProAvatarRing(size: size, child: avatar);
    }

    final step = _glowStepFor(size);
    return Container(
      padding: EdgeInsets.all(step.padding),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _glowGreen.withValues(alpha: 0.22),
        border: Border.all(color: _glowGreen, width: step.border),
        boxShadow: [
          BoxShadow(
            color: _glowGreen.withValues(alpha: 0.9),
            blurRadius: step.haloRadius,
          ),
        ],
      ),
      child: avatar,
    );
  }
}

// ---------------------------------------------------------------------------
// NameWithTick — Facebook-style verified name
// ---------------------------------------------------------------------------

/// The display name followed by the verified tick — "Kishan Raut ✔". The tick
/// belongs to the NAME, not the photo, and it works with truncation: the name
/// ellipsises from its tail and the tick stays visible right after it.
///
/// Place inside a [Flexible]/[Expanded] when siblings must keep their size —
/// the name is the lowest-priority element and yields first.
class NameWithTick extends StatelessWidget {
  final String name;

  /// Show the tick. Pass the row's own premium flag.
  final bool pro;
  final TextStyle? style;

  /// Tick diameter. Roughly the text's cap height (h3 -> 16, bodySmall -> 12).
  final double tickSize;

  const NameWithTick({
    super.key,
    required this.name,
    this.pro = false,
    this.style,
    this.tickSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (pro) ...[
          const SizedBox(width: 4),
          VerifiedTick(size: tickSize),
        ],
      ],
    );
  }
}
