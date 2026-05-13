import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../canvas/infinite_canvas_controller.dart';
import '../../layers/layer_controller.dart';

// ============================================================================
// 🎯 ERASER OVERLAY PAINTERS — public re-export of the eraser visual FX
//
// Originally lived as `_EraserTrailPainter` / `_EraserParticlePainter` inside
// the `fluera_canvas_screen.dart` part-file network. Moved here when the
// `FlueraCanvasView` extraction (God Object Decomposition) needed to draw
// the same trail and particles outside the screen library.
//
// The data classes ([EraserTrailPoint], [EraserParticle]) are mutable and
// owned by the screen wrapper's eraser tool — passed read-only to the view
// via [CanvasLegacyState].
// ============================================================================

/// Single sample of the eraser tool's trail. Position is in canvas-space;
/// timestamp is a wall-clock ms (compared against `now` in the painter).
class EraserTrailPoint {
  final Offset position;
  final int timestamp;
  const EraserTrailPoint(this.position, this.timestamp);
}

/// Particle emitted at erase intersection points (the "puff" FX).
class EraserParticle {
  Offset position;
  final Offset velocity;
  double opacity;
  final int createdAt;
  final double size;

  EraserParticle({
    required this.position,
    required this.velocity,
    this.opacity = 1.0,
    required this.createdAt,
    this.size = 3.0,
  });
}

/// 🎯 Eraser trail painter — fading polyline with gradient (orange→red),
/// trail-head glow, distance-based stroke width.
///
/// Renders in screen-space — the painter does its own
/// [InfiniteCanvasController.canvasToScreen] conversion per point.
class EraserTrailPainter extends CustomPainter {
  final List<EraserTrailPoint> trail;
  final InfiniteCanvasController canvasController;
  final int now;
  final bool isDark;

