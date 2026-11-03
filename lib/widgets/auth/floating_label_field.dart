import 'package:flutter/material.dart';

/// Animated floating-label text input — mirrors FloatingLabelField.tsx.
/// The label rests as the placeholder, then floats up and shrinks to 0.82 on
/// focus/value. Border washes from #E5E7EB to #1D4ED8 on focus (1.5px, radius
/// 12, minHeight 62). Always light on auth screens (they never follow
/// dark mode); the Change Password page opts into the [dark] variant so
/// its fields follow the app theme (NOTE-23).
class FloatingLabelField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final String? errorText;
  final bool secureToggle;
  final bool obscureText;
  final IconData? leftIcon;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool autoFocus;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final FocusNode? focusNode;
  final FocusNode? nextFocus;

  /// Dark-surface variant (NOTE-23): the Change Password page follows
  /// the app theme, so its fields render on the dark palette in dark
  /// mode. Auth screens never pass this — they stay always-light.
  final bool dark;

  const FloatingLabelField({
    super.key,
    required this.label,
    this.controller,
    this.errorText,
    this.secureToggle = false,
    this.obscureText = false,
    this.leftIcon,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.autoFocus = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.nextFocus,
    this.dark = false,
  });

  @override
  State<FloatingLabelField> createState() => _FloatingLabelFieldState();
}

class _FloatingLabelFieldState extends State<FloatingLabelField>
    with SingleTickerProviderStateMixin {
  static const _primary = Color(0xFF1D4ED8);
  static const _border = Color(0xFFE5E7EB);
  static const _textPrimary = Color(0xFF1F2937);
  static const _textSecondary = Color(0xFF6B7280);
  static const _error = Color(0xFFDC2626);

  // Dark variant tokens — aligned with ExpoPalette.dark (surfaceAlt /
  // textPrimary / textSecondary / a lifted border).
  static const _borderDark = Color(0xFF334155);
  static const _textPrimaryDark = Color(0xFFF1F5F9);
  static const _textSecondaryDark = Color(0xFF94A3B8);

  Color get _borderBase => widget.dark ? _borderDark : _border;
  Color get _textMain => widget.dark ? _textPrimaryDark : _textPrimary;
  Color get _textSub => widget.dark ? _textSecondaryDark : _textSecondary;

  late final AnimationController _anim;
  late final FocusNode _focusNode;
  late final TextEditingController _controller;
  bool _focused = false;
  bool _hidden = false;

  bool get _hasError => widget.errorText != null;
  bool get _hasValue => _controller.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _hidden = widget.obscureText;
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _focusNode = widget.focusNode ?? FocusNode();
    _controller = widget.controller ?? TextEditingController();
    if (_hasValue) _anim.value = 1.0;
    _focusNode.addListener(_onFocusChange);
    _controller.addListener(_onTextChange);
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
    _drive();
  }

  void _onTextChange() {
    if (!mounted) return;
    setState(() {});
    _drive();
  }

  void _drive() {
    if (_focused || _hasValue) {
      _anim.animateTo(1.0, curve: Curves.easeOutCubic);
    } else {
      _anim.animateTo(0.0, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.removeListener(_onTextChange);
    if (widget.focusNode == null) _focusNode.dispose();
    if (widget.controller == null) _controller.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final t = _anim.value;
        final borderColor =
            _hasError ? _error : Color.lerp(_borderBase, _primary, t)!;
        final labelColor =
            _hasError ? _error : Color.lerp(_textSub, _primary, t)!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 62),
              decoration: BoxDecoration(
                color: widget.dark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.leftIcon != null) ...[
                    Icon(
                      widget.leftIcon,
                      size: 20,
                      color: _focused ? _primary : _textSub,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 62,
                      child: Stack(
                        children: [
                          // Floating label — anchored left-center so it never
                          // drifts right as it scales.
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Transform.translate(
                                offset: Offset(0, -17.0 * t),
                                child: Transform.scale(
                                  scale: 1.0 - 0.18 * t,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    widget.label,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: labelColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: widget.autoFocus,
                            obscureText: widget.secureToggle
                                ? _hidden
                                : widget.obscureText,
                            keyboardType: widget.keyboardType,
                            textInputAction: widget.textInputAction,
                            onChanged: widget.onChanged,
                            onSubmitted: (_) {
                              if (widget.nextFocus != null) {
                                widget.nextFocus!.requestFocus();
                              } else {
                                widget.onSubmitted?.call();
                              }
                            },
                            style: TextStyle(
                              fontSize: 16,
                              color: _textMain,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.only(top: 20, bottom: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.secureToggle)
                    GestureDetector(
                      onTap: () => setState(() => _hidden = !_hidden),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: _textSub,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  widget.errorText!,
                  style: const TextStyle(fontSize: 12, color: _error),
                ),
              ),
          ],
        );
      },
    );
  }
}
