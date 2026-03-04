part of '../../fluera_canvas_screen.dart';

// ═══════════════════════════════════════
// 🎨 Canvas Layer — Custom Painters (Remote Strokes, PDF Loading, Sections)
// ═══════════════════════════════════════


/// ☁️ Paints live strokes from remote collaborators as simple polylines.
class _RemoteLiveStrokesPainter extends CustomPainter {
  final Map<String, List<Offset>> strokes;
  final Map<String, int> colors;
  final Map<String, double> widths;
  final InfiniteCanvasController controller;

  _RemoteLiveStrokesPainter({
    required this.strokes,
    required this.colors,
    required this.widths,
    required this.controller,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    for (final entry in strokes.entries) {
      final points = entry.value;
      if (points.length < 2) continue;

      final color = Color(colors[entry.key] ?? 0xFF42A5F5);
      final width = widths[entry.key] ?? 2.0;

      final paint =
          Paint()
            ..color = color.withValues(alpha: 0.6)
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RemoteLiveStrokesPainter oldDelegate) => true;
}

/// 📄 Paints loading placeholders for remote PDFs being uploaded.
class _PdfLoadingPlaceholderPainter extends CustomPainter {
  final List<_PdfLoadingPlaceholder> placeholders;
  final InfiniteCanvasController controller;
  final double pulseValue;

  _PdfLoadingPlaceholderPainter({
    required this.placeholders,
    required this.controller,
    this.pulseValue = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (placeholders.isEmpty) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    for (final placeholder in placeholders) {
      final rect = placeholder.rect;

      // 🎬 Fade-in: opacity ramps from 0→1 over 300ms
      final age =
          DateTime.now().difference(placeholder.createdAt).inMilliseconds;
      final fadeOpacity = (age / 300.0).clamp(0.0, 1.0);

      // 🎯 Smooth progress lerp (0.08 factor ≈ smooth interpolation at 30fps)
      final targetProgress = placeholder.progress;
      final currentAnimated = _animatedProgress[placeholder.documentId] ?? 0.0;
      final animated =
          currentAnimated + (targetProgress - currentAnimated) * 0.08;
      _animatedProgress[placeholder.documentId] = animated;

      // 📸 Thumbnail preview — decode and render as blurred background
      final thumbB64 = placeholder.thumbnailBase64;
      if (thumbB64 != null &&
          _decodedThumbnails.containsKey(placeholder.documentId)) {
        final thumbImage = _decodedThumbnails[placeholder.documentId]!;
        final srcRect = Rect.fromLTWH(
          0,
          0,
          thumbImage.width.toDouble(),
          thumbImage.height.toDouble(),
        );
        final thumbPaint =
            Paint()
              ..color = Colors.white.withValues(alpha: 0.4 * fadeOpacity)
              ..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3);
        canvas.save();
        canvas.clipRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        );
        canvas.drawImageRect(thumbImage, srcRect, rect, thumbPaint);
        canvas.restore();
      } else if (thumbB64 != null &&
          !_thumbnailDecodeRequested.contains(placeholder.documentId)) {
        _thumbnailDecodeRequested.add(placeholder.documentId);
        _decodeThumbnail(placeholder.documentId, thumbB64);
      }

      // Background — subtle shimmer
      final alpha = (0.08 + 0.04 * pulseValue) * fadeOpacity;
      final bgPaint =
          Paint()
            ..color = Colors.white.withValues(alpha: alpha)
            ..style = PaintingStyle.fill;
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      canvas.drawRRect(rrect, bgPaint);

      // Border
      final borderPaint =
          Paint()
            ..color = Colors.white.withValues(alpha: 0.3 * fadeOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
      canvas.drawRRect(rrect, borderPaint);

      // Loading icon (circular indicator) — centered
      final center = rect.center;
      final indicatorRadius = 20.0;
      final indicatorPaint =
          Paint()
            ..color = Colors.white.withValues(alpha: 0.5 * fadeOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0
            ..strokeCap = StrokeCap.round;

      // Draw arc that rotates with pulse
      final sweepAngle = 3.14 * 1.5;
      final startAngle = pulseValue * 3.14 * 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: indicatorRadius),
        startAngle,
        sweepAngle,
        false,
        indicatorPaint,
      );

      // Progress bar — shown when animated progress > 0.01
      if (animated > 0.01) {
        final barWidth = rect.width * 0.6;
        final barHeight = 6.0;
        final barLeft = center.dx - barWidth / 2;
        final barTop = center.dy + indicatorRadius + 8;

        // Background track
        final trackPaint =
            Paint()
              ..color = Colors.white.withValues(alpha: 0.15 * fadeOpacity)
              ..style = PaintingStyle.fill;
        final trackRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(barLeft, barTop, barWidth, barHeight),
          const Radius.circular(3),
        );
        canvas.drawRRect(trackRect, trackPaint);

        // Fill (using animated lerped value)
        final fillPaint =
            Paint()
              ..color = Colors.white.withValues(alpha: 0.6 * fadeOpacity)
              ..style = PaintingStyle.fill;
        final fillRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(barLeft, barTop, barWidth * animated, barHeight),
          const Radius.circular(3),
        );
        canvas.drawRRect(fillRect, fillPaint);
      }

      // Label text
      final label = placeholder.fileName ?? 'PDF';
      final pct = animated > 0.01 ? ' ${(animated * 100).toInt()}%' : '';
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Loading $label...$pct',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6 * fadeOpacity),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 40);

      final labelTop =
          animated > 0.01
              ? center.dy + indicatorRadius + 22
              : center.dy + indicatorRadius + 16;

      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2, labelTop),
      );

      // Page count badge
      final countPainter = TextPainter(
        text: TextSpan(
          text: '${placeholder.pageCount} pages',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4 * fadeOpacity),
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      countPainter.paint(
        canvas,
        Offset(
          center.dx - countPainter.width / 2,
          labelTop + textPainter.height + 6,
        ),
      );
    }

    canvas.restore();
  }

  // 📸 Static thumbnail decode cache — shared across painter instances
  static final Map<String, ui.Image> _decodedThumbnails = {};
  static final Set<String> _thumbnailDecodeRequested = {};
  // 🎯 Animated progress cache for smooth lerp
  static final Map<String, double> _animatedProgress = {};

  /// Async decode base64 PNG thumbnail → cache for next paint.
  static void _decodeThumbnail(String docId, String base64Str) async {
    try {
      final bytes = base64Decode(base64Str);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _decodedThumbnails[docId] = frame.image;
      codec.dispose();
    } catch (e) {}
  }

  @override
  bool shouldRepaint(covariant _PdfLoadingPlaceholderPainter oldDelegate) =>
      true;
}

