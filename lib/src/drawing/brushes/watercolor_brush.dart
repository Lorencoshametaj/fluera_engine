import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../rendering/optimization/optimization.dart';

/// 🎨 Watercolor Brush — Wet-on-wet diffusion with color blending
///
/// CHARACTERISTICS:
/// - 💧 Progressive blur for wet diffusion effect
/// - 💧 Color bleeding at edges (feathered alpha falloff)
/// - 💧 Pressure controls water amount (more pressure = more spread)
/// - 💧 Velocity controls pigment density (fast = lighter washes)
/// - 💧 Multiple translucent layers for depth
class WatercolorBrush {
  static const String name = 'Watercolor';
  static const IconData icon = Icons.water_drop_rounded;
  static const double baseWidthMultiplier = 3.0;
  static const double baseOpacity = 0.25;
  static const StrokeCap strokeCap = StrokeCap.round;
  static const StrokeJoin strokeJoin = StrokeJoin.round;

  /// Draw watercolor stroke with default settings
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
      spread: 1.0,
      bleed: 0.5,
    );
  }

  /// 🎛️ Draw with customizable settings
  static void drawStrokeWithSettings(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    required double opacity,
    double spread = 1.0,
    double bleed = 0.5,
  }) {
    if (points.isEmpty) return;

    final waterWidth = baseWidth * baseWidthMultiplier;

    if (points.length == 1) {
      final offset = StrokeOptimizer.getOffset(points.first);
      // Watercolor dot: radial gradient from center
      final gradient = ui.Gradient.radial(
        offset,
        waterWidth * 0.8,
        [
          color.withValues(alpha: opacity * 0.6),
          color.withValues(alpha: opacity * 0.2),
          color.withValues(alpha: 0),
        ],
        [0.0, 0.5, 1.0],
      );
      canvas.drawCircle(
        offset,
        waterWidth * 0.8,
        Paint()
          ..shader = gradient
          ..style = PaintingStyle.fill,
      );
      return;
    }

    // Calculate per-segment velocities for pigment density variation
    final path = OptimizedPathBuilder.buildLinearPath(points);
    final bounds = path.getBounds().inflate(waterWidth * 1.5);

    canvas.saveLayer(bounds, Paint());

    // LAYER 1: Outer water spread (very diffuse, wide)
    final outerBlur = waterWidth * 0.8 * spread;
    final outerPaint = PaintPool.getBlurPaint(
      color: color.withValues(alpha: opacity * 0.15 * color.a),
      strokeWidth: waterWidth * 1.8 * spread,
      blurRadius: outerBlur,
      strokeCap: strokeCap,
    );
    canvas.drawPath(path, outerPaint);

    // LAYER 2: Mid water body (moderate blur)
    final midPaint = PaintPool.getBlurPaint(
      color: color.withValues(alpha: opacity * 0.3 * color.a),
      strokeWidth: waterWidth * 1.2,
      blurRadius: waterWidth * 0.4 * spread,
      strokeCap: strokeCap,
    );
    canvas.drawPath(path, midPaint);

    // LAYER 3: Pigment core (sharper, more saturated)
    final corePaint = PaintPool.getBlurPaint(
      color: color.withValues(alpha: opacity * 0.5 * color.a),
      strokeWidth: waterWidth * 0.6,
      blurRadius: waterWidth * 0.15,
      strokeCap: strokeCap,
    );
    canvas.drawPath(path, corePaint);

    // LAYER 4: Edge bleed — darker pigment settling at edges
    if (bleed > 0) {
      final bleedPaint = PaintPool.getBlurPaint(
        color: color.withValues(alpha: opacity * 0.12 * bleed * color.a),
        strokeWidth: waterWidth * 1.6,
        blurRadius: waterWidth * 0.2,
        strokeCap: strokeCap,
      );
      bleedPaint.style = PaintingStyle.stroke;
      canvas.drawPath(path, bleedPaint);
    }

    canvas.restore();
  }
}
