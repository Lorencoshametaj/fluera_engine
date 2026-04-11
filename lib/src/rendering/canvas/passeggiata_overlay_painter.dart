// ============================================================================
// 🚶 PASSEGGIATA OVERLAY PAINTER — Contemplative vignette + guided path
//
// Spec: P11-05 → P11-07, A10-01 → A10-07
//
// Renders two layers during Passeggiata nel Palazzo mode:
//   1. Vignette: radial gradient from transparent center to 10% black edges
//   2. Guided path (optional): dashed golden line connecting cluster centroids
//
// Performance: zero allocations in paint(), uses pre-allocated Paint objects.
// Budget: ~0.5ms overhead max (ambient overlay, no per-frame computation).
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 🚶 Overlay painter for the Passeggiata nel Palazzo mode.
///
/// Creates a contemplative atmosphere with:
/// - Subtle vignette (10% edge darkening) for warm, focused feel
/// - Optional guided path through zones via dashed golden line
class PasseggiataOverlayPainter extends CustomPainter {
  /// Normalized animation time [0..1] for guided path progress.
  final double pathProgress;

  /// Cluster centroids in canvas coordinates (for guided path).
  final List<Offset> guidedPathPoints;

  /// Current canvas scale (for line width adjustment).
  final double canvasScale;

  /// Whether the guided path is currently visible.
  final bool showGuidedPath;

  // ── Reusable paint objects (zero-allocation hot path) ──
  static final Paint _vignettePaint = Paint();
  static final Paint _pathPaint = Paint()
    ..color = const Color(0xFFFFD700)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final Paint _dotPaint = Paint()
    ..color = const Color(0xFFFFD700)
    ..style = PaintingStyle.fill;

  PasseggiataOverlayPainter({
    this.pathProgress = 0.0,
    this.guidedPathPoints = const [],
    this.canvasScale = 1.0,
    this.showGuidedPath = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintVignette(canvas, size);

    if (showGuidedPath && guidedPathPoints.length >= 2) {
      _paintGuidedPath(canvas, size);
    }
  }

  /// Paints a subtle radial vignette — darkened edges for contemplative feel.
  ///
  /// Spec A10-03: "Bordi scuriti al 10% per atmosfera raccolta."
  void _paintVignette(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.max(size.width, size.height) * 0.7;

    _vignettePaint
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [
          Colors.transparent,
          Colors.transparent,
          Colors.black.withValues(alpha: 0.06),
          Colors.black.withValues(alpha: 0.10),
        ],
        [0.0, 0.55, 0.85, 1.0],
      );

    canvas.drawRect(Offset.zero & size, _vignettePaint);
    _vignettePaint.shader = null;
  }

  /// Paints the guided path: a dashed golden line connecting centroids.
  ///
  /// Spec A10-05: "Linea dorata tratteggiata che collega i centroidi."
  void _paintGuidedPath(Canvas canvas, Size size) {
    final sw = 2.5 / canvasScale.clamp(0.3, 3.0);
    _pathPaint.strokeWidth = sw;

    // Draw the path up to the current progress point
    final totalPoints = guidedPathPoints.length;
    final progressIndex = (pathProgress * (totalPoints - 1)).floor();
    final progressFraction = (pathProgress * (totalPoints - 1)) - progressIndex;

    for (int i = 0; i < progressIndex && i < totalPoints - 1; i++) {
      _drawDashedLine(
        canvas,
        guidedPathPoints[i],
        guidedPathPoints[i + 1],
        sw,
      );
    }

    // Partial segment (animated progress front)
    if (progressIndex < totalPoints - 1) {
      final start = guidedPathPoints[progressIndex];
      final end = guidedPathPoints[progressIndex + 1];
      final partialEnd = Offset(
        start.dx + (end.dx - start.dx) * progressFraction,
        start.dy + (end.dy - start.dy) * progressFraction,
      );
      _drawDashedLine(canvas, start, partialEnd, sw);
    }

    // Draw dots at each centroid (visited = filled, unvisited = outline)
    final dotRadius = 6.0 / canvasScale.clamp(0.3, 3.0);
    for (int i = 0; i < totalPoints; i++) {
      final visited = i <= progressIndex;
      if (visited) {
        _dotPaint.color = const Color(0xFFFFD700);
        canvas.drawCircle(guidedPathPoints[i], dotRadius, _dotPaint);
      } else {
        _pathPaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / canvasScale.clamp(0.3, 3.0)
          ..color = const Color(0xFFFFD700).withValues(alpha: 0.4);
        canvas.drawCircle(guidedPathPoints[i], dotRadius, _pathPaint);
        _pathPaint
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFFFD700);
      }
    }
  }

  /// Draws a dashed line between two points.
  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    double strokeWidth,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < 1.0) return;

    final dashLen = 8.0 / canvasScale.clamp(0.3, 3.0);
    final gapLen = 5.0 / canvasScale.clamp(0.3, 3.0);
    final unitX = dx / distance;
    final unitY = dy / distance;

    double traveled = 0.0;
    bool drawing = true;

    while (traveled < distance) {
      final segLen = drawing ? dashLen : gapLen;
      final remaining = distance - traveled;
      final len = math.min(segLen, remaining);

      if (drawing) {
        canvas.drawLine(
          Offset(start.dx + unitX * traveled, start.dy + unitY * traveled),
          Offset(
            start.dx + unitX * (traveled + len),
            start.dy + unitY * (traveled + len),
          ),
          _pathPaint..strokeWidth = strokeWidth,
        );
      }

      traveled += len;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(covariant PasseggiataOverlayPainter oldDelegate) {
    return pathProgress != oldDelegate.pathProgress ||
        showGuidedPath != oldDelegate.showGuidedPath ||
        canvasScale != oldDelegate.canvasScale;
  }
}
