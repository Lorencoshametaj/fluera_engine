import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../drawing/models/pro_drawing_point.dart';
import '../../reflow/zone_labeler.dart';
import '../infinite_canvas_controller.dart';
import './content_bounds_tracker.dart';
import './minimap_painter.dart';
import './camera_actions.dart';
import '../../layers/layer_controller.dart';

/// 📡 Local Context Radar — Camera-style zoom minimap.
///
/// PERFORMANCE OPTIMIZATIONS:
/// 🚀 #1: Skip-when-hidden — no work done when animation value is 0.
/// 🚀 #2: Throttled rebuild — controller listener does NOT call setState;
///         the AnimatedBuilder on the controller drives rebuilds only when
///         the radar is visible (gated by _showAnim).
/// 🚀 #3: Global bounds early-exit for edge detection — if global bounds
///         fits inside the neighborhood, skip the O(N) edge scan entirely.
/// 🚀 #4: Edge content cached separately with staleness check, not recomputed
///         on every controller tick.
/// 🚀 #5: Content summary cached (only recomputed when local regions change).
/// 🚀 #6: _EdgeGlowPainter uses pre-allocated static paints with shader swap.
/// 🚀 #7: Region filter uses cached list + identity check on source list.
class CanvasMinimap extends StatefulWidget {
  final InfiniteCanvasController controller;
  final ContentBoundsTracker boundsTracker;
  final LayerController layerController;
  final Size viewportSize;
  final bool visible;
  final Color canvasBackground;
  final ValueNotifier<bool>? isDrawing;
  final ValueNotifier<List<ProDrawingPoint>>? currentStroke;
  final Color currentStrokeColor;
  final ValueNotifier<Map<String, Map<String, dynamic>>>? remoteCursors;

  /// 🏛️ Monument cluster centroids (world coordinates). Rendered on the
  /// minimap as luminous dots per §1964. Empty → no monument layer drawn.
  final Map<String, Offset> monumentCentroids;

  /// 🗺️ Auto-derived macro-zone labels. Rendered as translucent colored
  /// regions + uppercase titles on the minimap (§1981). Empty → skipped.
  final List<ZoneLabel> zoneLabels;

  /// 📌 Spatial bookmark positions (world coordinates), keyed by bookmark
  /// id. Rendered as orange dots on the minimap (§1972-1977). Empty → no
  /// bookmark layer added (zero-cost fallback).
  final Map<String, Offset> bookmarkLocations;

  static const double kWidth = 220.0;
  static const double kHeight = 160.0;
  static const double _showThreshold = 0.7;
  static const Duration _autoHideDelay = Duration(seconds: 5);

  // ── HUD palette ──
  static const _glassBase = Color(0xBB0A0E1A);
  static const _neonCyan = Color(0xFF82C8FF);

  const CanvasMinimap({
    super.key,
    required this.controller,
    required this.boundsTracker,
    required this.layerController,
    required this.viewportSize,
    this.visible = true,
    this.canvasBackground = Colors.white,
    this.isDrawing,
    this.currentStroke,
    this.currentStrokeColor = const Color(0xFF4A90D9),
    this.remoteCursors,
    this.monumentCentroids = const <String, Offset>{},
    this.zoneLabels = const <ZoneLabel>[],
    this.bookmarkLocations = const <String, Offset>{},
  });

  @override
  State<CanvasMinimap> createState() => _CanvasMinimapState();
}

