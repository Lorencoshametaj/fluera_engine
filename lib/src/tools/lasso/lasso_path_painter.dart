import 'package:flutter/material.dart';
import '../../canvas/infinite_canvas_controller.dart';
import 'lasso_tool.dart';

// =============================================================================
// Visual Constants
// =============================================================================

/// Outer neon glow stroke width.
const double _kGlowWidth = 12.0;

/// Glow blur sigma.
const double _kGlowBlurSigma = 8.0;

/// Main border stroke width.
const double _kMainBorderWidth = 2.5;

/// Inner highlight stroke width.
const double _kInnerBorderWidth = 1.0;

/// Dash pattern: dash length in logical pixels.
const double _kDashLength = 8.0;

/// Dash pattern: gap length in logical pixels.
const double _kGapLength = 4.0;

/// Interval between key points drawn along the path.
const int _kKeyPointInterval = 30;

/// Distance threshold (in screen pixels) to show the "closing" indicator.
const double _kCloseThreshold = 50.0;

/// Special point outer radius.
const double _kSpecialPointOuterRadius = 8.0;

/// Special point white border radius.
const double _kSpecialPointBorderRadius = 5.5;

/// Special point inner radius.
const double _kSpecialPointInnerRadius = 4.0;

/// Closing indicator ring radius.
const double _kCloseIndicatorRadius = 7.0;

/// 🚀 PERF: Minimum squared screen-distance between decimated points.
/// Points closer than this are skipped to reduce path complexity.
const double _kDecimationDistSq = 4.0; // 2px squared

/// Widget showing the lasso path during drawing.
///
/// Supports freehand lasso, rectangular marquee, and elliptical marquee
/// rendering modes.
class LassoPathPainter extends CustomPainter {
  final List<Offset> path;
  final Color color;
  final InfiniteCanvasController canvasController;

  /// Current selection mode (determines visual shape).
  final SelectionMode selectionMode;

  /// Current marquee/ellipse bounding rect (for marquee and ellipse modes).
  final Rect? marqueeRect;

