import 'package:flutter/material.dart';
import '../../drawing/models/surface_material.dart';
import '../../services/canvas_performance_monitor.dart';
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
import '../../core/nodes/tabular_node.dart';
import '../scene_graph/tabular_renderer.dart';

import '../optimization/dirty_region_tracker.dart'; // 🎨 Phase 3: Incremental rendering
import '../optimization/tile_cache_manager.dart'; // 🧩 Tile caching
import '../optimization/stroke_paging_manager.dart'; // 🗂️ Stroke paging to disk
import '../../systems/spatial_index.dart' as si; // 🌲 R-Tree for render path
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

  // 🚀 Vectorial cache — scoped to EngineScope.
  StrokeCacheManager get _strokeCache =>
      EngineScope.hasScope
          ? EngineScope.current.renderCacheScope.strokeCache
          : _fallbackStrokeCache;
  static final StrokeCacheManager _fallbackStrokeCache = StrokeCacheManager();

  /// Scene graph version when the vectorial cache was last populated.
  /// Used alongside stroke count to detect non-stroke changes (shapes, text).
  int _cachedSceneVersion = -1;

  /// Viewport used when the current stroke cache was built.
  /// If the real viewport moves outside this area, the cache is invalidated
  /// so that newly-visible strokes are rendered.
  static Rect _cachedCacheViewport = Rect.zero;

  /// Inflated viewport used during the last paint() for PDF page rendering.
  /// When the real viewport exits this area, shouldRepaint returns true
  /// so that newly-visible PDF pages are rendered into the raster cache.
  static Rect _lastRenderedPdfViewport = Rect.zero;

  /// Widget size from the last paint() call, needed for viewport calculation
  /// in shouldRepaint (where the paint size parameter isn't available).
  static Size _lastPaintSize = Size.zero;

  /// 🧩 Tile cache for regional invalidation.
  /// Shared across DrawingPainter instances via EngineScope or static fallback.
  static final TileCacheManager _tileCache = TileCacheManager();

  /// 🌲 R-Tree spatial index for O(log N) node lookup during tile rebuild.
  static final si.SpatialIndex _renderIndex = si.SpatialIndex();
  static int _renderIndexVersion = -1;
  static int _renderIndexNodeCount = 0;
  static List<ProStroke>? _lastMaterializedStrokes;

  /// 🗂️ Stroke paging manager for memory-bounded 1M+ strokes.
  static final StrokePagingManager _pagingManager = StrokePagingManager();
  static bool _pagingInProgress = false;
  static Rect _lastPagingViewport = Rect.zero;

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

  // 🧬 Canvas surface material: passed to BrushEngine for surface-aware shaders
  final SurfaceMaterial? surface;
  final String?
  paperType; // 🚀 LAYER MERGE — not in shouldRepaint (cosmetic only)
  final Color?
  backgroundColor; // 🚀 LAYER MERGE — not in shouldRepaint (cosmetic only)

  /// 🚀 PERF: Per-page incremental annotation Picture cache.
  /// Key: pageIndex → cached (annotationCount, Picture).
  static final Map<int, _AnnotCacheEntry> _annotationPictureCache = {};

  /// 🚀 PERF: Lightweight PDF drag mode.
  /// When true, paint() skips ALL heavy rendering (strokes, PDF pages,
  /// annotations) and only draws simple rectangles for the dragged pages.
  /// Set by the drag controller at drag start, cleared at drag end.
  static bool isDraggingPdf = false;

  /// Rectangles of the pages being dragged — drawn as lightweight
  /// placeholders during drag. Set per frame by the drag update handler.
  static List<Rect> draggedPageRects = const [];

  // 🌲 Cached materialized strokes (lazily computed once per scene graph version)
  // STATIC: persists across DrawingPainter recreations (setState doesn't
  // destroy the cache). Without static, O(N) traversal runs on every widget
  // rebuild — catastrophic at 1M+ strokes.
  static List<ProStroke>? _materializedCache;
  static int _materializedVersion = -1;

  /// Scene graph version captured at construction time.
  ///
  /// `shouldRepaint` must compare THIS value (not `sceneGraph.version`)
  /// because both old and new delegates share the SAME SceneGraph object
  /// reference — by the time `shouldRepaint` runs, `bumpVersion()` has
  /// already mutated the shared instance, making live comparison useless.
  final int _sceneGraphVersion;

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
    this.showPdfPageNumbers = true, // 📑 Page number badges
    this.surface, // 🧬 Surface material for shader-aware rendering
    this.paperType,
    this.backgroundColor,
  }) : _sceneGraphVersion = sceneGraph.version,
       super(); // 🚀 NO repaint: controller — parent Transform handles pan/zoom
  // Flutter's raster cache persists across transform changes = 0ms raster

  /// 🌲 Effective strokes: materialized from the scene graph tree.
  ///
  /// FULLY INCREMENTAL:
  /// - Cache hit (same version): O(1) — returns cached list
  /// - New strokes added: O(k) append — only collects new strokes
  /// - Undo (strokes removed): O(k) trim from end
  /// - Structural change: O(N) full rebuild (rare: layer visibility, reorder)
  List<ProStroke> get _effectiveStrokes {
    if (_materializedCache != null &&
        _materializedVersion == sceneGraph.version) {
      return _materializedCache!;
    }

    if (_materializedCache == null) {
      // First build — full traversal O(N)
      _materializedCache = _collectAllStrokes();
      _materializedVersion = sceneGraph.version;
      return _materializedCache!;
    }

    // O(L) count where L = number of layers (usually 1-5)
    final currentCount = _countStrokes();
    final cachedCount = _materializedCache!.length;

    if (currentCount > cachedCount) {
      // ✅ ADD PATH: collect only the new tail strokes
      // Strokes are always appended at the end → skip the first cachedCount
      int skipped = 0;
      final newStrokes = <ProStroke>[];
      for (final layer in sceneGraph.layers) {
        if (!layer.isVisible) continue;
        _collectStrokesSkipping(layer, newStrokes, cachedCount, skipped);
        skipped += layer.strokes.length;
      }
      if (newStrokes.isNotEmpty) {
        _materializedCache!.addAll(newStrokes);
      } else {
        // Fallback: structural change — full rebuild
        _materializedCache = _collectAllStrokes();
      }
    } else if (currentCount < cachedCount) {
      // ✅ UNDO PATH O(1): trim from end — undo always removes last stroke
      _materializedCache!.length = currentCount;
    }
    // else: same count, different version — property change, cache valid

    _materializedVersion = sceneGraph.version;
    return _materializedCache!;
  }

  /// Collect strokes from a node, skipping the first [skip] strokes.
  /// Only adds strokes after the skip count to [result].
  static void _collectStrokesSkipping(
    CanvasNode node,
    List<ProStroke> result,
    int skip,
    int alreadySkipped,
  ) {
    if (node is StrokeNode) {
      if (alreadySkipped >= skip) {
        result.add(node.stroke);
      }
    } else if (node is GroupNode) {
      int localSkipped = alreadySkipped;
      for (final child in node.children) {
        if (!child.isVisible) continue;
        _collectStrokesSkipping(child, result, skip, localSkipped);
        localSkipped += (child is StrokeNode) ? 1 : 0;
      }
    }
  }

  /// Count total strokes across visible layers — O(L) where L = layer count.
  ///
  /// Uses CanvasLayer.strokes.length (O(1) per layer) instead of recursive
  /// scene graph traversal. Typical L = 1-5 → effectively O(1).
  int _countStrokes() {
    int count = 0;
    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      count += layer.strokes.length;
    }
    return count;
  }

  /// Collect all strokes from visible layers (full traversal).
  List<ProStroke> _collectAllStrokes() {
    final result = <ProStroke>[];
    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      _collectStrokes(layer, result);
    }
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

  /// 🌲 Ensure the render R-Tree is up to date with the scene graph.
  ///
  /// FULLY INCREMENTAL:
  /// - New strokes → insert O(k log N)
  /// - Undo/delete → remove O(k log N) instead of rebuild O(N log N)
  /// - Full rebuild only on first build
  void _ensureRenderIndex() {
    if (_renderIndexVersion == sceneGraph.version) return;

    final currentStrokes = _effectiveStrokes;
    final newCount = currentStrokes.length;
    final oldCount = _renderIndexNodeCount;

    if (_renderIndexVersion == -1) {
      // First build: full rebuild
      final nodes = <CanvasNode>[];
      for (final layer in sceneGraph.layers) {
        if (!layer.isVisible) continue;
        _collectLeafNodes(layer, nodes);
      }
      _renderIndex.rebuild(nodes);
      _renderIndexNodeCount = newCount;
    } else if (newCount < oldCount) {
      // Undo/delete: find removed strokes and remove them from R-Tree
      // Build set of current stroke IDs for O(1) lookup
      final currentIds = <String>{};
      for (final s in currentStrokes) {
        currentIds.add(s.id);
      }
      // Find IDs in the old cache that are no longer present
      final oldCache = _lastMaterializedStrokes;
      if (oldCache != null) {
        for (final s in oldCache) {
          if (!currentIds.contains(s.id)) {
            _renderIndex.remove(s.id);
          }
        }
        _renderIndexNodeCount = newCount;
      } else {
        // Fallback: no old cache → full rebuild
        final nodes = <CanvasNode>[];
        for (final layer in sceneGraph.layers) {
          if (!layer.isVisible) continue;
          _collectLeafNodes(layer, nodes);
        }
        _renderIndex.rebuild(nodes);
        _renderIndexNodeCount = newCount;
      }
    } else if (newCount > oldCount) {
      // New strokes added: insert only the new ones → O(k log N)
      for (int i = oldCount; i < newCount; i++) {
        final stroke = currentStrokes[i];
        _insertStrokeNode(stroke);
      }
      _renderIndexNodeCount = newCount;
    }
    // else: version changed but stroke count same (e.g. property change)
    // — R-Tree bounds are still valid, skip rebuild

    // Save current strokes for next undo comparison
    _lastMaterializedStrokes = currentStrokes;
    _renderIndexVersion = sceneGraph.version;
  }

  /// Insert a StrokeNode into the R-Tree by finding it in the scene graph.
  void _insertStrokeNode(ProStroke stroke) {
    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      final node = _findStrokeNode(layer, stroke);
      if (node != null) {
        _renderIndex.insert(node);
        return;
      }
    }
  }

  /// Find the CanvasNode that wraps a given ProStroke.
  static CanvasNode? _findStrokeNode(CanvasNode node, ProStroke stroke) {
    if (node is StrokeNode && identical(node.stroke, stroke)) {
      return node;
    }
    if (node is GroupNode) {
      // Search in reverse — new strokes are typically at the end
      for (int i = node.children.length - 1; i >= 0; i--) {
        final child = node.children[i];
        final found = _findStrokeNode(child, stroke);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Recursively collect leaf CanvasNodes for R-Tree indexing.
  static void _collectLeafNodes(CanvasNode node, List<CanvasNode> result) {
    if (node is GroupNode) {
      for (final child in node.children) {
        if (child.isVisible) _collectLeafNodes(child, result);
      }
    } else if (node.isVisible) {
      // Leaf node (StrokeNode, ShapeNode, TextNode, ImageNode, etc.)
      result.add(node);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 🔬 DIAGNOSTIC: per-section timing
    final _sw = Stopwatch()..start();

    // 🏎️ PERFORMANCE MONITORING: measure frame time
    CanvasPerformanceMonitor.instance.startFrame();

    // 🚀 SHADER WARM-UP: Pre-compile all GPU shaders on the first paint frame.
    // Avoids jank on the user's first stroke. Only runs once (_warmedUp guard).
    EngineScope.current.drawingModule?.shaderBrushService.warmUp(canvas);

    // ✂️ Collect PDF annotation IDs (cached per scene graph version)
    _collectPdfAnnotationIds();

    final _t0 = _sw.elapsedMicroseconds;

    // ✂️ Applica clipping se abilitato (per editing immagini)
    if (enableClipping) {
      canvas.clipRect(Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height));
    }

    // 🚀 VIEWPORT-LEVEL MODE: compute viewport for culling.
    // The TRANSFORM is applied by the parent widget (not here) so that
    // Flutter's raster cache persists across pan/zoom changes.
    final isViewportLevel = controller != null;
    final effectiveOffset = isViewportLevel ? controller!.offset : canvasOffset;
    final effectiveScale = isViewportLevel ? controller!.scale : canvasScale;
    final effectiveViewportSize = isViewportLevel ? size : viewportSize;
    if (isViewportLevel) _lastPaintSize = size;

    if (!isViewportLevel) {
      // Legacy mode (non-viewport): apply transform here
      canvas.save();
      canvas.translate(effectiveOffset.dx, effectiveOffset.dy);
      canvas.scale(effectiveScale);
    }

    // 🚀 VIEWPORT CULLING: calculate current viewport
    final viewport = ViewportCuller.calculateViewport(
      effectiveViewportSize,
      effectiveOffset,
      effectiveScale,
      rotation: controller?.rotation ?? 0.0,
    );

    // 🚀 LIGHTWEIGHT PDF DRAG: skip ALL heavy rendering, just replay
    // the existing stroke cache and draw simple page rectangles.
    if (isDraggingPdf) {
      // Replay cached strokes (O(1) drawPicture)
      _strokeCache.drawCached(canvas);

      // Draw lightweight page placeholders
      final dragPaint =
          Paint()
            ..color = const Color(0x30000000)
            ..style = PaintingStyle.fill;
      final borderPaint =
          Paint()
            ..color = const Color(0xFF1976D2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 / effectiveScale;
      for (final rect in draggedPageRects) {
        canvas.drawRect(rect, dragPaint);
        canvas.drawRect(rect, borderPaint);
      }

      if (!isViewportLevel) canvas.restore();
      CanvasPerformanceMonitor.instance.endFrame(_effectiveStrokes.length);
      return;
    }

    {
      // Vectorial cache path
      final tracker = dirtyRegionTracker;
      final hasDirty = tracker != null && tracker.hasDirtyRegions;
      final totalStrokes = _effectiveStrokes.length;
      if (hasDirty) {
        final dirtyBounds = tracker.dirtyBounds;
        if (dirtyBounds != null && _strokeCache.isCacheValid(totalStrokes)) {
          canvas.save();
          canvas.clipRect(dirtyBounds);
          _paintDirect(canvas, viewport, isDirtyClipped: true);
          canvas.restore();
        } else {
          _paintDirect(canvas, viewport);
        }
      } else {
        _paintDirect(canvas, viewport);
      }
    }

    final _t1 = _sw.elapsedMicroseconds;

    // Draw the current shape in preview (not yet in scene graph)
    if (currentShape != null) {
      ShapePainter.drawShape(canvas, currentShape!, isPreview: true);
    }

    // 📄 Draw PDF documents
    // 🚀 Inflate viewport to pre-render off-screen pages. With the Transform
    // architecture, paint() doesn't re-run on pan/zoom — the Transform
    // widget reveals cached raster. Pages must already be in the cache.
    final pdfViewport = viewport.inflate(viewport.longestSide * 2.0);
    _paintPdfDocuments(canvas, pdfViewport);
    _lastRenderedPdfViewport = pdfViewport;

    final _t2 = _sw.elapsedMicroseconds;

    // 📊 Draw Tabular (spreadsheet) nodes
    _paintTabularNodes(canvas, pdfViewport);

    // 🎨 Phase 3: Clear dirty regions after paint (prevents accumulation)
    dirtyRegionTracker?.clearDirty();

    // Clear per-frame skip set
    _pdfAnnotationIds = null;
    _delegateRenderer.skipStrokeIds = null;

    if (!isViewportLevel) {
      canvas.restore();
    }

    // 🏎️ PERFORMANCE MONITORING: end frame measurement
    CanvasPerformanceMonitor.instance.endFrame(_effectiveStrokes.length);

    // 🔬 DIAGNOSTIC: print breakdown on frames > 5ms
    final totalUs = _sw.elapsedMicroseconds;
    if (totalUs > 5000) {
      print(
        '🔬 PAINT ${(totalUs / 1000).toStringAsFixed(1)}ms: '
        'setup=${(_t0 / 1000).toStringAsFixed(1)}ms '
        'strokes=${((_t1 - _t0) / 1000).toStringAsFixed(1)}ms '
        'pdf=${((_t2 - _t1) / 1000).toStringAsFixed(1)}ms '
        'rest=${((totalUs - _t2) / 1000).toStringAsFixed(1)}ms',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // ✂️ PDF ANNOTATION ID COLLECTION
  // ---------------------------------------------------------------------------

  /// Per-frame set of stroke IDs linked to PDF pages.
  /// Strokes in this set are SKIPPED from the global render pass
  /// because they are drawn clipped inside [_paintPdfPage].
  Set<String>? _pdfAnnotationIds;

  /// Cached PDF annotation IDs and the scene version when they were collected.
  static Set<String>? _cachedPdfAnnotationIds;
  static int _cachedPdfAnnotationVersion = -1;

  /// Collect PDF annotation stroke IDs. Cached per scene graph version
  /// to avoid walking the tree every paint() call.
  void _collectPdfAnnotationIds() {
    if (_cachedPdfAnnotationVersion == sceneGraph.version) {
      _pdfAnnotationIds = _cachedPdfAnnotationIds;
      _delegateRenderer.skipStrokeIds = _cachedPdfAnnotationIds;
      return;
    }

    Set<String>? ids;
    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      _collectPdfAnnotationIdsFromNode(layer, ids ??= <String>{});
    }
    _pdfAnnotationIds = ids;
    _delegateRenderer.skipStrokeIds = ids;

    // Cache for next paint()
    _cachedPdfAnnotationIds = ids;
    _cachedPdfAnnotationVersion = sceneGraph.version;
  }

  /// Recursively collect annotation IDs from PDF nodes in a subtree.
  static void _collectPdfAnnotationIdsFromNode(
    CanvasNode node,
    Set<String> ids,
  ) {
    if (node is PdfDocumentNode) {
      for (final page in node.pageNodes) {
        final annotations = page.pageModel.annotations;
        if (annotations.isNotEmpty) {
          ids.addAll(annotations);
        }
      }
    } else if (node is GroupNode) {
      for (final child in node.children) {
        if (child.isVisible) {
          _collectPdfAnnotationIdsFromNode(child, ids);
        }
      }
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
  void _paintDirect(
    Canvas canvas,
    Rect viewport, {
    bool isDirtyClipped = false,
  }) {
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

    // Cache invalidation: scene graph version changed
    // 🚀 PERF: Do NOT invalidate _strokeCache here — the incremental
    // path handles new strokes efficiently (O(delta)). PDF pages are
    // excluded from the cache via skipPdfNodes, so no ghost pages.
    if (_cachedSceneVersion != sceneGraph.version) {
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

    // 🚀 VIEWPORT-BASED CACHE INVALIDATION: if the user has panned/zoomed
    // outside the area covered by the cached Picture, rebuild it.
    if (_strokeCache.isCacheValid(totalStrokes) &&
        _cachedCacheViewport != Rect.zero &&
        !(viewport.left >= _cachedCacheViewport.left &&
            viewport.top >= _cachedCacheViewport.top &&
            viewport.right <= _cachedCacheViewport.right &&
            viewport.bottom <= _cachedCacheViewport.bottom)) {
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

    // � Full render: no usable global cache.
    // 🧩 TILE CACHE: instead of rendering all strokes into one Picture,
    // render per-tile. Only missing/invalidated tiles are rebuilt.
    final hasEraserPreviewActive = eraserPreviewIds.isNotEmpty;

    // Can't use tile cache during eraser preview or dirty-clipped mode
    if (hasEraserPreviewActive ||
        isDirtyClipped ||
        _effectiveStrokes.length < 5) {
      // Fallback: direct render without caching
      final cacheViewport = viewport.inflate(viewport.longestSide * 2.0);
      final effectiveScale = controller?.scale ?? canvasScale;
      _delegateRenderer.skipPdfNodes = true;
      _delegateRenderer.render(
        canvas,
        sceneGraph,
        cacheViewport,
        scale: effectiveScale,
      );
      _delegateRenderer.skipPdfNodes = false;
      _drawEraserPreviews(canvas);
      return;
    }

    // 🧩 TILE CACHE PATH: draw cached tiles + rebuild missing ones
    // Invalidate tiles if scene changed (new stroke, undo, etc.)
    if (_tileCache.cachedStrokeCount != totalStrokes ||
        _tileCache.cachedVersion != sceneGraph.version) {
      // Find which strokes changed and invalidate only their tiles
      if (totalStrokes > _tileCache.cachedStrokeCount &&
          _tileCache.hasCachedTiles) {
        // New strokes added: invalidate only touched tiles
        for (int i = _tileCache.cachedStrokeCount; i < totalStrokes; i++) {
          final stroke = _effectiveStrokes[i];
          _tileCache.invalidateForBounds(stroke.bounds);
        }
      } else {
        // Undo/delete/major change: invalidate all
        _tileCache.invalidateAll();
      }
    }

    // 🌲 Ensure R-Tree is up to date for O(log N) tile queries
    _ensureRenderIndex();

    // Draw cached tiles and collect missing ones
    final missingTiles = _tileCache.drawAndCollectMissing(canvas, viewport);

    // Rebuild missing tiles using R-Tree O(log N) query
    for (final tileKey in missingTiles) {
      final tileBounds = TileCacheManager.tileBounds(tileKey);
      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);

      // 🌲 R-TREE QUERY: O(log N) instead of O(N) scene graph traversal
      final visibleNodes = _renderIndex.queryRange(tileBounds);
      for (final node in visibleNodes) {
        // Skip PDF nodes — rendered separately in _paintPdfDocuments
        if (node is PdfDocumentNode || node is PdfPageNode) continue;
        // Skip stub strokes (paged out to disk, no points to render)
        if (node is StrokeNode && node.stroke.isStub) continue;
        _delegateRenderer.renderNode(recCanvas, node, tileBounds);
      }

      final picture = recorder.endRecording();
      canvas.drawPicture(picture);
      _tileCache.cacheTile(tileKey, picture, sceneGraph.version);
    }

    // Mark tile cache as valid
    _tileCache.markValid(totalStrokes, sceneGraph.version);

    // Also update the global stroke cache for fast O(1) replay on next frame
    // Record all visible tiles into one Picture for the StrokeCacheManager
    if (missingTiles.isNotEmpty) {
      final globalRecorder = ui.PictureRecorder();
      final globalCanvas = Canvas(globalRecorder);
      _tileCache.drawAndCollectMissing(globalCanvas, viewport);
      final globalPicture = globalRecorder.endRecording();
      _strokeCache.adoptPicture(globalPicture, totalStrokes);
      _cachedSceneVersion = sceneGraph.version;
      _cachedCacheViewport = viewport.inflate(viewport.longestSide * 2.0);
    }

    // Draw eraser previews on top (overlay, not part of scene graph render)
    _drawEraserPreviews(canvas);

    // 🗂️ Trigger async stroke paging (non-blocking)
    _triggerPagingIfNeeded(viewport);
  }

  /// 🗂️ Async stroke paging: page out far strokes, page in near stubs.
  ///
  /// Runs in a fire-and-forget Future to avoid blocking paint.
  /// Uses hysteresis (8192 out / 4096 in) to prevent thrashing.
  void _triggerPagingIfNeeded(Rect viewport) {
    if (_pagingInProgress) return;
    if (!_pagingManager.isInitialized) return;
    final totalStrokes = _effectiveStrokes.length;
    if (totalStrokes < 500) return; // Not enough strokes to bother

    // Check if viewport moved enough to trigger paging
    if (_lastPagingViewport != Rect.zero) {
      final dx = (viewport.center.dx - _lastPagingViewport.center.dx).abs();
      final dy = (viewport.center.dy - _lastPagingViewport.center.dy).abs();
      if (dx < 2048 && dy < 2048) return; // Not moved enough
    }

    _pagingInProgress = true;
    _lastPagingViewport = viewport;

    // TODO: get canvasId from EngineScope or DrawingPainter field
    final canvasId = 'current'; // placeholder

    // Fire-and-forget: page out then page in
    Future<void>(() async {
      try {
        // Page out strokes far from viewport
        final pagedOut = await _pagingManager.pageOut(
          canvasId,
          _effectiveStrokes,
          viewport,
        );

        // Page in stubs that are now near viewport
        final restored = await _pagingManager.pageIn(viewport);

        // Replace stubs with restored strokes in scene graph
        if (restored.isNotEmpty) {
          for (final layer in sceneGraph.layers) {
            _replaceStubs(layer, restored);
          }
          // Invalidate caches for restored strokes
          for (final stroke in restored.values) {
            _tileCache.invalidateForBounds(stroke.bounds);
          }
        }

        // Replace full strokes with stubs for paged-out ones
        if (pagedOut.isNotEmpty) {
          final pagedOutSet = pagedOut.toSet();
          for (final layer in sceneGraph.layers) {
            _stubifyStrokes(layer, pagedOutSet);
          }
        }
      } finally {
        _pagingInProgress = false;
      }
    });
  }

  /// Replace stub strokes in the scene graph with restored full strokes.
  static void _replaceStubs(CanvasNode node, Map<String, ProStroke> restored) {
    if (node is StrokeNode && restored.containsKey(node.stroke.id)) {
      node.stroke = restored[node.stroke.id]!;
    } else if (node is GroupNode) {
      for (final child in node.children) {
        _replaceStubs(child, restored);
      }
    }
  }

  /// Replace full strokes with stubs for paged-out stroke IDs.
  static void _stubifyStrokes(CanvasNode node, Set<String> pagedOutIds) {
    if (node is StrokeNode && pagedOutIds.contains(node.stroke.id)) {
      if (!node.stroke.isStub) {
        node.stroke = node.stroke.toStub();
      }
    } else if (node is GroupNode) {
      for (final child in node.children) {
        _stubifyStrokes(child, pagedOutIds);
      }
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
    // 🚀 Always clear annotation cache — annotations may have moved
    // (e.g. PDF page drag translates stroke coordinates; count stays
    // the same but positions change → stale cache = wrong rendering).
    for (final p in _annotationPictureCache.values) {
      p.picture.dispose();
    }
    _annotationPictureCache.clear();

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

  /// 🚀 PERF: Invalidate ONLY the annotation Picture cache.
  /// Used during PDF page/document drag — annotation positions change
  /// but non-annotation strokes don't move, so stroke cache is preserved.
  static void invalidateAnnotationCaches() {
    for (final p in _annotationPictureCache.values) {
      p.picture.dispose();
    }
    _annotationPictureCache.clear();
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
      //  Culling: If document is off-screen, skip its pages entirely
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
            _paintPdfPage(
              canvas,
              child,
              viewport,
              painter,
              node.id,
              node.documentModel.nightMode,
            );
          } else {
            unlockedPages.add(child);
          }
        }
      }

      // Second pass: unlocked pages render on top
      for (final page in unlockedPages) {
        _paintPdfPage(
          canvas,
          page,
          viewport,
          painter,
          node.id,
          node.documentModel.nightMode,
        );
      }
    } else if (node is GroupNode) {
      for (final child in node.children) {
        if (child.isVisible) {
          _collectAndPaintPdfNodes(canvas, child, viewport, pagesPerDocument);
        }
      }
    }
  }

  // --------------------------------------------------------------------------
  // 📊 TABULAR NODE RENDERING
  // --------------------------------------------------------------------------

  /// Paint all TabularNode instances found in the scene graph.
  void _paintTabularNodes(Canvas canvas, Rect viewport) {
    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      _collectAndPaintTabularNodes(canvas, layer, viewport);
    }
    // Also check rootNode children (nodes added directly to root)
    for (final child in sceneGraph.rootNode.children) {
      if (child.isVisible) {
        _collectAndPaintTabularNodes(canvas, child, viewport);
      }
    }
  }

  /// Recursively find and paint TabularNodes in a subtree.
  void _collectAndPaintTabularNodes(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
  ) {
    if (node is TabularNode) {
      // Apply the node's local transform (position on canvas)
      canvas.save();
      final tx = node.localTransform.getTranslation();
      canvas.translate(tx.x, tx.y);
      // Transform viewport into the node's local space for culling/LOD.
      final localViewport = viewport.translate(-tx.x, -tx.y);
      TabularRenderer.drawTabularNode(canvas, node, visibleRect: localViewport);
      canvas.restore();
    } else if (node is GroupNode) {
      for (final child in node.children) {
        if (child.isVisible) {
          _collectAndPaintTabularNodes(canvas, child, viewport);
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
    bool nightMode = false,
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

    // Compute the effective rect accounting for rotation (for clipping/hit-test)
    final Rect effectiveRect;
    if (rotation != 0) {
      final quarterTurns = (rotation / (math.pi / 2)).round() % 4;
      if (quarterTurns == 1 || quarterTurns == 3) {
        effectiveRect = Rect.fromCenter(
          center: pageRect.center,
          width: size.height,
          height: size.width,
        );
      } else {
        effectiveRect = pageRect;
      }
    } else {
      effectiveRect = pageRect;
    }

    // ─── ROTATED CONTENT ────────────────────────────────────────────────
    // Page content (shadow, background, raster, border) is painted inside
    // the rotation transform so it visually rotates.
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
        nightMode: nightMode,
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

    // Thin border
    canvas.drawRect(pageRect, _pdfBorderPaint);

    // 💧 Watermark overlay (rotated diagonal text)
    if (documentId != null) {
      // Find the doc node to get watermark text
      for (final layer in sceneGraph.layers) {
        for (final child in layer.children) {
          if (child is PdfDocumentNode &&
              child.id == documentId &&
              child.documentModel.watermarkText != null) {
            final wm = child.documentModel.watermarkText!;
            canvas.save();
            final cx = pageRect.center.dx;
            final cy = pageRect.center.dy;
            canvas.translate(cx, cy);
            canvas.rotate(-0.5); // ~29°
            final tp = TextPainter(
              text: TextSpan(
                text: wm,
                style: TextStyle(
                  color: const Color(0x18000000),
                  fontSize: pageRect.width * 0.12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
            canvas.restore();
            break;
          }
        }
      }
    }

    // Close rotation transform — everything below is world-space
    if (rotation != 0) {
      canvas.restore();
    }

    // ─── WORLD-SPACE OVERLAYS ───────────────────────────────────────────
    // Annotations (strokes) are in world coordinates and must NOT be rotated.
    // Clip to the effective rotated page bounds so they only appear on the
    // visible page area.
    final annotations = pageNode.pageModel.annotations;
    if (annotations.isNotEmpty && pageNode.pageModel.showAnnotations) {
      // 🚀 PERF: Incremental annotation Picture cache.
      // Instead of re-rendering ALL annotations on cache miss,
      // replay the PREVIOUS cache + render only NEW annotations.
      // Cost: O(delta) instead of O(n), where delta is typically 1.
      final pageIdx = pageNode.pageModel.pageIndex;
      final cacheEntry = _annotationPictureCache[pageIdx];

      if (cacheEntry != null && cacheEntry.count == annotations.length) {
        // ✅ Cache hit: O(1) replay
        canvas.save();
        canvas.clipRect(effectiveRect);
        canvas.drawPicture(cacheEntry.picture);
        canvas.restore();
      } else {
        // Cache miss: incremental render
        final recorder = ui.PictureRecorder();
        final recCanvas = Canvas(recorder);

        if (cacheEntry != null && cacheEntry.count < annotations.length) {
          // 🚀 Incremental: replay old cache + render only NEW annotations
          recCanvas.drawPicture(cacheEntry.picture);
          // Only the delta annotations (from old count to new count)
          final newIds = annotations.sublist(cacheEntry.count);
          _paintPageAnnotations(recCanvas, newIds);
        } else {
          // Full rebuild (first time or count decreased)
          _paintPageAnnotations(recCanvas, annotations);
        }

        // Dispose old and store new
        cacheEntry?.picture.dispose();
        final newPicture = recorder.endRecording();
        _annotationPictureCache[pageIdx] = _AnnotCacheEntry(
          count: annotations.length,
          picture: newPicture,
        );

        // Draw on main canvas
        canvas.save();
        canvas.clipRect(effectiveRect);
        canvas.drawPicture(newPicture);
        canvas.restore();
      }
    }

    // 📝 Text selection highlight overlay
    if (pdfTextSelection != null &&
        pdfTextSelection!.isNotEmpty &&
        pdfTextSelection!.pageIndex == pageNode.pageModel.pageIndex) {
      _paintTextSelectionOverlay(canvas, pdfTextSelection!, effectiveRect);
    }

    // 📝 Structured annotations (highlights, underlines, sticky notes)
    final structuredAnnotations = pageNode.pageModel.structuredAnnotations;
    if (structuredAnnotations.isNotEmpty &&
        pageNode.pageModel.showAnnotations) {
      canvas.save();
      canvas.clipRect(effectiveRect);
      _paintStructuredAnnotations(canvas, structuredAnnotations, effectiveRect);
      canvas.restore();
    }

    // 🔍 Search highlights
    if (pdfSearchController != null && pdfSearchController!.hasMatches) {
      _paintSearchHighlights(canvas, pageNode, effectiveRect, documentId);
    }

    // 📑 Page number badge (bottom-right corner)
    if (showPdfPageNumbers) {
      _paintPageNumberBadge(canvas, pageNode, effectiveRect);
    }

    // 🔒 Lock indicator (subtle bottom strip)
    if (pageNode.pageModel.isLocked) {
      _paintLockIndicator(canvas, effectiveRect);
    }
  }

  /// Whether to show page number badges on PDF pages.
  final bool showPdfPageNumbers;

  /// Paint annotation strokes linked to a page.
  ///
  /// Looks up strokes by ID from all layer stroke lists and renders them.
  /// Assumes the canvas is already clipped to the page rect.
  ///
  /// NOTE: Renders directly via BrushEngine instead of [_renderStroke]
  /// because _renderStroke skips PDF-linked strokes (they're excluded
  /// from the global pass). Here we WANT to draw them — clipped.
  void _paintPageAnnotations(Canvas canvas, List<String> annotationIds) {
    if (layers == null) return;

    final idSet = annotationIds.toSet();
    for (final layer in layers!) {
      if (!layer.isVisible) continue;
      for (final stroke in layer.strokes) {
        if (idSet.contains(stroke.id)) {
          // Render directly — bypass _renderStroke's PDF skip check
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

  // F3: Pre-allocated paint for lock indicator strip
  static final Paint _lockStripPaint =
      Paint()..color = const Color(0x262196F3); // Material Blue at ~15% opacity
  static final Paint _badgePillPaint =
      Paint()..color = const Color(0x99000000); // Dark pill for page badges

  /// Paint a subtle lock indicator as a thin bottom-edge strip.
  ///
  /// Uses a constant screen-space height (3px) regardless of zoom,
  /// so it never scales up to obstruct page content. Fades out at
  /// high zoom where it would be visually distracting.
  void _paintLockIndicator(Canvas canvas, Rect pageRect) {
    final effectiveScale = controller?.scale ?? canvasScale;

    // Fade out at high zoom — not needed when the user is focused on content
    if (effectiveScale > 2.0) return;

    // Constant 3px screen-space height, converted to canvas-space
    final stripHeight = 3.0 / effectiveScale;

    final stripRect = Rect.fromLTWH(
      pageRect.left,
      pageRect.bottom - stripHeight,
      pageRect.width,
      stripHeight,
    );

    canvas.drawRect(stripRect, _lockStripPaint);
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

    canvas.drawRRect(badgeRect, _badgePillPaint);
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
    // Skip strokes linked to PDF pages — they are drawn clipped
    // inside _paintPdfPage, not in the global pass.
    if (_pdfAnnotationIds != null && _pdfAnnotationIds!.contains(stroke.id)) {
      return;
    }

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
        surface: surface,
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
    if (oldDelegate._sceneGraphVersion != _sceneGraphVersion ||
        oldDelegate.completedShapes != completedShapes ||
        oldDelegate.currentShape != currentShape ||
        oldDelegate.layers != layers ||
        oldDelegate.eraserPreviewIds != eraserPreviewIds ||
        oldDelegate.pdfLayoutVersion != pdfLayoutVersion) {
      return true;
    }

    // 🚀 VIEWPORT BOUNDARY CHECK: trigger repaint when the current viewport
    // exits the previously rendered inflated area. This ensures PDF pages
    // (and strokes) are re-rendered when the user scrolls/zooms far enough.
    if (controller != null && _lastRenderedPdfViewport != Rect.zero) {
      final vpSize = _lastPaintSize;
      final viewport = ViewportCuller.calculateViewport(
        vpSize,
        controller!.offset,
        controller!.scale,
        rotation: controller!.rotation,
      );
      if (!(viewport.left >= _lastRenderedPdfViewport.left &&
          viewport.top >= _lastRenderedPdfViewport.top &&
          viewport.right <= _lastRenderedPdfViewport.right &&
          viewport.bottom <= _lastRenderedPdfViewport.bottom)) {
        return true;
      }
    }

    return false;
  }

  /// 🚀 Incremental update (no-op, tile caching removed)
  static void incrementalUpdateForStroke(
    ProStroke stroke,
    double devicePixelRatio,
  ) {
    // Tile caching removed — vectorial cache handles this via scene version
  }

  /// 🚀 Invalidate tiles involved by a stroke (no-op, kept for API compatibility)
  static void invalidateTilesForStroke(ProStroke stroke) {
    // Tile caching removed — vectorial cache invalidated via scene version
  }

  /// 🚀 Invalidate caches (call after undo, clear, or structural changes).
  ///
  /// NOTE: Does NOT invalidate the vectorial stroke cache — that cache
  /// self-invalidates via the version check in _paintDirect() (incremental
  /// O(delta) path) and the stroke-count check (undo O(1) snapshot path).
  /// Explicitly destroying it would force a full O(N) rebuild.
  static void invalidateAllTiles() {
    _tileCache.invalidateAll();
    invalidateLayerCaches();
  }

  /// 🗂️ Initialize stroke paging manager with shared SQLite database.
  /// Call once during canvas setup to enable 1M+ stroke memory management.
  static Future<void> initializePaging(dynamic database) async {
    await _pagingManager.initialize(database);
  }

  /// 🗂️ Restore paged-out strokes before save to prevent data loss.
  ///
  /// Returns a map of strokeId → full ProStroke. The caller should
  /// temporarily replace stubs in the scene graph, save, then re-stub.
  /// Returns empty map if paging is inactive or no strokes are paged out.
  static Future<Map<String, ProStroke>> restorePagedStrokesForSave() async {
    if (!_pagingManager.isInitialized || !_pagingManager.hasPagedOutStrokes) {
      return const {};
    }
    return _pagingManager.restoreAllForSave();
  }

  /// 🗂️ Check if lazy-load index exists for a canvas.
  static Future<bool> hasStrokeIndex(String canvasId) async {
    if (!_pagingManager.isInitialized) return false;
    return _pagingManager.hasIndex(canvasId);
  }

  /// 🗂️ Index all strokes after save for lazy-load on next open.
  static Future<void> indexStrokesForLazyLoad(
    String canvasId,
    List<(String layerId, ProStroke stroke)> allStrokes,
  ) async {
    if (!_pagingManager.isInitialized) return;
    await _pagingManager.indexAllStrokes(canvasId, allStrokes);
  }

  /// 🗂️ Load lightweight stubs from index for lazy first-open.
  static Future<Map<String, List<ProStroke>>> loadStubsForLazyLoad(
    String canvasId,
  ) async {
    if (!_pagingManager.isInitialized) return const {};
    return _pagingManager.loadStubsFromIndex(canvasId);
  }

  /// 🚀 Invalidate tile cache only (no-op, kept for API compatibility)
  static void invalidateTileCacheOnly() {
    // Tile caching removed
  }

  /// 🚀 Invalidate tiles in bounds (no-op, kept for API compatibility)
  static void invalidateTilesInBounds(Rect bounds) {
    // Tile caching removed
  }

  /// 🚀 Clear all caches and free memory (call when leaving the canvas)
  static void clearTileCache() {
    if (EngineScope.hasScope) {
      final scope = EngineScope.current;
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

        case PdfAnnotationType.stamp:
          // Stamp outline + label text
          final stampPaint =
              Paint()
                ..color = annotation.color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.0;
          canvas.save();
          canvas.translate(annotRect.center.dx, annotRect.center.dy);
          canvas.rotate(-0.3);
          final stampR = Rect.fromCenter(
            center: Offset.zero,
            width: annotRect.width,
            height: annotRect.height,
          );
          canvas.drawRect(stampR, stampPaint);
          canvas.restore();
      }
    }
  }
}

/// 🚀 PERF: Cache entry for the incremental annotation Picture cache.
class _AnnotCacheEntry {
  final int count;
  final ui.Picture picture;
  const _AnnotCacheEntry({required this.count, required this.picture});
}