  EraserTrailPainter({
    required this.trail,
    required this.canvasController,
    required this.now,
    this.isDark = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    if (trail.length < 2) return;

    for (int i = 1; i < trail.length; i++) {
      final prev = trail[i - 1];
      final curr = trail[i];

      // Opacity fades over 300ms.
      final age = now - curr.timestamp;
      final alpha = (1.0 - (age / 300.0)).clamp(0.0, 1.0);
      if (alpha <= 0.01) continue;

      // V3: Distance-based gradient — older = orange, newer = red.
      final t = i / trail.length;
      final color = Color.lerp(
        isDark ? const Color(0xFFFFB74D) : const Color(0xFFFFA726),
        isDark ? const Color(0xFFE57373) : const Color(0xFFEF5350),
        t,
      )!;

      final p1 = canvasController.canvasToScreen(prev.position);
      final p2 = canvasController.canvasToScreen(curr.position);

      // V9: Trail width scales with position — newest = thick, oldest = thin.
      final widthT = t * alpha;
      final strokeWidth = 1.0 + widthT * 4.0; // 1px → 5px

      final paint = Paint()
        ..color = color.withValues(alpha: alpha * 0.6)
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(p1, p2, paint);
    }

    // V9: Glow circle at the trail head (newest point).
    if (trail.isNotEmpty) {
      final head = trail.last;
      final headAge = now - head.timestamp;
      final headAlpha = (1.0 - (headAge / 200.0)).clamp(0.0, 1.0);
      if (headAlpha > 0.05) {
        final headScreen = canvasController.canvasToScreen(head.position);
        final glowPaint = Paint()
          ..color = (isDark
                  ? const Color(0xFFEF9A9A)
                  : const Color(0xFFE57373))
              .withValues(alpha: headAlpha * 0.3)
          ..maskFilter =
              const ui.MaskFilter.blur(ui.BlurStyle.normal, 8.0);
        canvas.drawCircle(headScreen, 10.0 * headAlpha, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant EraserTrailPainter oldDelegate) => true;
}

/// 🎯 Eraser lasso path painter — translucent dashed polygon drawn while
/// the user defines a lasso erase area. `isAnimating` boosts fill opacity
/// for the closing pulse-in effect.
class EraserLassoPathPainter extends CustomPainter {
  final List<Offset> points;
  final InfiniteCanvasController canvasController;
  final bool isDark;
  final bool isAnimating;

  EraserLassoPathPainter({
    required this.points,
    required this.canvasController,
    this.isDark = false,
    this.isAnimating = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    if (points.length < 2) return;

    final fillAlpha = isAnimating ? 0.35 : 0.1;
    final fillPaint = Paint()
      ..color = (isDark ? const Color(0xFFE57373) : const Color(0xFFEF5350))
          .withValues(alpha: fillAlpha)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = isDark ? const Color(0xFFE57373) : const Color(0xFFEF5350)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = ui.Path();
    final first = canvasController.canvasToScreen(points.first);
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < points.length; i++) {
      final p = canvasController.canvasToScreen(points[i]);
      path.lineTo(p.dx, p.dy);
    }
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant EraserLassoPathPainter oldDelegate) => true;
}

/// 🎯 Eraser protected regions painter — semi-transparent blue rectangles
/// with lock icon, marking areas the eraser will skip.
class EraserProtectedRegionPainter extends CustomPainter {
  final List<ui.Rect> regions;
  final InfiniteCanvasController canvasController;
  final bool isDark;

  EraserProtectedRegionPainter({
    required this.regions,
    required this.canvasController,
    this.isDark = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    for (final region in regions) {
      final topLeft = canvasController.canvasToScreen(region.topLeft);
      final bottomRight = canvasController.canvasToScreen(region.bottomRight);
      final screenRect = Rect.fromPoints(topLeft, bottomRight);

      final fillPaint = Paint()
        ..color = (isDark ? const Color(0xFF64B5F6) : const Color(0xFF42A5F5))
            .withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = isDark ? const Color(0xFF64B5F6) : const Color(0xFF42A5F5)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      canvas.drawRect(screenRect, fillPaint);
      canvas.drawRect(screenRect, borderPaint);

      final iconPaint = TextPainter(
        text: const TextSpan(text: '🔒', style: TextStyle(fontSize: 14)),
        textDirection: TextDirection.ltr,
      )..layout();
      iconPaint.paint(
        canvas,
        Offset(screenRect.right - 20, screenRect.top + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant EraserProtectedRegionPainter oldDelegate) =>
      true;
}

/// 🎯 Eraser ghost preview painter — strokes about to be erased rendered
/// at low opacity with a soft red glow. Driven by [previewStrokeIds]
/// from the screen wrapper's eraser preview state.
class EraserGhostPreviewPainter extends CustomPainter {
  final Set<String> previewStrokeIds;
  final LayerController layerController;
  final InfiniteCanvasController canvasController;
  final bool isDark;

  EraserGhostPreviewPainter({
    required this.previewStrokeIds,
    required this.layerController,
    required this.canvasController,
    this.isDark = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    if (previewStrokeIds.isEmpty) return;

    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return;

    for (final stroke in activeLayer.strokes) {
      if (!previewStrokeIds.contains(stroke.id)) continue;
      if (stroke.points.length < 2) continue;

      final ghostPaint = Paint()
        ..color = (isDark ? const Color(0xFFEF9A9A) : const Color(0xFFEF5350))
            .withValues(alpha: 0.3)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

      final path = ui.Path();
      final first =
          canvasController.canvasToScreen(stroke.points.first.position);
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        final p = canvasController.canvasToScreen(stroke.points[i].position);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, ghostPaint);
    }
  }

  @override
  bool shouldRepaint(covariant EraserGhostPreviewPainter oldDelegate) => true;
}

/// 🎯 Magnetic snap indicator — orange dashed line from eraser cursor to
/// snap target (typically a stroke end-point). Both positions in screen-
/// space; the painter draws directly without canvas transform.
class MagneticSnapIndicatorPainter extends CustomPainter {
  final Offset cursorPos;
  final Offset snapTarget;
  final bool isDark;

  MagneticSnapIndicatorPainter({
    required this.cursorPos,
    required this.snapTarget,
    this.isDark = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    final dist = (cursorPos - snapTarget).distance;
    if (dist < 2.0) return;

    final dashPaint = Paint()
      ..color = (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00))
          .withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final direction = snapTarget - cursorPos;
    final length = direction.distance;
    final unit = direction / length;
    const dashLength = 6.0;
    const gapLength = 4.0;
    double drawn = 0;
    while (drawn < length) {
      final start = cursorPos + unit * drawn;
      final end = cursorPos + unit * math.min(drawn + dashLength, length);
      canvas.drawLine(start, end, dashPaint);
      drawn += dashLength + gapLength;
    }

    final targetPaint = Paint()
      ..color = isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(snapTarget, 4.0, targetPaint);

    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(snapTarget, 4.0, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant MagneticSnapIndicatorPainter oldDelegate) =>
      oldDelegate.cursorPos != cursorPos ||
      oldDelegate.snapTarget != snapTarget;
}

/// 🎯 Eraser particle painter — circular puffs at erase intersection points.
class EraserParticlePainter extends CustomPainter {
  final List<EraserParticle> particles;
  final InfiniteCanvasController canvasController;
  final bool isDark;

  EraserParticlePainter({
    required this.particles,
    required this.canvasController,
    this.isDark = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.opacity <= 0) continue;

      final screenPos = canvasController.canvasToScreen(p.position);
      final paint = Paint()
        ..color = (isDark
                ? const Color(0xFFEF9A9A)
                : const Color(0xFFEF5350))
            .withValues(alpha: p.opacity * 0.8)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(screenPos, p.size * p.opacity, paint);
    }
  }

  @override
  bool shouldRepaint(covariant EraserParticlePainter oldDelegate) => true;
}
