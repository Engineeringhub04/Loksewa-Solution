import 'package:flutter/material.dart';

/// Curved gradient header shared by all auth screens — mirrors AuthHeader.tsx.
/// Gradient #2563EB -> #1D4ED8 -> #0B1F5B top-to-bottom, 32px bottom corner
/// radius, 82x82 logo squircle tile (radius 18), title 26 bold white,
/// subtitle 14 rgba(255,255,255,0.88). Always light — never themed.
class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onBack;

  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF2563EB),
            Color(0xFF1D4ED8),
            Color(0xFF0B1F5B),
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: EdgeInsets.only(
        top: topPad + 16,
        bottom: 24,
        left: 32,
        right: 32,
      ),
      child: Stack(
        children: [
          if (onBack != null)
            Positioned(
              top: 30,
              left: -18,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back,
                    size: 22, color: Colors.white),
                padding: const EdgeInsets.all(6),
              ),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 82,
                  height: 82,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: const Color(0xFF000030),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x801E40AF),
                        blurRadius: 12,
                        offset: Offset(0, 0),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 82,
                    height: 82,
                    fit: BoxFit.cover,
                  ),
                ),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 14,
                    height: 20 / 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
