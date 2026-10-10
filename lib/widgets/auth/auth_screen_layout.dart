import 'package:flutter/material.dart';
import 'auth_header.dart';

/// Wraps AuthHeader + a scrollable body so the header stays FIXED while only
/// the body scrolls underneath it — mirrors AuthScreenLayout.tsx.
/// The body starts 22px under the header (OVERLAP) and slides behind it.
/// Always light (#F9FAFB), even in dark mode.
///
/// [illustrationAsset]: optional flat illustration shown in the empty space
/// between the header and the content card (e.g. the auth illustrations).
/// It scrolls with the body. Screens that toggle it themselves (login/signup
/// provider-selection state) pass nothing and render it inside their child.
class AuthScreenLayout extends StatefulWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final Widget child;
  final String? illustrationAsset;
  final double illustrationHeight;

  const AuthScreenLayout({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    required this.child,
    this.illustrationAsset,
    this.illustrationHeight = 190,
  });

  @override
  State<AuthScreenLayout> createState() => _AuthScreenLayoutState();
}

class _AuthScreenLayoutState extends State<AuthScreenLayout> {
  static const double _overlap = 22;
  final _headerKey = GlobalKey();
  double _headerHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    final box =
        _headerKey.currentContext?.findRenderObject() as RenderBox?;
    final h = box?.size.height ?? 0;
    if (h > 0 && h != _headerHeight && mounted) {
      setState(() => _headerHeight = h);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = _headerHeight > 0 ? _headerHeight - _overlap : 0.0;
    return Container(
      color: const Color(0xFFF9FAFB),
      child: Stack(
        children: [
          // Scrollable body — slides behind the fixed header.
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(top: topPad, bottom: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - topPad - 24,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Animated in/out (e.g. hidden on success states) —
                          // same AnimatedSwitcher pattern as the login
                          // email-form toggle (2026-10-10).
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: SizeTransition(
                                sizeFactor: animation,
                                axisAlignment: -1,
                                child: child,
                              ),
                            ),
                            child: widget.illustrationAsset != null
                                ? Padding(
                                    key: ValueKey(widget.illustrationAsset),
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 20),
                                    child: Image.asset(
                                      widget.illustrationAsset!,
                                      height: widget.illustrationHeight,
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey('no-illustration')),
                          ),
                          widget.child,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Fixed header — always on top, never scrolls.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: KeyedSubtree(
              key: _headerKey,
              child: AuthHeader(
                title: widget.title,
                subtitle: widget.subtitle,
                onBack: widget.onBack,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
