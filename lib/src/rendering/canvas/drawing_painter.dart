import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:ui' as ui;
import '../../drawing/models/pro_drawing_point.dart';
import '../../drawing/models/pro_brush_settings.dart';
import '../../core/models/shape_type.dart';
import '../../config/adaptive_rendering_config.dart'; // 🎯 Adaptive LOD per 120Hz
import './shape_painter.dart';
import '../../drawing/brushes/brushes.dart';
import '../optimization/viewport_culler.dart';
import '../optimization/spatial_index.dart';
import '../optimization/tile_cache_manager.dart';
import '../optimization/stroke_cache_manager.dart';
import '../../core/models/canvas_layer.dart';
import '../../canvas/infinite_canvas_controller.dart';
import '../../core/scene_graph/scene_graph.dart';
import '../../core/scene_graph/canvas_node.dart';
import '../../core/nodes/stroke_node.dart';
import '../../core/nodes/layer_node.dart';
import '../../core/nodes/group_node.dart';

import '../optimization/dirty_region_tracker.dart'; // 🎨 Phase 3: Incremental rendering
import '../optimization/advanced_tile_optimizer.dart'; // 📦 Stroke batching

/// 🎨 DRAWING PAINTER - Layer disegni completati
///
/// RESPONSIBILITIES:
/// - ✅ Rendering of all the completed strokes (strokes)
/// - ✅ Rendering of all geometric shapes
/// - ✅ Rendering of current shape in preview
/// - 🚀 Viewport culling: draw ONLY visible elements
/// - 🚀 QuadTree for 10k+ strokes: query O(log n)
///
/// ARCHITECTURE (Viewport-Level Mode):
/// - 🚀 Positioned at viewport level (outside Transform)
/// - 🚀 repaint: controller → paint() on every pan/zoom frame
/// - 🚀 Per-frame cost: O(1) via cache hit (drawPicture)
/// - 🚀 RepaintBoundary texture = viewport size (~20MB vs ~380MB)
///
/// NOTE: Current stroke is handled by CurrentStrokePainter (separate)
/// for optimal performance (zero widget rebuild during drawing)
class DrawingPainter extends CustomPainter {
  final List<GeometricShape> completedShapes;
  final GeometricShape? currentShape;

  // 🚀 Viewport parameters for culling
  final Offset canvasOffset;
  final double canvasScale;
  final Size viewportSize;

  // ✂️ Clipping parameters
  final bool enableClipping;
  final Size canvasSize;

  // 🚀 Spatial Index for query O(log n)
  final SpatialIndexManager? spatialIndex;

  // 🚀 Device pixel ratio for HiDPI
  final double devicePixelRatio;

  // 🎨 Phase 3: Dirty Region Tracker for incremental rendering
  final DirtyRegionTracker? dirtyRegionTracker;

  // 🚀 TILE CACHING: Activates when stroke count exceeds config threshold
  // Below the threshold, direct rendering (StrokeCacheManager) is faster

  // 🚀 Tile cache manager (singleton for persistence between paints)
  static TileCacheManager? _tileCacheManager;

  // 🚀 Vectorial cache: replay cached strokes as Picture (O(1))
  static final StrokeCacheManager _strokeCache = StrokeCacheManager();

  // 🎯 Adaptive rendering config per 120Hz support
  final AdaptiveRenderingConfig? adaptiveConfig;

  // 🎨 Per-layer blend mode: visible layers for per-layer compositing
  final List<CanvasLayer>? layers;

  // 🎯 Eraser preview: stroke IDs currently under the eraser cursor
  final Set<String> eraserPreviewIds;

  // 🚀 Viewport-level controller: when set, painter applies transform itself
  // and repaints every pan/zoom frame (O(1) via cache hit)
  final InfiniteCanvasController? controller;

  // 🌲 Scene graph: sole source of truth for strokes
  final SceneGraph sceneGraph;

  // 🌲 Cached materialized strokes (lazily computed once per paint frame)
  List<ProStroke>? _materializedCache;
  int _materializedVersion = -1;

