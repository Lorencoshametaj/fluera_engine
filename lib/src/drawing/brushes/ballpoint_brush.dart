import 'package:flutter/material.dart';
import '../../rendering/optimization/optimization.dart';

/// 🚀 Characteristics and rendering of the OPTIMIZED Ballpoint brush
///
/// FEATURES:
/// - Constant width (non varia with the pressione)
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
  ///
  /// OPTIMIZATIONS:
  /// - ✅ Use OptimizedPathBuilder for unified path
  /// - ✅ Use PaintPool for Paint reuse
  /// - ✅ A SINGLE drawPath() instead of N
  ///
  /// [canvas] Canvas to draw on
  /// [points] List of points of the stroke (with offset and pressure)
  /// [color] Color of the stroke
  /// [baseWidth] Base width of the stroke
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
  }) {
    if (points.isEmpty) return;

    if (points.length == 1) {
      // Single point: draw circle
      final offset = StrokeOptimizer.getOffset(points.first);
      final paint = PaintPool.getFillPaint(color: color);
      canvas.drawCircle(offset, baseWidth * 0.5, paint);
      return;
    }

    // Ballpoint = constant width. Use midpoint of pressure range
    // instead of iterating all points to compute average.
    final adjustedWidth =
        baseWidth * (minPressure + 0.5 * (maxPressure - minPressure));

    // 🚀 USE PAINT POOL instead of creating new Paint
    final paint = PaintPool.getStrokePaint(
      color: color,
      strokeWidth: adjustedWidth,
      strokeCap: strokeCap,
      strokeJoin: strokeJoin,
    );

    // 🚀 USE OPTIMIZED PATH BUILDER for unified path
    final path = OptimizedPathBuilder.buildSmoothPath(points);

    // 🚀 A SINGLE drawPath()!
    canvas.drawPath(path, paint);
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
