part of '../../fluera_canvas_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// ERASER PAINTERS — extracted from _build_ui.dart
// ═══════════════════════════════════════════════════════════════════

/// 🎯 CustomPainter for eraser trail — fading polyline with gradient
class _EraserTrailPainter extends CustomPainter {
  final List<_EraserTrailPoint> trail;
  final InfiniteCanvasController canvasController;
  final int now;
  final bool isDark;

  _EraserTrailPainter({
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

      // Opacity fades over 300ms
      final age = now - curr.timestamp;
      final alpha = (1.0 - (age / 300.0)).clamp(0.0, 1.0);
      if (alpha <= 0.01) continue;

      // 🎯 V3: Distance-based gradient — older = orange, newer = red
      final t = i / trail.length;
      final color =
          Color.lerp(
            isDark ? const Color(0xFFFFB74D) : const Color(0xFFFFA726),
            isDark ? const Color(0xFFE57373) : const Color(0xFFEF5350),
            t,
          )!;

      final p1 = canvasController.canvasToScreen(prev.position);
      final p2 = canvasController.canvasToScreen(curr.position);

      // V9: Trail width scales with position — newest = thick, oldest = thin
      final widthT = t * alpha;
      final strokeWidth = 1.0 + widthT * 4.0; // 1px → 5px

      final paint =
          Paint()
            ..color = color.withValues(alpha: alpha * 0.6)
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;

      canvas.drawLine(p1, p2, paint);
    }

    // V9: Glow circle at the trail head (newest point)
    if (trail.isNotEmpty) {
      final head = trail.last;
      final headAge = now - head.timestamp;
      final headAlpha = (1.0 - (headAge / 200.0)).clamp(0.0, 1.0);
      if (headAlpha > 0.05) {
        final headScreen = canvasController.canvasToScreen(head.position);
        final glowPaint =
            Paint()
              ..color = (isDark ? const Color(0xFFEF9A9A) : const Color(0xFFE57373))
                  .withValues(alpha: headAlpha * 0.3)
              ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8.0);
        canvas.drawCircle(headScreen, 10.0 * headAlpha, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EraserTrailPainter oldDelegate) => true;
}

/// 🎯 V3: CustomPainter for eraser boundary particles
class _EraserParticlePainter extends CustomPainter {
  final List<_EraserParticle> particles;
  final InfiniteCanvasController canvasController;
  final bool isDark;

  _EraserParticlePainter({
    required this.particles,
    required this.canvasController,
    this.isDark = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.opacity <= 0) continue;

      final screenPos = canvasController.canvasToScreen(p.position);
      final paint =
          Paint()
            ..color = (isDark ? const Color(0xFFEF9A9A) : const Color(0xFFEF5350)).withValues(
              alpha: p.opacity * 0.8,
            )
            ..style = PaintingStyle.fill;

      canvas.drawCircle(screenPos, p.size * p.opacity, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EraserParticlePainter oldDelegate) => true;
}

/// 🎯 CustomPainter for crosshair at eraser center
class _CrosshairPainter extends CustomPainter {
  final double radius;
  final Color color;

  _CrosshairPainter({
    required this.radius,
    this.color = const Color.fromRGBO(255, 255, 255, 0.6),
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final length = radius * 0.35; // Crosshair = 35% of radius

    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round;

    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - length, center.dy),
      Offset(center.dx + length, center.dy),
      paint,
    );
    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - length),
      Offset(center.dx, center.dy + length),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.color != color;
}

/// 🎯 V4: Lasso eraser path overlay — draws a dashed polygon
class _EraserLassoPathPainter extends CustomPainter {
  final List<Offset> points;
  final InfiniteCanvasController canvasController;
  final bool isDark;
  final bool isAnimating;

  _EraserLassoPathPainter({
    required this.points,
    required this.canvasController,
    this.isDark = false,
    this.isAnimating = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    if (points.length < 2) return;

    // V5: Boost fill opacity when animating (pulse-in effect)
    final fillAlpha = isAnimating ? 0.35 : 0.1;
    final fillPaint =
        Paint()
          ..color = (isDark ? const Color(0xFFE57373) : const Color(0xFFEF5350)).withValues(
            alpha: fillAlpha,
          )
          ..style = PaintingStyle.fill;

    final strokePaint =
        Paint()
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
  bool shouldRepaint(covariant _EraserLassoPathPainter oldDelegate) => true;
}

/// 🎯 V4: Protected regions overlay — blue hatched rectangles
class _EraserProtectedRegionPainter extends CustomPainter {
  final List<ui.Rect> regions;
  final InfiniteCanvasController canvasController;
  final bool isDark;

  _EraserProtectedRegionPainter({
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

      // Semi-transparent blue fill
      final fillPaint =
          Paint()
            ..color = (isDark ? const Color(0xFF64B5F6) : const Color(0xFF42A5F5))
                .withValues(alpha: 0.12)
            ..style = PaintingStyle.fill;

      // Dashed blue border
      final borderPaint =
          Paint()
            ..color = isDark ? const Color(0xFF64B5F6) : const Color(0xFF42A5F5)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;

      canvas.drawRect(screenRect, fillPaint);
      canvas.drawRect(screenRect, borderPaint);

      // Draw lock icon indicator (small 🔒 at top-right)
      final iconPaint = TextPainter(
        text: TextSpan(text: '🔒', style: TextStyle(fontSize: 14)),
        textDirection: TextDirection.ltr,
      );
      iconPaint.layout();
      iconPaint.paint(
        canvas,
        Offset(screenRect.right - 20, screenRect.top + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EraserProtectedRegionPainter oldDelegate) =>
      true;
}

/// 🎯 V5: Ghost preview painter — shows strokes about to be erased at low opacity
class _EraserGhostPreviewPainter extends CustomPainter {
  final Set<String> previewStrokeIds;
  final LayerController layerController;
  final InfiniteCanvasController canvasController;
  final bool isDark;

  _EraserGhostPreviewPainter({
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

      // Draw ghost version — semi-transparent with glow effect
      final ghostPaint =
          Paint()
            ..color = (isDark ? const Color(0xFFEF9A9A) : const Color(0xFFEF5350)).withValues(
              alpha: 0.3,
            )
            ..strokeWidth = 3.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

      final path = ui.Path();
      final first = canvasController.canvasToScreen(
        stroke.points.first.position,
      );
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        final p = canvasController.canvasToScreen(stroke.points[i].position);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, ghostPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EraserGhostPreviewPainter oldDelegate) => true;
}

/// 🎯 V5: Magnetic snap indicator — dashed line from cursor to snap point
class _MagneticSnapIndicatorPainter extends CustomPainter {
  final Offset cursorPos;
  final Offset snapTarget;
  final bool isDark;

  _MagneticSnapIndicatorPainter({
    required this.cursorPos,
    required this.snapTarget,
    this.isDark = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    final dist = (cursorPos - snapTarget).distance;
    if (dist < 2.0) return; // Too close, don't draw

    // Dashed line
    final dashPaint =
        Paint()
          ..color = (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00))
              .withValues(alpha: 0.7)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    // Draw dashed line manually
    final direction = (snapTarget - cursorPos);
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

    // Small circle at snap target
    final targetPaint =
        Paint()
          ..color = isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00)
          ..style = PaintingStyle.fill;
    canvas.drawCircle(snapTarget, 4.0, targetPaint);

    // Outline
    final outlinePaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
    canvas.drawCircle(snapTarget, 4.0, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _MagneticSnapIndicatorPainter oldDelegate) =>
      oldDelegate.cursorPos != cursorPos ||
      oldDelegate.snapTarget != snapTarget;
}

