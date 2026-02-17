import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import '../../core/vector/anchor_point.dart';

/// 🎨 CustomPainter that renders the Pen Tool overlay.
///
/// Draws the in-progress path with:
/// - Path preview line (Bézier curve)
/// - Fill preview (semi-transparent area fill when fill is active)
/// - Anchor point dots (filled circles, highlighted when editing)
/// - Handle lines and handle dots
/// - First-anchor close indicator (ring when cursor is near)
/// - Rubber-band line (animated DASHED "marching ants")
/// - Anchor count badge near cursor
///
/// All positions are in SCREEN coordinates (pre-transformed by the tool).
/// Supports dark/light mode via [isDarkMode].
class PenToolPainter extends CustomPainter {
  /// Anchor points in screen coordinates.
  final List<AnchorPoint> anchors;

  /// Current cursor position in screen coordinates (for rubber-band line).
  final Offset? cursorPosition;

  /// Handle being dragged from the last anchor (screen coords, absolute).
  final Offset? dragHandle;

  /// Whether the cursor is close enough to the first anchor to close the path.
  final bool showCloseIndicator;

  /// Stroke color for the path preview.
  final Color pathColor;

  /// Stroke width for the path preview.
  final double pathStrokeWidth;

  /// Number of anchors placed (for badge display).
  final int anchorCount;

  /// Whether the canvas is in dark mode.
  final bool isDarkMode;

  /// Optional fill color for fill preview during construction.
  final Color? fillColor;

  /// Index of anchor currently being edited (-1 = none).
  final int editingAnchorIndex;

  /// Set of anchor indices currently selected for batch operations.
  final Set<int> selectedAnchorIndices;

  /// Whether to draw the curvature comb visualization.
  final bool showCurvatureComb;

  /// Color for multi-selection highlight.
  static const Color _multiSelectColor = Color(0xFF42A5F5);

  PenToolPainter({
    required this.anchors,
    this.cursorPosition,
    this.dragHandle,
    this.showCloseIndicator = false,
    this.pathColor = const Color(0xFF2196F3),
    this.pathStrokeWidth = 2.0,
    this.anchorCount = 0,
    this.isDarkMode = false,
    this.fillColor,
    this.editingAnchorIndex = -1,
    this.selectedAnchorIndices = const {},
    this.showCurvatureComb = false,
  });

  // ==========================================================================
  // 🎯 THEME-AWARE COLORS
  // ==========================================================================

  Color get _anchorFillColor =>
      isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;

  Color get _anchorBorderColor =>
      isDarkMode ? const Color(0xFF64B5F6) : const Color(0xFF2196F3);

  Color get _handleColor =>
      isDarkMode ? const Color(0xFF42A5F5) : const Color(0xFF90CAF9);

  Color get _handleLineColor =>
      isDarkMode ? const Color(0xFF42A5F5) : const Color(0xFF64B5F6);

  Color get _rubberBandColor =>
      isDarkMode ? const Color(0x66BBDEFB) : const Color(0x882196F3);

  Color get _closeIndicatorColor =>
      isDarkMode ? const Color(0xFF66BB6A) : const Color(0xFF4CAF50);

  Color get _badgeBgColor =>
      isDarkMode ? const Color(0xCC424242) : const Color(0xCC000000);

  Color get _badgeTextColor =>
      isDarkMode ? const Color(0xFFE0E0E0) : Colors.white;

  static const Color _editHighlightColor = Color(0xFFFF9800);

  static const double _anchorRadius = 5.0;
  static const double _handleRadius = 3.5;
  static const double _closeIndicatorRadius = 10.0;

  // ==========================================================================
  // 🎨 CACHED PAINT OBJECTS
  // ==========================================================================

  // These are created lazily via getters to avoid allocation every frame
  // while still being instance-scoped (tied to current theme colors).

  Paint get _pathPaint =>
      Paint()
        ..color = pathColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = pathStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

  Paint get _rubberBandPaint =>
      Paint()
        ..color = _rubberBandColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;

  Paint get _handleLinePaint =>
      Paint()
        ..color = _handleLineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

