part of '../nebula_canvas_screen.dart';

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
            isDark ? Colors.orange[300]! : Colors.orange[400]!,
            isDark ? Colors.red[300]! : Colors.red[400]!,
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
              ..color = (isDark ? Colors.red[200]! : Colors.red[300]!)
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
            ..color = (isDark ? Colors.red[200]! : Colors.red[400]!).withValues(
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
          ..color = (isDark ? Colors.red[300]! : Colors.red[400]!).withValues(
            alpha: fillAlpha,
          )
          ..style = PaintingStyle.fill;

    final strokePaint =
        Paint()
          ..color = isDark ? Colors.red[300]! : Colors.red[400]!
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
            ..color = (isDark ? Colors.blue[300]! : Colors.blue[400]!)
                .withValues(alpha: 0.12)
            ..style = PaintingStyle.fill;

      // Dashed blue border
      final borderPaint =
          Paint()
            ..color = isDark ? Colors.blue[300]! : Colors.blue[400]!
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
            ..color = (isDark ? Colors.red[200]! : Colors.red[400]!).withValues(
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
          ..color = (isDark ? Colors.orange[300]! : Colors.orange[600]!)
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
          ..color = isDark ? Colors.orange[300]! : Colors.orange[600]!
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

// ═══════════════════════════════════════════════════════════════════
// V6 PAINTERS
// ═══════════════════════════════════════════════════════════════════

/// 🎯 V6: Dissolve particles — burst effect at erased points
class _DissolveParticlesPainter extends CustomPainter {
  final List<Offset> points;
  final InfiniteCanvasController canvasController;
  final bool isDark;

  _DissolveParticlesPainter({
    required this.points,
    required this.canvasController,
    this.isDark = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    final rng = math.Random(42);
    for (final pt in points) {
      final screenPt = canvasController.canvasToScreen(pt);
      // 8 particles per erase point
      for (int i = 0; i < 8; i++) {
        final angle = rng.nextDouble() * math.pi * 2;
        final dist = 4.0 + rng.nextDouble() * 18.0;
        final px = screenPt.dx + math.cos(angle) * dist;
        final py = screenPt.dy + math.sin(angle) * dist;
        final alpha = (1.0 - dist / 22.0).clamp(0.0, 1.0);
        final paint =
            Paint()
              ..color = (isDark ? Colors.red[200]! : Colors.red[400]!)
                  .withValues(alpha: alpha * 0.6)
              ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(px, py), 1.5 + rng.nextDouble(), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DissolveParticlesPainter oldDelegate) => true;
}

/// 🎯 V6: Heatmap trail — colors trail by touch frequency
class _HeatmapTrailPainter extends CustomPainter {
  final List<_EraserTrailPoint> trail;
  final EraserTool eraserTool;
  final InfiniteCanvasController canvasController;

  _HeatmapTrailPainter({
    required this.trail,
    required this.eraserTool,
    required this.canvasController,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    for (int i = 0; i < trail.length; i++) {
      final pt = canvasController.canvasToScreen(trail[i].position);
      final intensity = eraserTool.getHeatmapIntensity(trail[i].position);
      // Cold (blue) → warm (yellow) → hot (red)
      final color =
          Color.lerp(
            Color.lerp(Colors.blue[300]!, Colors.yellow[600]!, intensity),
            Colors.red[500]!,
            (intensity - 0.5).clamp(0.0, 1.0) * 2,
          )!;
      final age = i / trail.length; // 0=oldest, 1=newest
      final paint =
          Paint()
            ..color = color.withValues(alpha: 0.15 + age * 0.25)
            ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, 4.0 + age * 4.0, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapTrailPainter oldDelegate) => true;
}

/// 🎯 V6: Mask preview — shows erase radius coverage on full canvas
class _EraserMaskPreviewPainter extends CustomPainter {
  final Offset cursorPos;
  final double radius;
  final bool isDark;

  _EraserMaskPreviewPainter({
    required this.cursorPos,
    required this.radius,
    this.isDark = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    // Semi-transparent overlay with a clear circle at cursor
    final overlayPaint =
        Paint()
          ..color = (isDark ? Colors.black : Colors.white).withValues(
            alpha: 0.15,
          );
    canvas.drawRect(Offset.zero & size, overlayPaint);

    // Cut out the erase region
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = (isDark ? Colors.black : Colors.white).withValues(
          alpha: 0.15,
        ),
    );
    canvas.drawCircle(cursorPos, radius, clearPaint);
    canvas.restore();

    // Subtle ring around the clear zone
    final ringPaint =
        Paint()
          ..color = (isDark ? Colors.red[200]! : Colors.red[400]!).withValues(
            alpha: 0.3,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
    canvas.drawCircle(cursorPos, radius, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _EraserMaskPreviewPainter oldDelegate) =>
      oldDelegate.cursorPos != cursorPos || oldDelegate.radius != radius;
}

/// 🎯 V6: Auto-clean highlight — pulsing glow on suggested strokes
class _AutoCleanHighlightPainter extends CustomPainter {
  final Set<String> suggestionIds;
  final LayerController layerController;
  final InfiniteCanvasController canvasController;
  final bool isDark;

  _AutoCleanHighlightPainter({
    required this.suggestionIds,
    required this.layerController,
    required this.canvasController,
    this.isDark = false,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    if (suggestionIds.isEmpty) return;
    final activeLayer = layerController.activeLayer;
    if (activeLayer == null) return;

    for (final stroke in activeLayer.strokes) {
      if (!suggestionIds.contains(stroke.id)) continue;
      if (stroke.points.length < 2) continue;

      final highlightPaint =
          Paint()
            ..color = (isDark ? Colors.amber[300]! : Colors.amber[600]!)
                .withValues(alpha: 0.5)
            ..strokeWidth = 4.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

      final path = ui.Path();
      final first = canvasController.canvasToScreen(
        stroke.points.first.position,
      );
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        final p = canvasController.canvasToScreen(stroke.points[i].position);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AutoCleanHighlightPainter oldDelegate) => true;
}

/// 🎯 V6: History timeline — horizontal strip showing stroke count over time
class _EraserHistoryTimelinePainter extends CustomPainter {
  final List<(DateTime, int)> snapshots;
  final bool isDark;

  _EraserHistoryTimelinePainter({required this.snapshots, this.isDark = false});

  @override
  void paint(ui.Canvas canvas, Size size) {
    if (snapshots.isEmpty) return;

    // Background track
    final trackPaint =
        Paint()
          ..color = (isDark ? Colors.grey[800]! : Colors.grey[200]!).withValues(
            alpha: 0.6,
          )
          ..style = PaintingStyle.fill;
    final trackRRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(trackRRect, trackPaint);

    // Find max stroke count for normalization
    int maxCount = 1;
    for (final (_, count) in snapshots) {
      if (count > maxCount) maxCount = count;
    }

    // Draw bars
    final barWidth = (size.width - 8) / snapshots.length;
    for (int i = 0; i < snapshots.length; i++) {
      final (_, count) = snapshots[i];
      final ratio = count / maxCount;
      final barHeight = (size.height - 8) * ratio;
      final x = 4 + i * barWidth;
      final y = size.height - 4 - barHeight;

      final barPaint =
          Paint()
            ..color = Color.lerp(
              Colors.green[400]!,
              Colors.red[400]!,
              1.0 - ratio, // More red when fewer strokes (more erased)
            )!.withValues(alpha: 0.7)
            ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth - 2, barHeight),
          const Radius.circular(2),
        ),
        barPaint,
      );
    }

    // Label
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${snapshots.length} snapshots',
        style: TextStyle(
          color: isDark ? Colors.grey[500] : Colors.grey[600],
          fontSize: 8,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(6, 2));
  }

  @override
  bool shouldRepaint(covariant _EraserHistoryTimelinePainter oldDelegate) =>
      oldDelegate.snapshots.length != snapshots.length;
}

// ═══════════════════════════════════════════════════════════════════
// V7 PAINTERS
// ═══════════════════════════════════════════════════════════════════

/// V7: Undo ghost replay — draws semi-transparent strokes fading in
class _UndoGhostReplayPainter extends CustomPainter {
  final List<ProStroke> ghostStrokes;
  final double progress; // 0..1
  final InfiniteCanvasController canvasController;
  final bool isDark;

  _UndoGhostReplayPainter({
    required this.ghostStrokes,
    required this.progress,
    required this.canvasController,
    required this.isDark,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    if (ghostStrokes.isEmpty || progress <= 0) return;
    final alpha = (progress * 0.6).clamp(0.0, 0.6);

    for (final stroke in ghostStrokes) {
      if (stroke.points.length < 2) continue;
      final paint =
          Paint()
            ..color = stroke.color.withValues(alpha: alpha)
            ..strokeWidth = stroke.baseWidth * canvasController.scale
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;

      // Draw only the portion of the stroke based on progress
      final pointCount = (stroke.points.length * progress).ceil().clamp(
        1,
        stroke.points.length,
      );
      final path = Path();
      final first = canvasController.canvasToScreen(
        stroke.points.first.position,
      );
      path.moveTo(first.dx, first.dy);

      for (int i = 1; i < pointCount; i++) {
        final pt = canvasController.canvasToScreen(stroke.points[i].position);
        path.lineTo(pt.dx, pt.dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _UndoGhostReplayPainter old) =>
      old.progress != progress ||
      old.ghostStrokes.length != ghostStrokes.length;
}

/// V7: Eraser shape cursor — rectangle or line shape
class _EraserShapeCursorPainter extends CustomPainter {
  final Offset center;
  final EraserShape shape;
  final double radius;
  final double shapeWidth;
  final double angle;
  final bool isDark;

  _EraserShapeCursorPainter({
    required this.center,
    required this.shape,
    required this.radius,
    required this.shapeWidth,
    required this.angle,
    required this.isDark,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = (isDark ? Colors.cyan[300]! : Colors.blue[400]!).withValues(
            alpha: 0.6,
          )
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    switch (shape) {
      case EraserShape.rectangle:
        final halfW = shapeWidth / 2;
        final halfH = radius;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(-halfW, -halfH, halfW, halfH),
            const Radius.circular(3),
          ),
          paint,
        );
        // Fill with low alpha
        paint.style = PaintingStyle.fill;
        paint.color = paint.color.withValues(alpha: 0.1);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(-halfW, -halfH, halfW, halfH),
            const Radius.circular(3),
          ),
          paint,
        );
        break;
      case EraserShape.line:
        final lineLen = radius;
        canvas.drawLine(
          Offset(-lineLen, 0),
          Offset(lineLen, 0),
          paint..strokeWidth = 3.0,
        );
        // End caps
        final dotPaint =
            Paint()
              ..color = isDark ? Colors.cyan[200]! : Colors.blue[300]!
              ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(-lineLen, 0), 3, dotPaint);
        canvas.drawCircle(Offset(lineLen, 0), 3, dotPaint);
        break;
      case EraserShape.circle:
        break; // Handled by default cursor
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EraserShapeCursorPainter old) =>
      old.center != center ||
      old.shape != shape ||
      old.angle != angle ||
      old.radius != radius ||
      old.shapeWidth != shapeWidth;
}

/// V7: Edge-aware highlight — glowing dots at stroke edge points
class _EdgeAwareHighlightPainter extends CustomPainter {
  final Map<String, Offset> edgePoints;
  final InfiniteCanvasController canvasController;
  final bool isDark;

  _EdgeAwareHighlightPainter({
    required this.edgePoints,
    required this.canvasController,
    required this.isDark,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    if (edgePoints.isEmpty) return;

    final glowPaint =
        Paint()
          ..color = (isDark ? Colors.cyan[300]! : Colors.teal[400]!).withValues(
            alpha: 0.4,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final dotPaint =
        Paint()
          ..color = isDark ? Colors.cyan[200]! : Colors.teal[300]!
          ..style = PaintingStyle.fill;

    for (final entry in edgePoints.entries) {
      final screenPos = canvasController.canvasToScreen(entry.value);
      // Glow
      canvas.drawCircle(screenPos, 8, glowPaint);
      // Dot
      canvas.drawCircle(screenPos, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgeAwareHighlightPainter old) =>
      old.edgePoints.length != edgePoints.length;
}

/// V7: Smart selection preview — highlight the entire selected stroke
class _SmartSelectionPreviewPainter extends CustomPainter {
  final String strokeId;
  final LayerController layerController;
  final InfiniteCanvasController canvasController;
  final bool isDark;

  _SmartSelectionPreviewPainter({
    required this.strokeId,
    required this.layerController,
    required this.canvasController,
    required this.isDark,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    final layer = layerController.activeLayer;
    if (layer == null) return;

    ProStroke? targetStroke;
    for (final stroke in layer.strokes) {
      if (stroke.id == strokeId) {
        targetStroke = stroke;
        break;
      }
    }
    if (targetStroke == null || targetStroke.points.length < 2) return;

    // Draw highlighted stroke with glow
    final glowPaint =
        Paint()
          ..color = Colors.amber.withValues(alpha: 0.3)
          ..strokeWidth = (targetStroke.baseWidth + 6) * canvasController.scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final highlightPaint =
        Paint()
          ..color = Colors.amber.withValues(alpha: 0.7)
          ..strokeWidth = (targetStroke.baseWidth + 2) * canvasController.scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

    final path = Path();
    final first = canvasController.canvasToScreen(
      targetStroke.points.first.position,
    );
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < targetStroke.points.length; i++) {
      final pt = canvasController.canvasToScreen(
        targetStroke.points[i].position,
      );
      path.lineTo(pt.dx, pt.dy);
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant _SmartSelectionPreviewPainter old) =>
      old.strokeId != strokeId;
}

/// V7: Layer preview dim — semi-transparent overlay indicating non-active layers
class _LayerPreviewDimPainter extends CustomPainter {
  final List<int> nonActiveIndices;
  final LayerController layerController;
  final InfiniteCanvasController canvasController;
  final bool isDark;

  _LayerPreviewDimPainter({
    required this.nonActiveIndices,
    required this.layerController,
    required this.canvasController,
    required this.isDark,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    if (nonActiveIndices.isEmpty) return;

    // Draw a dim overlay over the entire canvas
    final dimPaint =
        Paint()
          ..color = (isDark ? Colors.black : Colors.white).withValues(
            alpha: 0.35,
          );

    canvas.drawRect(Offset.zero & size, dimPaint);

    // Then draw a label
    final tp = TextPainter(
      text: TextSpan(
        text: 'Active layer only',
        style: TextStyle(
          color: isDark ? Colors.cyan[300] : Colors.blue[600],
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, 8));
  }

  @override
  bool shouldRepaint(covariant _LayerPreviewDimPainter old) =>
      old.nonActiveIndices.length != nonActiveIndices.length;
}

/// V7: Pressure curve editor — visualizes the Bézier curve
class _PressureCurveEditorPainter extends CustomPainter {
  final List<Offset> controlPoints;
  final bool isDark;

  _PressureCurveEditorPainter({
    required this.controlPoints,
    required this.isDark,
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    // Background
    final bgPaint =
        Paint()
          ..color = (isDark ? Colors.grey[900]! : Colors.white).withValues(
            alpha: 0.9,
          );
    final borderPaint =
        Paint()
          ..color = isDark ? Colors.grey[700]! : Colors.grey[300]!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      bgPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      borderPaint,
    );

    // Draw grid
    final gridPaint =
        Paint()
          ..color = (isDark ? Colors.grey[800]! : Colors.grey[200]!)
          ..strokeWidth = 0.5;
    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 8), Offset(x, size.height - 8), gridPaint);
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), gridPaint);
    }

    // Draw Bézier curve
    final padding = 12.0;
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;

    final p0 = Offset(padding, size.height - padding); // (0,0)
    final p3 = Offset(size.width - padding, padding); // (1,1)
    final p1 = Offset(
      padding + controlPoints[0].dx * w,
      size.height - padding - controlPoints[0].dy * h,
    );
    final p2 = Offset(
      padding + controlPoints[1].dx * w,
      size.height - padding - controlPoints[1].dy * h,
    );

    // Control point lines
    final cpLinePaint =
        Paint()
          ..color = (isDark ? Colors.grey[600]! : Colors.grey[400]!).withValues(
            alpha: 0.5,
          )
          ..strokeWidth = 1;
    canvas.drawLine(p0, p1, cpLinePaint);
    canvas.drawLine(p3, p2, cpLinePaint);

    // Curve
    final path = Path();
    path.moveTo(p0.dx, p0.dy);
    path.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);

    final curvePaint =
        Paint()
          ..color = isDark ? Colors.cyan[300]! : Colors.blue[500]!
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
    canvas.drawPath(path, curvePaint);

    // Control points
    final cpPaint =
        Paint()
          ..color = Colors.amber
          ..style = PaintingStyle.fill;
    canvas.drawCircle(p1, 4, cpPaint);
    canvas.drawCircle(p2, 4, cpPaint);

    // Labels
    final tp = TextPainter(
      text: TextSpan(
        text: 'Pressure curve',
        style: TextStyle(
          color: isDark ? Colors.grey[500] : Colors.grey[600],
          fontSize: 7,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(padding, 2));
  }

  @override
  bool shouldRepaint(covariant _PressureCurveEditorPainter old) =>
      old.controlPoints != controlPoints;
}
