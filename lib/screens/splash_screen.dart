import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/course_setup_gate.dart';
import '../services/device_session.dart';
import '../services/onboarding_cache.dart';
import '../services/prefs_service.dart';
import '../services/remote_config.dart';

/// Splash — first screen on launch; initializes the app and routes correctly.
/// Mirrors app/index.tsx: gradient + line-art decorations, logo tile, tagline,
/// spinner, developer footer. Routing: maintenance → evicted → offline →
/// authenticated home → onboarding. Every network call is deadline-bounded so
/// the splash can never hang forever.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _minSplashMs = 1200;
  static const _callTimeout = Duration(seconds: 7);

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<T> _withTimeout<T>(Future<T> future, T fallback) =>
      future.timeout(_callTimeout, onTimeout: () => fallback);

  Future<void> _decide() async {
    if (splashHasRouted) return;
    final startedAt = DateTime.now();

    final user = await _withTimeout(AuthService.restoreSession(), null);

    // One account = one device, asked FIRST — before anything is warmed.
    var evicted = false;
    if (user != null) {
      final session = await _withTimeout(
        DeviceSession.verifyDeviceSession(user.uid),
        const SessionCheck(SessionVerdict.skipped, null),
      );
      if (session.verdict == SessionVerdict.evicted) {
        evicted = true;
        splashHasRouted = true;
        await DeviceSession.markEvictionNotice(session.deviceName);
        await AuthService.logout().catchError((_) {});
      }
    }

    // HARD DEADLINE — the splash must never wait forever.
    final config =
        await _withTimeout(fetchRemoteConfig(), const RemoteConfig());

    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    final remaining = _minSplashMs - elapsed;
    if (remaining > 0) await Future.delayed(Duration(milliseconds: remaining));

    if (!evicted && splashHasRouted) return;
    if (!evicted) splashHasRouted = true;
    if (!mounted) return;

    if (config.maintenanceMode) {
      context.go('/blocking/maintenance');
      return;
    }
    if (evicted) {
      context.go('/login');
      return;
    }
    final connectivity = await Connectivity().checkConnectivity();
    final offline = connectivity.contains(ConnectivityResult.none);
    if (offline && user == null) {
      context.go('/blocking/no-internet');
      return;
    }
    if (user != null) {
      // Logged in: gate on course setup too (user-explicit requirement —
      // React's splash doesn't gate, but the user wants setup enforced here
      // as well). Verified-incomplete → course-setup (initial mode);
      // verified-complete OR unknown (offline/error) → home.
      final setupDone =
          await _withTimeout(CourseSetupGate.isComplete(user.uid), null);
      if (!mounted) return;
      context.go(setupDone == false ? '/course-setup' : '/');
      return;
    }
    // Warm the onboarding image cache (disk + memory) so the onboarding
    // screen shows instantly. Hard deadline: the splash never hangs.
    if (!mounted) return;
    await OnboardingCache.warmUp(context)
        .timeout(const Duration(seconds: 10), onTimeout: () {});
    if (!mounted) return;
    context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final logoSize = (width * 0.44).clamp(0, 188).toDouble();
    final logoRadius = logoSize * 0.2237;

    // Transparent status bar with light icons so the splash gradient flows
    // under the clock — same edge-to-edge treatment as home pages; kills
    // the dark band that used to sit above the splash.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF061A73), Color(0xFF062C91), Color(0xFF03145C)],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: _SplashDecorations()),
              Positioned(
                top: MediaQuery.of(context).size.height * 0.30,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Container(
                      width: logoSize,
                      height: logoSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(logoRadius),
                        color: const Color(0xFF000030),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 18,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(logoRadius),
                        child: Image.asset('assets/images/app_logo.png',
                            fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Loksewa Solution',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Prepare Today. Lead Tomorrow.',
                      style: TextStyle(
                        color: Color(0xFFF0F6FF),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Color(0xFFD8E7FF)),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom + 18,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(color: Color(0xFFD7E3FF), fontSize: 13),
                      children: [
                        TextSpan(
                            text: 'Develop for Nepali student 🇳🇵 || by '),
                        TextSpan(
                          text: 'Kishan Raut',
                          style: TextStyle(
                            color: Color(0xFFF0A04B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: '.'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Line-art decorations — book, bank, target, chart, bookshelf, graduation
/// cap, dotted path, wave lines, dots, radial glow. Same layout language as
/// the Expo splash (stroke #76A9FF).
class _SplashDecorations extends StatelessWidget {
  const _SplashDecorations();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SplashPainter());
  }
}

class _SplashPainter extends CustomPainter {
  static const stroke = Color(0xFF76A9FF);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Radial glow behind the brand content
    final glowRect = Rect.fromCenter(
      center: Offset(w / 2, h * 0.42),
      width: w * 1.26,
      height: h * 0.56,
    );
    canvas.drawOval(
      glowRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0x94A7DCFF),
            Color(0x4759AFFF),
            Color(0x142D83FF),
            Color(0x002D83FF),
          ],
          stops: [0.0, 0.34, 0.72, 1.0],
        ).createShader(glowRect),
    );

    final iconPaint = Paint()
      ..color = stroke.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawIcon(Offset center, double s,
        void Function(Canvas, Offset, double, Paint) draw) {
      canvas.save();
      canvas.translate(center.dx - s / 2, center.dy - s / 2);
      draw(canvas, Offset.zero, s, iconPaint);
      canvas.restore();
    }

    drawIcon(Offset(-18 + 56, h * 0.12 + 56), 112, _book);
    drawIcon(Offset(w - 18 - 53, h * 0.13 + 53), 106, _bank);
    drawIcon(Offset(w * 0.13 + 46, h * 0.30 + 46), 92, _target);
    drawIcon(Offset(w - 18 - 47, h * 0.43 + 47), 94, _chart);
    drawIcon(Offset(32 + 46, h * 0.87 - 46), 92, _bookshelf);
    drawIcon(Offset(w - 27 - 52, h * 0.86 - 52), 104, _graduation);

    // Dotted path (top right)
    final dotted = Paint()
      ..color = stroke.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final dottedPath = Path()
      ..moveTo(w * 0.12, h * 0.02)
      ..cubicTo(w * 0.19, h * 0.12, w * 0.35, h * 0.13, w * 0.5, h * 0.18)
      ..cubicTo(w * 0.66, h * 0.24, w * 0.81, h * 0.28, w * 1.02, h * 0.27);
    _drawDashed(canvas, dottedPath, dotted, 3, 10);

    // Wave lines (bottom)
    final wavePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (var i = 0; i < 4; i++) {
      final y = h - 280 + i * 16.0;
      final wave = Path()
        ..moveTo(-35, y)
        ..cubicTo(w * 0.18, y - 27, w * 0.42, y + 30, w * 0.62, y + 120)
        ..cubicTo(w * 0.78, y + 194, w * 0.88, y + 228, w + 40, y + 241);
      canvas.drawPath(
          wave, wavePaint..color = stroke.withValues(alpha: 0.19 - i * 0.03));
    }

    // Scattered dots
    final dotPaint = Paint()
      ..color = stroke.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (final d in [
      [0.10, 0.25, 2.1],
      [0.62, 0.27, 1.5],
      [0.89, 0.47, 2.1],
      [0.76, 0.79, 1.5],
    ]) {
      canvas.drawCircle(Offset(w * (d[0] as double), h * (d[1] as double)),
          d[2] as double, dotPaint);
    }
  }

  void _drawDashed(
      Canvas canvas, Path path, Paint paint, double dash, double gap) {
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      var d = 0.0;
      while (d < m.length) {
        final end = (d + dash).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(d, end), paint);
        d += dash + gap;
      }
    }
  }

  static void _book(Canvas c, Offset o, double s, Paint p) {
    final u = s / 100;
    c.drawPath(
      Path()
        ..moveTo(o.dx + 8 * u, o.dy + 20 * u)
        ..cubicTo(o.dx + 23 * u, o.dy + 13 * u, o.dx + 38 * u, o.dy + 16 * u,
            o.dx + 50 * u, o.dy + 27 * u)
        ..lineTo(o.dx + 50 * u, o.dy + 81 * u)
        ..cubicTo(o.dx + 37 * u, o.dy + 71 * u, o.dx + 23 * u, o.dy + 68 * u,
            o.dx + 8 * u, o.dy + 75 * u)
        ..close(),
      p,
    );
    c.drawPath(
      Path()
        ..moveTo(o.dx + 92 * u, o.dy + 20 * u)
        ..cubicTo(o.dx + 77 * u, o.dy + 13 * u, o.dx + 62 * u, o.dy + 16 * u,
            o.dx + 50 * u, o.dy + 27 * u)
        ..lineTo(o.dx + 50 * u, o.dy + 81 * u)
        ..cubicTo(o.dx + 63 * u, o.dy + 71 * u, o.dx + 77 * u, o.dy + 68 * u,
            o.dx + 92 * u, o.dy + 75 * u)
        ..close(),
      p,
    );
  }

  static void _bank(Canvas c, Offset o, double s, Paint p) {
    final u = s / 100;
    c.drawPath(
      Path()
        ..moveTo(o.dx + 8 * u, o.dy + 29 * u)
        ..lineTo(o.dx + 50 * u, o.dy + 10 * u)
        ..lineTo(o.dx + 92 * u, o.dy + 29 * u)
        ..close(),
      p,
    );
    c.drawLine(Offset(o.dx + 13 * u, o.dy + 34 * u),
        Offset(o.dx + 87 * u, o.dy + 34 * u), p);
    for (final x in [19, 37, 63, 81]) {
      c.drawLine(Offset(o.dx + x * u, o.dy + 36 * u),
          Offset(o.dx + x * u, o.dy + 72 * u), p);
    }
    c.drawLine(Offset(o.dx + 12 * u, o.dy + 77 * u),
        Offset(o.dx + 88 * u, o.dy + 77 * u), p);
  }

  static void _target(Canvas c, Offset o, double s, Paint p) {
    final u = s / 100;
    final center = Offset(o.dx + 46 * u, o.dy + 54 * u);
    for (final r in [28, 17, 6]) {
      c.drawCircle(center, r * u, p);
    }
    c.drawLine(Offset(o.dx + 20 * u, o.dy + 79 * u),
        Offset(o.dx + 78 * u, o.dy + 21 * u), p);
  }

  static void _chart(Canvas c, Offset o, double s, Paint p) {
    final u = s / 100;
    c.drawLine(Offset(o.dx + 12 * u, o.dy + 83 * u),
        Offset(o.dx + 90 * u, o.dy + 83 * u), p);
    c.drawLine(Offset(o.dx + 16 * u, o.dy + 83 * u),
        Offset(o.dx + 16 * u, o.dy + 25 * u), p);
    for (final b in [
      [26, 59, 24],
      [44, 48, 35],
      [62, 35, 48],
    ]) {
      c.drawRect(
        Rect.fromLTWH(o.dx + (b[0] as int) * u, o.dy + (b[1] as int) * u,
            10 * u, (b[2] as int) * u),
        p,
      );
    }
  }

  static void _bookshelf(Canvas c, Offset o, double s, Paint p) {
    final u = s / 100;
    c.drawLine(Offset(o.dx + 12 * u, o.dy + 78 * u),
        Offset(o.dx + 88 * u, o.dy + 78 * u), p);
    c.drawRect(Rect.fromLTWH(o.dx + 18 * u, o.dy + 39 * u, 12 * u, 39 * u), p);
    c.drawRect(Rect.fromLTWH(o.dx + 34 * u, o.dy + 30 * u, 12 * u, 48 * u), p);
    c.drawRect(Rect.fromLTWH(o.dx + 51 * u, o.dy + 35 * u, 12 * u, 43 * u), p);
  }

  static void _graduation(Canvas c, Offset o, double s, Paint p) {
    final u = s / 100;
    c.drawPath(
      Path()
        ..moveTo(o.dx + 50 * u, o.dy + 13 * u)
        ..lineTo(o.dx + 91 * u, o.dy + 34 * u)
        ..lineTo(o.dx + 50 * u, o.dy + 55 * u)
        ..lineTo(o.dx + 9 * u, o.dy + 34 * u)
        ..close(),
      p,
    );
    c.drawPath(
      Path()
        ..moveTo(o.dx + 23 * u, o.dy + 43 * u)
        ..lineTo(o.dx + 23 * u, o.dy + 65 * u)
        ..cubicTo(o.dx + 38 * u, o.dy + 77 * u, o.dx + 62 * u, o.dy + 77 * u,
            o.dx + 77 * u, o.dy + 65 * u)
        ..lineTo(o.dx + 77 * u, o.dy + 43 * u),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
