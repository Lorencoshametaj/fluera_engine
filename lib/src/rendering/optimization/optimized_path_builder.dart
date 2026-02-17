import 'package:flutter/material.dart';

/// 🚀 Costruttore di Path Optimizeti
///
/// RESPONSIBILITIES:
/// - ✅ Builds a SINGLE Path instead of N separate segments
/// - ✅ Catmull-Rom spline per smoothness professionale
/// - ✅ Riduce draw calls da 100+ a 1
///
/// PERFORMANCE:
/// - Path unificato = 1 drawPath() invece di N drawPath()
/// - Nessuna allocazione ripetuta di Path temporanei
/// - GPU rendering ottimizzato
class OptimizedPathBuilder {
  /// 🚀 Builds un Path ottimizzato con Catmull-Rom spline
  ///
  /// [points] Lista di punti (Offset o oggetti con .offset)
  /// [closeLoop] Se true, chiude il path collegando last point al primo
  static Path buildSmoothPath(List<dynamic> points, {bool closeLoop = false}) {
    final path = Path();

    if (points.isEmpty) return path;

    final firstOffset = _getOffset(points.first);
    path.moveTo(firstOffset.dx, firstOffset.dy);

    if (points.length == 1) {
      // Punto singolo: non serve path
      return path;
    } else if (points.length == 2) {
      // Due punti: linea diretta
      final secondOffset = _getOffset(points[1]);
      path.lineTo(secondOffset.dx, secondOffset.dy);
    } else if (points.length == 3) {
      // Tre punti: quadratic bezier per smoothness
      final p1 = _getOffset(points[1]);
      final p2 = _getOffset(points[2]);
      path.quadraticBezierTo(p1.dx, p1.dy, p2.dx, p2.dy);
    } else {
      // 🚀 Catmull-Rom spline per curve ultra-smooth
      // ALL segments in a SINGLE path!
      for (int i = 0; i < points.length - 1; i++) {
        final p0 = i > 0 ? _getOffset(points[i - 1]) : _getOffset(points[i]);
        final p1 = _getOffset(points[i]);
        final p2 = _getOffset(points[i + 1]);
        final p3 =
            i < points.length - 2
                ? _getOffset(points[i + 2])
                : _getOffset(points[i + 1]);

        // Calculate punti di controllo Catmull-Rom
        final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
        final cp1y = p1.dy + (p2.dy - p0.dy) / 6;
        final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
        final cp2y = p2.dy - (p3.dy - p1.dy) / 6;

        path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      }
    }

    if (closeLoop && points.length > 2) {
      path.close();
    }

    return path;
  }

  /// 🚀 Builds un Path con cerchi unificati (per giunzioni)
  ///
  /// [points] Lista di punti dove disegnare cerchi
  /// [radii] Lista di raggi corrispondenti (stesso length di points)
  static Path buildCirclesPath(List<Offset> points, List<double> radii) {
    final path = Path();

    for (int i = 0; i < points.length; i++) {
      final radius = i < radii.length ? radii[i] : radii.last;
      path.addOval(Rect.fromCircle(center: points[i], radius: radius));
    }

    return path;
  }

  /// 🚀 Builds Path lineare semplice (per evidenziatore)
  ///
  /// [points] Lista di punti
  static Path buildLinearPath(List<dynamic> points) {
    final path = Path();

    if (points.isEmpty) return path;

    final firstOffset = _getOffset(points.first);
    path.moveTo(firstOffset.dx, firstOffset.dy);

    for (int i = 1; i < points.length; i++) {
      final offset = _getOffset(points[i]);
      path.lineTo(offset.dx, offset.dy);
    }

    return path;
  }

  /// Estrae Offset da un punto (gestisce sia Offset che oggetti con .offset)
  static Offset _getOffset(dynamic point) {
    if (point is Offset) return point;
    return point.offset;
  }

  /// Calculatates la lunghezza approssimativa del path
  static double estimatePathLength(List<dynamic> points) {
    if (points.length < 2) return 0;

    double length = 0;
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = _getOffset(points[i]);
      final p2 = _getOffset(points[i + 1]);
      length += (p2 - p1).distance;
    }
    return length;
  }
}