/// 📐 Paints a live preview rectangle while dragging to create a section.
/// Includes dashed border, corner marks, translucent fill, and dimension label.
class _SectionPreviewPainter extends CustomPainter {
  final Offset startPoint;
  final Offset endPoint;
  final InfiniteCanvasController controller;

  _SectionPreviewPainter({
    required this.startPoint,
    required this.endPoint,
    required this.controller,
  });

  static const _accentColor = Color(0xFF2196F3);
  static const _cornerLength = 14.0;
  static const _cornerStroke = 2.5;
  static const _dashLength = 6.0;
  static const _dashGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(startPoint, endPoint);
    if (rect.width < 2 && rect.height < 2) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    // 1. Translucent fill
    final fillPaint =
        Paint()
          ..color = _accentColor.withValues(alpha: 0.06)
          ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    // 2. Dashed border
    final borderPaint =
        Paint()
          ..color = _accentColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 / controller.scale;
    _drawDashedRect(canvas, rect, borderPaint);

    // 3. Corner marks (solid, thicker)
    final cornerPaint =
        Paint()
          ..color = _accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _cornerStroke / controller.scale
          ..strokeCap = StrokeCap.round;
    final cl = _cornerLength / controller.scale;
    _drawCornerMarks(canvas, rect, cornerPaint, cl);

    // 4. Dimension label
    final w = rect.width.round();
    final h = rect.height.round();
    if (w > 10 && h > 10) {
      final labelFontSize = 11.0 / controller.scale;
      final tp = TextPainter(
        text: TextSpan(
          text: '$w × $h',
          style: TextStyle(
            color: _accentColor,
            fontSize: labelFontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Position: centered at bottom of rect, slightly below
      final labelX = rect.center.dx - tp.width / 2;
      final labelY = rect.bottom + 6.0 / controller.scale;

      // Background pill
      final labelPadH = 6.0 / controller.scale;
      final labelPadV = 3.0 / controller.scale;
      final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          labelX - labelPadH,
          labelY - labelPadV,
          tp.width + labelPadH * 2,
          tp.height + labelPadV * 2,
        ),
        Radius.circular(4.0 / controller.scale),
      );
      canvas.drawRRect(labelRect, Paint()..color = const Color(0xE0121212));

      tp.paint(canvas, Offset(labelX, labelY));
    }

    canvas.restore();
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    final invScale = 1.0 / controller.scale;
    final dash = _dashLength * invScale;
    final gap = _dashGap * invScale;

    // Top edge
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, dash, gap);
    // Right edge
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint, dash, gap);
    // Bottom edge
    _drawDashedLine(
      canvas,
      rect.bottomRight,
      rect.bottomLeft,
      paint,
      dash,
      gap,
    );
    // Left edge
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint, dash, gap);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dashLen,
    double gapLen,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = Offset(dx, dy).distance;
    if (length < 1) return;
    final ux = dx / length;
    final uy = dy / length;

    double drawn = 0;
    bool drawing = true;
    while (drawn < length) {
      final segLen = drawing ? dashLen : gapLen;
      final remaining = length - drawn;
      final len = segLen < remaining ? segLen : remaining;

      if (drawing) {
        canvas.drawLine(
          Offset(start.dx + ux * drawn, start.dy + uy * drawn),
          Offset(start.dx + ux * (drawn + len), start.dy + uy * (drawn + len)),
          paint,
        );
      }
      drawn += len;
      drawing = !drawing;
    }
  }

  void _drawCornerMarks(Canvas canvas, Rect rect, Paint paint, double len) {
    // Top-left
    canvas.drawLine(rect.topLeft, Offset(rect.left + len, rect.top), paint);
    canvas.drawLine(rect.topLeft, Offset(rect.left, rect.top + len), paint);
    // Top-right
    canvas.drawLine(rect.topRight, Offset(rect.right - len, rect.top), paint);
    canvas.drawLine(rect.topRight, Offset(rect.right, rect.top + len), paint);
    // Bottom-left
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left + len, rect.bottom),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left, rect.bottom - len),
      paint,
    );
    // Bottom-right
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right - len, rect.bottom),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right, rect.bottom - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SectionPreviewPainter oldDelegate) =>
      startPoint != oldDelegate.startPoint || endPoint != oldDelegate.endPoint;
}

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
