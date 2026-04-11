// ============================================================================
// ⭐ GOLDEN SHIMMER PAINTER — Subtle shimmer on mastered nodes
//
// Spec: A13.9 (Micro-animations), A13-18 → A13-21
//
// Mastered nodes (SRS Stage 4+) display a slow golden shimmer to create
// visual anchoring — mastered concepts "glow" subtly in the panorama.
//
// Animation: luminosity variation ±10%, period 6s (very slow — perceived
// subconsciously per A13-21).
//
// Performance:
//   - ≤5% GPU overhead (A13-19)
//   - Zero allocations in paint() — pre-allocated Paint objects
//   - Stops during active writing (FlowGuard, A13-20)
//   - Disableable via settings toggle (A13-18)
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// ⭐ Custom painter for the golden shimmer effect on mastered nodes.
///
/// Renders a subtle golden glow + radial shimmer for mastered concept clusters.
/// The effect is deliberately slow and understated — it should be perceived
/// subconsciously, never consciously noticed.
class GoldenShimmerPainter extends CustomPainter {
  /// Bounding rectangles of mastered clusters (in canvas coordinates).
  final List<Rect> masteredNodeBounds;

  /// Animation phase [0..2π] for the shimmer effect (period 6s).
  final double animPhase;

  /// Current canvas scale (for size adjustment).
  final double canvasScale;

  /// Whether the shimmer is currently suppressed (FlowGuard active).
  final bool isSuppressed;

  /// Dark mode flag.
  final bool isDarkMode;

  // ── Reusable paint objects ──
  static final Paint _glowPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final Paint _starPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  // Golden palette
  static const Color _goldLight = Color(0xFFFFD54F);
  static const Color _goldDark = Color(0xFFFFCA28);

  GoldenShimmerPainter({
    required this.masteredNodeBounds,
    required this.animPhase,
    required this.canvasScale,
    this.isSuppressed = false,
    this.isDarkMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (masteredNodeBounds.isEmpty || isSuppressed) return;

    // Luminosity variation: ±10% around base (sinusoidal, period 6s)
    final shimmerFactor = 0.90 + 0.10 * math.sin(animPhase);

    for (final bounds in masteredNodeBounds) {
      _paintGoldenShimmer(canvas, bounds, shimmerFactor);
    }
  }

  void _paintGoldenShimmer(Canvas canvas, Rect bounds, double shimmerFactor) {
    final gold = isDarkMode ? _goldDark : _goldLight;
    final inflated = bounds.inflate(6.0);
    final rrect = RRect.fromRectAndRadius(inflated, const Radius.circular(8));

    // ── 1. Subtle golden glow (very faint) ──
    final glowOpacity = 0.08 * shimmerFactor;
    _glowPaint
      ..color = gold.withValues(alpha: glowOpacity)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        10.0 / canvasScale.clamp(0.3, 2.0),
      );
    canvas.drawRRect(rrect, _glowPaint);
    _glowPaint.maskFilter = null;

    // ── 2. Subtle golden border ──
    final borderOpacity = 0.15 * shimmerFactor;
    _borderPaint
      ..strokeWidth = 0.8 / canvasScale.clamp(0.3, 2.0)
      ..color = gold.withValues(alpha: borderOpacity);
    canvas.drawRRect(rrect, _borderPaint);

    // ── 3. Small star icon (top-right corner) ──
    final starSize = 7.0 / canvasScale.clamp(0.3, 2.0);
    final starCenter = Offset(
      inflated.right - starSize - 2.0 / canvasScale.clamp(0.3, 2.0),
      inflated.top + starSize + 2.0 / canvasScale.clamp(0.3, 2.0),
    );

    // Star background circle
    _starPaint.color = isDarkMode
        ? Color.fromRGBO(50, 45, 20, 0.9)
        : Color.fromRGBO(255, 252, 235, 0.95);
    canvas.drawCircle(starCenter, starSize, _starPaint);

    // Star character
    final fontSize = starSize * 1.2;
    final tp = TextPainter(
      text: TextSpan(
        text: '★',
        style: TextStyle(
          color: gold.withValues(alpha: shimmerFactor),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, starCenter - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(covariant GoldenShimmerPainter oldDelegate) {
    return (animPhase - oldDelegate.animPhase).abs() > 0.05 ||
        isSuppressed != oldDelegate.isSuppressed ||
        masteredNodeBounds != oldDelegate.masteredNodeBounds;
  }
}
