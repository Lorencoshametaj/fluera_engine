import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Pulsante compatto per azioni
class CompactActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  final double rotation;

  const CompactActionButton({
    super.key,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.rotation = 0,
  });

  @override
  State<CompactActionButton> createState() => _CompactActionButtonState();
}

class _CompactActionButtonState extends State<CompactActionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: 38,
            height: 38,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.12),
              border: Border.all(
                color: widget.color.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Transform.rotate(
              angle: widget.rotation * math.pi / 180,
              child: Icon(widget.icon, color: widget.color, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}
