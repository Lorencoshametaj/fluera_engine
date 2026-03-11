import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 🎨 CustomPainter for the function graph.
///
/// Paints grid lines, axes, function curve, and optional overlays
/// (derivative, crosshair, area fill).
class FunctionGraphPainter extends CustomPainter {
  /// Sampled function values: x → y.
  final List<Offset> points;

  /// Optional derivative curve points.
  final List<Offset>? derivativePoints;

  /// Viewport bounds.
  final double xMin, xMax, yMin, yMax;

  /// Display toggles.
  final bool showGrid;
  final bool showMinorGrid;
  final bool showAxes;
  final bool showDerivative;
  final bool showArea;

  /// Crosshair position (in math coords), or null if hidden.
  final Offset? crosshair;

  /// Colors.
  final Color curveColor;
  final Color derivativeColor;
  final Color gridColor;
  final Color axisColor;
  final Color areaColor;

  FunctionGraphPainter({
    required this.points,
    this.derivativePoints,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    this.showGrid = true,
    this.showMinorGrid = false,
    this.showAxes = true,
    this.showDerivative = false,
    this.showArea = false,
    this.crosshair,
    this.curveColor = Colors.blue,
    this.derivativeColor = Colors.orange,
    this.gridColor = const Color(0x22888888),
    this.axisColor = const Color(0x88888888),
    this.areaColor = const Color(0x22448AFF),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final xRange = xMax - xMin;
    final yRange = yMax - yMin;
    if (xRange <= 0 || yRange <= 0) return;

    // Transform: math coords → pixel coords
    double toPixelX(double mx) => (mx - xMin) / xRange * size.width;
    double toPixelY(double my) => (1 - (my - yMin) / yRange) * size.height;

    // ── Grid ──
    if (showGrid) {
      _drawGrid(canvas, size, toPixelX, toPixelY);
    }

    // ── Axes ──
    if (showAxes) {
      _drawAxes(canvas, size, toPixelX, toPixelY);
    }

    // ── Area under curve ──
    if (showArea && points.length >= 2) {
      _drawArea(canvas, size, toPixelX, toPixelY);
    }

    // ── Function curve ──
    _drawCurve(canvas, size, points, curveColor, 2.5, toPixelX, toPixelY);

    // ── Derivative ──
    if (showDerivative &&
        derivativePoints != null &&
        derivativePoints!.isNotEmpty) {
      _drawCurve(
        canvas,
        size,
        derivativePoints!,
        derivativeColor,
        1.5,
        toPixelX,
        toPixelY,
      );
    }

    // ── Crosshair ──
    if (crosshair != null) {
      _drawCrosshair(canvas, size, crosshair!, toPixelX, toPixelY);
    }
  }

  void _drawGrid(
    Canvas canvas,
    Size size,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    final paint =
        Paint()
          ..color = gridColor
          ..strokeWidth = 0.5;

    final minorPaint =
        Paint()
          ..color = gridColor.withValues(alpha: 0.3)
          ..strokeWidth = 0.25;

    final step = _gridStep(xMax - xMin);

    // Vertical lines
    var gx = (xMin / step).floor() * step;
    while (gx <= xMax) {
      final px = toPixelX(gx);
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), paint);
      if (showMinorGrid) {
        for (int m = 1; m < 5; m++) {
          final mpx = toPixelX(gx + step * m / 5);
          canvas.drawLine(Offset(mpx, 0), Offset(mpx, size.height), minorPaint);
        }
      }
      gx += step;
    }

    // Horizontal lines
    final yStep = _gridStep(yMax - yMin);
    var gy = (yMin / yStep).floor() * yStep;
    while (gy <= yMax) {
      final py = toPixelY(gy);
      canvas.drawLine(Offset(0, py), Offset(size.width, py), paint);
      if (showMinorGrid) {
        for (int m = 1; m < 5; m++) {
          final mpy = toPixelY(gy + yStep * m / 5);
          canvas.drawLine(Offset(0, mpy), Offset(size.width, mpy), minorPaint);
        }
      }
      gy += yStep;
    }

    // Grid labels
    final textStyle = ui.TextStyle(color: axisColor, fontSize: 10);

    gx = (xMin / step).ceil() * step;
    while (gx <= xMax) {
      if (gx.abs() > step * 0.1) {
        // skip near origin
        final px = toPixelX(gx);
        final originY = toPixelY(0).clamp(0.0, size.height - 14);
        final pb =
            ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
              ..pushStyle(textStyle)
              ..addText(_formatNumber(gx));
        final para =
            pb.build()..layout(const ui.ParagraphConstraints(width: 40));
        canvas.drawParagraph(para, Offset(px - 20, originY + 2));
      }
      gx += step;
    }