class _CanvasMinimapState extends State<CanvasMinimap>
    with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  bool _radarActive = false;
  Timer? _autoHideTimer;
  double _lastScale = 1.0;
  Offset _lastOffset = Offset.zero;

  late final AnimationController _showCtrl;
  late final Animation<double> _showAnim;

  // ── Smooth neighborhood lerping ──
  Rect _currentNeighborhood = Rect.zero;
  static const double _lerpSpeed = 0.15;

  // ── 🚀 #7: Region filter cache ──
  List<ContentRegion>? _lastAllRegions; // identity check
  Rect _lastFilterNeighborhood = Rect.zero;
  List<ContentRegion> _cachedLocalRegions = const [];

  // ── 🚀 #4: Edge content cache ──
  _EdgeContentData _cachedEdges = const _EdgeContentData.none();
  Rect _lastEdgeNeighborhood = Rect.zero;
  int _lastEdgeRegionCount = -1;

  // ── 🚀 #5: Content summary cache ──
  String _cachedSummary = '';
  int _lastSummaryRegionCount = -1;

  @override
  void initState() {
    super.initState();
    _lastScale = widget.controller.scale;
    _lastOffset = widget.controller.offset;
    widget.controller.addListener(_onControllerChanged);

    _showCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _showAnim = CurvedAnimation(
      parent: _showCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _autoHideTimer?.cancel();
    _showCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTROLLER LISTENER — no setState, drives animation only
  // ═══════════════════════════════════════════════════════════════════════════

  void _onControllerChanged() {
    final scale = widget.controller.scale;
    final offset = widget.controller.offset;
    final isZoomedIn = scale < CanvasMinimap._showThreshold;

    final scaleChanged = (scale - _lastScale).abs() > 0.005;
    final panChanged = (offset - _lastOffset).distance > 2.0;
    _lastScale = scale;
    _lastOffset = offset;

    if (isZoomedIn && (scaleChanged || panChanged)) {
      if (!_radarActive) {
        _radarActive = true;
        _showCtrl.forward();
        HapticFeedback.selectionClick();
      }
      _resetAutoHideTimer();
    } else if (!isZoomedIn && _radarActive) {
      _radarActive = false;
      _showCtrl.reverse();
      _autoHideTimer?.cancel();
    }
  }

  void _resetAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(CanvasMinimap._autoHideDelay, () {
      if (mounted && !_isDragging) {
        _radarActive = false;
        _showCtrl.reverse();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GEOMETRY — all pure functions, zero allocations beyond Rect
  // ═══════════════════════════════════════════════════════════════════════════

  Rect _computeViewportInCanvas() {
    final c = widget.controller;
    final s = widget.viewportSize;
    return Rect.fromPoints(
      c.screenToCanvas(Offset.zero),
      c.screenToCanvas(Offset(s.width, s.height)),
    );
  }

  Rect _computeTargetNeighborhood(Rect viewport) {
    final scale = widget.controller.scale;
    final t = ((CanvasMinimap._showThreshold - scale) /
            (CanvasMinimap._showThreshold - 0.1))
        .clamp(0.0, 1.0);
    final multiplier = 1.5 + t * 0.5; // 1.5x → 2x (tight = legible strokes)
    final expand = viewport.shortestSide * (multiplier - 1) / 2;
    return viewport.inflate(expand);
  }

  Rect _lerpNeighborhood(Rect target) {
    if (_currentNeighborhood == Rect.zero) {
      _currentNeighborhood = target;
      return target;
    }
    _currentNeighborhood = Rect.fromLTRB(
      _currentNeighborhood.left +
          (target.left - _currentNeighborhood.left) * _lerpSpeed,
      _currentNeighborhood.top +
          (target.top - _currentNeighborhood.top) * _lerpSpeed,
      _currentNeighborhood.right +
          (target.right - _currentNeighborhood.right) * _lerpSpeed,
      _currentNeighborhood.bottom +
          (target.bottom - _currentNeighborhood.bottom) * _lerpSpeed,
    );
    return _currentNeighborhood;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚀 #7: REGION FILTER — identity-based cache, avoids O(N) rescan
  // ═══════════════════════════════════════════════════════════════════════════

  List<ContentRegion> _filterLocalRegions(
    List<ContentRegion> allRegions,
    Rect neighborhood,
  ) {
    // Identity check: same list object AND same neighborhood → skip entirely.
    if (identical(allRegions, _lastAllRegions) &&
        neighborhood == _lastFilterNeighborhood) {
      return _cachedLocalRegions;
    }
    _lastAllRegions = allRegions;
    _lastFilterNeighborhood = neighborhood;
    _cachedLocalRegions =
        allRegions.where((r) => r.bounds.overlaps(neighborhood)).toList();
    return _cachedLocalRegions;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚀 #3 + #4: EDGE CONTENT — global bounds early-exit + caching
  // ═══════════════════════════════════════════════════════════════════════════

  _EdgeContentData _computeEdgeContent(
    List<ContentRegion> allRegions,
    Rect neighborhood,
  ) {
    // Cache check: same region count + same neighborhood → return cached.
    if (allRegions.length == _lastEdgeRegionCount &&
        neighborhood == _lastEdgeNeighborhood) {
      return _cachedEdges;
    }
    _lastEdgeRegionCount = allRegions.length;
    _lastEdgeNeighborhood = neighborhood;

    // 🚀 #3: EARLY EXIT — if global content bounds fits entirely inside
    // the neighborhood, there's no content outside → all edges false.
    final gb = widget.boundsTracker.bounds.value;
    if (gb != Rect.zero &&
        gb.left >= neighborhood.left &&
        gb.top >= neighborhood.top &&
        gb.right <= neighborhood.right &&
        gb.bottom <= neighborhood.bottom) {
      _cachedEdges = const _EdgeContentData.none();
      return _cachedEdges;
    }

    // O(N) scan — but only when cache is stale.
    bool above = false, below = false, left = false, right = false;
    for (final r in allRegions) {
      final b = r.bounds;
      if (!b.isFinite || b.isEmpty) continue;
      if (b.overlaps(neighborhood)) continue;
      if (b.bottom < neighborhood.top) above = true;
      if (b.top > neighborhood.bottom) below = true;
      if (b.right < neighborhood.left) left = true;
      if (b.left > neighborhood.right) right = true;
      if (above && below && left && right) break;
    }
    _cachedEdges = _EdgeContentData(
      above: above, below: below, left: left, right: right,
    );
    return _cachedEdges;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚀 #5: CONTENT SUMMARY — cached, only recomputed on region change
  // ═══════════════════════════════════════════════════════════════════════════

  String _buildContentSummary(List<ContentRegion> regions) {
    if (regions.length == _lastSummaryRegionCount) return _cachedSummary;
    _lastSummaryRegionCount = regions.length;

    if (regions.isEmpty) {
      _cachedSummary = '';
      return '';
    }
    int strokes = 0, texts = 0, images = 0, pdfs = 0, shapes = 0;
    for (final r in regions) {
      switch (r.nodeType) {
        case ContentNodeType.stroke: strokes++;
        case ContentNodeType.text: texts++;
        case ContentNodeType.image: images++;
        case ContentNodeType.pdf: pdfs++;
        case ContentNodeType.shape: shapes++;
        default: break;
      }
    }
    final buf = StringBuffer();
    if (strokes > 0) buf.write('$strokes✐');
    if (texts > 0) { if (buf.isNotEmpty) buf.write(' '); buf.write('$texts¶'); }
    if (images > 0) { if (buf.isNotEmpty) buf.write(' '); buf.write('$images▣'); }
    if (pdfs > 0) { if (buf.isNotEmpty) buf.write(' '); buf.write('$pdfs◧'); }
    if (shapes > 0) { if (buf.isNotEmpty) buf.write(' '); buf.write('$shapes◇'); }
    _cachedSummary = buf.toString();
    return _cachedSummary;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _onRadarInteraction(Offset localPosition, Rect neighborhood) {
    if (neighborhood.isEmpty) return;

    const padding = 8.0;
    const drawW = CanvasMinimap.kWidth - padding * 2;
    const drawH = CanvasMinimap.kHeight - padding * 2;

    final scaleX = drawW / neighborhood.width;
    final scaleY = drawH / neighborhood.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final scaledW = neighborhood.width * scale;
    final scaledH = neighborhood.height * scale;
    final offsetX = padding + (drawW - scaledW) / 2;
    final offsetY = padding + (drawH - scaledH) / 2;

    final worldX = neighborhood.left + (localPosition.dx - offsetX) / scale;
    final worldY = neighborhood.top + (localPosition.dy - offsetY) / scale;

    final c = widget.controller;
    final s = widget.viewportSize;
    final targetOffset = Offset(
      s.width / 2 - worldX * c.scale,
      s.height / 2 - worldY * c.scale,
    );

    if (_isDragging) {
      c.setOffset(targetOffset);
    } else {
      c.animateOffsetTo(targetOffset);
    }
    _resetAutoHideTimer();
  }

  void _onDoubleTap(Rect neighborhood, List<ContentRegion> localRegions) {
    if (localRegions.isEmpty) return;

    Rect tight = localRegions.first.bounds;
    for (int i = 1; i < localRegions.length; i++) {
      tight = tight.expandToInclude(localRegions[i].bounds);
    }

    final s = widget.viewportSize;
    final scaleX = s.width / (tight.width * 1.3);
    final scaleY = s.height / (tight.height * 1.3);
    final fitScale = math.min(scaleX, scaleY).clamp(0.05, 5.0);

    final center = tight.center;
    widget.controller.animateOffsetTo(Offset(
      s.width / 2 - center.dx * fitScale,
      s.height / 2 - center.dy * fitScale,
    ));
    widget.controller.animateZoomTo(
      fitScale,
      Offset(s.width / 2, s.height / 2),
    );

    HapticFeedback.mediumImpact();
    _resetAutoHideTimer();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD — 🚀 #1: skip-when-hidden gate
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0, right: 16.0),
      child: AnimatedBuilder(
        animation: _showAnim,
        builder: (context, child) {
          final t = _showAnim.value;
          // 🚀 #1: Zero work when completely hidden.
          if (t == 0.0) return const SizedBox.shrink();
          return Opacity(
            opacity: t,
            child: Transform.scale(
              scale: 0.85 + 0.15 * t,
              alignment: Alignment.bottomRight,
              child: child,
            ),
          );
        },
        // 🚀 #2: The child is only built once and reused across animation
        // frames. The AnimatedBuilder on controller inside _buildRadarCore
        // drives content updates.
        child: _buildMinimapContent(),
      ),
    );
  }

  Widget _buildMinimapContent() {
    Widget content = _buildRadarCore();
    if (widget.isDrawing != null) {
      content = ValueListenableBuilder<bool>(
        valueListenable: widget.isDrawing!,
        builder: (context, isDrawing, child) {
          return AnimatedOpacity(
            opacity: isDrawing ? 0.15 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(ignoring: isDrawing, child: child),
          );
        },
        child: content,
      );
    }
    return content;
  }

  Widget _buildRadarCore() {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        // 🚀 #1: Early exit — don't compute anything when hidden.
        if (_showAnim.value == 0.0) return const SizedBox.shrink();

        return ValueListenableBuilder<List<ContentRegion>>(
          valueListenable: widget.boundsTracker.regions,
          builder: (context, allRegions, _) {
            final viewport = _computeViewportInCanvas();
            final targetHood = _computeTargetNeighborhood(viewport);
            final neighborhood = _lerpNeighborhood(targetHood);
            final localRegions = _filterLocalRegions(allRegions, neighborhood);
            final edgeContent = _computeEdgeContent(allRegions, neighborhood);
            final zoomPercent = (widget.controller.scale * 100).round();
            final summary = _buildContentSummary(localRegions);

            return GestureDetector(
              onPanStart: (d) {
                _isDragging = true;
                HapticFeedback.lightImpact();
                _onRadarInteraction(d.localPosition, neighborhood);
              },
              onPanUpdate: (d) => _onRadarInteraction(d.localPosition, neighborhood),
              onPanEnd: (_) => _isDragging = false,
              onTapDown: (d) => _onRadarInteraction(d.localPosition, neighborhood),
              onDoubleTap: () => _onDoubleTap(neighborhood, localRegions),
              child: Container(
                width: CanvasMinimap.kWidth,
                height: CanvasMinimap.kHeight,
                decoration: _radarDecoration,
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // ── Layer 1: Local content (RepaintBoundary) ──
                    RepaintBoundary(
                      child: CustomPaint(
                        size: _radarSize,
                        painter: MinimapContentPainter(
                          regions: localRegions,
                          contentBounds: neighborhood,
                          minimapWidth: CanvasMinimap.kWidth,
                          minimapHeight: CanvasMinimap.kHeight,
                          canvasBackground: widget.canvasBackground,
                        ),
                      ),
                    ),

                    // ── Layer 1b: Landmarks — monuments + zones + bookmarks ──
                    // Drawn above content, below the viewport frame, so
                    // monuments, zone regions and bookmark dots float on
                    // the minimap without being occluded by stroke regions
                    // but don't cover the viewport indicator. Skipped at
                    // zero cost when all three collections are empty.
                    if (widget.monumentCentroids.isNotEmpty ||
                        widget.zoneLabels.isNotEmpty ||
                        widget.bookmarkLocations.isNotEmpty)
                      RepaintBoundary(
                        child: CustomPaint(
                          size: _radarSize,
                          painter: MinimapLandmarkPainter(
                            monumentCentroids: widget.monumentCentroids,
                            zoneLabels: widget.zoneLabels,
                            bookmarkLocations: widget.bookmarkLocations,
                            contentBounds: neighborhood,
                            minimapWidth: CanvasMinimap.kWidth,
                            minimapHeight: CanvasMinimap.kHeight,
                          ),
                        ),
                      ),

                    // ── Layer 2: Viewport indicator ──
                    CustomPaint(
                      size: _radarSize,
                      painter: MinimapViewportPainter(
                        contentBounds: neighborhood,
                        viewportInCanvas: viewport,
                        minimapWidth: CanvasMinimap.kWidth,
                        minimapHeight: CanvasMinimap.kHeight,
                        canvasBackground: widget.canvasBackground,
                      ),
                    ),

                    // ── Layer 3: Live stroke preview ──
                    if (widget.currentStroke != null)
                      RepaintBoundary(
                        child: ValueListenableBuilder<List<ProDrawingPoint>>(
                          valueListenable: widget.currentStroke!,
                          builder: (context, pts, _) {
                            if (pts.isEmpty) return const SizedBox.shrink();
                            return CustomPaint(
                              size: _radarSize,
                              painter: MinimapLiveStrokePainter(
                                strokePoints: pts,
                                contentBounds: neighborhood,
                                minimapWidth: CanvasMinimap.kWidth,
                                minimapHeight: CanvasMinimap.kHeight,
                                strokeColor: widget.currentStrokeColor,
                              ),
                            );
                          },
                        ),
                      ),

                    // ── Layer 4: Collaborator cursors ──
                    if (widget.remoteCursors != null)
                      ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
                        valueListenable: widget.remoteCursors!,
                        builder: (context, cursors, _) {
                          if (cursors.isEmpty) return const SizedBox.shrink();
                          return CustomPaint(
                            size: _radarSize,
                            painter: MinimapCursorsPainter(
                              remoteCursors: cursors,
                              contentBounds: neighborhood,
                              minimapWidth: CanvasMinimap.kWidth,
                              minimapHeight: CanvasMinimap.kHeight,
                            ),
                          );
                        },
                      ),

                    // ── Layer 5: Vignette edge glows ──
                    CustomPaint(
                      size: _radarSize,
                      painter: _EdgeGlowPainter(edgeContent),
                    ),

                    // ── Zoom % badge ──
                    Positioned(
                      top: 4,
                      left: 6,
                      child: Text(
                        '$zoomPercent%',
                        style: _zoomBadgeStyle,
                      ),
                    ),

                    // ── Content summary badge ──
                    if (summary.isNotEmpty)
                      Positioned(
                        top: 4,
                        right: 6,
                        child: Text(summary, style: _summaryBadgeStyle),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚀 PRE-ALLOCATED CONSTANTS — avoid re-creating on every build
  // ═══════════════════════════════════════════════════════════════════════════

  static const _radarSize = Size(CanvasMinimap.kWidth, CanvasMinimap.kHeight);

  static final _radarDecoration = BoxDecoration(
    color: CanvasMinimap._glassBase,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(
      color: CanvasMinimap._neonCyan.withValues(alpha: 0.2),
      width: 0.5,
    ),
  );

  static final _zoomBadgeStyle = TextStyle(
    color: CanvasMinimap._neonCyan.withValues(alpha: 0.6),
    fontSize: 9,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static final _summaryBadgeStyle = TextStyle(
    color: CanvasMinimap._neonCyan.withValues(alpha: 0.45),
    fontSize: 8,
    fontWeight: FontWeight.w500,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// 🚀 #6: EDGE GLOW PAINTER — pre-allocated paints, shader swap only
// ═════════════════════════════════════════════════════════════════════════════

class _EdgeGlowPainter extends CustomPainter {
  final _EdgeContentData edges;

  const _EdgeGlowPainter(this.edges);

  // 🚀 #6: Single static paint — only the shader changes per edge.
  static final Paint _glowPaint = Paint();

  // Size cache to avoid re-creating shaders when size hasn't changed.
  static double _lastW = 0;
  static double _lastH = 0;
  static ui.Shader? _topShader;
  static ui.Shader? _bottomShader;
  static ui.Shader? _leftShader;
  static ui.Shader? _rightShader;

  static void _ensureShaders(double w, double h) {
    if (w == _lastW && h == _lastH) return;
    _lastW = w;
    _lastH = h;
    const d = 16.0;
    const c = CanvasMinimap._neonCyan;
    final a0 = c.withValues(alpha: 0.2);
    final a1 = c.withValues(alpha: 0.0);

    _topShader = ui.Gradient.linear(
      Offset(w / 2, 0), Offset(w / 2, d), [a0, a1],
    );
    _bottomShader = ui.Gradient.linear(
      Offset(w / 2, h), Offset(w / 2, h - d), [a0, a1],
    );
    _leftShader = ui.Gradient.linear(
      Offset(0, h / 2), Offset(d, h / 2), [a0, a1],
    );
    _rightShader = ui.Gradient.linear(
      Offset(w, h / 2), Offset(w - d, h / 2), [a0, a1],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!edges.above && !edges.below && !edges.left && !edges.right) return;

    final w = size.width;
    final h = size.height;
    const d = 16.0;
    _ensureShaders(w, h);

    if (edges.above) {
      _glowPaint.shader = _topShader;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, d), _glowPaint);
    }
    if (edges.below) {
      _glowPaint.shader = _bottomShader;
      canvas.drawRect(Rect.fromLTWH(0, h - d, w, d), _glowPaint);
    }
    if (edges.left) {
      _glowPaint.shader = _leftShader;
      canvas.drawRect(Rect.fromLTWH(0, 0, d, h), _glowPaint);
    }
    if (edges.right) {
      _glowPaint.shader = _rightShader;
      canvas.drawRect(Rect.fromLTWH(w - d, 0, d, h), _glowPaint);
    }
    _glowPaint.shader = null; // Release reference
  }

  @override
  bool shouldRepaint(_EdgeGlowPainter old) =>
      edges.above != old.edges.above ||
      edges.below != old.edges.below ||
      edges.left != old.edges.left ||
      edges.right != old.edges.right;
}

/// Edge content flags.
class _EdgeContentData {
  final bool above;
  final bool below;
  final bool left;
  final bool right;

  const _EdgeContentData({
    required this.above,
    required this.below,
    required this.left,
    required this.right,
  });

  const _EdgeContentData.none()
      : above = false,
        below = false,
        left = false,
        right = false;
}
