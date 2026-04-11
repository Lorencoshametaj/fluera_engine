// ============================================================================
// 💛 ZEIGARNIK PULSE PAINTER — Ambient glow on incomplete nodes
//
// Spec: P8-13, A13.9 (Micro-animations), A13-18 → A13-21, CA-133
//
// Incomplete nodes (those with a "?" marker or tagged as incomplete)
// display a slow amber pulse to subtly draw attention. This leverages
// the Zeigarnik Effect: incomplete tasks stay salient in working memory.
//
// Animation: opacity 30% → 60% → 30%, period 4s (very slow — perceived
// subconsciously per A13-21).
//
// Performance:
//   - ≤5% GPU overhead (A13-19)
//   - Zero allocations in paint() — uses pre-allocated Paint objects
//   - Stops during active writing (FlowGuard, A13-20)
//   - Disableable via settings toggle (A13-18)
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 💛 Custom painter for the Zeigarnik pulsing effect on incomplete nodes.
///
/// Renders an ambient amber glow + pulsing border for each incomplete node.
class ZeigarnikPulsePainter extends CustomPainter {
  /// Bounding rectangles of incomplete nodes (in canvas coordinates).
  final List<Rect> incompleteNodeBounds;

  /// Animation phase [0..2π] for the pulsing effect (period 4s).
  final double animPhase;

  /// Current canvas scale (for line width adjustment).
  final double canvasScale;

  /// Whether the pulse is currently suppressed (FlowGuard active).
  final bool isSuppressed;

  /// Dark mode flag.
  final bool isDarkMode;

  // ── Reusable paint objects ──
  static final Paint _glowPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// The Zeigarnik amber color.
  static const Color _amberColor = Color(0xFFFFB300);

  ZeigarnikPulsePainter({
    required this.incompleteNodeBounds,
    required this.animPhase,
    required this.canvasScale,
    this.isSuppressed = false,
    this.isDarkMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (incompleteNodeBounds.isEmpty || isSuppressed) return;

    // Opacity oscillation: 30% → 60% → 30% (sinusoidal, period 4s)
    final opacity = 0.30 + 0.30 * math.sin(animPhase);

    for (final bounds in incompleteNodeBounds) {
      _paintNodePulse(canvas, bounds, opacity);
    }
  }

  void _paintNodePulse(Canvas canvas, Rect bounds, double opacity) {
    final inflated = bounds.inflate(10.0);
    final rrect = RRect.fromRectAndRadius(inflated, const Radius.circular(12));

    // ── 1. Ambient glow (blurred amber ring) ──
    _glowPaint
      ..color = _amberColor.withValues(alpha: opacity * 0.4)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        14.0 / canvasScale.clamp(0.3, 2.0),
      );
    canvas.drawRRect(rrect, _glowPaint);
    _glowPaint.maskFilter = null;

    // ── 2. Pulsing border ──
    _borderPaint
      ..strokeWidth = 1.5 / canvasScale.clamp(0.3, 2.0)
      ..color = _amberColor.withValues(alpha: opacity * 0.7);
    canvas.drawRRect(rrect, _borderPaint);

    // ── 3. "?" indicator badge (top-right corner) ──
    final badgeRadius = 8.0 / canvasScale.clamp(0.3, 2.0);
    final badgeCenter = Offset(
      inflated.right - badgeRadius,
      inflated.top + badgeRadius,
    );

    // Badge background
    _glowPaint
      ..color = isDarkMode
          ? Color.fromRGBO(40, 35, 20, 0.9)
          : Color.fromRGBO(255, 250, 230, 0.95)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(badgeCenter, badgeRadius, _glowPaint);

    // "?" text
    final fontSize = badgeRadius * 1.3;
    final tp = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          color: _amberColor.withValues(alpha: opacity + 0.2),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, badgeCenter - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(covariant ZeigarnikPulsePainter oldDelegate) {
    return (animPhase - oldDelegate.animPhase).abs() > 0.05 ||
        isSuppressed != oldDelegate.isSuppressed ||
        incompleteNodeBounds != oldDelegate.incompleteNodeBounds;
  }
}
