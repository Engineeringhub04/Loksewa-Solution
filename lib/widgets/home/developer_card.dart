import 'package:flutter/material.dart';

/// "About Developer" premium gradient card (mirrors DeveloperCard.tsx).
class DeveloperCard extends StatelessWidget {
  final String name;
  final String? description;
  final String? photoUrl;
  final String? viewUrl;

  const DeveloperCard({
    super.key,
    required this.name,
    this.description,
    this.photoUrl,
    this.viewUrl,
  });

  @override
  Widget build(BuildContext context) {
    // Glow bubbles are positioned relative to the CARD edges (like React's
    // absolute positioning on the card) and clipped by the card's rounded
    // border via ClipRRect — so they tuck under the card edge instead of
    // showing a hard straight cut inside the card.
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
                color: Colors.black38, blurRadius: 12, offset: Offset(0, 6)),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              left: -20,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar with sky border + verified badge.
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                const Color(0xFF38BDF8).withValues(alpha: 0.6),
                          ),
                          child: ClipOval(
                            child: (photoUrl != null && photoUrl!.isNotEmpty)
                                ? Image.network(
                                    photoUrl!,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child,
                                            progress) =>
                                        progress == null
                                            ? child
                                            : Container(
                                                color: const Color(0xFF38BDF8)
                                                    .withValues(alpha: 0.2),
                                                alignment: Alignment.center,
                                                child: const SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ),
                                    errorBuilder: (_, __, ___) =>
                                        _fallbackAvatar(),
                                  )
                                : _fallbackAvatar(),
                          ),
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF22C55E),
                              border: Border.all(
                                  color: const Color(0xFF0F172A), width: 2),
                            ),
                            child: const Icon(Icons.check,
                                size: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.code,
                                size: 16, color: Color(0xFF38BDF8)),
                          ],
                        ),
                        if (description != null && description!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            description!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                              height: 18 / 12,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        // NOTE: external portfolio links need url_launcher
                        // (not a current dependency), so the button is
                        // intentionally non-navigating for now. Pressing still
                        // gives the 0.85 opacity feedback — the visual result of
                        // the Expo card's pressed-opacity.
                        if (viewUrl != null && viewUrl!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _PortfolioButton(viewUrl: viewUrl!),
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

  Widget _fallbackAvatar() => Container(
        color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
        alignment: Alignment.center,
        child: const Icon(Icons.person, size: 36, color: Colors.white70),
      );
}

/// The "Visit Portfolio" pill with the Expo card's press feedback: the
/// button drops to 0.85 opacity while pressed. It stays non-navigating —
/// external links need url_launcher, which is not a dependency (flagged in
/// the final report).
class _PortfolioButton extends StatefulWidget {
  final String viewUrl;
  const _PortfolioButton({required this.viewUrl});

  @override
  State<_PortfolioButton> createState() => _PortfolioButtonState();
}

class _PortfolioButtonState extends State<_PortfolioButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {},
      child: Opacity(
        opacity: _pressed ? 0.85 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: const Color(0xFF38BDF8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Visit Portfolio',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 14, color: Color(0xFF0F172A)),
            ],
          ),
        ),
      ),
    );
  }
}
