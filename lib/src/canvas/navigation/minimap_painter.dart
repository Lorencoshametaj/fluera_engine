import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/shape_type.dart';
import '../../reflow/zone_labeler.dart';
import './content_bounds_tracker.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// 🗺️ Minimap Painters — split into Content + Viewport for performance.
//
// ARCHITECTURE:
// - [MinimapContentPainter]: draws background + content regions (strokes as
//   Catmull-Rom smooth paths, other nodes as rects). Lives inside its own
//   RepaintBoundary → only repaints when regions change.
// - [MinimapViewportPainter]: draws only the viewport position indicator.
//   Repaints on every camera pan/zoom — extremely cheap (single rect).
//
// PERFORMANCE:
// - Pre-allocated static Paint objects → zero per-frame allocations.
// - Reusable static Path → zero path allocations per stroke.
// - Stroke-region merging caps draw calls for many strokes.
// - Catmull-Rom interpolation for smooth stroke preview (few extra points).
// ═══════════════════════════════════════════════════════════════════════════════

// ── Shared constants & helpers ──────────────────────────────────────────────

/// When the number of stroke regions exceeds this, merge them into a
/// spatial grid instead of drawing each individually.
const int _kMergeThreshold = 200;

/// Adaptive grid resolution based on stroke count.
/// More strokes → finer grid for better spatial fidelity.
int _gridSizeForCount(int count) {
  if (count <= 100) return 2; // 2×2 = 4 cells
  if (count <= 300) return 4; // 4×4 = 16 cells
  if (count <= 800) return 6; // 6×6 = 36 cells
  return 8; // 8×8 = 64 cells max
}

/// Node type → color mapping (JARVIS HUD cyan palette).
const Map<ContentNodeType, Color> _nodeColors = {
  ContentNodeType.stroke: Color(0xCC60B0E8),  // Cyan blue
  ContentNodeType.shape: Color(0xCC50D0A0),   // Teal
  ContentNodeType.text: Color(0xCC82C8FF),    // Neon cyan
  ContentNodeType.image: Color(0xCCB0A050),   // Amber muted
  ContentNodeType.pdf: Color(0xCCD06058),      // Warm red (dim)
  ContentNodeType.other: Color(0xCC5A8CB8),   // Muted cyan
};

/// Compute the world→minimap mapping parameters.
/// Returns (scale, offsetX, offsetY, expandedBounds) or null if invalid.
({double scale, double offsetX, double offsetY, Rect expandedBounds})?
_computeMapping(Rect contentBounds, double width, double height) {
  if (contentBounds.isEmpty || !contentBounds.isFinite) return null;

  const padding = 8.0;
  final drawArea = Rect.fromLTWH(
    padding,
    padding,
    width - padding * 2,
    height - padding * 2,
  );

  final expandedBounds = contentBounds.inflate(
    contentBounds.shortestSide * 0.1,
  );

  final scaleX = drawArea.width / expandedBounds.width;
  final scaleY = drawArea.height / expandedBounds.height;
  final scale = scaleX < scaleY ? scaleX : scaleY;

  final scaledW = expandedBounds.width * scale;
  final scaledH = expandedBounds.height * scale;
  final offsetX = drawArea.left + (drawArea.width - scaledW) / 2;
  final offsetY = drawArea.top + (drawArea.height - scaledH) / 2;

  return (
    scale: scale,
    offsetX: offsetX,
    offsetY: offsetY,
    expandedBounds: expandedBounds,
  );
}

/// Transform a world-space rect to minimap-space.
Rect _worldToMinimap(
  Rect world,
  double scale,
  double offsetX,
  double offsetY,
  Rect expandedBounds,
) {
  return Rect.fromLTWH(
    offsetX + (world.left - expandedBounds.left) * scale,
    offsetY + (world.top - expandedBounds.top) * scale,
    world.width * scale,
    world.height * scale,
  );
}

/// Transform a world-space point to minimap-space.
Offset _worldPtToMinimap(
  Offset world,
  double scale,
  double offsetX,
  double offsetY,
  Rect expandedBounds,
) {
  return Offset(
    offsetX + (world.dx - expandedBounds.left) * scale,
    offsetY + (world.dy - expandedBounds.top) * scale,
  );
}

