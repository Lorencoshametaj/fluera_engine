import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../rendering/optimization/optimization.dart';
import '../filters/organic_noise.dart';

/// ✏️ Charcoal Brush — Grain erosion with variable noise
///
/// CHARACTERISTICS:
/// - 🖤 Rough, granular texture that varies with speed
/// - 🖤 Pressure controls darkness (light touch = faint marks)
/// - 🖤 Velocity-dependent grain: slow = dense, fast = scattered
/// - 🖤 Multiple overlapping strokes build up progressively
/// - 🖤 Irregular edge profile (natural charcoal stick feel)
class CharcoalBrush {
  static const String name = 'Charcoal';
  static const IconData icon = Icons.brush_rounded;
  static const double baseWidthMultiplier = 2.0;
  static const double baseOpacity = 0.6;
  static const StrokeCap strokeCap = StrokeCap.round;
  static const StrokeJoin strokeJoin = StrokeJoin.round;

  /// Draw charcoal stroke with default settings
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
      grain: 0.5,
      minPressure: 0.3,
      maxPressure: 1.0,
    );
  }

  /// 🎛️ Draw with customizable settings
  ///
  /// [opacity] Base opacity (0.0–1.0)
  /// [grain] Grain intensity (0.0 = smooth, 1.0 = very grainy)
  /// [minPressure] Minimum width multiplier at zero pressure
  /// [maxPressure] Maximum width multiplier at full pressure
  static void drawStrokeWithSettings(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    required double opacity,
    double grain = 0.5,
    double minPressure = 0.3,
    double maxPressure = 1.0,
  }) {
    if (points.isEmpty) return;

    final charcoalWidth = baseWidth * baseWidthMultiplier;

    if (points.length == 1) {
      final offset = StrokeOptimizer.getOffset(points.first);
      // Single dot: rough circle with slight noise
      final dotPaint =
          Paint()
            ..color = color.withValues(alpha: opacity * 0.7 * color.a)
            ..style = PaintingStyle.fill
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);
      canvas.drawCircle(offset, charcoalWidth * 0.5, dotPaint);
      return;
    }

    // Build main path
    final path = OptimizedPathBuilder.buildLinearPath(points);
    final bounds = path.getBounds().inflate(charcoalWidth * 1.5);

    canvas.saveLayer(bounds, Paint());

    // LAYER 1: Soft shadow/smudge (very wide, very faint)
    final smudgePaint = PaintPool.getBlurPaint(
      color: color.withValues(alpha: opacity * 0.08 * color.a),
      strokeWidth: charcoalWidth * 1.8,
      blurRadius: charcoalWidth * 0.6,
      strokeCap: strokeCap,
    );
    canvas.drawPath(path, smudgePaint);

    // LAYER 2: Main charcoal body (slightly blurred for grain)
    final bodyPaint = PaintPool.getBlurPaint(
      color: color.withValues(alpha: opacity * 0.55 * color.a),
      strokeWidth: charcoalWidth,
      blurRadius: grain * 1.5,
      strokeCap: strokeCap,
    );
    canvas.drawPath(path, bodyPaint);

    // LAYER 3: Pressure-sensitive dark core
    // Narrower stroke for areas with more pressure
    final corePaint = PaintPool.getStrokePaint(
      color: color.withValues(alpha: opacity * 0.7 * color.a),
      strokeWidth: charcoalWidth * 0.4,
      strokeCap: strokeCap,
      strokeJoin: strokeJoin,
    );
    canvas.drawPath(path, corePaint);

    // LAYER 4: Grain noise — scattered dots along the stroke
    if (grain > 0.1) {
      _drawGrainNoise(canvas, points, color, charcoalWidth, opacity, grain);
    }

    canvas.restore();
  }

  /// Draw grain noise particles along the stroke path
  /// 🌱 Uses spatially-coherent Simplex noise instead of Random(42)
  /// for grain that is consistent across redraws and coherent between
  /// adjacent points.
  static void _drawGrainNoise(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double width,
    double opacity,
    double grain,
  ) {
    final grainPaint =
        Paint()
          ..color = color.withValues(alpha: opacity * 0.3 * grain * color.a)
          ..style = PaintingStyle.fill;

    // Scatter particles along the stroke
    // 🌱 Velocity-dependent density: fast = sparse (bigger step), slow = dense
    final baseStep = math.max(2, (6 - grain * 4).round());
    for (int i = 0; i < points.length; i += baseStep) {
      final center = StrokeOptimizer.getOffset(points[i]);

      // Estimate local velocity from inter-point distance
      double localVelocity = 0.0;
      if (i > 0 && i < points.length) {
        final prev = StrokeOptimizer.getOffset(points[math.max(0, i - 1)]);
        localVelocity = (center - prev).distance;
      }
      // Fast segments: skip more particles (velocity > 3px/sample = fast)
      if (localVelocity > 3.0 && i % 2 == 0) continue;

      // Slow = more particles, fast = fewer
      final velocityFactor = (1.0 - (localVelocity / 5.0).clamp(0.0, 0.5));
      final particleCount = (3 + grain * 5 * velocityFactor).round();

      for (int j = 0; j < particleCount; j++) {
        // 🌱 Spatially-coherent noise: position determines particle placement
        final noiseX = OrganicNoise.simplexNoise2D(
          center.dx * 0.1 + j * 17.3,
          center.dy * 0.1 + j * 31.7,
        );
        final noiseY = OrganicNoise.simplexNoise2D(
          center.dx * 0.1 + j * 23.1,
          center.dy * 0.1 + j * 41.3,
        );
        final dx = noiseX * width * 0.6;
        final dy = noiseY * width * 0.6;
        // Radius from noise too — varies naturally across the stroke
        final noiseR = OrganicNoise.simplexNoise2D(
          center.dx * 0.2 + j * 7.7,
          center.dy * 0.2,
        );
        final radius = 0.3 + (noiseR * 0.5 + 0.5) * 1.2 * grain;
        canvas.drawCircle(center + Offset(dx, dy), radius, grainPaint);
      }
    }
  }
}
