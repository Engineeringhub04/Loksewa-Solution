import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_language.dart';

/// Full-screen premium overlay for the gateway payment flow.
enum PaymentOverlayState { verifying, success, failure }

class PaymentStatusOverlay extends StatefulWidget {
  final PaymentOverlayState state;
  final String title;
  final String subtitle;
  final VoidCallback? onClose;
  final VoidCallback? onRetry;

  const PaymentStatusOverlay({
    super.key,
    required this.state,
    required this.title,
    required this.subtitle,
    this.onClose,
    this.onRetry,
  });

  @override
  State<PaymentStatusOverlay> createState() => _PaymentStatusOverlayState();
}

class _PaymentStatusOverlayState extends State<PaymentStatusOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _draw;
  late final Animation<double> _drawAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _draw = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _drawAnim = CurvedAnimation(parent: _draw, curve: Curves.easeOutCubic);
    if (widget.state != PaymentOverlayState.verifying) {
      _draw.forward();
      _pulse.stop();
    }
  }

  @override
  void didUpdateWidget(PaymentStatusOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      if (widget.state == PaymentOverlayState.verifying) {
        _draw.reset();
        _pulse.repeat();
      } else {
        _pulse.stop();
        _draw.forward();
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _draw.dispose();
    super.dispose();
  }

  Color get _accent {
    switch (widget.state) {
      case PaymentOverlayState.verifying:
        return const Color(0xFF3B82F6);
      case PaymentOverlayState.success:
        return const Color(0xFF22C55E);
      case PaymentOverlayState.failure:
        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: _accent.withValues(alpha: 0.35), width: 1),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.18),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusIcon(
                    pulse: _pulse,
                    drawAnim: _drawAnim,
                    accent: _accent,
                    state: widget.state),
                const SizedBox(height: 22),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: 0.62)),
                ),
                if (widget.state == PaymentOverlayState.failure) ...[
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      if (widget.onRetry != null)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: widget.onRetry,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(AppLanguage.tr(
                                'Try Again', 'पुनः प्रयास गर्नुहोस्')),
                          ),
                        ),
                      if (widget.onRetry != null) const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.onClose ??
                              () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                                color:
                                    Colors.white.withValues(alpha: 0.25)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                              AppLanguage.tr('Close', 'बन्द गर्नुहोस्')),
                        ),
                      ),
                    ],
                  ),
                ],
                if (widget.state == PaymentOverlayState.success) ...[
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: widget.onClose ??
                          () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(AppLanguage.tr(
                          'Continue', 'अगाडि बढ्नुहोस्')),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends AnimatedWidget {
  final Animation<double> drawAnim;
  final Color accent;
  final PaymentOverlayState state;

  const _StatusIcon({
    required Animation<double> pulse,
    required this.drawAnim,
    required this.accent,
    required this.state,
  }) : super(listenable: pulse);

  Animation<double> get _pulse => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    final verifying = state == PaymentOverlayState.verifying;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding pulse rings while verifying.
          if (verifying)
            for (var i = 0; i < 3; i++)
              _PulseRing(progress: (_pulse.value + i / 3) % 1.0, color: accent),
          // Rotating arc while verifying.
          if (verifying)
            RotationTransition(
              turns: _pulse,
              child: CustomPaint(
                size: const Size(88, 88),
                painter: _ArcPainter(color: accent),
              ),
            ),
          // Solid glowing disc.
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: verifying ? 0.30 : 0.38),
                  accent.withValues(alpha: 0.10),
                ],
              ),
              border: Border.all(
                  color: accent.withValues(alpha: 0.65), width: 2),
            ),
          ),
          if (verifying)
            Icon(Icons.lock_outline,
                size: 36, color: accent.withValues(alpha: 0.95))
          else
            AnimatedBuilder(
              animation: drawAnim,
              builder: (_, __) => CustomPaint(
                size: const Size(40, 40),
                painter: state == PaymentOverlayState.success
                    ? _CheckPainter(
                        progress: drawAnim.value, color: accent)
                    : _CrossPainter(
                        progress: drawAnim.value, color: accent),
              ),
            ),
        ],
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  final double progress;
  final Color color;
  const _PulseRing({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    final scale = 0.75 + progress * 0.55;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: (1 - progress) * 0.5),
            width: 2,
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final Color color;
  _ArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromLTWH(0, 0, size.width, size.height),
        -math.pi / 2, math.pi * 1.2, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  _CheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p1 = Offset(size.width * 0.26, size.height * 0.54);
    final p2 = Offset(size.width * 0.44, size.height * 0.72);
    final p3 = Offset(size.width * 0.76, size.height * 0.30);
    // Draw leg 1 then leg 2 as progress goes 0→1.
    if (progress < 0.45) {
      final t = progress / 0.45;
      canvas.drawLine(p1, Offset.lerp(p1, p2, t)!, paint);
    } else {
      canvas.drawLine(p1, p2, paint);
      final t = (progress - 0.45) / 0.55;
      canvas.drawLine(p2, Offset.lerp(p2, p3, t)!, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _CrossPainter extends CustomPainter {
  final double progress;
  final Color color;
  _CrossPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final a1 = Offset(size.width * 0.30, size.height * 0.30);
    final a2 = Offset(size.width * 0.70, size.height * 0.70);
    final b1 = Offset(size.width * 0.70, size.height * 0.30);
    final b2 = Offset(size.width * 0.30, size.height * 0.70);
    if (progress < 0.5) {
      final t = progress / 0.5;
      canvas.drawLine(a1, Offset.lerp(a1, a2, t)!, paint);
    } else {
      canvas.drawLine(a1, a2, paint);
      final t = (progress - 0.5) / 0.5;
      canvas.drawLine(b1, Offset.lerp(b1, b2, t)!, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CrossPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
