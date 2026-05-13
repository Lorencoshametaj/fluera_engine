part of '../../fluera_canvas_screen.dart';

// ═══════════════════════════════════════
// 🎨 Canvas Layer — Custom Painters (Sections, TechPen, Section preview)
//
// ⚠️ The `_RemoteLiveStrokesPainter` and `_PdfLoadingPlaceholderPainter`
// previously defined here have been extracted to
// `lib/src/rendering/canvas/collab_overlay_painters.dart` as public
// `RemoteLiveStrokesPainter` / `PdfLoadingPlaceholderPainter` so that
// [FlueraCanvasView] (outside this library) can use the same FX.
// The data class `PdfLoadingPlaceholder` has likewise been made public.
// ═══════════════════════════════════════

// _PdfLoadingPlaceholderPainter moved to
// `lib/src/rendering/canvas/collab_overlay_painters.dart` as public
// `PdfLoadingPlaceholderPainter` — the one used by both the screen
// (via `PdfLoadingPlaceholderPainter(...)` after the rename) and
// `FlueraCanvasView`.


/// Highlight painter for section drag/resize visual feedback.
class _SectionHighlightPainter extends CustomPainter {
  final SectionNode section;
  final InfiniteCanvasController controller;
  final bool isResizing;

  _SectionHighlightPainter({
    required this.section,
    required this.controller,
    required this.isResizing,
  });

  static const _accentColor = Color(0xFF2196F3);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    final tx = section.worldTransform.getTranslation();
    final rect = Rect.fromLTWH(
      tx.x,
      tx.y,
      section.sectionSize.width,
      section.sectionSize.height,
    );
    final invScale = 1.0 / controller.scale;
    final cr = section.cornerRadius;

    // 1. Translucent highlight fill
    final fillPaint =
        Paint()
          ..color = _accentColor.withValues(alpha: 0.05)
          ..style = PaintingStyle.fill;
    if (cr > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cr)),
        fillPaint,
      );
    } else {
      canvas.drawRect(rect, fillPaint);
    }

    // 2. Glowing blue border
    final borderPaint =
        Paint()
          ..color = _accentColor.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * invScale
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 * invScale);
    if (cr > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cr)),
        borderPaint,
      );
    } else {
      canvas.drawRect(rect, borderPaint);
    }

    // Solid border on top
    final solidPaint =
        Paint()
          ..color = _accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * invScale;
    if (cr > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cr)),
        solidPaint,
      );
    } else {
      canvas.drawRect(rect, solidPaint);
    }

    // 3. Corner handles highlighted during resize
    if (isResizing) {
      final handleRadius = 5.0 * invScale;
      final handlePaint = Paint()..color = _accentColor;
      final handleRing =
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * invScale;
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ]) {
        canvas.drawCircle(corner, handleRadius, handlePaint);
        canvas.drawCircle(corner, handleRadius, handleRing);
      }
    }

    // 4. Real-time dimension badge
    final w = rect.width.round();
    final h = rect.height.round();
    final label = isResizing ? '↔ $w × $h' : '✥ ${section.sectionName}';
    final labelFontSize = 11.0 * invScale;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: labelFontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelX = rect.center.dx - tp.width / 2;
    final labelY = rect.bottom + 8.0 * invScale;
    final padH = 8.0 * invScale;
    final padV = 4.0 * invScale;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelX - padH,
        labelY - padV,
        tp.width + padH * 2,
        tp.height + padV * 2,
      ),
      Radius.circular(6.0 * invScale),
    );
    canvas.drawRRect(badgeRect, Paint()..color = _accentColor);
    tp.paint(canvas, Offset(labelX, labelY));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SectionHighlightPainter oldDelegate) => true;
}

/// 📐 Paints technical pen visual guides: crosshair, protractor arc, snap line,
/// angle badge, length label, close-shape glow, and straight ghost.
class _TechPenGuidePainter extends CustomPainter {
  final Offset anchor;
  final double angleDeg;
  final double segmentLength;
  final InfiniteCanvasController controller;
  final Color color;
  final bool nearStartPoint;
  final Offset? startPoint;
  final Offset? straightGhostEnd;
  final List<Offset> intersections;

