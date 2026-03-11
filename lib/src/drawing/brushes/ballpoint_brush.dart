import 'package:flutter/material.dart';
import '../../rendering/optimization/optimization.dart';

/// 🚀 Characteristics and rendering of the OPTIMIZED Ballpoint brush
///
/// FEATURES:
/// - Constant width (does not vary with pressure)
/// - Uniform and opaque color
/// - Ideal for precise writing
/// - Ballpoint ink effect
class BallpointBrush {
  /// Displayed tool name
  static const String name = 'Biro';

  /// Representative icon
  static const IconData icon = Icons.edit;

  /// Default width multiplier
  static const double defaultWidthMultiplier = 1.0;

  /// Opacity of the stroke (0.0-1.0)
  static const double opacity = 1.0;

  /// StrokeCap to use
  static const StrokeCap strokeCap = StrokeCap.round;

  /// StrokeJoin to use
  static const StrokeJoin strokeJoin = StrokeJoin.round;

  /// Use pressure to vary the width?
  static const bool usePressureForWidth = false;

  /// Use pressure to vary opacity?
  static const bool usePressureForOpacity = false;

  /// Does it have blur effect?
  static const bool hasBlur = false;

  /// 🚀 Draw a stroke with OPTIMIZED ballpoint brush
  static void drawStroke(
    Canvas canvas,
    List<dynamic>
    points, // Can be List<Offset> or List with .offset and .pressure
    Color color,
    double baseWidth,
  ) {
    drawStrokeWithSettings(
      canvas,
      points,
      color,
      baseWidth,
      minPressure: 0.7,
      maxPressure: 1.1,
    );
  }

  /// 🎛️ Draw with custom parameters from the dialog
  static void drawStrokeWithSettings(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    required double minPressure,
    required double maxPressure,
    bool isLive = false,
    Path? cachedPath,
  }) {
    if (points.isEmpty) return;

    if (points.length == 1) {
      final offset = StrokeOptimizer.getOffset(points.first);
      final paint = PaintPool.getFillPaint(color: color);
      canvas.drawCircle(offset, baseWidth * 0.5, paint);
      return;
    }

    // Ballpoint = constant width (midpoint of pressure range).
    final adjustedWidth =
        baseWidth * (minPressure + 0.5 * (maxPressure - minPressure));

    // ─── Subtle entry taper: first 3 segments ────────────────────
    const taperPoints = 3;
    const taperStartFrac = 0.60;

    if (points.length > taperPoints + 1) {
      // Draw 3 tapered segments at the start
      for (int i = 0; i < taperPoints; i++) {
        final p0 = StrokeOptimizer.getOffset(points[i]);
        final p1 = StrokeOptimizer.getOffset(points[i + 1]);
        final t = (i + 1) / taperPoints; // 0.33 → 0.66 → 1.0
        final ease = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
        final w =
            adjustedWidth * (taperStartFrac + (1.0 - taperStartFrac) * ease);

        canvas.drawLine(
          p0,
          p1,
          PaintPool.getStrokePaint(
            color: color,
            strokeWidth: w,
            strokeCap: strokeCap,
            strokeJoin: strokeJoin,
          ),
        );
      }

      // Draw rest as single smooth path (constant width)
      final mainPaint = PaintPool.getStrokePaint(
        color: color,
        strokeWidth: adjustedWidth,
        strokeCap: strokeCap,
        strokeJoin: strokeJoin,
      );
      // Build path from taperPoints onward for smooth Catmull-Rom
      final path = cachedPath ?? _buildSubPath(points, taperPoints);
      canvas.drawPath(path, mainPaint);
    } else {
      // Short stroke: single path, no taper
      final paint = PaintPool.getStrokePaint(
        color: color,
        strokeWidth: adjustedWidth,
        strokeCap: strokeCap,
        strokeJoin: strokeJoin,
      );
      final path =
          cachedPath ??
          (isLive
              ? OptimizedPathBuilder.buildSmoothPathIncremental(points)
              : OptimizedPathBuilder.buildSmoothPath(points));
      canvas.drawPath(path, paint);
    }
  }

  /// Build a Catmull-Rom sub-path starting from [startIndex].
  static Path _buildSubPath(List<dynamic> points, int startIndex) {
    final path = Path();
    if (startIndex >= points.length) return path;
    final first = StrokeOptimizer.getOffset(points[startIndex]);
    path.moveTo(first.dx, first.dy);
    if (startIndex >= points.length - 1) return path;

    for (int i = startIndex; i < points.length - 1; i++) {
      final p0 =
          i > 0
              ? StrokeOptimizer.getOffset(points[i - 1])
              : StrokeOptimizer.getOffset(points[i]);
      final p1 = StrokeOptimizer.getOffset(points[i]);
      final p2 = StrokeOptimizer.getOffset(points[i + 1]);
      final p3 =
          i < points.length - 2
              ? StrokeOptimizer.getOffset(points[i + 2])
              : StrokeOptimizer.getOffset(points[i + 1]);
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    return path;
  }

  /// Calculates the width for a specific point (ballpoint = constant)
  static double calculateWidth(double baseWidth, double pressure) {
    return baseWidth; // Constant width
  }

  /// Calculates the opacity for a specific point (ballpoint = opaque)
  static double calculateOpacity(double pressure) {
    return opacity; // Constant opacity
  }
}
