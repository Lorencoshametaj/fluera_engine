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
import '../../core/engine_scope.dart';
import '../../core/nodes/shape_node.dart';
import '../cache/render_cache_scope.dart';
import '../../core/nodes/layer_node.dart';
import '../../core/nodes/group_node.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../core/scene_graph/node_id.dart'; // 🚀 Added for NodeId
import '../../core/effects/paint_stack.dart'; // 🚀 Added for FillLayer and StrokeLayer
import '../../core/nodes/pdf_page_node.dart';
import '../../core/models/pdf_annotation_model.dart';
import '../canvas/pdf_page_painter.dart';
import '../scene_graph/scene_graph_renderer.dart'; // 🚀 Added for GAP 3
import '../../tools/pdf/pdf_text_selection_controller.dart';
import '../../tools/pdf/pdf_search_controller.dart';
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

  // 🚀 Internal renderer — scoped to avoid cross-canvas contamination.
  SceneGraphRenderer get _delegateRenderer =>
      EngineScope.hasScope
          ? EngineScope.current.renderCacheScope.delegateRenderer
          : _fallbackDelegateRenderer;
  static final SceneGraphRenderer _fallbackDelegateRenderer =
      SceneGraphRenderer();

  // 🚀 TILE CACHING: Activates when stroke count exceeds config threshold
  // Below the threshold, direct rendering (StrokeCacheManager) is faster

  // 🚀 Tile cache manager (uses EngineScope)
  TileCacheManager? get _tileCacheRef =>
      EngineScope.hasScope ? EngineScope.current.tileCacheManager : null;

  // 🚀 Vectorial cache — scoped to EngineScope.
  StrokeCacheManager get _strokeCache =>
      EngineScope.hasScope
          ? EngineScope.current.renderCacheScope.strokeCache
          : _fallbackStrokeCache;
  static final StrokeCacheManager _fallbackStrokeCache = StrokeCacheManager();

  /// Scene graph version when the vectorial cache was last populated.
  /// Used alongside stroke count to detect non-stroke changes (shapes, text).
  int _cachedSceneVersion = -1;

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

  // 🔍 Search controller for full-text search highlights
  final PdfSearchController? pdfSearchController;

  // 📄 PDF layout version: incremented on in-place PDF mutations
  // (lock toggle, rotate, grid change) to force shouldRepaint → true.
  // Unlike sceneGraph (shared object ref), this is a value type that
  // differs between old and new painter instances.
  final int pdfLayoutVersion;

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
    this.pdfSearchController, // 🔍 Full-text search highlights
    this.pdfLayoutVersion = 0, // 📄 PDF layout mutation counter
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
      _paintWithTileCaching(canvas, viewport, effectiveScale);
    } else {
      _paintDirect(canvas, viewport);
    }

    // Draw the current shape in preview (not yet in scene graph)
    if (currentShape != null) {
      ShapePainter.drawShape(canvas, currentShape!, isPreview: true);
    }

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

  void _paintWithTileCaching(Canvas canvas, Rect viewport, double scale) {
    final tcm = _tileCacheRef;
    if (tcm == null) return; // No EngineScope — fall back to direct rendering

    // Calculate bounding box of ALL content
    final contentBounds = _calculateContentBounds();
    if (contentBounds == null) return;

    // 🗺️ Get ALL tiles that contain strokes
    final allContentTiles = tcm.getTilesForBounds(contentBounds);

    // 🛡️ FALLBACK: if too many tiles, use vector cache (always working)
    if (allContentTiles.length > TileCacheManager.maxCachedTiles) {
      _paintDirect(canvas, viewport);
      return;
    }

    // 🎯 Collect dirty tiles and sort by viewport priority
    final dirtyTiles = <(int, int)>[];
    for (final (tileX, tileY) in allContentTiles) {
      if (tcm.isTileDirty(tileX, tileY) || !tcm.hasTileCached(tileX, tileY)) {
        dirtyTiles.add((tileX, tileY));
      }
    }

    if (dirtyTiles.isNotEmpty) {
      // 🎯 VIEWPORT-PRIORITY: sort dirty tiles by distance from viewport center.
      // Visible/near tiles warm first, offscreen tiles warm later.
      final viewportCenter = viewport.center;
      final ts = tcm.currentTileSize;
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
        final tileBounds = tcm.getTileBounds(tileX, tileY, scale);
        final strokesInTile = _getStrokesInBounds(tileBounds);
        tcm.rasterizeTile(tileX, tileY, strokesInTile, devicePixelRatio);
        if (sw.elapsedMilliseconds >= frameBudgetMs) break;
      }
      sw.stop();
    }

    // Check if ALL tiles are now warm
    final allReady = allContentTiles.every(
      (t) => tcm.hasTileCached(t.$1, t.$2) && !tcm.isTileDirty(t.$1, t.$2),
    );

    if (allReady) {
      // ✅ All tiles cached — pure GPU bitmap compositing (fastest path)
      tcm.paintAllCachedTiles(canvas);
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
    // 🎨 PER-LAYER BLEND MODE: if any scene graph layer has non-default
    // compositing, render each layer inside its own saveLayer() group.
    final hasLayerCompositing = sceneGraph.layers.any(
      (l) => l.blendMode != ui.BlendMode.srcOver || l.opacity < 1.0,
    );

    if (hasLayerCompositing) {
      _paintPerLayer(canvas, viewport);
      return;
    }

    // 🚀 VECTORIAL CACHE: replay cached strokes + draw only new ones
    // This avoids re-rendering all N strokes via BrushEngine on every paint()
    final totalStrokes = _effectiveStrokes.length;
    final hasEraserPreview = eraserPreviewIds.isNotEmpty;

    // Cache invalidation: scene graph version changed (non-stroke changes)
    if (_cachedSceneVersion != sceneGraph.version) {
      _strokeCache.invalidateCache();
      invalidateLayerCaches();
      _cachedSceneVersion = sceneGraph.version;
    }

    // Cache invalidation: undo/delete (stroke count decreased)
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

    // 📄 Full render: no usable cache.
    // Delegate to SceneGraphRenderer for unified tree traversal.
    // This renders ALL node types (strokes, shapes, text, images, etc.)
    // in correct z-order, with viewport culling and adaptive LOD.
    final effectiveScale = controller?.scale ?? canvasScale;
    final hasEraserPreviewActive = eraserPreviewIds.isNotEmpty;

    // Render the scene graph via unified pipeline
    _delegateRenderer.render(
      canvas,
      sceneGraph,
      viewport,
      scale: effectiveScale,
    );

    // Draw eraser previews on top (overlay, not part of scene graph render)
    _drawEraserPreviews(canvas);

    // 🚀 RECORD-ONCE CACHE: record a full render into a Picture for future
    // O(1) replay. Only when enough strokes and no eraser preview.
    if (!hasEraserPreviewActive && _effectiveStrokes.length >= 5) {
      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);
      _delegateRenderer.render(
        recCanvas,
        sceneGraph,
        // Use infinite viewport for cache (include all content)
        const Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6),
        scale: 1.0,
      );
      _strokeCache.adoptPicture(
        recorder.endRecording(),
        _effectiveStrokes.length,
      );
      _cachedSceneVersion = sceneGraph.version;
    }
  }

  /// 🎨 Render strokes grouped by layer, each with its own blend mode.
  ///
  /// Per-layer vectorial caching: each layer's strokes are cached as a
  /// ui.Picture keyed by sceneGraph.version. ANY mutation (add, delete,
  /// modify, reorder) increments the version → automatic cache miss.
  /// Per-scope layer caches.
  Map<String, ui.Picture> get _layerCaches =>
      EngineScope.hasScope
          ? EngineScope.current.renderCacheScope.layerCaches
          : _fallbackLayerCaches;
  static final Map<String, ui.Picture> _fallbackLayerCaches = {};

  int get _layerCacheVersion =>
      EngineScope.hasScope
          ? EngineScope.current.renderCacheScope.layerCacheVersion
          : _fallbackLayerCacheVersion;
  set _layerCacheVersion(int value) {
    if (EngineScope.hasScope) {
      EngineScope.current.renderCacheScope.layerCacheVersion = value;
    } else {
      _fallbackLayerCacheVersion = value;
    }
  }

  static int _fallbackLayerCacheVersion = -1;

  /// Invalidate all per-layer caches (e.g. on undo or eraser).
  static void invalidateLayerCaches() {
    if (EngineScope.hasScope) {
      EngineScope.current.renderCacheScope.invalidateLayerCaches();
    } else {
      for (final picture in _fallbackLayerCaches.values) {
        picture.dispose();
      }
      _fallbackLayerCaches.clear();
      _fallbackLayerCacheVersion = -1;
    }
  }

  void _paintPerLayer(Canvas canvas, Rect viewport) {
    final hasEraserPreview = eraserPreviewIds.isNotEmpty;
    final effectiveScale = controller?.scale ?? canvasScale;

    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;

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

      final cacheKey = layer.id.value;
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

      // Cache miss: record this layer via SceneGraphRenderer into a Picture
      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);

      _delegateRenderer.renderNode(recCanvas, layer, viewport);

      final picture = recorder.endRecording();

      // Draw to live canvas
      canvas.drawPicture(picture);

      // Draw eraser previews on top (not cached)
      if (hasEraserPreview) {
        _drawEraserPreviews(canvas);
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

      // 🔑 Two-pass rendering: locked pages first, then unlocked on top.
      // When a page is unlocked, performGridLayout re-grids the remaining
      // locked pages, causing the next locked page to fill the unlocked
      // page's grid position. Without two-pass rendering, the locked page
      // paints ON TOP of the unlocked page, making it appear to vanish.
      final unlockedPages = <PdfPageNode>[];

      for (final child in node.children) {
        if (child is PdfPageNode && child.isVisible) {
          docPages.add(child);
          if (child.pageModel.isLocked) {
            _paintPdfPage(canvas, child, viewport, painter, node.id);
          } else {
            unlockedPages.add(child);
          }
        }
      }

      // Second pass: unlocked pages render on top
      for (final page in unlockedPages) {
        _paintPdfPage(canvas, page, viewport, painter, node.id);
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

  // 🏷️ Structured annotation render paints
  static final Paint _annotHighlightPaint = Paint(); // I6: reuse for highlights
  static final Paint _underlinePaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
  static final Paint _stickyIconBgPaint =
      Paint()..color = const Color(0xFFFFF176);
  static final Paint _stickyFoldPaint =
      Paint()..color = const Color(0x40000000); // I7: static fold paint
  static final Path _stickyFoldPath = Path(); // I7: reusable fold path

  /// Paint a single PDF page with professional styling.
  ///
  /// Features: drop shadow, white background, LOD-aware content via
  /// [PdfPagePainter], thin border. Falls back to a numbered placeholder
  /// if no [PdfPagePainter] is available for this document.
  void _paintPdfPage(
    Canvas canvas,
    PdfPageNode pageNode,
    Rect viewport,
    PdfPagePainter? painter, [
    String? documentId,
  ]) {
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

    // 📝 Structured annotations (highlights, underlines, sticky notes)
    final structuredAnnotations = pageNode.pageModel.structuredAnnotations;
    if (structuredAnnotations.isNotEmpty &&
        pageNode.pageModel.showAnnotations) {
      canvas.save();
      canvas.clipRect(pageRect);
      _paintStructuredAnnotations(canvas, structuredAnnotations, pageRect);
      canvas.restore();
    }

    // 🔍 Search highlights
    if (pdfSearchController != null && pdfSearchController!.hasMatches) {
      _paintSearchHighlights(canvas, pageNode, pageRect, documentId);
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
        oldDelegate.eraserPreviewIds != eraserPreviewIds ||
        oldDelegate.pdfLayoutVersion != pdfLayoutVersion;
  }

  /// 🚀 Incremental update: overlay new stroke on cached tiles
  /// Falls back to full invalidation for tiles not yet cached
  static void incrementalUpdateForStroke(
    ProStroke stroke,
    double devicePixelRatio,
  ) {
    if (!EngineScope.hasScope) return;
    final tcm = EngineScope.current.tileCacheManager;
    final bounds = stroke.bounds;
    if (bounds == Rect.zero) return;

    for (final (tileX, tileY) in tcm.getTilesForBounds(bounds)) {
      // Try incremental overlay on existing cached tile
      final success = tcm.incrementalUpdateTile(
        tileX,
        tileY,
        stroke,
        devicePixelRatio,
      );
      // If incremental failed (tile not in cache), mark dirty for full rasterization
      if (!success) {
        tcm.invalidateTile(tileX, tileY);
      }
    }
  }

  /// 🚀 Invalidate tiles involved by a stroke (call after add/remove)
  static void invalidateTilesForStroke(ProStroke stroke) {
    if (!EngineScope.hasScope) return;
    EngineScope.current.tileCacheManager.invalidateTilesForStroke(stroke);
  }

  /// 🚀 Invalidate all caches (call after complete undo or clear)
  static void invalidateAllTiles() {
    if (EngineScope.hasScope) {
      EngineScope.current.tileCacheManager.invalidateAll();
    }
    if (EngineScope.hasScope) {
      EngineScope.current.renderCacheScope.strokeCache.invalidateCache();
    }
    invalidateLayerCaches();
  }

  /// 🚀 Clear all caches and free memory (call when leaving the canvas)
  static void clearTileCache() {
    if (EngineScope.hasScope) {
      final scope = EngineScope.current;
      scope.tileCacheManager.clear();
      scope.renderCacheScope.strokeCache.invalidateCache();
      scope.renderCacheScope.strokeCache.clearUndoSnapshots();
    }
    invalidateLayerCaches();
  }

  // ===========================================================================
  // 🔍 PDF Search Highlights
  // ===========================================================================

  /// Paint search match highlights on a PDF page.
  ///
  /// Uses a realistic highlighter-marker effect: the rects are padded
  /// slightly (to absorb minor positioning imprecision) and drawn with
  /// soft, rounded edges that mimic a physical marker pen.
  void _paintSearchHighlights(
    Canvas canvas,
    PdfPageNode pageNode,
    Rect pageRect, [
    String? documentId,
  ]) {
    if (pdfSearchController == null || !pdfSearchController!.hasMatches) return;

    if (pageNode.textRects == null || pageNode.textRects!.isEmpty) {
      return;
    }

    final pageOffset = Offset(pageRect.left, pageRect.top);

    canvas.save();
    canvas.clipRect(pageRect);

    // All matches on this page (yellow marker)
    final allRects = pdfSearchController!.highlightRectsForPage(
      pageNode,
      documentId: documentId,
    );
    for (final r in allRects) {
      _drawMarkerHighlight(
        canvas,
        r.shift(pageOffset),
        _markerYellow,
        _markerYellowEdge,
      );
    }

    // Current match (orange marker + pulse)
    final currentRect = pdfSearchController!.currentMatchRectForPage(
      pageNode,
      documentId: documentId,
    );
    if (currentRect != null) {
      final ms = DateTime.now().millisecondsSinceEpoch;
      final phase = (ms % 1200) / 1200.0;
      final sinVal = math.sin(phase * 3.14159265 * 2);
      final alpha = (0.6 + 0.2 * sinVal).clamp(0.4, 0.8);
      final pulseFill =
          Paint()..color = Color.fromRGBO(255, 152, 0, alpha * 0.45);
      final pulseEdge =
          Paint()
            ..color = Color.fromRGBO(255, 130, 0, alpha * 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8;
      _drawMarkerHighlight(
        canvas,
        currentRect.shift(pageOffset),
        pulseFill,
        pulseEdge,
      );
    }

    canvas.restore();
  }

  /// Draw a single highlight with realistic marker-pen styling.
  ///
  /// Applies smart padding (H: ±4%, V: ±20% of line height) so the
  /// highlight comfortably covers the text even with small alignment
  /// imprecision. Uses generous corner radius (40% of height) for the
  /// soft, rounded look of a real marker stroke.
  void _drawMarkerHighlight(Canvas canvas, Rect r, Paint fill, Paint edge) {
    // Smart padding: absorb ~2-3% positioning imprecision
    final h = r.height;
    final w = r.width;
    final padH = w * 0.04; // 4% horizontal expansion
    final padV = h * 0.20; // 20% vertical expansion (markers are thick)
    final padded = Rect.fromLTRB(
      r.left - padH,
      r.top - padV,
      r.right + padH,
      r.bottom + padV,
    );

    // Generous corner radius (40% of padded height) → capsule-like ends
    final radius = Radius.circular(padded.height * 0.40);
    final rrect = RRect.fromRectAndRadius(padded, radius);

    // Fill + soft edge stroke (simulates marker ink-bleed)
    canvas.drawRRect(rrect, fill);
    canvas.drawRRect(rrect, edge);
  }

  // Pre-built paints for marker-style highlights
  static final Paint _markerYellow =
      Paint()..color = const Color(0x38FFEB3B); // Yellow ~22% opacity
  static final Paint _markerYellowEdge =
      Paint()
        ..color = const Color(0x18FBC02D) // Darker yellow ~10% opacity
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

  // ===========================================================================
  // 🏷️ PDF Structured Annotations
  // ===========================================================================

  /// Paint structured annotations (highlights, underlines, sticky notes).
  ///
  /// Assumes canvas is already clipped to page bounds.
  void _paintStructuredAnnotations(
    Canvas canvas,
    List<PdfAnnotation> annotations,
    Rect pageRect,
  ) {
    final pageOffset = Offset(pageRect.left, pageRect.top);

    for (final annotation in annotations) {
      final annotRect = annotation.rect.shift(pageOffset);

      // I8: Skip annotations entirely outside the page clip rect
      if (!annotRect.overlaps(pageRect)) continue;

      switch (annotation.type) {
        case PdfAnnotationType.highlight:
          // I6: Reuse static Paint — set color per annotation
          _annotHighlightPaint.color = annotation.color;
          canvas.drawRect(annotRect, _annotHighlightPaint);

        case PdfAnnotationType.underline:
          _underlinePaint.color = annotation.color;
          canvas.drawLine(
            Offset(annotRect.left, annotRect.bottom),
            Offset(annotRect.right, annotRect.bottom),
            _underlinePaint,
          );

        case PdfAnnotationType.stickyNote:
          final iconSize = math.min(20.0, annotRect.width);
          final iconRect = Rect.fromLTWH(
            annotRect.left,
            annotRect.top,
            iconSize,
            iconSize,
          );
          _stickyIconBgPaint.color = annotation.color;
          canvas.drawRRect(
            RRect.fromRectAndRadius(iconRect, const Radius.circular(3)),
            _stickyIconBgPaint,
          );
          // I7: Reuse static fold Path — reset and rebuild
          final foldSize = iconSize * 0.3;
          _stickyFoldPath.reset();
          _stickyFoldPath.moveTo(iconRect.right - foldSize, iconRect.top);
          _stickyFoldPath.lineTo(iconRect.right, iconRect.top + foldSize);
          _stickyFoldPath.lineTo(
            iconRect.right - foldSize,
            iconRect.top + foldSize,
          );
          _stickyFoldPath.close();
          canvas.drawPath(_stickyFoldPath, _stickyFoldPaint);
      }
    }
  }
}
