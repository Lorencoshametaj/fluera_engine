import 'package:flutter/material.dart';
import '../../rendering/optimization/optimization.dart';

/// 🚀 Characteristics and rendering of the OPTIMIZED Ballpoint brush
///
/// CARATTERISTICHE:
/// - Larghezza costante (non varia with the pressione)
/// - Colore uniforme e opaco
/// - Ideale per scrittura precisa
/// - Effetto inchiostro a sfera
class BallpointBrush {
  /// Nome visualizzato dell'utensile
  static const String name = 'Biro';

  /// Icona rappresentativa
  static const IconData icon = Icons.edit;

  /// Moltiplicatore larghezza di default
  static const double defaultWidthMultiplier = 1.0;

  /// Opacity of the stroke (0.0-1.0)
  static const double opacity = 1.0;

  /// StrokeCap da utilizzare
  static const StrokeCap strokeCap = StrokeCap.round;

  /// StrokeJoin da utilizzare
  static const StrokeJoin strokeJoin = StrokeJoin.round;

  /// Use pressure to vary the width?
  static const bool usePressureForWidth = false;

  /// Use pressure to vary opacity?
  static const bool usePressureForOpacity = false;

  /// Ha effetto blur?
  static const bool hasBlur = false;

  /// 🚀 Draw un tratto con pennello biro OTTIMIZZATO
  ///
  /// OTTIMIZZAZIONI:
  /// - ✅ Usa OptimizedPathBuilder per path unificato
  /// - ✅ Use PaintPool for Paint reuse
  /// - ✅ UN SOLO drawPath() invece di N
  ///
  /// [canvas] Canvas su cui disegnare
  /// [points] Lista di punti of the stroke (con offset e pressure)
  /// [color] Colore of the stroke
  /// [baseWidth] Larghezza base of the stroke
  static void drawStroke(
    Canvas canvas,
    List<dynamic>
    points, // Può essere List<Offset> o List con .offset e .pressure
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

  /// 🎛️ Draw con parametri personalizzati dal dialog
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
      // Punto singolo: disegna cerchio
      final offset = StrokeOptimizer.getOffset(points.first);
      final paint = PaintPool.getFillPaint(color: color);
      canvas.drawCircle(offset, baseWidth * 0.5, paint);
      return;
    }

    // Ballpoint = constant width. Use midpoint of pressure range
    // instead of iterating all points to compute average.
    final adjustedWidth =
        baseWidth * (minPressure + 0.5 * (maxPressure - minPressure));

    // 🚀 USA PAINT POOL invece di creare nuovo Paint
    final paint = PaintPool.getStrokePaint(
      color: color,
      strokeWidth: adjustedWidth,
      strokeCap: strokeCap,
      strokeJoin: strokeJoin,
    );

    // 🚀 USA OPTIMIZED PATH BUILDER per path unificato
    final path = OptimizedPathBuilder.buildSmoothPath(points);

    // 🚀 UN SOLO drawPath()!
    canvas.drawPath(path, paint);
  }

  /// Calculatates la larghezza for a punto specifico (biro = costante)
  static double calculateWidth(double baseWidth, double pressure) {
    return baseWidth; // Larghezza costante
  }

  /// Calculatates l'opacity for a punto specifico (biro = opaca)
  static double calculateOpacity(double pressure) {
    return opacity; // Opacity costante
  }
}
