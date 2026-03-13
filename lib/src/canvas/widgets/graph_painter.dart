import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 🎨 CustomPainter for the function graph.
///
/// Paints grid lines, axes, function curve, and optional overlays
/// (derivative, crosshair, area fill, root markers, gradient curve,
/// critical points, asymptotes, integral display).
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

  /// Area fill mode: 0 = to x-axis (integral), 1 = to viewport bottom (fill below).
  final int areaMode;

  /// Crosshair position (in math coords), or null if hidden.
  final Offset? crosshair;

  /// Colors.
  final Color curveColor;
  final Color derivativeColor;
  final Color gridColor;
  final Color axisColor;
  final Color areaColor;

  /// G6: Whether to use gradient for the main curve.
  final bool useGradient;

  /// G5: Whether to show root markers.
  final bool showRoots;

  /// A1: Whether to show critical points (min/max).
  final bool showCriticalPoints;

  /// A2: Whether to show asymptote lines.
  final bool showAsymptotes;

  /// A3: Integral value to display (null = don't show).
  final double? integralValue;

  /// A4: Curve animation progress (0.0 → 1.0).
  final double curveProgress;

  /// A7: Snap crosshair info (label to show near dot).
  final String? crosshairSnapLabel;

  /// B1: Tangent slope at crosshair point (null = don't draw).
  final double? tangentSlope;

  /// B2: Inflection points (where f''(x) = 0).
  final List<Offset>? inflectionPoints;

  /// B3: Whether to color by monotonicity (green ↑, red ↓).
  final bool showMonotonicity;

  /// B5: Whether we're in dark mode.
  final bool isDark;

  /// B6: Whether to show the legend.
  final bool showLegend;

  /// C1: Crosshair opacity (0.0-1.0) for fade animation.
  final double crosshairOpacity;

  /// E1: Extra function curves (index 1, 2, ...). Primary is in [points].
  final List<List<Offset>> extraPoints;

  /// E1: Colors for extra curves.
  final List<Color> extraColors;

  /// E1: Labels for functions in legend.
  final List<String> functionLabels;

  /// E2: Y-values for extra functions at crosshair x.
  final List<double> extraCrosshairYs;

  /// E3: Intersection points between curves.
  final List<Offset> intersectionPoints;

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
    this.areaMode = 0,
    this.crosshair,
    this.curveColor = Colors.blue,
    this.derivativeColor = Colors.orange,
    this.gridColor = const Color(0x22888888),
    this.axisColor = const Color(0x88888888),
    this.areaColor = const Color(0x22448AFF),
    this.useGradient = true,
    this.showRoots = true,
    this.showCriticalPoints = false,
    this.showAsymptotes = false,
    this.integralValue,
    this.curveProgress = 1.0,
    this.crosshairSnapLabel,
    this.tangentSlope,
    this.inflectionPoints,
    this.showMonotonicity = false,
    this.isDark = false,
    this.showLegend = false,
    this.crosshairOpacity = 1.0,
    this.extraPoints = const [],
    this.extraColors = const [],
    this.functionLabels = const [],
    this.extraCrosshairYs = const [],
    this.intersectionPoints = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final xRange = xMax - xMin;
    final yRange = yMax - yMin;
    if (xRange <= 0 || yRange <= 0) return;

    double toPixelX(double mx) => (mx - xMin) / xRange * size.width;
    double toPixelY(double my) => (1 - (my - yMin) / yRange) * size.height;

    // ── C3: Dot pattern background ──
    _drawDotPattern(canvas, size);

    // ── Grid ──
    if (showGrid) {
      _drawGrid(canvas, size, toPixelX, toPixelY);
    }

    // ── Axes with tick marks + labels ──
    if (showAxes) {
      _drawAxes(canvas, size, toPixelX, toPixelY);
    }

    // ── A2: Asymptotes ──
    if (showAsymptotes) {
      _drawAsymptotes(canvas, size, toPixelX, toPixelY);
    }

    // A4: Get animated subset of curve points
    final visiblePoints = _getAnimatedPoints();

    // ── Area under curve (uses animated points) ──
    if (showArea && visiblePoints.length >= 2) {
      _drawArea(canvas, size, visiblePoints, toPixelX, toPixelY);
    }

    // ── Function curve (G2+G6: smooth + gradient, B3: monotonicity) ──
    if (showMonotonicity && derivativePoints != null && derivativePoints!.isNotEmpty) {
      _drawMonotonicityCurve(canvas, size, visiblePoints, toPixelX, toPixelY);
    } else if (useGradient) {
      _drawGradientCurve(canvas, size, visiblePoints, toPixelX, toPixelY);
    } else {
      _drawSmoothCurve(canvas, size, visiblePoints, curveColor, 2.5, toPixelX, toPixelY);
    }

    // ── E1: Extra function curves ──
    for (int i = 0; i < extraPoints.length; i++) {
      final pts = _getAnimatedPointsFrom(extraPoints[i]);
      final color = i < extraColors.length ? extraColors[i] : Colors.grey;
      _drawSmoothCurve(canvas, size, pts, color, 2.0, toPixelX, toPixelY);
    }

    // ── Derivative ──
    if (showDerivative && derivativePoints != null && derivativePoints!.isNotEmpty) {
      final visibleDeriv = _getAnimatedPointsFrom(derivativePoints!);
      _drawSmoothCurve(canvas, size, visibleDeriv, derivativeColor, 1.5, toPixelX, toPixelY);
    }

    // ── G5: Root markers ──
    if (showRoots) {
      _drawRootMarkers(canvas, size, toPixelX, toPixelY);
    }

    // ── A1: Critical points ──
    if (showCriticalPoints && derivativePoints != null && derivativePoints!.isNotEmpty) {
      _drawCriticalPoints(canvas, size, toPixelX, toPixelY);
    }

    // ── A3: Integral badge ──
    if (integralValue != null && showArea) {
      _drawIntegralBadge(canvas, size, integralValue!);
    }

    // ── B2: Inflection points ──
    if (inflectionPoints != null && inflectionPoints!.isNotEmpty) {
      _drawInflectionPoints(canvas, size, toPixelX, toPixelY);
    }

    // ── E3: Intersection markers ──
    if (intersectionPoints.isNotEmpty) {
      _drawIntersections(canvas, size, toPixelX, toPixelY);
    }

    // ── Crosshair ──
    if (crosshair != null) {
      _drawCrosshair(canvas, size, crosshair!, toPixelX, toPixelY);
    }

    // ── B1: Tangent line at crosshair ──
    if (crosshair != null && tangentSlope != null && tangentSlope!.isFinite) {
      _drawTangentLine(canvas, size, crosshair!, tangentSlope!, toPixelX, toPixelY);
    }

    // ── B6: Legend ──
    if (showLegend) {
      _drawLegend(canvas, size);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // A4: Animation support — returns points up to curveProgress
  // ─────────────────────────────────────────────────────────────────────────

  List<Offset> _getAnimatedPoints() => _getAnimatedPointsFrom(points);

  List<Offset> _getAnimatedPointsFrom(List<Offset> pts) {
    if (curveProgress >= 1.0 || pts.isEmpty) return pts;
    final count = (pts.length * curveProgress.clamp(0.0, 1.0)).round();
    return pts.sublist(0, count.clamp(1, pts.length));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Grid
  // ─────────────────────────────────────────────────────────────────────────

  void _drawGrid(
    Canvas canvas,
    Size size,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    final minorPaint = Paint()
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
        final px = toPixelX(gx);
        final originY = toPixelY(0).clamp(0.0, size.height - 14);
        final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
          ..pushStyle(textStyle)
          ..addText(_formatNumber(gx));
        final para = pb.build()..layout(const ui.ParagraphConstraints(width: 40));
        canvas.drawParagraph(para, Offset(px - 20, originY + 2));
      }
      gx += step;
    }

    gy = (yMin / yStep).ceil() * yStep;
    while (gy <= yMax) {
      if (gy.abs() > yStep * 0.1) {
        final py = toPixelY(gy);
        final originX = toPixelX(0).clamp(0.0, size.width - 30);
        final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.right))
          ..pushStyle(textStyle)
          ..addText(_formatNumber(gy));
        final para = pb.build()..layout(const ui.ParagraphConstraints(width: 36));
        canvas.drawParagraph(para, Offset(originX - 38, py - 6));
      }
      gy += yStep;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // G4+A6: Axes with tick marks, origin label, and axis labels
  // ─────────────────────────────────────────────────────────────────────────

  void _drawAxes(
    Canvas canvas,
    Size size,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    final paint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.5;

    final step = _gridStep(xMax - xMin);
    final yStep = _gridStep(yMax - yMin);

    // X axis
    if (yMin <= 0 && yMax >= 0) {
      final y0 = toPixelY(0);
      canvas.drawLine(Offset(0, y0), Offset(size.width, y0), paint);

      // Arrow
      final path = Path()
        ..moveTo(size.width, y0)
        ..lineTo(size.width - 8, y0 - 4)
        ..lineTo(size.width - 8, y0 + 4)
        ..close();
      canvas.drawPath(path, Paint()..color = axisColor);

      // A6: "x" label at arrow tip
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
        ..pushStyle(ui.TextStyle(
          color: axisColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
        ))
        ..addText('x');
      final para = pb.build()..layout(const ui.ParagraphConstraints(width: 14));
      canvas.drawParagraph(para, Offset(size.width - 14, y0 + 6));

      // Tick marks on X axis
      final tickPaint = Paint()
        ..color = axisColor
        ..strokeWidth = 1.0;
      var tx = (xMin / step).ceil() * step;
      while (tx <= xMax) {
        if (tx.abs() > step * 0.1) {
          final px = toPixelX(tx);
          canvas.drawLine(Offset(px, y0 - 3), Offset(px, y0 + 3), tickPaint);
        }
        tx += step;
      }
    }

    // Y axis
    if (xMin <= 0 && xMax >= 0) {
      final x0 = toPixelX(0);
      canvas.drawLine(Offset(x0, 0), Offset(x0, size.height), paint);

      // Arrow
      final path = Path()
        ..moveTo(x0, 0)
        ..lineTo(x0 - 4, 8)
        ..lineTo(x0 + 4, 8)
        ..close();
      canvas.drawPath(path, Paint()..color = axisColor);

      // A6: "y" label at arrow tip
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
        ..pushStyle(ui.TextStyle(
          color: axisColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
        ))
        ..addText('y');
      final para = pb.build()..layout(const ui.ParagraphConstraints(width: 14));
      canvas.drawParagraph(para, Offset(x0 + 6, 2));

      // Tick marks on Y axis
      final tickPaint = Paint()
        ..color = axisColor
        ..strokeWidth = 1.0;
      var ty = (yMin / yStep).ceil() * yStep;
      while (ty <= yMax) {
        if (ty.abs() > yStep * 0.1) {
          final py = toPixelY(ty);
          canvas.drawLine(Offset(x0 - 3, py), Offset(x0 + 3, py), tickPaint);
        }
        ty += yStep;
      }
    }

    // Origin "O" label
    if (xMin <= 0 && xMax >= 0 && yMin <= 0 && yMax >= 0) {
      final x0 = toPixelX(0);
      final y0 = toPixelY(0);
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
        ..pushStyle(ui.TextStyle(
          color: axisColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ))
        ..addText('O');
      final para = pb.build()..layout(const ui.ParagraphConstraints(width: 14));
      canvas.drawParagraph(para, Offset(x0 - 14, y0 + 4));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // A2: Asymptote detection and rendering
  // ─────────────────────────────────────────────────────────────────────────

  void _drawAsymptotes(
    Canvas canvas,
    Size size,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.4)
      ..strokeWidth = 1.0;

    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];

      // Detect discontinuity: finite → not-finite, or sudden huge jump
      final isDiscontinuity =
          (a.dy.isFinite && !b.dy.isFinite) ||
          (!a.dy.isFinite && b.dy.isFinite) ||
          (a.dy.isFinite && b.dy.isFinite && (b.dy - a.dy).abs() > (yMax - yMin) * 5);

      if (isDiscontinuity) {
        // Draw at midpoint between the two x positions
        final asymX = (a.dx + b.dx) / 2;
        final px = toPixelX(asymX);
        _drawDashedLine(canvas, Offset(px, 0), Offset(px, size.height), paint, 5, 4);

        // Label
        final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
          ..pushStyle(ui.TextStyle(
            color: Colors.red.withValues(alpha: 0.6),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ))
          ..addText('x=${_formatNumber(asymX)}');
        final para = pb.build()..layout(const ui.ParagraphConstraints(width: 50));
        canvas.drawParagraph(para, Offset(px - 25, 4));
      }
    }
  }

  void _drawArea(
    Canvas canvas,
    Size size,
    List<Offset> pts,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    final path = Path();
    bool started = false;

    // Bottom line: y=0 for integral mode, viewport bottom for fill-below mode
    final baseY = areaMode == 1 ? size.height : toPixelY(0);

    for (final pt in pts) {
      if (pt.dy.isFinite) {
        final px = toPixelX(pt.dx);
        final py = toPixelY(pt.dy).clamp(-100.0, size.height + 100);
        if (!started) {
          path.moveTo(px, baseY);
          path.lineTo(px, py);
          started = true;
        } else {
          path.lineTo(px, py);
        }
      }
    }

    if (started) {
      path.lineTo(toPixelX(pts.last.dx), baseY);
      path.close();

      // Gradient fill for area
      final gradientTop = areaMode == 1
          ? toPixelY(yMax)  // top of viewport
          : toPixelY((yMax + yMin) / 2);
      final areaGradient = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, gradientTop),
          Offset(0, baseY),
          [curveColor.withValues(alpha: 0.25), curveColor.withValues(alpha: 0.05)],
        )
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, areaGradient);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // G2: Smooth curve via Catmull-Rom → cubic Bézier
  // ─────────────────────────────────────────────────────────────────────────

  void _drawSmoothCurve(
    Canvas canvas,
    Size size,
    List<Offset> pts,
    Color color,
    double width,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    if (pts.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final segments = _buildSegments(pts, size, toPixelX, toPixelY);
    for (final seg in segments) {
      canvas.drawPath(_catmullRomPath(seg), paint);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // G6: Gradient curve with glow
  // ─────────────────────────────────────────────────────────────────────────

  void _drawGradientCurve(
    Canvas canvas,
    Size size,
    List<Offset> pts,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    if (pts.length < 2) return;

    final hsl = HSLColor.fromColor(curveColor);
    final startColor = hsl.withLightness((hsl.lightness - 0.1).clamp(0.0, 1.0)).toColor();
    final endColor = hsl.withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + 0.1).clamp(0.0, 1.0))
        .toColor();

    final segments = _buildSegments(pts, size, toPixelX, toPixelY);

    for (final seg in segments) {
      final path = _catmullRomPath(seg);

      double minX = double.infinity, maxX = double.negativeInfinity;
      for (final p in seg) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
      }
      if (minX == maxX) maxX = minX + 1;

      final paint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(minX, 0),
          Offset(maxX, 0),
          [startColor, endColor],
        )
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      canvas.drawPath(path, paint);

      // Glow
      final glowPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(minX, 0),
          Offset(maxX, 0),
          [startColor.withValues(alpha: 0.15), endColor.withValues(alpha: 0.15)],
        )
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4)
        ..isAntiAlias = true;

      canvas.drawPath(path, glowPaint);
    }
  }

  List<List<Offset>> _buildSegments(
    List<Offset> pts,
    Size size,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    final segments = <List<Offset>>[];
    var current = <Offset>[];

    for (final pt in pts) {
      if (pt.dy.isFinite && pt.dy.abs() < 1e10) {
        final px = toPixelX(pt.dx);
        final py = toPixelY(pt.dy).clamp(-500.0, size.height + 500);
        current.add(Offset(px, py));
      } else {
        if (current.length >= 2) segments.add(current);
        current = <Offset>[];
      }
    }
    if (current.length >= 2) segments.add(current);
    return segments;
  }

  Path _catmullRomPath(List<Offset> seg) {
    final path = Path();
    if (seg.isEmpty) return path;

    path.moveTo(seg[0].dx, seg[0].dy);

    if (seg.length == 2) {
      path.lineTo(seg[1].dx, seg[1].dy);
      return path;
    }

    const tension = 6.0;

    for (int i = 0; i < seg.length - 1; i++) {
      final p0 = i > 0 ? seg[i - 1] : seg[i];
      final p1 = seg[i];
      final p2 = seg[i + 1];
      final p3 = i + 2 < seg.length ? seg[i + 2] : seg[i + 1];

      final cp1x = p1.dx + (p2.dx - p0.dx) / tension;
      final cp1y = p1.dy + (p2.dy - p0.dy) / tension;
      final cp2x = p2.dx - (p3.dx - p1.dx) / tension;
      final cp2y = p2.dy - (p3.dy - p1.dy) / tension;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // G5: Root markers
  // ─────────────────────────────────────────────────────────────────────────

  void _drawRootMarkers(
    Canvas canvas,
    Size size,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    final dotPaint = Paint()
      ..color = curveColor
      ..style = PaintingStyle.fill;
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];

      if (!a.dy.isFinite || !b.dy.isFinite) continue;
      if (a.dy.abs() > 1e10 || b.dy.abs() > 1e10) continue;

      if ((a.dy > 0 && b.dy < 0) || (a.dy < 0 && b.dy > 0) || a.dy == 0) {
        double rootX;
        if (a.dy == 0) {
          rootX = a.dx;
        } else {
          final t = a.dy / (a.dy - b.dy);
          rootX = a.dx + t * (b.dx - a.dx);
        }

        final px = toPixelX(rootX);
        final py = toPixelY(0);

        canvas.drawCircle(Offset(px, py), 5, dotPaint);
        canvas.drawCircle(Offset(px, py), 5, ringPaint);

        final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
          ..pushStyle(ui.TextStyle(
            color: curveColor,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ))
          ..addText(_formatNumber(rootX));
        final para = pb.build()..layout(const ui.ParagraphConstraints(width: 40));
        canvas.drawParagraph(para, Offset(px - 20, py + 8));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // A1: Critical points (local min/max where f'(x) ≈ 0)
  // ─────────────────────────────────────────────────────────────────────────

  void _drawCriticalPoints(
    Canvas canvas,
    Size size,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    if (derivativePoints == null || derivativePoints!.length < 3) return;

    final dp = derivativePoints!;

    for (int i = 1; i < dp.length - 1; i++) {
      if (!dp[i - 1].dy.isFinite || !dp[i].dy.isFinite || !dp[i + 1].dy.isFinite) continue;

      // Sign change in derivative = local extremum
      final prev = dp[i - 1].dy;
      final next = dp[i + 1].dy;

      bool isMax = prev > 0 && next < 0; // f' goes + → −
      bool isMin = prev < 0 && next > 0; // f' goes − → +

      if (!isMax && !isMin) continue;

      // Use the corresponding function value
      if (i >= points.length) continue;
      final pt = points[i];
      if (!pt.dy.isFinite || pt.dy.abs() > 1e10) continue;

      final px = toPixelX(pt.dx);
      final py = toPixelY(pt.dy);

      final color = isMax ? Colors.green : Colors.orange;

      // Outer glow
      canvas.drawCircle(Offset(px, py), 10, Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill);

      // Filled dot
      canvas.drawCircle(Offset(px, py), 5, Paint()
        ..color = color
        ..style = PaintingStyle.fill);
      canvas.drawCircle(Offset(px, py), 5, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);

      // Label
      final label = isMax ? 'MAX' : 'MIN';
      final value = _formatNumber(pt.dy);
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
        ..pushStyle(ui.TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ))
        ..addText('$label\n($value)');
      final para = pb.build()..layout(const ui.ParagraphConstraints(width: 50));
      canvas.drawParagraph(para, Offset(px - 25, py - (isMax ? 24 : -10)));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // A3: Integral badge
  // ─────────────────────────────────────────────────────────────────────────

  void _drawIntegralBadge(Canvas canvas, Size size, double value) {
    final text = '∫ ≈ ${_formatNumber(value)}';

    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
      ..pushStyle(ui.TextStyle(
        color: curveColor,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ))
      ..addText(text);
    final para = pb.build()..layout(const ui.ParagraphConstraints(width: 120));

    // Background pill
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width / 2 - 60, size.height - 28, 120, 22),
      const Radius.circular(11),
    );
    canvas.drawRRect(rect, Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill);
    canvas.drawRRect(rect, Paint()
      ..color = curveColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);

    canvas.drawParagraph(para, Offset(size.width / 2 - 60, size.height - 26));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Crosshair with A7 snap label
  // ─────────────────────────────────────────────────────────────────────────

  void _drawCrosshair(
    Canvas canvas,
    Size size,
    Offset pos,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    if (!pos.dx.isFinite || !pos.dy.isFinite) return;
    final px = toPixelX(pos.dx);
    final py = toPixelY(pos.dy);
    if (!px.isFinite || !py.isFinite) return;

    final paint = Paint()
      ..color = curveColor.withValues(alpha: 0.4)
      ..strokeWidth = 1.0;

    _drawDashedLine(canvas, Offset(px, 0), Offset(px, size.height), paint, 4, 3);
    _drawDashedLine(canvas, Offset(0, py), Offset(size.width, py), paint, 4, 3);

    // Projection to axes
    final projPaint = Paint()
      ..color = curveColor.withValues(alpha: 0.2)
      ..strokeWidth = 0.8;

    if (yMin <= 0 && yMax >= 0) {
      canvas.drawLine(Offset(px, py), Offset(px, toPixelY(0)), projPaint);
    }
    if (xMin <= 0 && xMax >= 0) {
      canvas.drawLine(Offset(px, py), Offset(toPixelX(0), py), projPaint);
    }

    // Ripple
    canvas.drawCircle(Offset(px, py), 10, Paint()
      ..color = curveColor.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill);
    canvas.drawCircle(Offset(px, py), 5, Paint()
      ..color = curveColor
      ..style = PaintingStyle.fill);
    canvas.drawCircle(Offset(px, py), 5, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);

    // A7: Snap label near dot
    if (crosshairSnapLabel != null) {
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
        ..pushStyle(ui.TextStyle(
          color: Colors.green,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ))
        ..addText(crosshairSnapLabel!);
      final para = pb.build()..layout(const ui.ParagraphConstraints(width: 60));
      canvas.drawParagraph(para, Offset(px - 30, py - 18));
    }

    // E2: Extra function dots on crosshair
    for (int i = 0; i < extraCrosshairYs.length; i++) {
      final ey = extraCrosshairYs[i];
      if (!ey.isFinite) continue;
      final epy = toPixelY(ey);
      if (!epy.isFinite || epy < 0 || epy > size.height) continue;
      final color = i < extraColors.length ? extraColors[i] : Colors.grey;
      // Small colored dot
      canvas.drawCircle(Offset(px, epy), 4, Paint()
        ..color = color
        ..style = PaintingStyle.fill);
      canvas.drawCircle(Offset(px, epy), 4, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint, double dashLen, double gapLen) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0) return;

    final ux = dx / dist;
    final uy = dy / dist;
    var d = 0.0;
    bool drawing = true;

    while (d < dist) {
      final segLen = drawing ? dashLen : gapLen;
      final nextD = math.min(d + segLen, dist);
      if (drawing) {
        canvas.drawLine(
          Offset(start.dx + ux * d, start.dy + uy * d),
          Offset(start.dx + ux * nextD, start.dy + uy * nextD),
          paint,
        );
      }
      d = nextD;
      drawing = !drawing;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Grid step (G1 — fixed with dart:math)
  // ─────────────────────────────────────────────────────────────────────────

  double _gridStep(double range) {
    if (range <= 0 || !range.isFinite) return 1;
    final raw = range / 8;
    if (raw <= 0 || !raw.isFinite) return 1;
    final logVal = math.log(raw) / math.ln10;
    if (!logVal.isFinite) return 1;
    final mag = math.pow(10, logVal.floor()).toDouble();
    if (mag <= 0 || !mag.isFinite) return 1;
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

    return step * mag;
  }

  String _formatNumber(double n) {
    if (n == n.roundToDouble() && n.abs() < 10000) {
      return n.toInt().toString();
    }
    return n.toStringAsFixed(2);
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
        oldDelegate.areaMode != areaMode ||
        oldDelegate.crosshair != crosshair ||
        oldDelegate.useGradient != useGradient ||
        oldDelegate.showRoots != showRoots ||
        oldDelegate.showCriticalPoints != showCriticalPoints ||
        oldDelegate.showAsymptotes != showAsymptotes ||
        oldDelegate.integralValue != integralValue ||
        oldDelegate.curveProgress != curveProgress ||
        oldDelegate.crosshairSnapLabel != crosshairSnapLabel ||
        oldDelegate.tangentSlope != tangentSlope ||
        oldDelegate.showMonotonicity != showMonotonicity ||
        oldDelegate.isDark != isDark ||
        oldDelegate.showLegend != showLegend ||
        oldDelegate.inflectionPoints != inflectionPoints ||
        oldDelegate.crosshairOpacity != crosshairOpacity ||
        oldDelegate.extraPoints != extraPoints ||
        oldDelegate.extraColors != extraColors ||
        oldDelegate.functionLabels != functionLabels ||
        oldDelegate.extraCrosshairYs != extraCrosshairYs ||
        oldDelegate.intersectionPoints != intersectionPoints;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // C3: Dot pattern background
  // ─────────────────────────────────────────────────────────────────────────

  void _drawDotPattern(Canvas canvas, Size size) {
    final dotColor = isDark
        ? const Color(0x0DFFFFFF) // very subtle white
        : const Color(0x0A000000); // very subtle black
    final paint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    const spacing = 20.0;
    const radius = 0.8;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // B1: Tangent line at crosshair
  // ─────────────────────────────────────────────────────────────────────────

  void _drawTangentLine(
    Canvas canvas,
    Size size,
    Offset pos,
    double slope,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    // Tangent line: y = f(a) + f'(a)(x - a)
    final a = pos.dx;
    final fa = pos.dy;

    // Compute y at viewport edges
    final yAtXMin = fa + slope * (xMin - a);
    final yAtXMax = fa + slope * (xMax - a);

    final p1 = Offset(toPixelX(xMin), toPixelY(yAtXMin));
    final p2 = Offset(toPixelX(xMax), toPixelY(yAtXMax));

    // Tangent line
    final paint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    canvas.drawLine(p1, p2, paint);

    // Slope badge near the crosshair
    final slopeStr = 'm=${slope.toStringAsFixed(2)}';
    final px = toPixelX(a);
    final py = toPixelY(fa);
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
      ..pushStyle(ui.TextStyle(
        color: Colors.amber,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ))
      ..addText(slopeStr);
    final para = pb.build()..layout(const ui.ParagraphConstraints(width: 60));
    canvas.drawParagraph(para, Offset(px - 30, py + 14));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // B2: Inflection points (where f''(x) = 0)
  // ─────────────────────────────────────────────────────────────────────────

  void _drawInflectionPoints(
    Canvas canvas,
    Size size,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    for (final ip in inflectionPoints!) {
      if (!ip.dy.isFinite || ip.dy.abs() > 1e10) continue;

      final px = toPixelX(ip.dx);
      final py = toPixelY(ip.dy);

      // Diamond shape
      final path = Path()
        ..moveTo(px, py - 6)
        ..lineTo(px + 5, py)
        ..lineTo(px, py + 6)
        ..lineTo(px - 5, py)
        ..close();

      canvas.drawPath(path, Paint()
        ..color = Colors.purple.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill);
      canvas.drawPath(path, Paint()
        ..color = Colors.purple
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);

      // Label
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
        ..pushStyle(ui.TextStyle(
          color: Colors.purple,
          fontSize: 8,
          fontWeight: FontWeight.w600,
        ))
        ..addText('FLESSO');
      final para = pb.build()..layout(const ui.ParagraphConstraints(width: 40));
      canvas.drawParagraph(para, Offset(px - 20, py - 18));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // B3: Monotonicity coloring — green when f'(x)>0, red when f'(x)<0
  // ─────────────────────────────────────────────────────────────────────────

  void _drawMonotonicityCurve(
    Canvas canvas,
    Size size,
    List<Offset> pts,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    if (pts.length < 2 || derivativePoints == null) return;

    final dp = derivativePoints!;
    const width = 2.8;

    final incPaint = Paint()
      ..color = const Color(0xFF4CAF50) // green
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final decPaint = Paint()
      ..color = const Color(0xFFF44336) // red
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      if (!a.dy.isFinite || !b.dy.isFinite) continue;
      if (a.dy.abs() > 1e10 || b.dy.abs() > 1e10) continue;

      final pxA = toPixelX(a.dx);
      final pyA = toPixelY(a.dy).clamp(-500.0, size.height + 500);
      final pxB = toPixelX(b.dx);
      final pyB = toPixelY(b.dy).clamp(-500.0, size.height + 500);

      // Get derivative sign at this point
      final di = i < dp.length ? dp[i].dy : 0.0;
      final paint = (di.isFinite && di >= 0) ? incPaint : decPaint;

      canvas.drawLine(Offset(pxA, pyA), Offset(pxB, pyB), paint);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // B6: Legend
  // ─────────────────────────────────────────────────────────────────────────

  void _drawLegend(Canvas canvas, Size size) {
    final entries = <(Color, String)>[];

    // E1: Multi-function labels
    if (functionLabels.length > 1) {
      entries.add((curveColor, 'f₁(x)'));
      for (int i = 1; i < functionLabels.length; i++) {
        final color = (i - 1) < extraColors.length ? extraColors[i - 1] : Colors.grey;
        entries.add((color, 'f${_subscript(i + 1)}(x)'));
      }
    } else if (showMonotonicity) {
      entries.add((const Color(0xFF4CAF50), 'Crescente'));
      entries.add((const Color(0xFFF44336), 'Decrescente'));
    } else {
      entries.add((curveColor, 'f(x)'));
    }
    if (showDerivative) {
      entries.add((derivativeColor, "f'(x)"));
    }
    if (showArea) {
      entries.add((curveColor.withValues(alpha: 0.3), 'Area'));
    }
    if (intersectionPoints.isNotEmpty) {
      entries.add((const Color(0xFFFFD600), '✖ Intersezioni'));
    }

    if (entries.isEmpty) return;

    final bgColor = isDark
        ? const Color(0xDD1E1E1E)
        : const Color(0xDDFFFFFF);
    final textColor = isDark ? Colors.white70 : Colors.black87;

    const lineH = 14.0;
    const padding = 8.0;
    final totalH = entries.length * lineH + padding * 2;
    const totalW = 110.0;

    // Background pill
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, size.height - totalH - 8, totalW, totalH),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = bgColor);
    canvas.drawRRect(rect, Paint()
      ..color = (isDark ? Colors.white12 : Colors.black12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5);

    // Entries
    for (int i = 0; i < entries.length; i++) {
      final (color, label) = entries[i];
      final y = size.height - totalH - 8 + padding + i * lineH;

      // Color swatch
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(16, y + 2, 12, 8),
          const Radius.circular(2),
        ),
        Paint()..color = color,
      );

      // Label
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
        ..pushStyle(ui.TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ))
        ..addText(label);
      final para = pb.build()..layout(const ui.ParagraphConstraints(width: 80));
      canvas.drawParagraph(para, Offset(32, y));
    }
  }

  /// Helper for subscript digits
  static String _subscript(int n) {
    const subs = '₀₁₂₃₄₅₆₇₈₉';
    return String.fromCharCodes(
      n.toString().codeUnits.map((c) => subs.codeUnitAt(c - 48)),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // E3: Intersection point markers
  // ─────────────────────────────────────────────────────────────────────────

  void _drawIntersections(
    Canvas canvas,
    Size size,
    double Function(double) toPixelX,
    double Function(double) toPixelY,
  ) {
    const markerColor = Color(0xFFFFD600); // gold
    for (final pt in intersectionPoints) {
      if (!pt.dx.isFinite || !pt.dy.isFinite) continue;
      final px = toPixelX(pt.dx);
      final py = toPixelY(pt.dy);
      if (!px.isFinite || !py.isFinite) continue;
      if (px < -10 || px > size.width + 10 || py < -10 || py > size.height + 10) continue;

      // Diamond marker
      final path = Path()
        ..moveTo(px, py - 5)
        ..lineTo(px + 5, py)
        ..lineTo(px, py + 5)
        ..lineTo(px - 5, py)
        ..close();
      canvas.drawPath(path, Paint()
        ..color = markerColor
        ..style = PaintingStyle.fill);
      canvas.drawPath(path, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }
  }
}
