import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
const int _kMergeThreshold = 50;

/// Adaptive grid resolution based on stroke count.
/// More strokes → finer grid for better spatial fidelity.
int _gridSizeForCount(int count) {
  if (count <= 100) return 2; // 2×2 = 4 cells
  if (count <= 300) return 4; // 4×4 = 16 cells
  if (count <= 800) return 6; // 6×6 = 36 cells
  return 8; // 8×8 = 64 cells max
}

/// Node type → color mapping.
const Map<ContentNodeType, Color> _nodeColors = {
  ContentNodeType.stroke: Color(0xCC4A90D9),
  ContentNodeType.shape: Color(0xCC5CB85C),
  ContentNodeType.text: Color(0xCCA0A0A0),
  ContentNodeType.image: Color(0xCCE8A838),
  ContentNodeType.pdf: Color(0xCCD9534F),
  ContentNodeType.other: Color(0xCC8E8E93),
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
  static final Paint _bgPaintLight = Paint()..color = const Color(0xE6F0F0F5);
  static final Paint _bgPaintDark = Paint()..color = const Color(0xCC1A1A2E);

  static final Paint _borderPaintLight =
      Paint()
        ..color = const Color(0x30000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
  static final Paint _borderPaintDark =
      Paint()
        ..color = const Color(0x40FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

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

  bool get _isLightBg => canvasBackground.computeLuminance() > 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    // ── Background ─────────────────────────────────────────────────────────
    final isLight = _isLightBg;
    final bgPaint = isLight ? _bgPaintLight : _bgPaintDark;
    final borderPaint = isLight ? _borderPaintLight : _borderPaintDark;

    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgRRect = RRect.fromRectAndRadius(bgRect, const Radius.circular(8));
    canvas.drawRRect(bgRRect, bgPaint);
    canvas.drawRRect(bgRRect, borderPaint);

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

    // ── Non-stroke regions ─────────────────────────────────────────────────
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
        r.width < 1.5 ? 1.5 : r.width,
        r.height < 1.5 ? 1.5 : r.height,
      );
      _nodePaint.color =
          _nodeColors[region.nodeType] ?? const Color(0xCC8E8E93);
      canvas.drawRect(drawRect, _nodePaint);
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
        _strokePathPaint.color = color.withValues(alpha: 0.85);
        _strokePathPaint.strokeWidth = (scale * 3.0).clamp(0.5, 2.5);
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
        canvas.drawCircle(center, 1.0, _nodePaint);
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
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(1.5)),
        _nodePaint,
      );
    }
  }

  @override
  bool shouldRepaint(MinimapContentPainter oldDelegate) =>
      contentBounds != oldDelegate.contentBounds ||
      canvasBackground != oldDelegate.canvasBackground ||
      _regionFingerprint(regions) != _regionFingerprint(oldDelegate.regions);
}

// ═══════════════════════════════════════════════════════════════════════════════
// VIEWPORT PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Painter for the minimap viewport indicator only.
///
/// Repaints on every camera change — extremely cheap (single rect + border).
class MinimapViewportPainter extends CustomPainter {
  final Rect contentBounds;
  final Rect viewportInCanvas;
  final double minimapWidth;
  final double minimapHeight;
  final Color canvasBackground;

  // ── Pre-allocated paints ─────────────────────────────────────────────────
  static final Paint _viewportStrokePaintLight =
      Paint()
        ..color = const Color(0x88333333)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
  static final Paint _viewportStrokePaintDark =
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

  static final Paint _viewportFillPaintLight =
      Paint()..color = const Color(0x0D000000);
  static final Paint _viewportFillPaintDark =
      Paint()..color = const Color(0x0DFFFFFF);

  MinimapViewportPainter({
    required this.contentBounds,
    required this.viewportInCanvas,
    required this.minimapWidth,
    required this.minimapHeight,
    this.canvasBackground = Colors.white,
    super.repaint,
  });

  bool get _isLightBg => canvasBackground.computeLuminance() > 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (viewportInCanvas.isEmpty || !viewportInCanvas.isFinite) return;

    final mapping = _computeMapping(contentBounds, minimapWidth, minimapHeight);
    if (mapping == null) return;

    final (:scale, :offsetX, :offsetY, :expandedBounds) = mapping;

    // Clip to rounded panel bounds (same as content painter).
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.clipRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(8)));

    final isLight = _isLightBg;
    final strokePaint =
        isLight ? _viewportStrokePaintLight : _viewportStrokePaintDark;
    final fillPaint =
        isLight ? _viewportFillPaintLight : _viewportFillPaintDark;

    final vr = _worldToMinimap(
      viewportInCanvas,
      scale,
      offsetX,
      offsetY,
      expandedBounds,
    );
    canvas.drawRect(vr, fillPaint);
    canvas.drawRect(vr, strokePaint);
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
    _liveStrokePaint.strokeWidth = (scale * 3.5).clamp(0.8, 3.0);
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
