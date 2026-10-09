import 'package:flutter/material.dart';

import 'disk_cached_image.dart';

/// Shared leaderboard podium — the EXACT UI from the main leaderboard
/// (mirrors components/leaderboard/Podium.tsx), reused by the exam ranking
/// screen. Same UI, only the data differs.
///
/// Display order of [entries] is 2nd, 1st, 3rd. Always three stands, even
/// with a single participant — empty places show [emptyLabel] so the layout
/// never collapses.
///
/// The screen is FIXED to its own dark palette (like React) and does NOT
/// follow the app theme: the podium is a designed surface and re-tinting the
/// medals per theme would wreck their contrast.
class PodiumEntry {
  final String name;
  final String? photoURL;
  final bool isPro;

  /// Pre-formatted headline stat shown in the pill (e.g. "38%").
  final String stat;

  /// Optional second line under the pill (e.g. "1200 pts"). Null = hidden.
  final String? subStat;

  const PodiumEntry({
    required this.name,
    this.photoURL,
    required this.isPro,
    required this.stat,
    this.subStat,
  });
}

const _text = Color(0xFFFFFFFF);
const _textDim = Color(0xB8FFFFFF); // rgba(255,255,255,0.72)

class _PlaceTheme {
  final int place;
  final Color ring;
  final Color glow;
  final List<Color> block;
  final Color onRing;
  final Color pill;
  final IconData icon;
  final double iconSize;
  final double height;
  final double avatar;

  const _PlaceTheme({
    required this.place,
    required this.ring,
    required this.glow,
    required this.block,
    required this.onRing,
    required this.pill,
    required this.icon,
    required this.iconSize,
    required this.height,
    required this.avatar,
  });
}

/// First place is GREEN, not gold — a deliberate product choice (see Podium.tsx).
const _placeThemes = <int, _PlaceTheme>{
  1: _PlaceTheme(
    place: 1,
    ring: Color(0xFF34D399),
    glow: Color(0xD934D399),
    block: [Color(0xFF34D399), Color(0xFF047857)],
    onRing: Color(0xFF052E1A),
    pill: Color(0x5910B981),
    icon: Icons.emoji_events,
    iconSize: 24,
    height: 112,
    avatar: 78,
  ),
  2: _PlaceTheme(
    place: 2,
    ring: Color(0xFF7DD3FC),
    glow: Color(0xB37DD3FC),
    block: [Color(0xFF7DD3FC), Color(0xFF0369A1)],
    onRing: Color(0xFF052E45),
    pill: Color(0x4D38BDF8),
    icon: Icons.military_tech,
    iconSize: 17,
    height: 82,
    avatar: 64,
  ),
  3: _PlaceTheme(
    place: 3,
    ring: Color(0xFFFBBF24),
    glow: Color(0xB3FBBF24),
    block: [Color(0xFFFBBF24), Color(0xFFB45309)],
    onRing: Color(0xFF3D2103),
    pill: Color(0x4DF59E0B),
    icon: Icons.military_tech,
    iconSize: 17,
    height: 64,
    avatar: 64,
  ),
};

class LeaderboardPodium extends StatelessWidget {
  /// [2nd, 1st, 3rd] — null = open spot.
  final List<PodiumEntry?> entries;
  final String emptyLabel;

  const LeaderboardPodium({
    super.key,
    required this.entries,
    this.emptyLabel = 'Open spot',
  });

  @override
  Widget build(BuildContext context) {
    const order = [2, 1, 3];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        final place = order[i];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 3, right: i == 2 ? 0 : 3),
            child: _PodiumSlot(
              entry: entries[i],
              theme: _placeThemes[place]!,
              emptyLabel: emptyLabel,
            ),
          ),
        );
      }),
    );
  }
}

class _PodiumSlot extends StatefulWidget {
  final PodiumEntry? entry;
  final _PlaceTheme theme;
  final String emptyLabel;

  const _PodiumSlot(
      {required this.entry, required this.theme, required this.emptyLabel});

  @override
  State<_PodiumSlot> createState() => _PodiumSlotState();
}

class _PodiumSlotState extends State<_PodiumSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // Slow breathing glow on the winner only (1.5s each way, like Podium.tsx).
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.entry != null && widget.theme.place == 1) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final entry = widget.entry;
    final filled = entry != null;
    final isWinner = theme.place == 1;
    final size = theme.avatar;

    return Column(
      children: [
        SizedBox(
          height: 26,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: filled
                  ? Icon(theme.icon, size: theme.iconSize, color: theme.ring)
                  : SizedBox(height: theme.iconSize),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            final pulseValue =
                (filled && isWinner) ? 0.55 + 0.45 * _pulse.value : 1.0;
            final shadowAlpha =
                filled ? (isWinner ? pulseValue : 0.9) : 0.0;
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: filled
                      ? theme.ring
                      : const Color(0x38FFFFFF), // white 0.22
                  width: 3,
                ),
                color: filled
                    ? const Color(0x24FFFFFF) // white 0.14
                    : const Color(0x0FFFFFFF), // white 0.06
                boxShadow: shadowAlpha > 0
                    ? [
                        BoxShadow(
                          color: theme.glow.withValues(
                              alpha: theme.glow.a * shadowAlpha),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  filled && entry.photoURL != null && entry.photoURL!.isNotEmpty
                      ? ClipOval(
                          child: DiskCachedImage(
                            url: entry.photoURL!,
                            width: size - 12,
                            height: size - 12,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(
                              _initialsOf(entry.name),
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _text),
                            ),
                          ),
                        )
                      : Text(
                          filled ? _initialsOf(entry.name) : '—',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: filled ? _text : _textDim),
                        ),
                  Positioned(
                    bottom: -7,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? theme.ring
                            : const Color(0x40FFFFFF), // white 0.25
                      ),
                      alignment: Alignment.center,
                      child: Text('${theme.place}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  filled ? theme.onRing : _text)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Center(
            child: _PodiumName(
                name: filled ? entry.name : widget.emptyLabel,
                isPro: filled && entry.isPro,
                filled: filled),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 5),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: filled
                ? theme.pill
                : const Color(0x14FFFFFF), // white 0.08
          ),
          child: Text(
            filled ? entry.stat : '--',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: filled ? _text : _textDim),
          ),
        ),
        if (filled && entry.subStat != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(entry.subStat!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, color: _textDim)),
          )
        else
          const SizedBox(height: 3),
        // The block itself — gradient block, no bright cap on top.
        Container(
          margin: const EdgeInsets.only(top: 9),
          height: theme.height,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(14)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: filled
                  ? theme.block
                  : const [
                      Color(0x24FFFFFF), // white 0.14
                      Color(0x0DFFFFFF), // white 0.05
                    ],
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${theme.place}',
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: filled
                                ? const Color(0xEBFFFFFF) // white 0.92
                                : const Color(0x73FFFFFF))), // white 0.45
                    Text(
                      theme.place == 1
                          ? 'FIRST'
                          : theme.place == 2
                              ? 'SECOND'
                              : 'THIRD',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xA6FFFFFF)), // white 0.65
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _initialsOf(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : ''))
        .toUpperCase();
  }
}

/// Podium name with the verified tick beside it (Facebook style).
class _PodiumName extends StatelessWidget {
  final String name;
  final bool isPro;
  final bool filled;

  const _PodiumName(
      {required this.name, required this.isPro, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: filled ? _text : _textDim)),
        ),
        if (isPro)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.verified,
                size: 14, color: Color(0xFF3B82F6)),
          ),
      ],
    );
  }
}
