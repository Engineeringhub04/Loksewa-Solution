// Shared discussion avatar: photo URL with a grey initial-letter fallback.
// Mirrors the React avatar treatment (NOT the brand watermark).
import 'package:flutter/material.dart';

class DiscussionAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double radius;

  const DiscussionAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    this.radius = 18,
  });

  String get _initial {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final rune = t.runes.first;
    return String.fromCharCode(rune).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = (photoUrl ?? '').trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE2E8F0),
      child: url.isEmpty
          ? _InitialText(initial: _initial, radius: radius)
          : ClipOval(
              child: Image.network(
                url,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _InitialText(initial: _initial, radius: radius),
              ),
            ),
    );
  }
}

class _InitialText extends StatelessWidget {
  final String initial;
  final double radius;

  const _InitialText({required this.initial, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Text(
      initial,
      style: TextStyle(
        fontSize: radius * 0.85,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF64748B),
        decoration: TextDecoration.none,
      ),
    );
  }
}