  Paint get _handleDotPaint =>
      Paint()
        ..color = _handleColor
        ..style = PaintingStyle.fill;

  Paint get _handleDotBorderPaint =>
      Paint()
        ..color = _anchorBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

  Paint get _anchorFillPaint =>
      Paint()
        ..color = _anchorFillColor
        ..style = PaintingStyle.fill;

  Paint get _anchorBorderPaint =>
      Paint()
        ..color = _anchorBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

  // ==========================================================================
  // 🎨 PAINT
  // ==========================================================================

  @override
  void paint(Canvas canvas, Size size) {
    if (anchors.isEmpty) return;

    _drawFillPreview(canvas);
    _drawPathPreview(canvas);
    _drawPathDirectionArrows(canvas);
    if (showCurvatureComb) _drawCurvatureComb(canvas);
    _drawRubberBand(canvas);
    _drawHandles(canvas);
    _drawHandleLengthReadout(canvas);
    _drawAnchorPoints(canvas);
    _drawCloseIndicator(canvas);
    _drawAnchorCountBadge(canvas);
  }

  /// #4: Draw a semi-transparent fill preview during path construction.
  void _drawFillPreview(Canvas canvas) {
    if (fillColor == null || anchors.length < 2) return;

    final vectorPath = AnchorPoint.toVectorPath(anchors, closed: true);
    final flutterPath = vectorPath.toFlutterPath();

    canvas.drawPath(
      flutterPath,
      Paint()
        ..color = fillColor!.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
  }

  /// Draw the Bézier path connecting all placed anchors.
  void _drawPathPreview(Canvas canvas) {
    if (anchors.length < 2) return;

    final vectorPath = AnchorPoint.toVectorPath(anchors, closed: false);
    final flutterPath = vectorPath.toFlutterPath();
    canvas.drawPath(flutterPath, _pathPaint);
  }

  /// #5: Draw the animated DASHED rubber-band (marching ants) from last anchor.
  void _drawRubberBand(Canvas canvas) {
    if (anchors.isEmpty || cursorPosition == null) return;

    final lastAnchor = anchors.last;
    Path curvePath;

    if (dragHandle != null) {
      curvePath =
          Path()
            ..moveTo(lastAnchor.position.dx, lastAnchor.position.dy)
            ..cubicTo(
              dragHandle!.dx,
              dragHandle!.dy,
              cursorPosition!.dx,
              cursorPosition!.dy,
              cursorPosition!.dx,
              cursorPosition!.dy,
            );
    } else {
      final handleOut = lastAnchor.handleOutAbsolute;
      if (handleOut != null) {
        curvePath =
            Path()
              ..moveTo(lastAnchor.position.dx, lastAnchor.position.dy)
              ..cubicTo(
                handleOut.dx,
                handleOut.dy,
                cursorPosition!.dx,
                cursorPosition!.dy,
                cursorPosition!.dx,
                cursorPosition!.dy,
              );
      } else {
        curvePath =
            Path()
              ..moveTo(lastAnchor.position.dx, lastAnchor.position.dy)
              ..lineTo(cursorPosition!.dx, cursorPosition!.dy);
      }
    }

    _drawDashedPath(canvas, curvePath, _rubberBandPaint);
  }

  /// Draws a path as a dashed line (6px dash, 4px gap).
  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const double dashLength = 6.0;
    const double gapLength = 4.0;

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashLength, metric.length);
        final segment = metric.extractPath(distance, end);
        canvas.drawPath(segment, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  /// Draw handle lines and handle dots for each anchor.
  void _drawHandles(Canvas canvas) {
    final linePaint = _handleLinePaint;
    final dotPaint = _handleDotPaint;
    final dotBorder = _handleDotBorderPaint;

    for (final anchor in anchors) {
      final hIn = anchor.handleInAbsolute;
      if (hIn != null) {
        canvas.drawLine(anchor.position, hIn, linePaint);
        canvas.drawCircle(hIn, _handleRadius, dotPaint);
        canvas.drawCircle(hIn, _handleRadius, dotBorder);
      }

      final hOut = anchor.handleOutAbsolute;
      if (hOut != null) {
        canvas.drawLine(anchor.position, hOut, linePaint);
        canvas.drawCircle(hOut, _handleRadius, dotPaint);
        canvas.drawCircle(hOut, _handleRadius, dotBorder);
      }
    }

    // Active drag handle (not yet committed).
    if (dragHandle != null && anchors.isNotEmpty) {
      final lastAnchor = anchors.last;
      canvas.drawLine(lastAnchor.position, dragHandle!, linePaint);
      canvas.drawCircle(dragHandle!, _handleRadius, dotPaint);
      canvas.drawCircle(dragHandle!, _handleRadius, dotBorder);

      // Mirror handle (symmetric).
      final mirror = lastAnchor.position * 2.0 - dragHandle!;
      canvas.drawLine(lastAnchor.position, mirror, linePaint);
      canvas.drawCircle(mirror, _handleRadius, dotPaint);
      canvas.drawCircle(mirror, _handleRadius, dotBorder);
    }
  }

  /// Draw anchor point markers — ● circle for smooth/symmetric, ◆ diamond for corner.
  void _drawAnchorPoints(Canvas canvas) {
    final fillPaint = _anchorFillPaint;
    final borderPaint = _anchorBorderPaint;

    for (int i = 0; i < anchors.length; i++) {
      final anchor = anchors[i];
      final pos = anchor.position;
      final isCorner = anchor.type == AnchorType.corner;

      // Currently editing this anchor — highlight in orange.
      if (i == editingAnchorIndex) {
        final glowPaint =
            Paint()
              ..color = _editHighlightColor.withValues(alpha: 0.3)
              ..style = PaintingStyle.fill;
        final editBorderPaint =
            Paint()
              ..color = _editHighlightColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;

        if (isCorner) {
          _drawDiamond(canvas, pos, _anchorRadius + 2, glowPaint);
          _drawDiamond(canvas, pos, _anchorRadius, fillPaint);
          _drawDiamond(canvas, pos, _anchorRadius, editBorderPaint);
        } else {
          canvas.drawCircle(pos, _anchorRadius + 2, glowPaint);
          canvas.drawCircle(pos, _anchorRadius, fillPaint);
          canvas.drawCircle(pos, _anchorRadius, editBorderPaint);
        }
        continue;
      }

      // A2: Multi-selected anchor — blue glow ring.
      if (selectedAnchorIndices.contains(i)) {
        final selectGlow =
            Paint()
              ..color = _multiSelectColor.withValues(alpha: 0.25)
              ..style = PaintingStyle.fill;
        final selectBorder =
            Paint()
              ..color = _multiSelectColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5;

        if (isCorner) {
          _drawDiamond(canvas, pos, _anchorRadius + 3, selectGlow);
          _drawDiamond(canvas, pos, _anchorRadius, fillPaint);
          _drawDiamond(canvas, pos, _anchorRadius, selectBorder);
        } else {
          canvas.drawCircle(pos, _anchorRadius + 3, selectGlow);
          canvas.drawCircle(pos, _anchorRadius, fillPaint);
          canvas.drawCircle(pos, _anchorRadius, selectBorder);
        }
        continue;
      }

      // First anchor with close indicator active.
      if (i == 0 && showCloseIndicator) {
        final closeFill =
            Paint()
              ..color = _closeIndicatorColor.withValues(alpha: 0.3)
              ..style = PaintingStyle.fill;
        final closeBorder =
            Paint()
              ..color = _closeIndicatorColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;

        if (isCorner) {
          _drawDiamond(canvas, pos, _anchorRadius, closeFill);
          _drawDiamond(canvas, pos, _anchorRadius, closeBorder);
        } else {
          canvas.drawCircle(pos, _anchorRadius, closeFill);
          canvas.drawCircle(pos, _anchorRadius, closeBorder);
        }
        continue;
      }

      // Normal anchor — corner ◆ vs smooth ●.
      if (isCorner) {
        _drawDiamond(canvas, pos, _anchorRadius, fillPaint);
        _drawDiamond(canvas, pos, _anchorRadius, borderPaint);
      } else {
        canvas.drawCircle(pos, _anchorRadius, fillPaint);
        canvas.drawCircle(pos, _anchorRadius, borderPaint);
      }
    }
  }

  /// Draw a 45°-rotated square (diamond) centered at [center] with [radius].
  void _drawDiamond(Canvas canvas, Offset center, double radius, Paint paint) {
    final path =
        Path()
          ..moveTo(center.dx, center.dy - radius)
          ..lineTo(center.dx + radius, center.dy)
          ..lineTo(center.dx, center.dy + radius)
          ..lineTo(center.dx - radius, center.dy)
          ..close();
    canvas.drawPath(path, paint);
  }

  /// Draw the close indicator ring around the first anchor.
  void _drawCloseIndicator(Canvas canvas) {
    if (!showCloseIndicator || anchors.length < 3) return;

    final firstPos = anchors.first.position;
    canvas.drawCircle(
      firstPos,
      _closeIndicatorRadius,
      Paint()
        ..color = _closeIndicatorColor.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  /// Draw a small badge near the cursor showing the anchor count.
  void _drawAnchorCountBadge(Canvas canvas) {
    if (anchorCount < 1 || cursorPosition == null) return;

    final badgePos = cursorPosition! + const Offset(16, -16);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: badgePos, width: 22, height: 18),
        const Radius.circular(9),
      ),
      Paint()
        ..color = _badgeBgColor
        ..style = PaintingStyle.fill,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: '$anchorCount',
        style: TextStyle(
          color: _badgeTextColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, badgePos - Offset(tp.width / 2, tp.height / 2));
  }

  // ==========================================================================
  // 🧭 PATH DIRECTION ARROWS (#4)
  // ==========================================================================

  /// Draw small chevron arrows at midpoints of each segment to show direction.
  void _drawPathDirectionArrows(Canvas canvas) {
    if (anchors.length < 2) return;

    final arrowPaint =
        Paint()
          ..color = pathColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

    for (int i = 0; i < anchors.length - 1; i++) {
      final a = anchors[i];
      final b = anchors[i + 1];

      // Compute midpoint on the segment (approximate for Bézier).
      final hOut = a.handleOutAbsolute;
      final hIn = b.handleInAbsolute;
      Offset mid;
      double angle;

      if (hOut != null || hIn != null) {
        // Cubic Bézier midpoint at t=0.5.
        final cp1 = hOut ?? a.position;
        final cp2 = hIn ?? b.position;
        mid = _cubicAt(0.5, a.position, cp1, cp2, b.position);
        // Tangent at t=0.5 for arrow direction.
        final tangent = _cubicTangentAt(0.5, a.position, cp1, cp2, b.position);
        angle = tangent.direction;
      } else {
        mid = Offset(
          (a.position.dx + b.position.dx) / 2,
          (a.position.dy + b.position.dy) / 2,
        );
        angle = (b.position - a.position).direction;
      }

      // Draw chevron (>).
      const size = 5.0;
      final p1 = mid + Offset.fromDirection(angle + 2.5, size);
      final p2 = mid + Offset.fromDirection(angle, 0); // tip
      final p3 = mid + Offset.fromDirection(angle - 2.5, size);

      canvas.drawLine(p1, p2, arrowPaint);
      canvas.drawLine(p3, p2, arrowPaint);
    }
  }

  /// Cubic Bézier point at parameter t.
  static Offset _cubicAt(double t, Offset p0, Offset p1, Offset p2, Offset p3) {
    final u = 1 - t;
    return p0 * (u * u * u) +
        p1 * (3 * u * u * t) +
        p2 * (3 * u * t * t) +
        p3 * (t * t * t);
  }

  /// Cubic Bézier tangent at parameter t.
  static Offset _cubicTangentAt(
    double t,
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
  ) {
    final u = 1 - t;
    return (p1 - p0) * (3 * u * u) +
        (p2 - p1) * (6 * u * t) +
        (p3 - p2) * (3 * t * t);
  }

  // ==========================================================================
  // 📏 HANDLE LENGTH READOUT (#5)
  // ==========================================================================

  /// When editing an anchor, draw handle length labels near handle dots.
  void _drawHandleLengthReadout(Canvas canvas) {
    if (editingAnchorIndex < 0 || editingAnchorIndex >= anchors.length) return;

    final anchor = anchors[editingAnchorIndex];
    final bg =
        isDarkMode
            ? Colors.black.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.8);
    final fg = isDarkMode ? Colors.white70 : Colors.black87;

    void drawLabel(Offset handleAbs) {
      final len = (handleAbs - anchor.position).distance;
      final label = '${len.toStringAsFixed(1)}px';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final pos = handleAbs + const Offset(8, -14);
      final rect = Rect.fromLTWH(
        pos.dx - 2,
        pos.dy - 1,
        tp.width + 4,
        tp.height + 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color = bg
          ..style = PaintingStyle.fill,
      );
      tp.paint(canvas, pos);
    }

    final hIn = anchor.handleInAbsolute;
    if (hIn != null) drawLabel(hIn);

    final hOut = anchor.handleOutAbsolute;
    if (hOut != null) drawLabel(hOut);
  }

