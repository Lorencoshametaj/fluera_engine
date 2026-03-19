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
    this.color = Colors.blue,
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
    // Skip points that are < 2px apart in screen space to reduce path complexity.
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

    // Always include the very last point for accurate end position
    final lastScreen = canvasController.canvasToScreen(path.last);
    if (screenPath.last != lastScreen) {
      screenPath.add(lastScreen);
    }

    if (screenPath.length < 2) return;

    // Build the path from decimated screen coordinates
    final pathToDraw = Path();
    pathToDraw.moveTo(screenPath.first.dx, screenPath.first.dy);
    for (var i = 1; i < screenPath.length; i++) {
      pathToDraw.lineTo(screenPath[i].dx, screenPath[i].dy);
    }

    // 1. Outer neon glow (electric blue, wide blur)
    final glowPaint =
        Paint()
          ..color = const Color(0xFF00D4FF).withValues(alpha: 0.25)
          ..strokeWidth = _kGlowWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            _kGlowBlurSigma,
          );
    canvas.drawPath(pathToDraw, glowPaint);

    // 1b. Inner neon glow (brighter, tighter)
    final innerGlowPaint =
        Paint()
          ..color = const Color(0xFF82C8FF).withValues(alpha: 0.35)
          ..strokeWidth = 5.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawPath(pathToDraw, innerGlowPaint);

    // 2. Semi-transparent holographic fill
    final fillPaint =
        Paint()
          ..color = const Color(0xFF00D4FF).withValues(alpha: 0.04)
          ..style = PaintingStyle.fill;
    canvas.drawPath(pathToDraw, fillPaint);

    // 3. Main neon border (solid, bright)
    final mainPaint =
        Paint()
          ..color = const Color(0xFF82C8FF).withValues(alpha: 0.9)
          ..strokeWidth = _kMainBorderWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(pathToDraw, mainPaint);

    // 4. Inner white core for depth
    final innerPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = _kInnerBorderWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(pathToDraw, innerPaint);

    // 5. Neon energy points along the path
    for (var i = 0; i < screenPath.length; i += _kKeyPointInterval) {
      // Glow
      canvas.drawCircle(
        screenPath[i],
        4.5,
        Paint()
          ..color = const Color(0xFF00D4FF).withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );
      // Core
      canvas.drawCircle(
        screenPath[i],
        2.0,
        Paint()..color = const Color(0xFFDDEEFF),
      );
    }

    // 6. Special start and end points
    if (screenPath.isNotEmpty) {
      _drawSpecialPoint(canvas, screenPath.first, color, isStart: true);
      if (screenPath.length > 3) {
        final distance = (screenPath.last - screenPath.first).distance;
        _drawSpecialPoint(
          canvas,
          screenPath.last,
          color,
          isStart: false,
          isClosing: distance < _kCloseThreshold,
        );
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

    // Glow
    canvas.drawRect(
      screenRect,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = _kGlowWidth
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _kGlowBlurSigma),
    );

    // Fill
    canvas.drawRect(
      screenRect,
      Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );

    // Dashed border
    final rectPath = Path()..addRect(screenRect);
    final dashPath = _createDashedPath(rectPath, dashLength: _kDashLength, gapLength: _kGapLength);
    canvas.drawPath(
      dashPath,
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..strokeWidth = _kMainBorderWidth
        ..style = PaintingStyle.stroke,
    );

    // Corner handles
    for (final corner in [screenRect.topLeft, screenRect.topRight, screenRect.bottomLeft, screenRect.bottomRight]) {
      canvas.drawCircle(corner, 4.0, Paint()..color = Colors.white);
      canvas.drawCircle(corner, 2.5, Paint()..color = color);
    }
  }

  // ===========================================================================
  // Ellipse Marquee Rendering
  // ===========================================================================

  void _paintEllipseMarquee(Canvas canvas, Rect rect) {
    final screenTL = canvasController.canvasToScreen(rect.topLeft);
    final screenBR = canvasController.canvasToScreen(rect.bottomRight);
    final screenRect = Rect.fromPoints(screenTL, screenBR);

    // Glow
    canvas.drawOval(
      screenRect,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = _kGlowWidth
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _kGlowBlurSigma),
    );

    // Fill
    canvas.drawOval(
      screenRect,
      Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );

    // Dashed border
    final ovalPath = Path()..addOval(screenRect);
    final dashPath = _createDashedPath(ovalPath, dashLength: _kDashLength, gapLength: _kGapLength);
    canvas.drawPath(
      dashPath,
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..strokeWidth = _kMainBorderWidth
        ..style = PaintingStyle.stroke,
    );

    // Inner highlight
    canvas.drawOval(
      screenRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..strokeWidth = _kInnerBorderWidth
        ..style = PaintingStyle.stroke,
    );

    // Axis handles (top, right, bottom, left)
    final cx = screenRect.center.dx;
    final cy = screenRect.center.dy;
    final handles = [
      Offset(cx, screenRect.top),
      Offset(screenRect.right, cy),
      Offset(cx, screenRect.bottom),
      Offset(screenRect.left, cy),
    ];
    for (final h in handles) {
      canvas.drawCircle(h, 4.0, Paint()..color = Colors.white);
      canvas.drawCircle(h, 2.5, Paint()..color = color);
    }
  }

  /// 🚀 PERF: Repainting is driven by the `repaint` Listenable passed in
  /// the constructor, so shouldRepaint can always return false.
  @override
  bool shouldRepaint(LassoPathPainter oldDelegate) => false;
}