  _TechPenGuidePainter({
    required this.anchor,
    required this.angleDeg,
    required this.segmentLength,
    required this.controller,
    required this.color,
    this.nearStartPoint = false,
    this.startPoint,
    this.straightGhostEnd,
    this.intersections = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    final invScale = 1.0 / controller.scale;
    final angleRad = angleDeg * math.pi / 180.0;
    final dir = Offset(math.cos(angleRad), math.sin(angleRad));

    // ── 1. Crosshair at anchor ──
    final crossLen = 12.0 * invScale;
    final crossPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1.0 * invScale;
    canvas.drawLine(
      Offset(anchor.dx - crossLen, anchor.dy),
      Offset(anchor.dx + crossLen, anchor.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(anchor.dx, anchor.dy - crossLen),
      Offset(anchor.dx, anchor.dy + crossLen),
      crossPaint,
    );

    // ── 2. Protractor arc (from 0° reference to snapped angle) ──
    final arcRadius = 22.0 * invScale;
    final arcPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1.5 * invScale
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCircle(center: anchor, radius: arcRadius),
      0, // Start from 0° (right)
      angleRad, // Sweep to snapped angle
      false,
      arcPaint,
    );
    // Small filled dot at arc end
    final arcEndPaint = Paint()..color = color.withValues(alpha: 0.5);
    final arcEndPos = anchor + Offset(
      arcRadius * math.cos(angleRad),
      arcRadius * math.sin(angleRad),
    );
    canvas.drawCircle(arcEndPos, 2.0 * invScale, arcEndPaint);

    // ── 3. Dashed extension line ──
    final extLen = 2000.0;
    final dashPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 0.8 * invScale
      ..style = PaintingStyle.stroke;
    _drawDashed(canvas, anchor - dir * extLen, anchor + dir * extLen,
        dashPaint, 8.0 * invScale, 6.0 * invScale);

    // ── 4. Angle badge ──
    final displayAngle = ((angleDeg % 360) + 360) % 360;
    final niceDeg = displayAngle > 180 ? displayAngle - 360 : displayAngle;
    final angleText = '${niceDeg.round()}°';
    final badgeOffset = anchor + dir * (segmentLength * 0.5).clamp(30.0, 150.0);

    final padH = 6.0 * invScale;
    final padV = 3.0 * invScale;
    _drawBadge(canvas, angleText, badgeOffset + Offset(0, -14.0 * invScale),
        color.withValues(alpha: 0.7), Colors.white, 11.0 * invScale, padH, padV,
        bold: true);

    // ── 5. Length label ──
    if (segmentLength > 20.0) {
      final midpoint = anchor + dir * segmentLength * 0.5;
      _drawBadge(canvas, '${segmentLength.round()}px',
          midpoint + Offset(0, 12.0 * invScale),
          const Color(0xCC1A1A1A), Colors.white.withValues(alpha: 0.7),
          10.0 * invScale, padH, padV);
    }

    // ── 6. Close-shape glow: glowing circle at start point ──
    if (nearStartPoint && startPoint != null) {
      final glowPaint = Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8.0 * invScale);
      canvas.drawCircle(startPoint!, 10.0 * invScale, glowPaint);
      final ringPaint = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * invScale;
      canvas.drawCircle(startPoint!, 6.0 * invScale, ringPaint);
      // "Close" label
      _drawBadge(canvas, '⊕ Close',
          startPoint! + Offset(0, -18.0 * invScale),
          Colors.greenAccent.withValues(alpha: 0.8), Colors.white,
          9.0 * invScale, padH, padV, bold: true);
    }

    // ── 7. Straight ghost preview ──
    if (straightGhostEnd != null) {
      final ghostPaint = Paint()
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = 2.0 * invScale
        ..style = PaintingStyle.stroke;
      canvas.drawLine(anchor, straightGhostEnd!, ghostPaint);
    }

    // ── 8. Intersection markers ──
    for (final ix in intersections) {
      final ixRadius = 4.0 * invScale;
      // Orange diamond
      canvas.drawCircle(ix, ixRadius, Paint()..color = Colors.orangeAccent.withValues(alpha: 0.6));
      // White cross
      final crossP = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.0 * invScale;
      canvas.drawLine(
        Offset(ix.dx - ixRadius * 0.7, ix.dy),
        Offset(ix.dx + ixRadius * 0.7, ix.dy),
        crossP,
      );
      canvas.drawLine(
        Offset(ix.dx, ix.dy - ixRadius * 0.7),
        Offset(ix.dx, ix.dy + ixRadius * 0.7),
        crossP,
      );
    }

    canvas.restore();
  }

  void _drawBadge(Canvas canvas, String text, Offset center,
      Color bg, Color fg, double fontSize, double padH, double padV,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: fg,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final invScale = 1.0 / controller.scale;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: tp.width + padH * 2, height: tp.height + padV * 2),
      Radius.circular(4.0 * invScale),
    );
    canvas.drawRRect(rect, Paint()..color = bg);
    tp.paint(canvas, Offset(rect.left + padH, rect.top + padV));
  }

  void _drawDashed(Canvas canvas, Offset a, Offset b, Paint paint, double dash, double gap) {
    final delta = b - a;
    final length = delta.distance;
    if (length < 1) return;
    final ux = delta.dx / length;
    final uy = delta.dy / length;
    double drawn = 0;
    bool on = true;
    while (drawn < length) {
      final seg = on ? dash : gap;
      final len = math.min(seg, length - drawn);
      if (on) {
        canvas.drawLine(
          Offset(a.dx + ux * drawn, a.dy + uy * drawn),
          Offset(a.dx + ux * (drawn + len), a.dy + uy * (drawn + len)),
          paint,
        );
      }
      drawn += len;
      on = !on;
    }
  }

  @override
  bool shouldRepaint(covariant _TechPenGuidePainter old) =>
      anchor != old.anchor || angleDeg != old.angleDeg ||
      segmentLength != old.segmentLength || nearStartPoint != old.nearStartPoint ||
      straightGhostEnd != old.straightGhostEnd || intersections.length != old.intersections.length;
}

/// 🔲 Paints visible grid dots when techGridSnap is active.
class _TechPenGridPainter extends CustomPainter {
  final double gridSize;
  final InfiniteCanvasController controller;
  final Color color;

  _TechPenGridPainter({
    required this.gridSize,
    required this.controller,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    final invScale = 1.0 / controller.scale;
    // Calculate visible area in canvas coordinates
    final topLeft = Offset(-controller.offset.dx, -controller.offset.dy) * (1 / controller.scale);
    final botRight = topLeft + Offset(size.width, size.height) * invScale;

    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final startX = (topLeft.dx / gridSize).floor() * gridSize;
    final startY = (topLeft.dy / gridSize).floor() * gridSize;
    final dotRadius = 1.2 * invScale;

    for (double x = startX; x <= botRight.dx; x += gridSize) {
      for (double y = startY; y <= botRight.dy; y += gridSize) {
        canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TechPenGridPainter old) =>
      gridSize != old.gridSize;
}
