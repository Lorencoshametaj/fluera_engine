import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// =============================================================================
// ↩️ ACTION FLASH OVERLAY — Undo/Redo HUD Feedback
//
// Displays a brief, holographic flash icon (↩️ or ↪️) at the center of the
// screen when Undo/Redo gesture fires. Fades in fast, scales up, then
// dissolves — like a HUD confirmation in Iron Man's helmet.
// =============================================================================

class ActionFlashOverlay extends StatefulWidget {
  const ActionFlashOverlay({super.key});

  @override
  State<ActionFlashOverlay> createState() => ActionFlashOverlayState();
}

class ActionFlashOverlayState extends State<ActionFlashOverlay>
    with SingleTickerProviderStateMixin {
  bool _isVisible = false;
  bool _isUndo = true;
  double _t = 0.0;

  late final Ticker _ticker;
  Duration _startTime = Duration.zero;
  bool _animating = false;

  static const _duration = 600; // ms

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Trigger an undo flash
  void showUndo() => _show(true, null);

  /// Trigger a redo flash
  void showRedo() => _show(false, null);

  /// Trigger a text flash (e.g. "3 selected")
  void showText(String text) => _show(true, text);

  String? _text;

  void _show(bool isUndo, String? text) {
    _isUndo = isUndo;
    _text = text;
    _isVisible = true;
    _animating = true;
    _startTime = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
    setState(() {});
  }

  void _onTick(Duration elapsed) {
    if (!_animating) return;
    if (_startTime == Duration.zero) { _startTime = elapsed; return; }
    final ms = (elapsed - _startTime).inMilliseconds;
    _t = (ms / _duration).clamp(0.0, 1.0);

    if (_t >= 1.0) {
      _animating = false;
      _isVisible = false;
      _ticker.stop();
      _startTime = Duration.zero;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    // Phase 1: 0..0.3 = fade in + scale up
    // Phase 2: 0.3..1.0 = fade out + float up
    final opacity = _t < 0.3
        ? (_t / 0.3).clamp(0.0, 1.0)
        : (1.0 - (_t - 0.3) / 0.7).clamp(0.0, 1.0);
    final scale = _t < 0.3
        ? 0.5 + 0.5 * Curves.easeOutBack.transform((_t / 0.3).clamp(0.0, 1.0))
        : 1.0 + 0.15 * ((_t - 0.3) / 0.7);
    final yOffset = _t < 0.3 ? 0.0 : -30.0 * ((_t - 0.3) / 0.7);

    return Center(
      child: IgnorePointer(
        child: Transform.translate(
          offset: Offset(0, yOffset),
          child: Transform.scale(
            scale: scale,
            child: _text != null
                ? _buildTextFlash(opacity)
                : CustomPaint(
                    size: const Size(80, 80),
                    painter: _FlashPainter(
                      isUndo: _isUndo,
                      opacity: opacity,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextFlash(double opacity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Color.fromARGB((opacity * 180).toInt(), 10, 14, 26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF82C8FF).withValues(alpha: opacity * 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF82C8FF).withValues(alpha: opacity * 0.2),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Text(
        _text!,
        style: TextStyle(
          color: Colors.white.withValues(alpha: opacity),
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _FlashPainter extends CustomPainter {
  final bool isUndo;
  final double opacity;

  _FlashPainter({required this.isUndo, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final p = Paint();
    final alpha = opacity;

    // Outer glow
    p..color = const Color(0xFF82C8FF).withValues(alpha: alpha * 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 35, p);

    // Glass bg
    p..color = Color.fromARGB((alpha * 80).toInt(), 10, 14, 26)
      ..maskFilter = null;
    canvas.drawCircle(center, 28, p);

    // Rim
    p..color = const Color(0xFF82C8FF).withValues(alpha: alpha * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 28, p);

    // Arrow icon
    _paintArrow(canvas, center, p, alpha);
  }

  void _paintArrow(Canvas canvas, Offset center, Paint p, double alpha) {
    final path = Path();
    final dir = isUndo ? -1.0 : 1.0;

    // Curved arrow
    final arrowCenter = Offset(center.dx + dir * 2, center.dy - 2);
    final r = 12.0;
    final startAngle = isUndo ? -math.pi * 0.8 : -math.pi * 0.2;
    final sweepAngle = isUndo ? math.pi * 1.3 : -math.pi * 1.3;

    path.addArc(
      Rect.fromCircle(center: arrowCenter, radius: r),
      startAngle,
      sweepAngle,
    );

    p..color = Colors.white.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, p);

    // Arrowhead
    final endAngle = startAngle + sweepAngle;
    final tip = Offset(
      arrowCenter.dx + r * math.cos(endAngle),
      arrowCenter.dy + r * math.sin(endAngle),
    );
    final headSize = 6.0;
    final headAngle1 = endAngle + (isUndo ? -0.5 : 0.5) + math.pi * 0.7;
    final headAngle2 = endAngle + (isUndo ? -0.5 : 0.5) + math.pi * 1.3;

    final head = Path();
    head.moveTo(
      tip.dx + headSize * math.cos(headAngle1),
      tip.dy + headSize * math.sin(headAngle1),
    );
    head.lineTo(tip.dx, tip.dy);
    head.lineTo(
      tip.dx + headSize * math.cos(headAngle2),
      tip.dy + headSize * math.sin(headAngle2),
    );

    p..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(head, p);
  }

  @override
  bool shouldRepaint(_FlashPainter old) =>
      old.opacity != opacity || old.isUndo != isUndo;
}
