part of '../../nebula_canvas_screen.dart';

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
