part of '../../fluera_canvas_screen.dart';

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
          ..color = (isDark ? const Color(0xFF4DD0E1) : const Color(0xFF42A5F5)).withValues(
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
              ..color = isDark ? const Color(0xFF80DEEA) : const Color(0xFF64B5F6)
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
          ..color = (isDark ? const Color(0xFF4DD0E1) : const Color(0xFF26A69A)).withValues(
            alpha: 0.4,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final dotPaint =
        Paint()
          ..color = isDark ? const Color(0xFF80DEEA) : const Color(0xFF4DB6AC)
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
          color: isDark ? const Color(0xFF4DD0E1) : const Color(0xFF1E88E5),
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
          ..color = (isDark ? const Color(0xFF212121) : Colors.white).withValues(
            alpha: 0.9,
          );
    final borderPaint =
        Paint()
          ..color = isDark ? const Color(0xFF616161) : const Color(0xFFE0E0E0)
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
          ..color = (isDark ? const Color(0xFF424242) : const Color(0xFFEEEEEE))
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
          ..color = (isDark ? const Color(0xFF757575) : const Color(0xFFBDBDBD)).withValues(
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
          ..color = isDark ? const Color(0xFF4DD0E1) : const Color(0xFF2196F3)
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
          color: isDark ? const Color(0xFF9E9E9E) : const Color(0xFF757575),
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
