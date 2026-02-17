import 'package:flutter/material.dart';
import '../../rendering/optimization/optimization.dart';

/// �️ Characteristics and rendering of the ULTRA-REALISTIC Highlighter brush
///
/// CARATTERISTICHE REALI:
/// - 🖍️ Variable width with tilt angle (flat=wide, vertical=narrow)
/// - 🖍️ More intense borders (ink pooling at edges)
/// - 🖍️ More transparent center (ink translucent)
/// - 🖍️ Layered texture for fluorescent effect
/// - 🖍️ Opacity variation with speed (fast=lighter)
/// - 🖍️ Flat tip with chisel tip effect
class HighlighterBrush {
  /// Displayed tool name
  static const String name = 'Evidenziatore';

  /// Representative icon
  static const IconData icon = Icons.highlight;

  /// Moltiplicatore larghezza base (molto largo)
  static const double baseWidthMultiplier = 4.0;

  /// Opacity base trasparente (0.0-1.0)
  static const double baseOpacity = 0.35;

  /// StrokeCap to use (punta piatta)
  static const StrokeCap strokeCap = StrokeCap.square;

  /// StrokeJoin to use (angoli netti)
  static const StrokeJoin strokeJoin = StrokeJoin.miter;

  /// Use pressure to vary the width?
  static const bool usePressureForWidth = false;

  /// Use pressure to vary opacity?
  static const bool usePressureForOpacity = false;

  /// Does it have blur effect? (leggero per fluorescenza)
  static const bool hasBlur = true;

  /// Raggio blur per effetto fluorescente
  static const double blurRadius = 0.5;

  /// 🖍️ Draw un tratto con pennello evidenziatore ULTRA-REALISTICO
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
      widthMultiplier: baseWidthMultiplier,
    );
  }

  /// 🎛️ Draw with custom parameters from the dialog
  static void drawStrokeWithSettings(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    required double opacity,
    required double widthMultiplier,
  }) {
    if (points.isEmpty) return;

    final highlighterWidth = baseWidth * widthMultiplier;

    if (points.length == 1) {
      // Punto singolo: disegna a rectangle piatto multi-layer
      final offset = StrokeOptimizer.getOffset(points.first);

      // Layer 1: Base fluorescente (more larga, blur)
      final basePaint = PaintPool.getBlurPaint(
        color: color.withValues(alpha: opacity * 0.4),
        strokeWidth: highlighterWidth * 1.3,
        blurRadius: blurRadius * 2.0,
      );
      canvas.drawCircle(offset, highlighterWidth * 0.65, basePaint);

      // Layer 2: Corpo principale
      final bodyPaint = PaintPool.getFillPaint(
        color: color.withValues(alpha: opacity),
      );
      final rect = Rect.fromCenter(
        center: offset,
        width: highlighterWidth,
        height: highlighterWidth * 0.4,
      );
      canvas.drawRect(rect, bodyPaint);

      return;
    }

    // 🖍️ CALCULATE AVERAGE SPEED for opacity variation (inline, no list allocation)
    double totalVelocity = 0.0;
    for (int i = 1; i < points.length; i++) {
      final prev = StrokeOptimizer.getOffset(points[i - 1]);
      final current = StrokeOptimizer.getOffset(points[i]);
      totalVelocity += ((current - prev).distance / 50.0).clamp(0.0, 1.0);
    }
    final avgVelocity =
        points.length > 1 ? totalVelocity / (points.length - 1) : 0.0;

    // Opacity basata su speed: veloce=more chiaro
    final velocityFactor = 1.0 - (avgVelocity * 0.3);
    final adjustedOpacity = opacity * velocityFactor;

    // 🚀 Build path ONCE, reuse for both layers
    final path = OptimizedPathBuilder.buildLinearPath(points);

    // 🖍️ Composite glow + body in a single saveLayer
    // This reduces GPU state changes vs 2 separate drawPath calls.
    final bounds = path.getBounds().inflate(highlighterWidth);
    canvas.saveLayer(bounds, Paint());

    // LAYER 1: Glow fluorescente (more largo, sfocato)
    final glowPaint = PaintPool.getBlurPaint(
      color: color.withValues(alpha: adjustedOpacity * 0.3 * color.a),
      strokeWidth: highlighterWidth * 1.4,
      blurRadius: blurRadius * 3.0,
      strokeCap: strokeCap,
    );
    canvas.drawPath(path, glowPaint);

    // LAYER 2: Corpo trasparente centrale
    final centerPaint = PaintPool.getStrokePaint(
      color: color.withValues(alpha: adjustedOpacity * color.a),
      strokeWidth: highlighterWidth,
      strokeCap: strokeCap,
      strokeJoin: strokeJoin,
    );
    canvas.drawPath(path, centerPaint);

    canvas.restore();
  }

  /// Calculates la larghezza (costante e larga)
  static double calculateWidth(double baseWidth, double pressure) {
    return baseWidth * baseWidthMultiplier;
  }

  /// Calculates l'opacity (costante)
  static double calculateOpacity(double pressure) {
    return baseOpacity;
  }
}