/// Lightweight fingerprint for region list: length + first/last bounds.
int _regionFingerprint(List<ContentRegion> regions) {
  if (regions.isEmpty) return 0;
  return Object.hash(regions.length, regions.first.bounds, regions.last.bounds);
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONTENT PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Painter for the minimap content layer (background + strokes + nodes).
///
/// Lives inside a [RepaintBoundary] — only repaints when content changes.
class MinimapContentPainter extends CustomPainter {
  final List<ContentRegion> regions;
  final Rect contentBounds;
  final double minimapWidth;
  final double minimapHeight;
  final Color canvasBackground;

  // ── Pre-allocated paints ─────────────────────────────────────────────────
  // NOTE: Background is now drawn by _MinimapHudFramePainter (dark glass).
  // This painter only draws content regions on a transparent surface.
  static final Paint _nodePaint = Paint();

  static final Paint _strokePathPaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

  /// Reusable path object — reset + reused per stroke (zero alloc).
  static final ui.Path _reusablePath = ui.Path();

  MinimapContentPainter({
    required this.regions,
    required this.contentBounds,
    required this.minimapWidth,
    required this.minimapHeight,
    this.canvasBackground = Colors.white,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background drawn by _MinimapHudFramePainter — just clip to panel.
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgRRect = RRect.fromRectAndRadius(bgRect, const Radius.circular(10));
    canvas.clipRRect(bgRRect);

    final mapping = _computeMapping(contentBounds, minimapWidth, minimapHeight);
    if (mapping == null) return;

    final (:scale, :offsetX, :offsetY, :expandedBounds) = mapping;

    // ── Separate stroke vs non-stroke ──────────────────────────────────────
    final strokeRegions = <ContentRegion>[];
    final otherRegions = <ContentRegion>[];
    for (final region in regions) {
      if (region.nodeType == ContentNodeType.stroke) {
        strokeRegions.add(region);
      } else {
        otherRegions.add(region);
      }
    }

    // ── Non-stroke regions (with distinctive visual glyphs) ────────────────
    for (final region in otherRegions) {
      final r = _worldToMinimap(
        region.bounds,
        scale,
        offsetX,
        offsetY,
        expandedBounds,
      );
      final drawRect = Rect.fromLTWH(
        r.left,
        r.top,
        r.width < 3.0 ? 3.0 : r.width,
        r.height < 3.0 ? 3.0 : r.height,
      );

      switch (region.nodeType) {
        case ContentNodeType.text:
          _paintTextGlyph(canvas, drawRect);
        case ContentNodeType.image:
          _paintImageGlyph(canvas, drawRect);
        case ContentNodeType.pdf:
          _paintPdfGlyph(canvas, drawRect);
        case ContentNodeType.shape:
          _paintShapeGlyph(canvas, drawRect, region.shapeType);
        default:
          _nodePaint.color =
              _nodeColors[region.nodeType] ?? const Color(0xCC8E8E93);
          canvas.drawRect(drawRect, _nodePaint);
      }
    }

    // ── Stroke regions ─────────────────────────────────────────────────────
    if (strokeRegions.length > _kMergeThreshold) {
      _paintMergedStrokes(
        canvas,
        strokeRegions,
        scale,
        offsetX,
        offsetY,
        expandedBounds,
      );
    } else {
      _paintStrokePaths(
        canvas,
        strokeRegions,
        scale,
        offsetX,
        offsetY,
        expandedBounds,
      );
    }
  }

  /// Render individual strokes as Catmull-Rom smooth paths.
  void _paintStrokePaths(
    Canvas canvas,
    List<ContentRegion> strokes,
    double scale,
    double offsetX,
    double offsetY,
    Rect expandedBounds,
  ) {
    for (final region in strokes) {
      final polyline = region.minimapPolyline;

      if (polyline != null && polyline.length >= 2) {
        // Reuse path — reset instead of creating a new instance.
        _reusablePath.reset();

        // Convert all points to minimap space.
        final pts =
            polyline
                .map(
                  (p) => _worldPtToMinimap(
                    p,
                    scale,
                    offsetX,
                    offsetY,
                    expandedBounds,
                  ),
                )
                .toList();

        if (pts.length == 2) {
          // Just two points — straight line.
          _reusablePath.moveTo(pts[0].dx, pts[0].dy);
          _reusablePath.lineTo(pts[1].dx, pts[1].dy);
        } else {
          // Catmull-Rom → cubic Bézier for smooth curves.
          _reusablePath.moveTo(pts[0].dx, pts[0].dy);
          for (int i = 0; i < pts.length - 1; i++) {
            final p0 = i > 0 ? pts[i - 1] : pts[i];
            final p1 = pts[i];
            final p2 = pts[i + 1];
            final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];

            // Catmull-Rom to cubic Bézier control points (alpha = 0.5).
            final cp1 = Offset(
              p1.dx + (p2.dx - p0.dx) / 6.0,
              p1.dy + (p2.dy - p0.dy) / 6.0,
            );
            final cp2 = Offset(
              p2.dx - (p3.dx - p1.dx) / 6.0,
              p2.dy - (p3.dy - p1.dy) / 6.0,
            );
            _reusablePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
          }
        }

        final color =
            region.strokeColor ?? _nodeColors[ContentNodeType.stroke]!;
        _strokePathPaint.color = color.withValues(alpha: 0.9);
        _strokePathPaint.strokeWidth = (scale * 12.0).clamp(2.5, 5.0);
        canvas.drawPath(_reusablePath, _strokePathPaint);
      } else {
        // Fallback: dot at center.
        _nodePaint.color =
            region.strokeColor ?? _nodeColors[ContentNodeType.stroke]!;
        final center = _worldPtToMinimap(
          region.bounds.center,
          scale,
          offsetX,
          offsetY,
          expandedBounds,
        );
        canvas.drawCircle(center, 3.0, _nodePaint);
      }
    }
  }

  /// Spatially merge strokes with density-based opacity (heat map).
  /// Uses adaptive grid resolution based on stroke count.
  void _paintMergedStrokes(
    Canvas canvas,
    List<ContentRegion> strokes,
    double scale,
    double offsetX,
    double offsetY,
    Rect expandedBounds,
  ) {
    final gridSize = _gridSizeForCount(strokes.length);
    final cellW = expandedBounds.width / gridSize;
    final cellH = expandedBounds.height / gridSize;
    if (cellW <= 0 || cellH <= 0) return;

    final cells = gridSize * gridSize;
    final grid = List<Rect?>.filled(cells, null);
    final counts = List<int>.filled(cells, 0);

    for (final s in strokes) {
      final col = ((s.bounds.center.dx - expandedBounds.left) / cellW)
          .floor()
          .clamp(0, gridSize - 1);
      final row = ((s.bounds.center.dy - expandedBounds.top) / cellH)
          .floor()
          .clamp(0, gridSize - 1);
      final idx = row * gridSize + col;
      grid[idx] =
          grid[idx] != null ? grid[idx]!.expandToInclude(s.bounds) : s.bounds;
      counts[idx]++;
    }

    final maxCount = counts.reduce((a, b) => a > b ? a : b);
    if (maxCount == 0) return;

    final baseColor = _nodeColors[ContentNodeType.stroke]!;

    for (int i = 0; i < grid.length; i++) {
      final worldRect = grid[i];
      if (worldRect == null) continue;

      final density = counts[i] / maxCount;
      final alpha = 0.3 + density * 0.6;

      _nodePaint.color = baseColor.withValues(alpha: alpha);
      final r = _worldToMinimap(
        worldRect,
        scale,
        offsetX,
        offsetY,
        expandedBounds,
      );
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(1.5));
      canvas.drawRRect(rr, _nodePaint);

      // Subtle border for cell separation
      _strokePathPaint.color = baseColor.withValues(alpha: 0.15);
      _strokePathPaint.strokeWidth = 0.5;
      canvas.drawRRect(rr, _strokePathPaint);
    }
  }

  @override
  bool shouldRepaint(MinimapContentPainter oldDelegate) =>
      contentBounds != oldDelegate.contentBounds ||
      canvasBackground != oldDelegate.canvasBackground ||
      _regionFingerprint(regions) != _regionFingerprint(oldDelegate.regions);

  // ════════════════════════════════════════════════════════════════════════════
  // VISUAL GLYPHS — distinctive representations for non-stroke content
  // ════════════════════════════════════════════════════════════════════════════

  static final Paint _glyphLinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// 📝 Text glyph: horizontal lines mimicking text layout.
  void _paintTextGlyph(Canvas canvas, Rect r) {
    final color = _nodeColors[ContentNodeType.text]!;

    // Background fill (subtle)
    _nodePaint.color = color.withValues(alpha: 0.12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(1.0)),
      _nodePaint,
    );

    // Horizontal lines (text representation)
    _glyphLinePaint.color = color.withValues(alpha: 0.8);
    _glyphLinePaint.strokeWidth = 1.0;
    final lineCount = (r.height / 3.0).floor().clamp(1, 6);
    final lineSpacing = r.height / (lineCount + 1);
    final inset = r.width * 0.15;
    for (int i = 1; i <= lineCount; i++) {
      final y = r.top + lineSpacing * i;
      // Last line shorter (mimics ragged text)
      final rightInset = i == lineCount ? r.width * 0.35 : inset;
      canvas.drawLine(
        Offset(r.left + inset, y),
        Offset(r.right - rightInset, y),
        _glyphLinePaint,
      );
    }
  }

  /// 🖼️ Image glyph: filled rect with diagonal cross and small mountain icon.
  void _paintImageGlyph(Canvas canvas, Rect r) {
    final color = _nodeColors[ContentNodeType.image]!;

    // Background fill
    _nodePaint.color = color.withValues(alpha: 0.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(1.0)),
      _nodePaint,
    );

    // Border
    _glyphLinePaint.color = color.withValues(alpha: 0.6);
    _glyphLinePaint.strokeWidth = 0.8;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(1.0)),
      _glyphLinePaint,
    );

    // Diagonal cross (image placeholder)
    _glyphLinePaint.color = color.withValues(alpha: 0.45);
    _glyphLinePaint.strokeWidth = 0.8;
    canvas.drawLine(r.topLeft, r.bottomRight, _glyphLinePaint);
    canvas.drawLine(r.topRight, r.bottomLeft, _glyphLinePaint);

    // Small "mountain" triangle in bottom-left quadrant
    if (r.width > 4 && r.height > 4) {
      _reusablePath.reset();
      final mtnLeft = r.left + r.width * 0.15;
      final mtnRight = r.left + r.width * 0.65;
      final mtnBottom = r.bottom - r.height * 0.2;
      final mtnPeak = r.top + r.height * 0.35;
      _reusablePath.moveTo(mtnLeft, mtnBottom);
      _reusablePath.lineTo((mtnLeft + mtnRight) * 0.4, mtnPeak);
      _reusablePath.lineTo(mtnRight, mtnBottom);
      _reusablePath.close();
      _nodePaint.color = color.withValues(alpha: 0.45);
      canvas.drawPath(_reusablePath, _nodePaint);
    }
  }

  /// 📄 PDF glyph: page with folded corner.
  void _paintPdfGlyph(Canvas canvas, Rect r) {
    final color = _nodeColors[ContentNodeType.pdf]!;
    final foldSize = (r.width * 0.25).clamp(1.0, 4.0);

    // Page body (with cut corner)
    _reusablePath.reset();
    _reusablePath.moveTo(r.left, r.top);
    _reusablePath.lineTo(r.right - foldSize, r.top);
    _reusablePath.lineTo(r.right, r.top + foldSize);
    _reusablePath.lineTo(r.right, r.bottom);
    _reusablePath.lineTo(r.left, r.bottom);
    _reusablePath.close();

    _nodePaint.color = color.withValues(alpha: 0.2);
    canvas.drawPath(_reusablePath, _nodePaint);

    // Border
    _glyphLinePaint.color = color.withValues(alpha: 0.7);
    _glyphLinePaint.strokeWidth = 0.8;
    canvas.drawPath(_reusablePath, _glyphLinePaint);

    // Fold triangle
    _reusablePath.reset();
    _reusablePath.moveTo(r.right - foldSize, r.top);
    _reusablePath.lineTo(r.right - foldSize, r.top + foldSize);
    _reusablePath.lineTo(r.right, r.top + foldSize);
    _reusablePath.close();
    _nodePaint.color = color.withValues(alpha: 0.4);
    canvas.drawPath(_reusablePath, _nodePaint);

    // Text lines inside page
    if (r.height > 5) {
      _glyphLinePaint.color = color.withValues(alpha: 0.45);
      _glyphLinePaint.strokeWidth = 0.7;
      final lineCount = (r.height / 3.5).floor().clamp(1, 5);
      final startY = r.top + foldSize + 1.5;
      final availableH = r.bottom - startY - 1.5;
      if (availableH > 2) {
        final spacing = availableH / (lineCount + 1);
        for (int i = 1; i <= lineCount; i++) {
          final y = startY + spacing * i;
          canvas.drawLine(
            Offset(r.left + 1.5, y),
            Offset(r.right - 1.5, y),
            _glyphLinePaint,
          );
        }
      }
    }
  }

  /// 🔷 Shape glyph: renders the actual shape outline.
  void _paintShapeGlyph(Canvas canvas, Rect r, ShapeType? shapeType) {
    final color = _nodeColors[ContentNodeType.shape]!;
    _glyphLinePaint.color = color.withValues(alpha: 0.8);
    _glyphLinePaint.strokeWidth = 1.2;

    switch (shapeType) {
      case ShapeType.circle:
        _nodePaint.color = color.withValues(alpha: 0.1);
        canvas.drawOval(r, _nodePaint);
        canvas.drawOval(r, _glyphLinePaint);

      case ShapeType.rectangle:
        _nodePaint.color = color.withValues(alpha: 0.1);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(0.5)),
          _nodePaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(0.5)),
          _glyphLinePaint,
        );

      case ShapeType.triangle:
        _reusablePath.reset();
        _reusablePath.moveTo(r.center.dx, r.top);
        _reusablePath.lineTo(r.right, r.bottom);
        _reusablePath.lineTo(r.left, r.bottom);
        _reusablePath.close();
        _nodePaint.color = color.withValues(alpha: 0.1);
        canvas.drawPath(_reusablePath, _nodePaint);
        canvas.drawPath(_reusablePath, _glyphLinePaint);

      case ShapeType.line:
        canvas.drawLine(r.topLeft, r.bottomRight, _glyphLinePaint);

      case ShapeType.arrow:
        canvas.drawLine(r.centerLeft, r.centerRight, _glyphLinePaint);
        // Arrowhead
        final headSize = math.min(r.width * 0.3, 3.0);
        canvas.drawLine(
          r.centerRight,
          Offset(r.right - headSize, r.center.dy - headSize * 0.6),
          _glyphLinePaint,
        );
        canvas.drawLine(
          r.centerRight,
          Offset(r.right - headSize, r.center.dy + headSize * 0.6),
          _glyphLinePaint,
        );

      case ShapeType.diamond:
        _reusablePath.reset();
        _reusablePath.moveTo(r.center.dx, r.top);
        _reusablePath.lineTo(r.right, r.center.dy);
        _reusablePath.lineTo(r.center.dx, r.bottom);
        _reusablePath.lineTo(r.left, r.center.dy);
        _reusablePath.close();
        _nodePaint.color = color.withValues(alpha: 0.1);
        canvas.drawPath(_reusablePath, _nodePaint);
        canvas.drawPath(_reusablePath, _glyphLinePaint);

      case ShapeType.star:
        _paintStarGlyph(canvas, r, color);

      default:
        // Freehand, pentagon, hexagon, heart, etc. → outlined rect
        _nodePaint.color = color.withValues(alpha: 0.12);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(1.0)),
          _nodePaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(1.0)),
          _glyphLinePaint,
        );
    }
  }

  /// ⭐ Star glyph: 5-pointed star outline.
  void _paintStarGlyph(Canvas canvas, Rect r, Color color) {
    final cx = r.center.dx;
    final cy = r.center.dy;
    final outerR = math.min(r.width, r.height) / 2;
    final innerR = outerR * 0.4;

    _reusablePath.reset();
    for (int i = 0; i < 10; i++) {
      final radius = i.isEven ? outerR : innerR;
      final angle = (i * math.pi / 5) - math.pi / 2;
      final px = cx + radius * math.cos(angle);
      final py = cy + radius * math.sin(angle);
      if (i == 0) {
        _reusablePath.moveTo(px, py);
      } else {
        _reusablePath.lineTo(px, py);
      }
    }
    _reusablePath.close();

    _nodePaint.color = color.withValues(alpha: 0.1);
    canvas.drawPath(_reusablePath, _nodePaint);
    _glyphLinePaint.color = color.withValues(alpha: 0.8);
    _glyphLinePaint.strokeWidth = 0.8;
    canvas.drawPath(_reusablePath, _glyphLinePaint);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VIEWPORT PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Painter for the minimap viewport indicator — JARVIS HUD style.
///
/// Neon cyan outline with corner indicator dots and faint fill.
/// Repaints on every camera change — extremely cheap.
class MinimapViewportPainter extends CustomPainter {
  final Rect contentBounds;
  final Rect viewportInCanvas;
  final double minimapWidth;
  final double minimapHeight;
  final Color canvasBackground;

  // ── Minimal HUD paints ────────────────────────────────────────────────────
  static const _neonCyan = Color(0xFF82C8FF);

  static final Paint _viewportStrokePaint =
      Paint()
        ..color = _neonCyan.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

  static final Paint _viewportFillPaint =
      Paint()..color = _neonCyan.withValues(alpha: 0.08);

  static final Paint _viewportGlowPaint =
      Paint()
        ..color = _neonCyan.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

  static final Paint _dimOverlayPaint =
      Paint()..color = const Color(0x30000000);

  static final Paint _cornerDotPaint =
      Paint()
        ..color = _neonCyan.withValues(alpha: 0.75)
        ..style = PaintingStyle.fill;

  MinimapViewportPainter({
    required this.contentBounds,
    required this.viewportInCanvas,
    required this.minimapWidth,
    required this.minimapHeight,
    this.canvasBackground = Colors.white,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (viewportInCanvas.isEmpty || !viewportInCanvas.isFinite) return;

    final mapping = _computeMapping(contentBounds, minimapWidth, minimapHeight);
    if (mapping == null) return;

    final (:scale, :offsetX, :offsetY, :expandedBounds) = mapping;

    // Clip to rounded panel bounds.
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.clipRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(10)));

    final vr = _worldToMinimap(
      viewportInCanvas,
      scale,
      offsetX,
      offsetY,
      expandedBounds,
    );

    // ── Dim everything outside viewport (subtle focus effect) ──
    // Save layer, draw full dim, then cut out the viewport area.
    canvas.saveLayer(bgRect, Paint());
    canvas.drawRect(bgRect, _dimOverlayPaint);
    canvas.drawRect(vr, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // ── Outer glow (blurred halo) ──
    canvas.drawRect(vr, _viewportGlowPaint);

    // ── Bright fill ──
    canvas.drawRect(vr, _viewportFillPaint);

    // ── Sharp cyan border ──
    canvas.drawRect(vr, _viewportStrokePaint);

    // ── Corner dots (navigation anchors) ──
    const dotR = 2.0;
    canvas.drawCircle(vr.topLeft, dotR, _cornerDotPaint);
    canvas.drawCircle(vr.topRight, dotR, _cornerDotPaint);
    canvas.drawCircle(vr.bottomLeft, dotR, _cornerDotPaint);
    canvas.drawCircle(vr.bottomRight, dotR, _cornerDotPaint);
  }

  @override
  bool shouldRepaint(MinimapViewportPainter oldDelegate) =>
      viewportInCanvas != oldDelegate.viewportInCanvas ||
      contentBounds != oldDelegate.contentBounds;
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIVE STROKE PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Painter for the live in-progress stroke on the minimap.
///
/// Renders the current stroke as a Catmull-Rom smooth path in real time.
/// Lightweight — only active while the user is drawing.
class MinimapLiveStrokePainter extends CustomPainter {
  final List<dynamic> strokePoints;
  final Rect contentBounds;
  final double minimapWidth;
  final double minimapHeight;
  final Color strokeColor;

  static final Paint _liveStrokePaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

  static final ui.Path _livePath = ui.Path();

  MinimapLiveStrokePainter({
    required this.strokePoints,
    required this.contentBounds,
    required this.minimapWidth,
    required this.minimapHeight,
    this.strokeColor = const Color(0xFF4A90D9),
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strokePoints.length < 2) return;

    final mapping = _computeMapping(contentBounds, minimapWidth, minimapHeight);
    if (mapping == null) return;

    final (:scale, :offsetX, :offsetY, :expandedBounds) = mapping;

    // Clip to panel bounds.
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.clipRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(8)));

    // Decimate: sample at most 16 points from the live stroke.
    final points = strokePoints;
    final maxPts = 16;
    final List<Offset> pts;
    if (points.length <= maxPts) {
      pts =
          points
              .map<Offset>(
                (p) => _worldPtToMinimap(
                  p.position as Offset,
                  scale,
                  offsetX,
                  offsetY,
                  expandedBounds,
                ),
              )
              .toList();
    } else {
      pts = <Offset>[];
      final step = points.length / maxPts;
      for (int i = 0; i < maxPts; i++) {
        final idx = (i * step).floor().clamp(0, points.length - 1);
        pts.add(
          _worldPtToMinimap(
            points[idx].position as Offset,
            scale,
            offsetX,
            offsetY,
            expandedBounds,
          ),
        );
      }
      // Always include last point.
      pts.add(
        _worldPtToMinimap(
          points.last.position as Offset,
          scale,
          offsetX,
          offsetY,
          expandedBounds,
        ),
      );
    }

    // Draw as Catmull-Rom smooth path.
    _livePath.reset();
    _livePath.moveTo(pts[0].dx, pts[0].dy);

    if (pts.length == 2) {
      _livePath.lineTo(pts[1].dx, pts[1].dy);
    } else {
      for (int i = 0; i < pts.length - 1; i++) {
        final p0 = i > 0 ? pts[i - 1] : pts[i];
        final p1 = pts[i];
        final p2 = pts[i + 1];
        final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];

        final cp1 = Offset(
          p1.dx + (p2.dx - p0.dx) / 6.0,
          p1.dy + (p2.dy - p0.dy) / 6.0,
        );
        final cp2 = Offset(
          p2.dx - (p3.dx - p1.dx) / 6.0,
          p2.dy - (p3.dy - p1.dy) / 6.0,
        );
        _livePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
      }
    }

    _liveStrokePaint.color = strokeColor.withValues(alpha: 0.9);
    _liveStrokePaint.strokeWidth = (scale * 12.0).clamp(2.5, 5.0);
    canvas.drawPath(_livePath, _liveStrokePaint);
  }

  @override
  bool shouldRepaint(MinimapLiveStrokePainter oldDelegate) =>
      strokePoints.length != oldDelegate.strokePoints.length ||
      contentBounds != oldDelegate.contentBounds;
}

