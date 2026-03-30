part of 'pdf_reader_screen.dart';

// =============================================================================
// Painters
// =============================================================================

/// Draws the pre-rendered PDF page image.
class _DirectPagePainter extends CustomPainter {
  final ui.Image image;
  final bool isZoomed;
  _DirectPagePainter({required this.image, this.isZoomed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, src, dst,
      Paint()..filterQuality = isZoomed ? FilterQuality.medium : FilterQuality.high);
  }

  @override
  bool shouldRepaint(_DirectPagePainter old) =>
      !identical(old.image, image) || old.isZoomed != isZoomed;
}

/// Draws a bookmark ribbon (flag shape).
class _BookmarkRibbonPainter extends CustomPainter {
  final Color color;
  _BookmarkRibbonPainter({this.color = const Color(0xFFEF5350)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0) ..lineTo(size.width, 0) ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.72) ..lineTo(0, size.height) ..close();
    final shadowPaint = Paint()..color = const Color(0x40000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BookmarkRibbonPainter old) => old.color != color;
}

/// Draws annotation strokes on top of a PDF page.
class _AnnotationOverlayPainter extends CustomPainter {
  final List<ProStroke> strokes;
  final List<ProDrawingPoint>? livePoints;
  final Color liveColor;
  final double liveWidth;
  final ProPenType livePenType;
  final Size pageOriginalSize;
  final Size displaySize;
  final Rect? visibleRect;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final ShapeType shapeType;
  final ProBrushSettings liveBrushSettings;
  final ui.Image? pageImage;
  final bool isZoomed;

  _AnnotationOverlayPainter({
    required this.strokes, this.livePoints, required this.liveColor, required this.liveWidth,
    required this.livePenType, required this.pageOriginalSize, required this.displaySize,
    this.visibleRect, this.shapeStart, this.shapeEnd, this.shapeType = ShapeType.freehand,
    this.liveBrushSettings = const ProBrushSettings(), this.pageImage, this.isZoomed = false,
    ValueNotifier<int>? repaintNotifier,
  }) : super(repaint: repaintNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (pageImage != null) {
      final src = Rect.fromLTWH(0, 0, pageImage!.width.toDouble(), pageImage!.height.toDouble());
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(pageImage!, src, dst,
        Paint()..filterQuality = isZoomed ? FilterQuality.medium : FilterQuality.high);
    }

    final sx = displaySize.width / pageOriginalSize.width;
    final sy = displaySize.height / pageOriginalSize.height;
    canvas.save(); canvas.scale(sx, sy);

    for (final stroke in strokes) {
      if (visibleRect != null && !stroke.bounds.overlaps(visibleRect!)) continue;
      BrushEngine.renderStroke(canvas, stroke.points, stroke.color, stroke.baseWidth, stroke.penType, stroke.settings, engineVersion: stroke.engineVersion);
    }

    if (livePoints != null && livePoints!.length >= 2) {
      BrushEngine.renderStroke(canvas, livePoints!, liveColor, liveWidth, livePenType, liveBrushSettings, isLive: true);
    }

    if (shapeStart != null && shapeEnd != null && shapeType != ShapeType.freehand) {
      _drawShapePreview(canvas, shapeStart!, shapeEnd!, shapeType);
    }
    canvas.restore();
  }

