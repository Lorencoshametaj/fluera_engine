import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;
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
import '../../core/nodes/pdf_document_node.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../canvas/pdf_page_painter.dart';
import '../../tools/pdf/pdf_text_selection_controller.dart';
import '../../export/pdf_annotation_exporter.dart';

import '../optimization/dirty_region_tracker.dart'; // 🎨 Phase 3: Incremental rendering
import '../optimization/advanced_tile_optimizer.dart'; // 📦 Stroke batching
import '../shaders/shader_brush_service.dart'; // 🚀 Shader warm-up

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

  // 📄 PDF painters: one per document ID
  final Map<String, PdfPagePainter> pdfPainters;

  // 📄 Callback to trigger repaint when async PDF renders complete
  final VoidCallback? onPdfRepaint;

  // 📝 Active text selection on PDF pages
  final PdfTextSelection? pdfTextSelection;

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
    this.pdfPainters = const {}, // 📄 PDF page painters
    this.onPdfRepaint, // 📄 Repaint callback for async PDF renders
    this.pdfTextSelection, // 📝 Text selection overlay
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
    // 🚀 SHADER WARM-UP: Pre-compile all GPU shaders on the first paint frame.
    // Avoids jank on the user's first stroke. Only runs once (_warmedUp guard).
    ShaderBrushService.instance.warmUp(canvas);

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
      if (controller!.rotation != 0.0) {
        canvas.rotate(controller!.rotation);
      }
      canvas.scale(effectiveScale);
    }

    // 🚀 VIEWPORT CULLING: calculate current viewport
    final viewport = ViewportCuller.calculateViewport(
      effectiveViewportSize,
      effectiveOffset,
      effectiveScale,
      rotation: controller?.rotation ?? 0.0,
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

    // 📄 Draw PDF documents
    _paintPdfDocuments(canvas, viewport);

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

    // 🔍 ADAPTIVE LOD: skip sub-pixel strokes at low zoom.
    // Only active when scale < 0.5 — at normal zoom, zero overhead.
    // Never modifies geometry — strokes are fully rendered or fully skipped.
    final effectiveScale = controller?.scale ?? canvasScale;
    final lodStrokes = ViewportCuller.applyAdaptiveLOD(strokes, effectiveScale);

    // Separate fill overlays and eraser previews (not cacheable)
    // from normal strokes (cacheable via batch rendering).
    final batchableStrokes = <ProStroke>[];

    for (final stroke in lodStrokes) {
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

      // 🔍 ADAPTIVE LOD: skip sub-pixel strokes at low zoom
      final effectiveScale = controller?.scale ?? canvasScale;
      final lodStrokes = ViewportCuller.applyAdaptiveLOD(
        strokes,
        effectiveScale,
      );

      if (lodStrokes.isEmpty) {
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

  /// 📄 Paint all PDF document nodes found in the scene graph layers.
  ///
  /// Uses [PdfPagePainter] for LOD-aware progressive rendering with
  /// prefetching, LRU eviction, and debounced LOD upgrades.
  void _paintPdfDocuments(Canvas canvas, Rect viewport) {
    // Collect pages per document (not globally!) for correct isolation
    final pagesPerDocument = <String, List<PdfPageNode>>{};

    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      _collectAndPaintPdfNodes(canvas, layer, viewport, pagesPerDocument);
    }

    // Prefetch, flush, evict — each painter only sees its OWN document's pages
    for (final entry in pdfPainters.entries) {
      final docId = entry.key;
      final painter = entry.value;
      final docPages = pagesPerDocument[docId] ?? const [];

      painter.prefetchAdjacent(
        docPages,
        viewport,
        currentZoom: controller?.scale ?? canvasScale,
        onNeedRepaint: onPdfRepaint,
      );
      painter.flushStaleQueue(viewport);
      painter.evictOffViewport(docPages, viewport);
      painter.cleanupStalePages(docPages);
    }
  }

  /// Recursively find and paint PDF nodes in a subtree.
  void _collectAndPaintPdfNodes(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
    Map<String, List<PdfPageNode>> pagesPerDocument,
  ) {
    if (node is PdfDocumentNode) {
      // 🚀 Culling: If document is off-screen, skip its pages entirely
      if (!node.worldBounds.overlaps(viewport)) return;

      final painter = pdfPainters[node.id];
      final docPages = pagesPerDocument.putIfAbsent(node.id, () => []);
      for (final child in node.children) {
        if (child is PdfPageNode && child.isVisible) {
          docPages.add(child);
          _paintPdfPage(canvas, child, viewport, painter);
        }
      }
    } else if (node is GroupNode) {
      for (final child in node.children) {
        if (child.isVisible) {
          _collectAndPaintPdfNodes(canvas, child, viewport, pagesPerDocument);
        }
      }
    }
  }

  // 📄 Reusable Paint objects for PDF rendering (zero per-frame allocation)
  static final Paint _pdfShadowPaint =
      Paint()
        ..color = const Color(0x30000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
  static final Paint _pdfPageBgPaint = Paint()..color = const Color(0xFFFFFFFF);
  static final Paint _pdfBorderPaint =
      Paint()
        ..color = const Color(0xFFE0E0E0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;

  /// Paint a single PDF page with professional styling.
  ///
  /// Features: drop shadow, white background, LOD-aware content via
  /// [PdfPagePainter], thin border. Falls back to a numbered placeholder
  /// if no [PdfPagePainter] is available for this document.
  void _paintPdfPage(
    Canvas canvas,
    PdfPageNode pageNode,
    Rect viewport,
    PdfPagePainter? painter,
  ) {
    final pos = pageNode.position;
    final size = pageNode.pageModel.originalSize;
    final pageRect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);

    // Viewport culling (rotation-aware: rotated pages have inflated bounds)
    final rotation = pageNode.pageModel.rotation;
    final cullRect =
        rotation != 0
            ? PdfAnnotationExporter.inflatedBoundsForRotation(
              pageRect,
              rotation,
            )
            : pageRect;
    if (!cullRect.overlaps(viewport)) return;

    // 🔄 Apply page rotation around center
    if (rotation != 0) {
      canvas.save();
      final cx = pageRect.center.dx;
      final cy = pageRect.center.dy;
      canvas.translate(cx, cy);
      canvas.rotate(rotation);
      canvas.translate(-cx, -cy);
    }

    // 🎨 Drop shadow (professional paper look)
    final shadowRect = pageRect.translate(0, 4);
    canvas.drawRect(shadowRect, _pdfShadowPaint);

    // White page background
    canvas.drawRect(pageRect, _pdfPageBgPaint);

    // Draw page content via PdfPagePainter (LOD-aware) or fallback
    canvas.save();
    canvas.translate(pos.dx, pos.dy);

    if (painter != null) {
      painter.paintPage(
        canvas,
        pageNode,
        currentZoom: controller?.scale ?? canvasScale,
        onNeedRepaint: onPdfRepaint,
        viewport: viewport,
      );
    } else {
      // Fallback: basic placeholder with page number
      final localRect = Rect.fromLTWH(0, 0, size.width, size.height);
      final pageNum = '${pageNode.pageModel.pageIndex + 1}';
      final tp = TextPainter(
        text: TextSpan(
          text: pageNum,
          style: const TextStyle(
            color: Color(0xFFBBBBBB),
            fontSize: 28,
            fontWeight: FontWeight.w300,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (localRect.width - tp.width) / 2,
          (localRect.height - tp.height) / 2,
        ),
      );
    }

    canvas.restore();

    // 📝 Annotation layer: draw strokes linked to this page, clipped to bounds
    final annotations = pageNode.pageModel.annotations;
    if (annotations.isNotEmpty && pageNode.pageModel.showAnnotations) {
      canvas.save();
      canvas.clipRect(pageRect);
      _paintPageAnnotations(canvas, annotations);
      canvas.restore();
    }

    // 📝 Text selection highlight overlay
    if (pdfTextSelection != null &&
        pdfTextSelection!.isNotEmpty &&
        pdfTextSelection!.pageIndex == pageNode.pageModel.pageIndex) {
      _paintTextSelectionOverlay(canvas, pdfTextSelection!, pageRect);
    }

    // Thin border
    canvas.drawRect(pageRect, _pdfBorderPaint);

    // 📑 Page number badge (bottom-right corner)
    if (showPdfPageNumbers) {
      _paintPageNumberBadge(canvas, pageNode, pageRect);
    }

    // 🔒 Lock icon overlay (small pill at top-right)
    if (pageNode.pageModel.isLocked) {
      _paintLockIndicator(canvas, pageRect);
    }

    // Close rotation transform if applied
    if (rotation != 0) {
      canvas.restore();
    }
  }

  /// Whether to show page number badges on PDF pages.
  bool showPdfPageNumbers = true;

  /// Paint annotation strokes linked to a page.
  ///
  /// Looks up strokes by ID from all layer stroke lists and renders them.
  /// Assumes the canvas is already clipped to the page rect.
  void _paintPageAnnotations(Canvas canvas, List<String> annotationIds) {
    if (layers == null) return;

    final idSet = annotationIds.toSet();
    for (final layer in layers!) {
      if (!layer.isVisible) continue;
      for (final stroke in layer.strokes) {
        if (idSet.contains(stroke.id)) {
          _renderStroke(canvas, stroke);
        }
      }
    }
  }

  // Pre-allocated paints for text selection overlay (B6: avoid per-frame alloc)
  static final Paint _selectionHighlightPaint =
      Paint()
        ..color = const Color(0x4D2196F3) // Material Blue 20%
        ..style = PaintingStyle.fill;

  static final Paint _selectionHandlePaint =
      Paint()
        ..color = const Color(0xFF2196F3) // Material Blue solid
        ..style = PaintingStyle.fill;

  /// Paint text selection highlights and drag handles.
  ///
  /// [selection] contains the selected spans in page-local coordinates.
  /// [pageRect] is the page's canvas-space rect, used to offset the spans.
  void _paintTextSelectionOverlay(
    Canvas canvas,
    PdfTextSelection selection,
    Rect pageRect,
  ) {
    if (selection.isEmpty) return;

    final pageOffset = Offset(pageRect.left, pageRect.top);

    // Clip to page bounds so highlights don't bleed outside
    canvas.save();
    canvas.clipRect(pageRect);

    // Draw highlight rectangles for each selected span
    for (final span in selection.spans) {
      final r = span.rect.shift(pageOffset);
      canvas.drawRect(r, _selectionHighlightPaint);
    }

    // Draw drag handles at start and end of selection
    // Scale inversely with zoom so handles stay visually consistent
    final effectiveScale = controller?.scale ?? canvasScale;
    final handleRadius = math.max(3.0, 5.0 / effectiveScale);

    if (selection.spans.isNotEmpty) {
      final firstRect = selection.spans.first.rect.shift(pageOffset);
      final lastRect = selection.spans.last.rect.shift(pageOffset);

      // Start handle: left edge, center vertically
      canvas.drawCircle(
        Offset(firstRect.left, firstRect.center.dy),
        handleRadius,
        _selectionHandlePaint,
      );

      // End handle: right edge, center vertically
      canvas.drawCircle(
        Offset(lastRect.right, lastRect.center.dy),
        handleRadius,
        _selectionHandlePaint,
      );
    }

    canvas.restore();
  }

  // F3: Pre-allocated paints for lock indicator (avoid per-frame alloc)
  static final Paint _lockPillPaint = Paint()..color = const Color(0x99000000);
  static final Paint _lockBodyPaint = Paint()..color = const Color(0xFFFFFFFF);
  static final Paint _lockShacklePaint =
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke;

  /// Paint a small lock indicator pill at the top-right of a page.
  void _paintLockIndicator(Canvas canvas, Rect pageRect) {
    final effectiveScale = controller?.scale ?? canvasScale;
    final iconSize = 14.0 / effectiveScale;
    final padding = 6.0 / effectiveScale;
    final pillWidth = iconSize + padding * 2;
    final pillHeight = iconSize + padding * 2;

    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        pageRect.right - pillWidth - padding,
        pageRect.top + padding,
        pillWidth,
        pillHeight,
      ),
      Radius.circular(pillHeight / 2),
    );

    // Semi-transparent dark pill
    canvas.drawRRect(pillRect, _lockPillPaint);

    // Lock icon (draw a simple padlock shape)
    final cx = pillRect.center.dx;
    final cy = pillRect.center.dy;
    final s = iconSize * 0.35;

    // Body (rounded rect)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy + s * 0.2),
          width: s * 1.6,
          height: s * 1.4,
        ),
        Radius.circular(s * 0.2),
      ),
      _lockBodyPaint,
    );

    // Shackle (arc) — strokeWidth is dynamic so set per-call
    _lockShacklePaint.strokeWidth = s * 0.35;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, cy - s * 0.3),
        width: s * 1.0,
        height: s * 1.0,
      ),
      math.pi,
      math.pi,
      false,
      _lockShacklePaint,
    );
  }

  /// Paint a small page-number pill at the bottom-right of a page.
  void _paintPageNumberBadge(
    Canvas canvas,
    PdfPageNode pageNode,
    Rect pageRect,
  ) {
    final totalPages =
        (pageNode.parent is PdfDocumentNode)
            ? (pageNode.parent as PdfDocumentNode).documentModel.totalPages
            : 0;
    if (totalPages == 0) return;

    final pageNum = pageNode.pageModel.pageIndex + 1;
    final label = '$pageNum / $totalPages';

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgePad = 6.0;
    final badgeW = tp.width + badgePad * 2;
    final badgeH = tp.height + badgePad;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        pageRect.right - badgeW - 8,
        pageRect.bottom - badgeH - 8,
        badgeW,
        badgeH,
      ),
      const Radius.circular(6),
    );

    canvas.drawRRect(badgeRect, _lockPillPaint); // reuse same dark pill paint
    tp.paint(
      canvas,
      Offset(badgeRect.left + badgePad, badgeRect.top + badgePad / 2),
    );
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