// ═══════════════════════════════════════════════════════════════════════════════
// COLLABORATOR CURSORS PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Painter for remote collaborator cursor indicators on the minimap.
///
/// Renders each remote user's cursor as a colored dot at their canvas position.
/// Lightweight — only draws when there are active remote cursors.
class MinimapCursorsPainter extends CustomPainter {
  /// Remote cursors: userId → { 'x': double, 'y': double, 'c': int (color), 'n': String (name), 'd': bool (drawing) }
  final Map<String, Map<String, dynamic>> remoteCursors;
  final Rect contentBounds;
  final double minimapWidth;
  final double minimapHeight;

  static final Paint _cursorPaint = Paint();
  static final Paint _cursorRingPaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

  MinimapCursorsPainter({
    required this.remoteCursors,
    required this.contentBounds,
    required this.minimapWidth,
    required this.minimapHeight,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (remoteCursors.isEmpty) return;

    final mapping = _computeMapping(contentBounds, minimapWidth, minimapHeight);
    if (mapping == null) return;

    final (:scale, :offsetX, :offsetY, :expandedBounds) = mapping;

    // Clip to panel bounds.
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.clipRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(8)));

    for (final entry in remoteCursors.entries) {
      final data = entry.value;
      final x = (data['x'] as num?)?.toDouble() ?? 0.0;
      final y = (data['y'] as num?)?.toDouble() ?? 0.0;
      final colorValue = (data['c'] as num?)?.toInt() ?? 0xFF42A5F5;
      final isDrawing = (data['d'] as bool?) ?? false;

      final cursorColor = Color(colorValue);
      final pt = _worldPtToMinimap(
        Offset(x, y),
        scale,
        offsetX,
        offsetY,
        expandedBounds,
      );

      // Skip cursors outside the minimap bounds.
      if (pt.dx < 0 || pt.dy < 0 || pt.dx > size.width || pt.dy > size.height) {
        continue;
      }

      // Draw cursor dot. Larger + pulsing ring when drawing.
      final radius = isDrawing ? 3.5 : 2.5;

      // White outline ring for visibility.
      _cursorRingPaint.color = const Color(0xBBFFFFFF);
      canvas.drawCircle(pt, radius + 1.0, _cursorRingPaint);

      // Colored fill.
      _cursorPaint.color = cursorColor;
      canvas.drawCircle(pt, radius, _cursorPaint);
    }
  }

  @override
  bool shouldRepaint(MinimapCursorsPainter oldDelegate) =>
      remoteCursors.length != oldDelegate.remoteCursors.length ||
      contentBounds != oldDelegate.contentBounds;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 🏛️ LANDMARK PAINTER — monuments + zone labels on the minimap
