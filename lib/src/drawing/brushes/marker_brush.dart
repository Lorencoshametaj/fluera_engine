import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../rendering/optimization/optimization.dart';

/// 🖊️ Marker Brush — Flat-tip marker with saturated alpha accumulation
///
/// CHARACTERISTICS:
/// - 🖊️ Flat chisel tip (rectangular cross-section)
/// - 🖊️ Alpha accumulation: overlapping strokes darken progressively
/// - 🖊️ Consistent width (minimal pressure variation)
/// - 🖊️ Slight edge darkening for ink pooling effect
/// - 🖊️ BlendMode.darken for realistic marker layering
class MarkerBrush {
  static const String name = 'Marker';
  static const IconData icon = Icons.format_paint_rounded;
  static const double baseWidthMultiplier = 2.5;
  static const double baseOpacity = 0.7;
  static const StrokeCap strokeCap = StrokeCap.round;
  static const StrokeJoin strokeJoin = StrokeJoin.round;

  /// Draw marker stroke with default settings
  static void drawStroke(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth,
  ) {
    drawStrokeWithSettings(
      canvas,
      points,
      color,
      baseWidth,
      opacity: baseOpacity,
      flatness: 0.4,
    );
  }

  /// 🎛️ Draw with customizable settings
  ///
  /// [opacity] Base ink opacity (0.0–1.0)
  /// [flatness] How flat the tip is (0.0 = round, 1.0 = very flat chisel)
  static void drawStrokeWithSettings(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    required double opacity,
    double flatness = 0.4,
  }) {
    if (points.isEmpty) return;

    final markerWidth = baseWidth * baseWidthMultiplier;

    if (points.length == 1) {
      final offset = StrokeOptimizer.getOffset(points.first);
      // Single dot: draw a flat rectangle for chisel tip effect
      final rect = Rect.fromCenter(
        center: offset,
        width: markerWidth,
        height: markerWidth * (1.0 - flatness * 0.6),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withValues(alpha: opacity * color.a)
          ..style = PaintingStyle.fill,
      );
      return;
    }

    // 🎯 Use smooth Catmull-Rom path instead of linear segments.
    final path = OptimizedPathBuilder.buildSmoothPath(points);
    final bounds = path.getBounds().inflate(markerWidth);

    // 🎯 FIX: Draw at FULL opacity inside a saveLayer with the desired alpha.
    // When a thick semi-transparent stroke curves tightly, the stroke's
    // width causes self-overlap. Drawing with semi-transparent paint
    // directly would accumulate alpha in the overlap zone → visible bumps.
    // By drawing opaque inside a translucent layer, self-overlap is
    // invisible (the GPU composites the layer as a single unit).
    final layerAlpha = (opacity * color.a).clamp(0.0, 1.0);
    canvas.saveLayer(
      bounds,
      Paint()..color = Color.fromRGBO(0, 0, 0, layerAlpha),
    );

    final bodyPaint = PaintPool.getStrokePaint(
      color: color.withValues(alpha: 1.0), // Full opacity inside layer
      strokeWidth: markerWidth,
      strokeCap: strokeCap,
      strokeJoin: strokeJoin,
    );
    canvas.drawPath(path, bodyPaint);

    canvas.restore();
  }
}
