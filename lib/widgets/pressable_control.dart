import 'package:flutter/material.dart';

class PressableControl extends StatefulWidget {
  const PressableControl({
    super.key,
    required this.enabled,
    required this.borderRadius,
    required this.child,
    required this.onPressed,
    required this.onReleased,
  });

  final bool enabled;
  final BorderRadius borderRadius;
  final Widget child;
  final VoidCallback onPressed;
  final VoidCallback onReleased;

  @override
  State<PressableControl> createState() => _PressableControlState();
}

class _PressableControlState extends State<PressableControl> {
  bool _pressed = false;

  void _press() {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
    widget.onPressed();
  }

  void _release() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.onReleased();
  }

  @override
  void didUpdateWidget(covariant PressableControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) _release();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? .96 : 1,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        borderRadius: widget.borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: widget.borderRadius,
          splashColor: const Color(0xFF69F0AE).withValues(alpha: .18),
          highlightColor: Colors.white.withValues(alpha: .06),
          onTapDown: widget.enabled ? (_) => _press() : null,
          onTapUp: widget.enabled ? (_) => _release() : null,
          onTapCancel: widget.enabled ? _release : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            foregroundDecoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              gradient: _pressed
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: .12),
                        const Color(0xFF69F0AE).withValues(alpha: .08),
                      ],
                    )
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