  // ==========================================================================
  // REPAINT — #7: use listEquals for proper comparison
  // ==========================================================================

  @override
  bool shouldRepaint(PenToolPainter oldDelegate) {
    return !listEquals(anchors, oldDelegate.anchors) ||
        cursorPosition != oldDelegate.cursorPosition ||
        dragHandle != oldDelegate.dragHandle ||
        showCloseIndicator != oldDelegate.showCloseIndicator ||
        anchorCount != oldDelegate.anchorCount ||
        isDarkMode != oldDelegate.isDarkMode ||
        fillColor != oldDelegate.fillColor ||
        editingAnchorIndex != oldDelegate.editingAnchorIndex ||
        !_setEquals(selectedAnchorIndices, oldDelegate.selectedAnchorIndices) ||
        showCurvatureComb != oldDelegate.showCurvatureComb;
  }

  /// Compare two sets for equality (order-independent).
  static bool _setEquals(Set<int> a, Set<int> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  // ==========================================================================
  // A3: CURVATURE COMB VISUALIZATION
  // ==========================================================================

  /// Draw perpendicular "comb" ticks along each segment, showing curvature.
  void _drawCurvatureComb(Canvas canvas) {
    if (anchors.length < 2) return;

    final combPaint =
        Paint()
          ..color =
              (isDarkMode ? const Color(0x66CE93D8) : const Color(0x669C27B0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;

    const int samples = 30;
    const double combScale = 50.0; // visual multiplier for curvature magnitude

    for (int i = 0; i < anchors.length - 1; i++) {
      final a = anchors[i];
      final b = anchors[i + 1];

      final p0 = a.position;
      final p1 = a.handleOutAbsolute ?? p0;
      final p2 = b.handleInAbsolute ?? b.position;
      final p3 = b.position;

      for (int s = 1; s < samples; s++) {
        final t = s / samples;

        // Point on curve.
        final pt = _cubicAt(t, p0, p1, p2, p3);

        // First and second derivatives.
        final d1 = _cubicTangentAt(t, p0, p1, p2, p3);
        final d2 = _cubicSecondDerivAt(t, p0, p1, p2, p3);

        // Curvature = |d1 x d2| / |d1|^3
        final cross = d1.dx * d2.dy - d1.dy * d2.dx;
        final d1Len = d1.distance;
        if (d1Len < 0.001) continue;
        final curvature = cross / (d1Len * d1Len * d1Len);

        // Normal direction (perpendicular to tangent).
        final normal = Offset(-d1.dy, d1.dx) / d1Len;

        // Tick from point on curve, length proportional to curvature.
        final tickEnd = pt + normal * curvature * combScale;
        canvas.drawLine(pt, tickEnd, combPaint);
      }
    }
  }

  /// Second derivative of cubic Bézier at parameter t.
  Offset _cubicSecondDerivAt(
    double t,
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
  ) {
    final mt = 1.0 - t;
    return (p2 - p1 * 2 + p0) * (6 * mt) + (p3 - p2 * 2 + p1) * (6 * t);
  }
}