// ═══════════════════════════════════════════════════════════════════════════════
//
// Theory contract (§1964): "I nodi-monumento sono visibili sulla minimap
// come punti luminosi." Plus the implicit extension for zone labels
// from §1981 (macro-zone names visible on the continental map).
//
// This painter lives above [MinimapContentPainter] (content) and below
// [MinimapViewportPainter] (viewport frame) so landmarks float over the
// stroke regions without obscuring the viewport indicator.
//
// Both inputs are optional — if either is empty, the corresponding layer
// is skipped, keeping the minimap clean for canvases that don't yet have
// the required structure (few connections → no monuments; single dense
// region → no zones).

class MinimapLandmarkPainter extends CustomPainter {
  /// Monument cluster centroids in world coordinates. Key = cluster id
  /// (not rendered; just used for stable shouldRepaint diffing).
  final Map<String, Offset> monumentCentroids;

  /// Zones from the [ZoneLabeler]. Renders both the label text at the
  /// zone centroid and a translucent colored region halo over its bounds.
  final List<ZoneLabel> zoneLabels;

  /// 📌 Spatial bookmark positions (world coordinates). Rendered as
  /// distinctive orange dots above zones and monuments so the student
  /// can spot saved navigation anchors at a glance on the minimap
  /// (§1972-1977). Empty → bookmark layer skipped.
  final Map<String, Offset> bookmarkLocations;