  DrawingPainter({
    required this.completedShapes,
    this.currentShape,
    required this.canvasOffset,
    required this.canvasScale,
    required this.viewportSize,
    this.enableClipping = false,
    this.canvasSize = const Size(100000, 100000),
    this.spatialIndex,
    this.devicePixelRatio = 1.0,
    this.dirtyRegionTracker, // Phase 3
    this.adaptiveConfig, // 🎯 120Hz support
    this.layers, // 🎨 Per-layer blend mode
    this.eraserPreviewIds = const {}, // 🎯 Eraser preview
    this.controller, // 🚀 Viewport-level mode
    required this.sceneGraph, // 🌲 Scene graph source (sole source of truth)
  }) : super(repaint: controller); // repaint on pan/zoom when controller set

  /// 🌲 Effective strokes: materialized from the scene graph tree.
  /// Cached per scene graph version — O(1) on cache hit.
  List<ProStroke> get _effectiveStrokes {
    if (_materializedCache != null &&
        _materializedVersion == sceneGraph.version) {
      return _materializedCache!;
    }
    // Walk scene graph and collect strokes from visible layers
    final result = <ProStroke>[];
    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      _collectStrokes(layer, result);
    }
    _materializedCache = result;
    _materializedVersion = sceneGraph.version;
    return result;
  }

  /// Recursively collect ProStroke instances from a node subtree.
  static void _collectStrokes(CanvasNode node, List<ProStroke> result) {
    if (node is StrokeNode) {
      result.add(node.stroke);
    } else if (node is GroupNode) {
      for (final child in node.children) {
        if (child.isVisible) _collectStrokes(child, result);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ✂️ Applica clipping se abilitato (per editing immagini)
    if (enableClipping) {
      canvas.clipRect(Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height));
    }

    // 🚀 VIEWPORT-LEVEL MODE: apply transform and use size as viewport
    final isViewportLevel = controller != null;
    final effectiveOffset = isViewportLevel ? controller!.offset : canvasOffset;
    final effectiveScale = isViewportLevel ? controller!.scale : canvasScale;
    final effectiveViewportSize = isViewportLevel ? size : viewportSize;

    if (isViewportLevel) {
      canvas.save();
      canvas.translate(effectiveOffset.dx, effectiveOffset.dy);
      canvas.scale(effectiveScale);
    }

    // 🚀 VIEWPORT CULLING: calculate current viewport
    final viewport = ViewportCuller.calculateViewport(
      effectiveViewportSize,
      effectiveOffset,
      effectiveScale,
    );

    // 🚀 TILE CACHING: active for canvases with many strokes
    final tileCachingThreshold =
        adaptiveConfig?.tileCachingStrokeThreshold ?? 50;
    final useTileCaching =
        (adaptiveConfig?.enableTileCaching ?? false) &&
        _effectiveStrokes.length > tileCachingThreshold;

    if (useTileCaching) {
      _paintWithTileCaching(canvas, viewport);
    } else {
      _paintDirect(canvas, viewport);
    }

    // Draw shapes (always direct rendering - typically few)
    _paintShapes(canvas, viewport);

    // 🎨 Phase 3: Clear dirty regions after paint (prevents accumulation)
    dirtyRegionTracker?.clearDirty();

    if (isViewportLevel) {
      canvas.restore();
    }
  }

  /// 🚀 TILE CACHING with viewport-prioritized, time-budgeted rasterization.
  ///
  /// ARCHITECTURE:
  /// - Dirty tiles are sorted by distance from viewport center (visible first).
  /// - Rasterization is time-budgeted: uses a Stopwatch to stay within the
  ///   frame budget (6ms @120Hz, 12ms @60Hz), adapting to device capability.
  /// - While tiles are warming, falls back to _paintDirect() (O(1) vectorial
  ///   cache). Once ALL tiles are warm, switches to pure GPU bitmap compositing.
  /// - If too many tiles (>maxCachedTiles), falls back to _paintDirect.

  void _paintWithTileCaching(Canvas canvas, Rect viewport) {
    _tileCacheManager ??= TileCacheManager.instance;

    // Calculate bounding box of ALL content
    final contentBounds = _calculateContentBounds();
    if (contentBounds == null) return;

    // 🗺️ Get ALL tiles that contain strokes
    final allContentTiles = _tileCacheManager!.getTilesForBounds(contentBounds);

    // 🛡️ FALLBACK: if too many tiles, use vector cache (always working)
    if (allContentTiles.length > TileCacheManager.maxCachedTiles) {
      _paintDirect(canvas, viewport);
      return;
    }

    // 🎯 Collect dirty tiles and sort by viewport priority
    final dirtyTiles = <(int, int)>[];
    for (final (tileX, tileY) in allContentTiles) {
      if (_tileCacheManager!.isTileDirty(tileX, tileY) ||
          !_tileCacheManager!.hasTileCached(tileX, tileY)) {
        dirtyTiles.add((tileX, tileY));
      }
    }

    if (dirtyTiles.isNotEmpty) {
      // 🎯 VIEWPORT-PRIORITY: sort dirty tiles by distance from viewport center.
      // Visible/near tiles warm first, offscreen tiles warm later.
      final viewportCenter = viewport.center;
      final ts = TileCacheManager.tileSize;
      dirtyTiles.sort((a, b) {
        final centerA = Offset(a.$1 * ts + ts * 0.5, a.$2 * ts + ts * 0.5);
        final centerB = Offset(b.$1 * ts + ts * 0.5, b.$2 * ts + ts * 0.5);
        final distA = (centerA - viewportCenter).distanceSquared;
        final distB = (centerB - viewportCenter).distanceSquared;
        return distA.compareTo(distB);
      });

      // ⏱️ ADAPTIVE FRAME BUDGET: rasterize tiles until time budget is spent.
      // Automatically adapts to device capability — powerful devices rasterize
      // more tiles per frame, weak devices fewer.
      final frameBudgetMs =
          (adaptiveConfig?.frameBudgetMs ?? 16.0) * 0.75; // 75% headroom
      final sw = Stopwatch()..start();

      for (final (tileX, tileY) in dirtyTiles) {
        final tileBounds = _tileCacheManager!.getTileBounds(tileX, tileY);
        final strokesInTile = _getStrokesInBounds(tileBounds);
        _tileCacheManager!.rasterizeTile(
          tileX,
          tileY,
          strokesInTile,
          devicePixelRatio,
        );
        if (sw.elapsedMilliseconds >= frameBudgetMs) break;
      }
      sw.stop();
    }

    // Check if ALL tiles are now warm
    final allReady = allContentTiles.every(
      (t) =>
          _tileCacheManager!.hasTileCached(t.$1, t.$2) &&
          !_tileCacheManager!.isTileDirty(t.$1, t.$2),
    );

    if (allReady) {
      // ✅ All tiles cached — pure GPU bitmap compositing (fastest path)
      _tileCacheManager!.paintAllCachedTiles(canvas);
    } else {
      // 🔄 Tiles still warming up — use vectorial cache as fallback
      // (O(1) replay, no lag). Request another frame to continue warming.
      _paintDirect(canvas, viewport);
      SchedulerBinding.instance.scheduleFrame();
    }
  }

  /// Calculates the bounding box of all completed strokes
  Rect? _calculateContentBounds() {
    if (_effectiveStrokes.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final stroke in _effectiveStrokes) {
      final b = stroke.bounds;
      if (b == Rect.zero) continue;
      if (b.left < minX) minX = b.left;
      if (b.top < minY) minY = b.top;
      if (b.right > maxX) maxX = b.right;
      if (b.bottom > maxY) maxY = b.bottom;
    }

    if (minX == double.infinity) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Gets strokes che intersecano un bounds (usa QuadTree se disponibile)
  List<ProStroke> _getStrokesInBounds(Rect bounds) {
    if (spatialIndex != null && spatialIndex!.isBuilt) {
      return spatialIndex!.queryVisibleStrokes(bounds);
    }
    // Fallback: filter manually
    return _effectiveStrokes
        .where((stroke) => stroke.bounds.overlaps(bounds))
        .toList();
  }

  /// 🚀 Rendering with VIEWPORT CULLING + LOD
  ///
  /// - < 20 strokes: draw all (culling overhead > rendering them all)
  /// - ≥ 20 strokes: filter only visible in the viewport (with 1000px prefetch)
  /// - zoom < 50%: simplify points via Douglas-Peucker (up to 20x less work)
  void _paintDirect(Canvas canvas, Rect viewport) {
    // 🎨 PER-LAYER BLEND MODE: if any layer has non-default compositing,
    // render each layer inside its own saveLayer() group.
    final hasLayerCompositing =
        layers != null &&
        layers!.any(
          (l) => l.blendMode != ui.BlendMode.srcOver || l.opacity < 1.0,
        );

    if (hasLayerCompositing && layers != null) {
      _paintPerLayer(canvas, viewport);
      return;
    }

    // 🚀 VECTORIAL CACHE: replay cached strokes + draw only new ones
    // This avoids re-rendering all N strokes via BrushEngine on every paint()
    final totalStrokes = _effectiveStrokes.length;
    final hasEraserPreview = eraserPreviewIds.isNotEmpty;

    // Cache invalidation: undo/delete (count decreased)
    if (totalStrokes < _strokeCache.cachedStrokeCount) {
      // Invalidate per-layer caches (layer content changed)
      invalidateLayerCaches();
      // 🔄 UNDO SNAPSHOT: try ring buffer before full invalidation
      if (_strokeCache.tryRestoreFromUndoSnapshot(totalStrokes)) {
        // ✅ Snapshot hit: O(1) undo replay
        _strokeCache.drawCached(canvas);
        _drawEraserPreviews(canvas);
        return;
      }
      _strokeCache.invalidateCache();
    }

    // 🎯 ERASER PREVIEW OVERLAY: replay cache + overlay tinted previews.
    // The cache stays valid — preview strokes are drawn ON TOP, not re-rendered.
    if (hasEraserPreview && _strokeCache.isCacheValid(totalStrokes)) {
      _strokeCache.drawCached(canvas);
      _drawEraserPreviews(canvas);
      return;
    }

    if (!hasEraserPreview && _strokeCache.isCacheValid(totalStrokes)) {
      // ✅ Perfect cache hit: replay all strokes in O(1)
      _strokeCache.drawCached(canvas);
      return;
    }

    if (_strokeCache.hasCacheForStrokes(totalStrokes)) {
      // 🚀 Incremental update: replay cache + draw only NEW strokes
      _strokeCache.drawCached(canvas);

      final newStrokes = _effectiveStrokes.sublist(
        _strokeCache.cachedStrokeCount,
      );

      // Draw new strokes directly on canvas
      for (final stroke in newStrokes) {
        _renderStroke(canvas, stroke);
      }

      // Draw eraser previews on top (overlay, not cached)
      _drawEraserPreviews(canvas);

      // Update cache to include the new strokes (skip during eraser preview
      // to avoid polluting cache with transient preview state)
      if (!hasEraserPreview) {
        _strokeCache.updateCache(
          newStrokes,
          (c, s) => _renderStroke(c, s as ProStroke),
          Size.zero,
        );
      }
      return;
    }

    // 📝 Full render: no usable cache — record-once rendering.
    // Record all cacheable strokes into a PictureRecorder, then replay
    // the Picture onto the live canvas AND adopt it as the cache.
    // This eliminates the previous double-rendering (render + re-cache).
    final strokes =
        _effectiveStrokes.length < 20
            ? _effectiveStrokes
            : ViewportCuller.filterVisibleStrokesOptimized(
              _effectiveStrokes,
              viewport,
              spatialIndex: spatialIndex,
            );

    // Separate fill overlays and eraser previews (not cacheable)
    // from normal strokes (cacheable via batch rendering).
    final batchableStrokes = <ProStroke>[];

    for (final stroke in strokes) {
      final isPreview = eraserPreviewIds.contains(stroke.id);
      if (stroke.isFill) {
        _drawFillOverlay(canvas, stroke);
      } else if (isPreview) {
        // 🎯 Eraser preview: composite body + tint in one saveLayer
        final bounds = stroke.bounds.inflate(stroke.baseWidth * 2);
        canvas.saveLayer(bounds, Paint()..color = const Color(0x66FFFFFF));
        _renderStroke(canvas, stroke);
        canvas.drawRect(bounds, Paint()..color = const Color(0x40FF0000));
        canvas.restore();
      } else {
        batchableStrokes.add(stroke);
      }
    }

    // 📦 Draw batched strokes (ballpoint paths combined into single drawPath)
    if (batchableStrokes.isNotEmpty) {
      final optimizer = AdvancedTileOptimizer.instance;
      final batches = optimizer.batchStrokes(batchableStrokes);
      for (final entry in batches.entries) {
        optimizer.drawStrokeBatch(canvas, entry.key, entry.value);
      }
    }

    // 🚀 RECORD-ONCE CACHE: record ALL strokes into a Picture, replay onto
    // the live canvas would double-paint visible strokes. Instead, we record
    // all _effectiveStrokes (including offscreen) into the cache and adopt it.
    // The visible strokes have already been drawn above; the cache stores the
    // full set for future O(1) replay.
    if (!hasEraserPreview && _effectiveStrokes.length >= 5) {
      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);
      for (final stroke in _effectiveStrokes) {
        _renderStroke(recCanvas, stroke);
      }
      _strokeCache.adoptPicture(
        recorder.endRecording(),
        _effectiveStrokes.length,
      );
    }
  }

  /// 🎨 Render strokes grouped by layer, each with its own blend mode.
  ///
  /// Per-layer vectorial caching: each layer's strokes are cached as a
  /// ui.Picture keyed by sceneGraph.version. ANY mutation (add, delete,
  /// modify, reorder) increments the version → automatic cache miss.
  static final Map<String, ui.Picture> _layerCaches = {};
  static int _layerCacheVersion = -1;

  /// Invalidate all per-layer caches (e.g. on undo or eraser).
  static void invalidateLayerCaches() {
    for (final picture in _layerCaches.values) {
      picture.dispose();
    }
    _layerCaches.clear();
    _layerCacheVersion = -1;
  }

  void _paintPerLayer(Canvas canvas, Rect viewport) {
    final hasEraserPreview = eraserPreviewIds.isNotEmpty;

    for (final layer in layers!) {
      if (!layer.isVisible || layer.strokes.isEmpty) continue;

      // saveLayer() creates an offscreen buffer for compositing
      final layerPaint =
          Paint()
            ..blendMode = layer.blendMode
            ..color = Color.fromARGB(
              (layer.opacity * 255).round(),
              255,
              255,
              255,
            );
      canvas.saveLayer(null, layerPaint);

      final cacheKey = layer.id;
      final hasCachedPicture = _layerCaches.containsKey(cacheKey);

      // Cache hit: replay saved Picture (O(1))
      // Valid when sceneGraph hasn't changed and no eraser preview
      if (!hasEraserPreview &&
          hasCachedPicture &&
          _layerCacheVersion == sceneGraph.version) {
        canvas.drawPicture(_layerCaches[cacheKey]!);
        canvas.restore();
        continue;
      }

      // Cache miss: record this layer's strokes into a Picture
      final strokes =
          layer.strokes.length < 20
              ? layer.strokes
              : ViewportCuller.filterVisibleStrokesOptimized(
                layer.strokes,
                viewport,
                spatialIndex: spatialIndex,
              );

      if (strokes.isEmpty) {
        canvas.restore();
        continue;
      }

      // Record strokes for cache (uses ALL strokes, not viewport-culled)
      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);

      for (final stroke in layer.strokes) {
        _renderStroke(recCanvas, stroke);
      }

      final picture = recorder.endRecording();

      // Draw to live canvas
      canvas.drawPicture(picture);

      // Draw eraser previews on top (not cached)
      if (hasEraserPreview) {
        for (final stroke in strokes) {
          if (eraserPreviewIds.contains(stroke.id)) {
            final bounds = stroke.bounds.inflate(stroke.baseWidth * 2);
            canvas.saveLayer(bounds, Paint()..color = const Color(0x66FFFFFF));
            _renderStroke(canvas, stroke);
            canvas.drawRect(bounds, Paint()..color = const Color(0x40FF0000));
            canvas.restore();
          }
        }
      }

      // Save cache (skip during eraser preview — strokes may be transient)
      if (!hasEraserPreview) {
        _layerCaches[cacheKey]?.dispose();
        _layerCaches[cacheKey] = picture;
        _layerCacheVersion = sceneGraph.version;
      } else {
        picture.dispose();
      }

      canvas.restore();
    }
  }

  /// 🎯 Draw eraser preview overlays on top of the cached canvas.
  ///
  /// Each preview stroke is drawn with a semi-transparent tint to indicate
  /// it will be erased. This avoids invalidating the vectorial cache.
  void _drawEraserPreviews(Canvas canvas) {
    if (eraserPreviewIds.isEmpty) return;
    for (final stroke in _effectiveStrokes) {
      if (!eraserPreviewIds.contains(stroke.id)) continue;
      final bounds = stroke.bounds.inflate(stroke.baseWidth * 2);
      canvas.saveLayer(bounds, Paint()..color = const Color(0x66FFFFFF));
      _renderStroke(canvas, stroke);
      canvas.drawRect(bounds, Paint()..color = const Color(0x40FF0000));
      canvas.restore();
    }
  }

  /// Draws geometric shapes
  void _paintShapes(Canvas canvas, Rect viewport) {
    // Filter visible shapes
    final visibleShapes = ViewportCuller.filterVisibleShapesOptimized(
      completedShapes,
      viewport,
      spatialIndex: spatialIndex,
    );

    // Draw all completed geometric shapes (ONLY visible ones)
    for (final shape in visibleShapes) {
      ShapePainter.drawShape(canvas, shape);
    }

    // Draw the current shape in preview (always visible if present)
    if (currentShape != null) {
      ShapePainter.drawShape(canvas, currentShape!, isPreview: true);
    }
  }

  /// 🪣 Draw fill overlay as raster image at its canvas-space bounds
  void _drawFillOverlay(Canvas canvas, ProStroke stroke) {
    if (stroke.fillOverlay == null || stroke.fillBounds == null) return;
    final paint = Paint()..filterQuality = FilterQuality.low;
    canvas.drawImageRect(
      stroke.fillOverlay!,
      Rect.fromLTWH(
        0,
        0,
        stroke.fillOverlay!.width.toDouble(),
        stroke.fillOverlay!.height.toDouble(),
      ),
      stroke.fillBounds!,
      paint,
    );
  }

  /// 🚀 DRY stroke rendering helper.
  /// Handles both fill overlays and normal strokes in one call.
  void _renderStroke(Canvas canvas, ProStroke stroke) {
    if (stroke.isFill) {
      _drawFillOverlay(canvas, stroke);
    } else {
      BrushEngine.renderStroke(
        canvas,
        stroke.points,
        stroke.color,
        stroke.baseWidth,
        stroke.penType,
        stroke.settings,
      );
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) {
    // 🎨 Phase 3: If using incremental rendering, check dirty regions
    if (dirtyRegionTracker != null && dirtyRegionTracker!.hasDirtyRegions) {
      final viewport = ViewportCuller.calculateViewport(
        viewportSize,
        canvasOffset,
        canvasScale,
      );

      if (dirtyRegionTracker!.shouldRepaint(viewport)) {
        return true;
      }
    }

    // 🚀 Repaint ONLY if strokes/shapes change (add/remove)
    // The parent Transform widget handles zoom/pan visually →
    // NO repaint for offset/scale/viewportSize, at any
    // number of strokes. Cached tiles are GPU-scaled bitmaps.
    // 🌲 Scene graph version-based change detection
    return oldDelegate.sceneGraph.version != sceneGraph.version ||
        oldDelegate.completedShapes != completedShapes ||
        oldDelegate.currentShape != currentShape ||
        oldDelegate.layers != layers ||
        oldDelegate.eraserPreviewIds != eraserPreviewIds;
  }

  /// 🚀 Incremental update: overlay new stroke on cached tiles
  /// Falls back to full invalidation for tiles not yet cached
  static void incrementalUpdateForStroke(
    ProStroke stroke,
    double devicePixelRatio,
  ) {
    if (_tileCacheManager == null) return;
    final bounds = stroke.bounds;
    if (bounds == Rect.zero) return;

    for (final (tileX, tileY) in _tileCacheManager!.getTilesForBounds(bounds)) {
      // Try incremental overlay on existing cached tile
      final success = _tileCacheManager!.incrementalUpdateTile(
        tileX,
        tileY,
        stroke,
        devicePixelRatio,
      );
      // If incremental failed (tile not in cache), mark dirty for full rasterization
      if (!success) {
        _tileCacheManager!.invalidateTile(tileX, tileY);
      }
    }
  }

  /// 🚀 Invalidate tiles involved by a stroke (call after add/remove)
  static void invalidateTilesForStroke(ProStroke stroke) {
    _tileCacheManager?.invalidateTilesForStroke(stroke);
  }

  /// 🚀 Invalidate all caches (call after complete undo or clear)
  static void invalidateAllTiles() {
    _tileCacheManager?.invalidateAll();
    _strokeCache.invalidateCache();
    invalidateLayerCaches();
  }

  /// 🚀 Clear all caches and free memory (call when leaving the canvas)
  static void clearTileCache() {
    _tileCacheManager?.clear();
    _strokeCache.invalidateCache();
    _strokeCache.clearUndoSnapshots();
    invalidateLayerCaches();
  }
}