  void _drawShapePreview(Canvas canvas, Offset start, Offset end, ShapeType type) {
    final paint = Paint()..color = liveColor..strokeWidth = liveWidth..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    switch (type) {
      case ShapeType.freehand: break;
      case ShapeType.line: canvas.drawLine(start, end, paint); break;
      case ShapeType.rectangle: canvas.drawRect(Rect.fromPoints(start, end), paint); break;
      case ShapeType.circle: canvas.drawOval(Rect.fromPoints(start, end), paint); break;
      case ShapeType.arrow:
        canvas.drawLine(start, end, paint);
        final dx = end.dx - start.dx; final dy = end.dy - start.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > 1) {
          final nx = dx / len; final ny = dy / len;
          final headLen = len * 0.2; final headW = headLen * 0.6;
          final path = ui.Path()
            ..moveTo(end.dx - nx * headLen - ny * headW, end.dy - ny * headLen + nx * headW)
            ..lineTo(end.dx, end.dy)
            ..lineTo(end.dx - nx * headLen + ny * headW, end.dy - ny * headLen - nx * headW);
          canvas.drawPath(path, paint);
        }
        break;
      default:
        final path = ui.Path();
        final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final rx = (end.dx - start.dx).abs() / 2; final ry = (end.dy - start.dy).abs() / 2;
        List<Offset> pts;
        switch (type) {
          case ShapeType.triangle: pts = [Offset(center.dx, start.dy), Offset(end.dx, end.dy), Offset(start.dx, end.dy), Offset(center.dx, start.dy)]; break;
          case ShapeType.star:
            pts = []; for (int i = 0; i <= 10; i++) { final angle = math.pi / 2 + (2 * math.pi * i / 10); final r = i.isEven ? 1.0 : 0.4; pts.add(Offset(center.dx + rx * r * math.cos(angle), center.dy - ry * r * math.sin(angle))); } break;
          case ShapeType.diamond: pts = [Offset(center.dx, start.dy), Offset(end.dx, center.dy), Offset(center.dx, end.dy), Offset(start.dx, center.dy), Offset(center.dx, start.dy)]; break;
          case ShapeType.pentagon: pts = List.generate(6, (i) { final angle = -math.pi / 2 + 2 * math.pi * i / 5; return Offset(center.dx + rx * math.cos(angle), center.dy + ry * math.sin(angle)); }); break;
          case ShapeType.hexagon: pts = List.generate(7, (i) { final angle = 2 * math.pi * i / 6; return Offset(center.dx + rx * math.cos(angle), center.dy + ry * math.sin(angle)); }); break;
          case ShapeType.heart: pts = List.generate(37, (i) { final t = 2 * math.pi * i / 36; return Offset(center.dx + rx * 16 * math.pow(math.sin(t), 3) / 16, center.dy - ry * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) / 16); }); break;
          default: pts = [];
        }
        if (pts.length >= 2) { path.moveTo(pts.first.dx, pts.first.dy); for (int i = 1; i < pts.length; i++) { path.lineTo(pts[i].dx, pts[i].dy); } canvas.drawPath(path, paint); }
    }
  }

  @override
  bool shouldRepaint(_AnnotationOverlayPainter old) {
    return old.strokes.length != strokes.length || !identical(old.pageImage, pageImage) ||
      old.visibleRect != visibleRect || old.liveColor != liveColor || old.liveWidth != liveWidth ||
      old.livePenType != livePenType || old.shapeStart != shapeStart || old.shapeEnd != shapeEnd ||
      old.shapeType != shapeType || old.isZoomed != isZoomed;
  }
}

/// Shimmer loading placeholder for pages not yet rendered.
class _PageShimmer extends StatefulWidget {
  const _PageShimmer();
  @override
  State<_PageShimmer> createState() => _PageShimmerState();
}

class _PageShimmerState extends State<_PageShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _controller, builder: (context, child) {
      return DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
        end: Alignment(-0.5 + 2.0 * _controller.value, 0),
        colors: const [Color(0x08FFFFFF), Color(0x18FFFFFF), Color(0x08FFFFFF)])));
    });
  }
}

// =============================================================================
// Text Highlight Painter
// =============================================================================

class _TextHighlightPainter extends CustomPainter {
  final List<PdfTextRect> selectionSpans;
  final List<Rect> searchHighlights;
  final Rect? currentSearchHighlight;

  _TextHighlightPainter({required this.selectionSpans, this.searchHighlights = const [], this.currentSearchHighlight});

  @override
  void paint(Canvas canvas, Size size) {
    if (searchHighlights.isNotEmpty) {
      final searchPaint = Paint()..color = const Color(0x55FFEB3B)..style = PaintingStyle.fill;
      for (final r in searchHighlights) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height), const Radius.circular(2)), searchPaint);
      }
    }
    if (currentSearchHighlight != null) {
      final r = currentSearchHighlight!;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height), const Radius.circular(2)),
        Paint()..color = const Color(0x88FF9800)..style = PaintingStyle.fill);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height), const Radius.circular(2)),
        Paint()..color = const Color(0xCCFF9800)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
    if (selectionSpans.isNotEmpty) {
      final selPaint = Paint()..color = const Color(0x444FC3F7)..style = PaintingStyle.fill;
      for (final span in selectionSpans) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(span.rect.left * size.width, span.rect.top * size.height, span.rect.right * size.width, span.rect.bottom * size.height), const Radius.circular(2)), selPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_TextHighlightPainter old) =>
    selectionSpans != old.selectionSpans || searchHighlights != old.searchHighlights || currentSearchHighlight != old.currentSearchHighlight;
}