  final Rect contentBounds;
  final double minimapWidth;
  final double minimapHeight;

  static final Paint _zoneFillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _zoneBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6;
  static final Paint _monumentGlow = Paint()
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
  static final Paint _monumentCore = Paint()..style = PaintingStyle.fill;
  static final Paint _bookmarkGlow = Paint()
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
  static final Paint _bookmarkCore = Paint()..style = PaintingStyle.fill;

  const MinimapLandmarkPainter({
    required this.monumentCentroids,
    required this.zoneLabels,
    required this.contentBounds,
    required this.minimapWidth,
    required this.minimapHeight,
    this.bookmarkLocations = const <String, Offset>{},
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (monumentCentroids.isEmpty && zoneLabels.isEmpty) return;
    final mapping = _computeMapping(contentBounds, minimapWidth, minimapHeight);
    if (mapping == null) return;
    final (:scale, :offsetX, :offsetY, :expandedBounds) = mapping;

    // Clip to the minimap panel so overflowing landmarks don't bleed
    // beyond the HUD frame.
    final clipRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.clipRRect(
      RRect.fromRectAndRadius(clipRect, const Radius.circular(10)),
    );

    // ── 1. Zone regions (under monuments) ─────────────────────────────
    for (var i = 0; i < zoneLabels.length; i++) {
      final zone = zoneLabels[i];
      // Deterministic per-zone tint — same zone renders same color on every
      // repaint even when zone ordering changes.
      final hue = (zone.id.hashCode & 0xFFFF) / 0xFFFF * 360.0;
      final tint = HSLColor.fromAHSL(1.0, hue, 0.55, 0.65).toColor();

      final rect = _worldToMinimap(
        zone.bounds,
        scale,
        offsetX,
        offsetY,
        expandedBounds,
      );
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(math.min(rect.shortestSide * 0.2, 6)),
      );
      _zoneFillPaint.color = tint.withValues(alpha: 0.12);
      canvas.drawRRect(rrect, _zoneFillPaint);
      _zoneBorderPaint.color = tint.withValues(alpha: 0.45);
      canvas.drawRRect(rrect, _zoneBorderPaint);

      // Zone name pinned above the region (or inside if the region is
      // already at the panel top).
      final tp = TextPainter(
        text: TextSpan(
          text: zone.label.toUpperCase(),
          style: TextStyle(
            color: tint.withValues(alpha: 0.95),
            fontSize: 7.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            shadows: const [
              Shadow(color: Color(0xCC000000), blurRadius: 2, offset: Offset(0, 1)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelTop = rect.top - tp.height - 1;
      final x = (rect.center.dx - tp.width / 2)
          .clamp(2.0, size.width - tp.width - 2);
      final y = labelTop < 2 ? rect.top + 2 : labelTop;
      tp.paint(canvas, Offset(x, y));
    }

    // ── 2. Monument luminous dots (above zones) ──────────────────────
    for (final entry in monumentCentroids.entries) {
      final center = _worldPtToMinimap(
        entry.value,
        scale,
        offsetX,
        offsetY,
        expandedBounds,
      );
      // Outer glow — warm amber, stands out against the cyan content palette.
      _monumentGlow.color = const Color(0xFFFFD54F).withValues(alpha: 0.55);
      canvas.drawCircle(center, 4.0, _monumentGlow);
      // Bright white core.
      _monumentCore.color = Colors.white.withValues(alpha: 0.95);
      canvas.drawCircle(center, 1.5, _monumentCore);
    }

    // ── 3. Bookmark flags (top of stack) ─────────────────────────────
    // Distinct SHAPE (flag/triangle marker) rather than a circle, so
    // bookmarks are unambiguous vs monuments (amber circles) even on
    // small screens / low contrast. Orange (#FF9800) palette marries
    // with the FAB + radial menu icon for end-to-end visual continuity.
    if (bookmarkLocations.isNotEmpty) {
      _bookmarkGlow.color = const Color(0xFFFF9800).withValues(alpha: 0.60);
      _bookmarkCore.color = const Color(0xFFFF9800).withValues(alpha: 0.95);
      for (final pos in bookmarkLocations.values) {
        final center = _worldPtToMinimap(
          pos,
          scale,
          offsetX,
          offsetY,
          expandedBounds,
        );
        _drawFlagMarker(canvas, center);
      }
    }
  }

  /// Paint a small flag glyph anchored at [anchor].
  /// Shape: vertical pole (line) + pennant triangle to the right, giving
  /// the marker an immediately recognizable "pinned here" silhouette
  /// distinct from monument circles and zone rectangles.
  static final Path _flagPath = Path();
  void _drawFlagMarker(Canvas canvas, Offset anchor) {
    const poleHeight = 9.0;
    const pennantWidth = 5.5;
    const pennantHeight = 4.0;

    // Soft amber halo behind the glyph for discoverability at small sizes.
    canvas.drawCircle(anchor, 4.0, _bookmarkGlow);

    // Pole.
    canvas.drawLine(
      anchor,
      Offset(anchor.dx, anchor.dy - poleHeight),
      Paint()
        ..color = const Color(0xFFFF9800)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    // Pennant triangle (fill).
    _flagPath
      ..reset()
      ..moveTo(anchor.dx, anchor.dy - poleHeight)
      ..lineTo(anchor.dx + pennantWidth, anchor.dy - poleHeight + pennantHeight / 2)
      ..lineTo(anchor.dx, anchor.dy - poleHeight + pennantHeight)
      ..close();
    canvas.drawPath(_flagPath, _bookmarkCore);
  }

  @override
  bool shouldRepaint(MinimapLandmarkPainter oldDelegate) =>
      contentBounds != oldDelegate.contentBounds ||
      monumentCentroids.length != oldDelegate.monumentCentroids.length ||
      zoneLabels.length != oldDelegate.zoneLabels.length ||
      bookmarkLocations.length != oldDelegate.bookmarkLocations.length;
}
