import 'package:flutter/material.dart';
import '../../canvas/infinite_canvas_controller.dart';
import '../../drawing/models/pro_drawing_point.dart';

/// Draws the Apple Pencil native predicted-touch tail above the live stroke
/// overlay for visual anti-lag. Points come from iOS's `predictedTouches(for:)`
/// and are never committed to the stroke — they just cover the 15-20 ms gap
/// between the physical pencil tip and the rendered ink.
///
/// Mounted on top of the Metal/Vulkan direct overlay (which can't accept
/// predicted samples without tessellator jitter, see
/// [VulkanStrokeOverlayService.updateAndRender] comments). Because CAMetalLayer
/// doesn't participate in UIKit hit-testing, a Flutter [CustomPaint]
/// positioned above it renders correctly on iOS.
class PredictedTailPainter extends CustomPainter {
  PredictedTailPainter({
    required Listenable repaint,
    required this.getRealStroke,
    required this.getPredictedTail,
    required this.color,
    required this.width,
    this.controller,
  }) : super(repaint: repaint);

  final List<ProDrawingPoint> Function() getRealStroke;
  final List<ProDrawingPoint> Function() getPredictedTail;
  final Color color;
  final double width;
  final InfiniteCanvasController? controller;

  static const double _baseAlpha = 0.55;
  static const double _tipAlpha = 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    final tail = getPredictedTail();
    if (tail.isEmpty) return;
    final real = getRealStroke();
    if (real.isEmpty) return;

    canvas.save();
    if (controller != null) {
      canvas.translate(controller!.offset.dx, controller!.offset.dy);
      if (controller!.rotation != 0.0) {
        canvas.rotate(controller!.rotation);
      }
      canvas.scale(controller!.scale);
    }

    // Build canvas-space points: last real sample + predicted samples.
    // Real is already in canvas-space (DrawingInputHandler ingestion ran
    // screenToCanvas upstream). Predicted is transformed in the canvas
    // screen's onPredictedPointsUpdated callback before hitting the notifier.
    final pts = <Offset>[real.last.position, for (final p in tail) p.position];

    if (pts.length < 2) {
      canvas.restore();
      return;
    }

    // Fade alpha from last real → tip of predicted. Segment-by-segment so
    // the first segment is nearly opaque (continuity with the real stroke)
    // and the last is barely visible (just enough to pull the eye forward).
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width;

    final segments = pts.length - 1;
    for (int i = 0; i < segments; i++) {
      final t = segments == 1 ? 0.5 : i / (segments - 1);
      final a = _baseAlpha + (_tipAlpha - _baseAlpha) * t;
      paint.color = color.withValues(alpha: a.clamp(0.0, 1.0));
      canvas.drawLine(pts[i], pts[i + 1], paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PredictedTailPainter old) {
    return old.color != color ||
        old.width != width ||
        old.controller != controller;
  }
}