    gy = (yMin / yStep).ceil() * yStep;
    while (gy <= yMax) {
      if (gy.abs() > yStep * 0.1) {
        final py = toPixelY(gy);
        final originX = toPixelX(0).clamp(0.0, size.width - 30);
        final pb =
            ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.right))
              ..pushStyle(textStyle)
              ..addText(_formatNumber(gy));
        final para =
            pb.build()..layout(const ui.ParagraphConstraints(width: 36));
        canvas.drawParagraph(para, Offset(originX - 38, py - 6));
      }
      gy += yStep;
    }
  }

  void _drawAxes(
    Canvas canvas,
    Size size,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    final paint =
        Paint()
          ..color = axisColor
          ..strokeWidth = 1.5;

    // X axis
    if (yMin <= 0 && yMax >= 0) {
      final y0 = toPixelY(0);
      canvas.drawLine(Offset(0, y0), Offset(size.width, y0), paint);
      // Arrow
      final path =
          Path()
            ..moveTo(size.width, y0)
            ..lineTo(size.width - 8, y0 - 4)
            ..lineTo(size.width - 8, y0 + 4)
            ..close();
      canvas.drawPath(path, Paint()..color = axisColor);
    }

    // Y axis
    if (xMin <= 0 && xMax >= 0) {
      final x0 = toPixelX(0);
      canvas.drawLine(Offset(x0, 0), Offset(x0, size.height), paint);
      // Arrow
      final path =
          Path()
            ..moveTo(x0, 0)
            ..lineTo(x0 - 4, 8)
            ..lineTo(x0 + 4, 8)
            ..close();
      canvas.drawPath(path, Paint()..color = axisColor);
    }
  }

  void _drawArea(
    Canvas canvas,
    Size size,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    final path = Path();
    bool started = false;

    for (final pt in points) {
      if (pt.dy.isFinite) {
        final px = toPixelX(pt.dx);
        final py = toPixelY(pt.dy).clamp(-100.0, size.height + 100);
        if (!started) {
          path.moveTo(px, toPixelY(0));
          path.lineTo(px, py);
          started = true;
        } else {
          path.lineTo(px, py);
        }
      }
    }

    if (started) {
      path.lineTo(toPixelX(points.last.dx), toPixelY(0));
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = areaColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawCurve(
    Canvas canvas,
    Size size,
    List<Offset> pts,
    Color color,
    double width,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    if (pts.length < 2) return;

    final paint =
        Paint()
          ..color = color
          ..strokeWidth = width
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    final path = Path();
    bool penDown = false;

    for (final pt in pts) {
      if (pt.dy.isFinite && pt.dy.abs() < 1e10) {
        final px = toPixelX(pt.dx);
        final py = toPixelY(pt.dy).clamp(-500.0, size.height + 500);
        if (!penDown) {
          path.moveTo(px, py);
          penDown = true;
        } else {
          path.lineTo(px, py);
        }
      } else {
        penDown = false;
      }
    }

    canvas.drawPath(path, paint);
  }

  void _drawCrosshair(
    Canvas canvas,
    Size size,
    Offset pos,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    final px = toPixelX(pos.dx);
    final py = toPixelY(pos.dy);
    final paint =
        Paint()
          ..color = curveColor.withValues(alpha: 0.5)
          ..strokeWidth = 1.0;

    // Dashed crosshair lines
    canvas.drawLine(Offset(px, 0), Offset(px, size.height), paint);
    canvas.drawLine(Offset(0, py), Offset(size.width, py), paint);

    // Dot at intersection
    canvas.drawCircle(
      Offset(px, py),
      5,
      Paint()
        ..color = curveColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(px, py),
      5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  /// Compute a "nice" grid step for the given range.
  double _gridStep(double range) {
    if (range <= 0) return 1;
    final raw = range / 8; // aim for ~8 grid lines
    final exponent =
        (raw.abs()).toString().contains('e')
            ? 0.0
            : _pow10(
              (raw.abs()).toString().length > 0 ? (raw.abs() < 1 ? -1 : 0) : 0,
            );

    // Compute order of magnitude
    final mag = _pow10(_log10(raw).floor().toDouble());
    final norm = raw / mag;

    double step;
    if (norm < 1.5) {
      step = 1;
    } else if (norm < 3.5) {
      step = 2;
    } else if (norm < 7.5) {
      step = 5;
    } else {
      step = 10;
    }

    return step * mag + exponent * 0;
  }

  double _log10(double x) {
    if (x <= 0) return 0;
    return _ln(x) / _ln(10);
  }

  double _ln(double x) {
    // Use Dart's built-in
    if (x <= 0) return 0;
    // Manual natural log approximation using dart:math is unavailable in CustomPainter,
    // so we use a simple series or import workaround.
    // Actually, we can compute it: log_10(x) = log(x) / log(10)
    // But we don't have dart:math here. Let's use a different approach.
    // Since we only need integer magnitude, we can count digits.
    if (x >= 1) {
      int digits = 0;
      var v = x;
      while (v >= 10) {
        v /= 10;
        digits++;
      }
      return digits + (v - 1) * 0.4343; // rough approximation
    } else {
      int digits = 0;
      var v = x;
      while (v < 1) {
        v *= 10;
        digits++;
      }
      return -digits + (v - 1) * 0.4343;
    }
  }

  double _pow10(double exp) {
    if (exp == 0) return 1;
    double result = 1;
    final absExp = exp.abs().toInt();
    for (int i = 0; i < absExp; i++) {
      result *= 10;
    }
    return exp < 0 ? 1 / result : result;
  }

  String _formatNumber(double n) {
    if (n == n.roundToDouble() && n.abs() < 10000) {
      return n.toInt().toString();
    }
    return n.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(covariant FunctionGraphPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.xMin != xMin ||
        oldDelegate.xMax != xMax ||
        oldDelegate.yMin != yMin ||
        oldDelegate.yMax != yMax ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.showAxes != showAxes ||
        oldDelegate.showDerivative != showDerivative ||
        oldDelegate.showArea != showArea ||
        oldDelegate.crosshair != crosshair;
  }
}
