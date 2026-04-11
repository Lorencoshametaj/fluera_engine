// ============================================================================
// ✨ LASER POINTER PAINTER — Renders P2P laser strokes (P7-15)
//
// Paints temporary luminous strokes from the teaching peer:
//   - Bright yellow glow (P7-15)
//   - Linear fade-out over 2s lifetime
//   - Not saved to canvas
//   - Multiple segments can overlap (trails)
//
// ARCHITECTURE: CustomPainter, driven by ChangeNotifier.
// PERFORMANCE: 16ms budget — draws only visible segments.
// ============================================================================

import 'package:flutter/material.dart';
import '../../p2p/channels/laser_pointer_channel.dart';

/// ✨ Laser Pointer Painter (P7-15).
///
/// Renders temporary luminous strokes drawn by the teaching peer.
/// Strokes glow yellow and fade out linearly over 2 seconds.
///
/// Usage:
/// ```dart
/// CustomPaint(
///   painter: LaserPointerPainter(
///     receiver: engine.laserReceiver,
///     canvasTransform: controller.transformationMatrix,
///   ),
/// )
/// ```
class LaserPointerPainter extends CustomPainter {
  /// Laser pointer receiver with active segments.
  final LaserPointerReceiver receiver;

  /// Canvas offset (from InfiniteCanvasController).
  final Offset canvasOffset;

  /// Canvas scale (from InfiniteCanvasController).
  final double canvasScale;

  // ── Cached Paints ──────────────────────────────────────────────────

  /// Base laser color (bright yellow, P7-15).
  static const Color laserColor = Color(0xFFFFEB3B);

  /// Glow color (outer).
  static const Color glowColor = Color(0xFFFFC107);

  /// Laser stroke width.
  static const double strokeWidth = 3.0;

  /// Glow stroke width.
  static const double glowWidth = 8.0;

  late final Paint _laserPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  late final Paint _glowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = glowWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

  LaserPointerPainter({
    required this.receiver,
    required this.canvasOffset,
    required this.canvasScale,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!receiver.hasVisibleSegments) return;

    canvas.save();
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

    for (final segment in receiver.segments) {
      final opacity = receiver.getSegmentOpacity(segment);
      if (opacity <= 0.01) continue;

      final points = segment.points;
      if (points.length < 4) continue; // Need at least 2 points (x,y pairs)

      // Build path from interleaved points.
      final path = Path();
      path.moveTo(points[0], points[1]);
      for (int i = 2; i < points.length - 1; i += 2) {
        path.lineTo(points[i], points[i + 1]);
      }

      // Draw glow (outer, blurred).
      _glowPaint.color = glowColor.withValues(alpha: opacity * 0.4);
      canvas.drawPath(path, _glowPaint);

      // Draw core laser stroke.
      _laserPaint.color = laserColor.withValues(alpha: opacity);
      canvas.drawPath(path, _laserPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(LaserPointerPainter oldDelegate) {
    // Repaint every frame when segments are visible (for fade-out).
    return receiver.hasVisibleSegments;
  }
}