  LassoPathPainter({
    required this.path,
    this.color = const Color(0xFF818CF8),
    required this.canvasController,
    this.selectionMode = SelectionMode.lasso,
    this.marqueeRect,
    Listenable? repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    // Marquee or Ellipse mode: draw shape from marqueeRect
    if (selectionMode == SelectionMode.marquee && marqueeRect != null) {
      _paintMarqueeRect(canvas, marqueeRect!);
      return;
    }
    if (selectionMode == SelectionMode.ellipse && marqueeRect != null) {
      _paintEllipseMarquee(canvas, marqueeRect!);
      return;
    }

    // Freehand lasso mode
    if (path.length < 2) return;

    // 🚀 PERF: Convert to screen coords with decimation.
    final screenPath = <Offset>[];
    Offset last = canvasController.canvasToScreen(path.first);
    screenPath.add(last);

    for (var i = 1; i < path.length; i++) {
      final sp = canvasController.canvasToScreen(path[i]);
      final dx = sp.dx - last.dx;
      final dy = sp.dy - last.dy;
      if (dx * dx + dy * dy >= _kDecimationDistSq) {
        screenPath.add(sp);
        last = sp;
      }
    }

    final lastScreen = canvasController.canvasToScreen(path.last);
    if (screenPath.last != lastScreen) {
      screenPath.add(lastScreen);
    }

    if (screenPath.length < 2) return;

    // Build smooth path via Catmull-Rom spline for organic feel
    final smoothPath = Path();
    smoothPath.moveTo(screenPath.first.dx, screenPath.first.dy);
    if (screenPath.length <= 3) {
      for (var i = 1; i < screenPath.length; i++) {
        smoothPath.lineTo(screenPath[i].dx, screenPath[i].dy);
      }
    } else {
      // Catmull-Rom → cubic bezier conversion for buttery smooth curves
      for (int i = 0; i < screenPath.length - 1; i++) {
        final p0 = i > 0 ? screenPath[i - 1] : screenPath[i];
        final p1 = screenPath[i];
        final p2 = screenPath[i + 1];
        final p3 = i + 2 < screenPath.length ? screenPath[i + 2] : p2;

        final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
        final cp1y = p1.dy + (p2.dy - p0.dy) / 6;
        final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
        final cp2y = p2.dy - (p3.dy - p1.dy) / 6;

        smoothPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      }
    }

    // Compute bounding rect for gradient
    final pathBounds = smoothPath.getBounds();

    // ── 1. Frosted glass fill ──────────────────────────────────────────────
    final fillPath = Path.from(smoothPath)..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6366F1).withValues(alpha: 0.06),
            const Color(0xFF06B6D4).withValues(alpha: 0.08),
            const Color(0xFFA855F7).withValues(alpha: 0.05),
          ],
        ).createShader(pathBounds)
        ..style = PaintingStyle.fill,
    );

    // ── 2. Ambient glow — SINGLE path draw (cheap) ──────────────────────────
    canvas.drawPath(
      smoothPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF6366F1).withValues(alpha: 0.18),
            const Color(0xFF06B6D4).withValues(alpha: 0.22),
            const Color(0xFFEC4899).withValues(alpha: 0.18),
          ],
        ).createShader(pathBounds)
        ..strokeWidth = 8.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
    );

    // ── 3. Main stroke — per-segment with velocity width + trail fade ──────
    // 🚀 PERF: Downsample to max 60 segments to cap draw calls
    final segCount = screenPath.length - 1;
    const maxSegs = 60;
    final step = segCount > maxSegs ? segCount / maxSegs : 1.0;

    const gradientColors = [
      Color(0xFF818CF8), Color(0xFF22D3EE),
      Color(0xFFC084FC), Color(0xFFF472B6),
    ];

    for (double fi = 0; fi < segCount; fi += step) {
      final i = fi.floor().clamp(0, segCount - 1);
      final t = segCount > 1 ? i / (segCount - 1) : 0.0;

      // Trail fade: 30% → 100%
      final fadeAlpha = 0.30 + 0.70 * t;

      // Velocity width
      final dist = (screenPath[i + 1] - screenPath[i]).distance.clamp(1.0, 40.0);
      final strokeW = 1.2 + (1.0 - (dist - 1.0) / 39.0) * 2.8;

      // Color interpolation
      final ct = t * (gradientColors.length - 1);
      final ci = ct.floor().clamp(0, gradientColors.length - 2);
      final segColor = Color.lerp(gradientColors[ci], gradientColors[ci + 1], ct - ci)!;

      canvas.drawLine(
        screenPath[i], screenPath[i + 1],
        Paint()
          ..color = segColor.withValues(alpha: fadeAlpha * 0.9)
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── 4. Inner white highlight — SINGLE path draw (cheap) ─────────────────
    canvas.drawPath(
      smoothPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // ── 3. Start point — subtle frosted dot ─────────────────────────────────
    if (screenPath.isNotEmpty) {
      canvas.drawCircle(
        screenPath.first,
        6.0,
        Paint()
          ..color = const Color(0xFF818CF8).withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
      );
      canvas.drawCircle(
        screenPath.first,
        3.5,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        screenPath.first,
        2.0,
        Paint()..color = const Color(0xFF818CF8),
      );
    }

    // ── 4. Glow cursor at finger (end point) ────────────────────────────────
    if (screenPath.length > 2) {
      final cursor = screenPath.last;
      // Outer aura
      canvas.drawCircle(
        cursor,
        12.0,
        Paint()
          ..color = const Color(0xFFF472B6).withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0),
      );
      // Mid ring
      canvas.drawCircle(
        cursor,
        5.0,
        Paint()
          ..color = const Color(0xFFF472B6).withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );
      // White core
      canvas.drawCircle(
        cursor,
        2.5,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.95)
          ..style = PaintingStyle.fill,
      );
    }

    // ── 5. Closing indicator — magnetic snap ────────────────────────────────
    if (screenPath.length > 5) {
      final distance = (screenPath.last - screenPath.first).distance;
      if (distance < _kCloseThreshold) {
        final t = (1.0 - distance / _kCloseThreshold).clamp(0.0, 1.0);
        canvas.drawCircle(
          screenPath.first,
          6.0 + t * 8.0,
          Paint()
            ..color = const Color(0xFF34D399).withValues(alpha: 0.15 + t * 0.35)
            ..strokeWidth = 2.0 + t * 1.0
            ..style = PaintingStyle.stroke
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.0 + t * 3.0),
        );
        if (t > 0.3) {
          final closingPath = Path()
            ..moveTo(screenPath.last.dx, screenPath.last.dy)
            ..lineTo(screenPath.first.dx, screenPath.first.dy);
          canvas.drawPath(
            closingPath,
            Paint()
              ..color = const Color(0xFF34D399).withValues(alpha: t * 0.5)
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }
  }

  /// Draw start/end key points with visual indicators.
  void _drawSpecialPoint(
    Canvas canvas,
    Offset point,
    Color color, {
    required bool isStart,
    bool isClosing = false,
  }) {
    // Outer glow
    canvas.drawCircle(
      point,
      _kSpecialPointOuterRadius,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );

    // White border
    canvas.drawCircle(
      point,
      _kSpecialPointBorderRadius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Color center
    canvas.drawCircle(
      point,
      _kSpecialPointInnerRadius,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    // Green ring to indicate close-ready
    if (!isStart && isClosing) {
      canvas.drawCircle(
        point,
        _kCloseIndicatorRadius,
        Paint()
          ..color = Colors.green.withValues(alpha: 0.6)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }
  }

  /// Create a dashed path from a source path.
  Path _createDashedPath(
    Path source, {
    required double dashLength,
    required double gapLength,
  }) {
    final dashes = Path();
    final metricsIterator = source.computeMetrics().iterator;

    while (metricsIterator.moveNext()) {
      final metric = metricsIterator.current;
      double distance = 0.0;
      bool draw = true;

      while (distance < metric.length) {
        final length = draw ? dashLength : gapLength;
        final endDistance = (distance + length).clamp(0.0, metric.length);

        if (draw) {
          dashes.addPath(
            metric.extractPath(distance, endDistance),
            Offset.zero,
          );
        }

        distance = endDistance;
        draw = !draw;
      }
    }

    return dashes;
  }

  // ===========================================================================
  // Marquee Rect Rendering
  // ===========================================================================

  void _paintMarqueeRect(Canvas canvas, Rect rect) {
    final screenTL = canvasController.canvasToScreen(rect.topLeft);
    final screenBR = canvasController.canvasToScreen(rect.bottomRight);
    final screenRect = Rect.fromPoints(screenTL, screenBR);
    final rrect = RRect.fromRectAndRadius(screenRect, const Radius.circular(4));

    // Frosted fill
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6366F1).withValues(alpha: 0.06),
            const Color(0xFF06B6D4).withValues(alpha: 0.08),
          ],
        ).createShader(screenRect)
        ..style = PaintingStyle.fill,
    );

    // Ambient glow
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF818CF8).withValues(alpha: 0.18),
            const Color(0xFF22D3EE).withValues(alpha: 0.22),
          ],
        ).createShader(screenRect)
        ..strokeWidth = 8.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
    );

    // Gradient border
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            Color(0xFF818CF8),
            Color(0xFF22D3EE),
            Color(0xFFC084FC),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(screenRect)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // White inner highlight
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );

    // Corner handles — frosted glass rounded squares
    for (final corner in [screenRect.topLeft, screenRect.topRight, screenRect.bottomLeft, screenRect.bottomRight]) {
      final hr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: corner, width: 10, height: 10),
        const Radius.circular(3),
      );
      canvas.drawRRect(hr.inflate(1), Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0));
      canvas.drawRRect(hr, Paint()..color = Colors.white);
      canvas.drawRRect(hr, Paint()
        ..color = const Color(0xFF818CF8)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke);
    }
  }

  // ===========================================================================
  // Ellipse Marquee Rendering
  // ===========================================================================

  void _paintEllipseMarquee(Canvas canvas, Rect rect) {
    final screenTL = canvasController.canvasToScreen(rect.topLeft);
    final screenBR = canvasController.canvasToScreen(rect.bottomRight);
    final screenRect = Rect.fromPoints(screenTL, screenBR);

    // Frosted fill
    canvas.drawOval(
      screenRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6366F1).withValues(alpha: 0.06),
            const Color(0xFF06B6D4).withValues(alpha: 0.08),
          ],
        ).createShader(screenRect)
        ..style = PaintingStyle.fill,
    );

    // Ambient glow
    canvas.drawOval(
      screenRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF818CF8).withValues(alpha: 0.18),
            const Color(0xFF22D3EE).withValues(alpha: 0.22),
          ],
        ).createShader(screenRect)
        ..strokeWidth = 8.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
    );

    // Gradient border
    canvas.drawOval(
      screenRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            Color(0xFF818CF8),
            Color(0xFF22D3EE),
            Color(0xFFC084FC),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(screenRect)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // White inner highlight
    canvas.drawOval(
      screenRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );

    // Axis handles — frosted glass rounded squares
    final cx = screenRect.center.dx;
    final cy = screenRect.center.dy;
    final handles = [
      Offset(cx, screenRect.top),
      Offset(screenRect.right, cy),
      Offset(cx, screenRect.bottom),
      Offset(screenRect.left, cy),
    ];
    for (final h in handles) {
      final hr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: h, width: 10, height: 10),
        const Radius.circular(3),
      );
      canvas.drawRRect(hr.inflate(1), Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0));
      canvas.drawRRect(hr, Paint()..color = Colors.white);
      canvas.drawRRect(hr, Paint()
        ..color = const Color(0xFF818CF8)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke);
    }
  }

  /// 🚀 PERF: Repainting is driven by the `repaint` Listenable passed in
  /// the constructor, so shouldRepaint can always return false.
  @override
  bool shouldRepaint(LassoPathPainter oldDelegate) => false;
}
