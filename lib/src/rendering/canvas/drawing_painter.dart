library drawing_painter;

import 'dart:typed_data';
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
import '../optimization/spatial_index.dart' as rtree_lib show RTree;
import '../optimization/persistent_spatial_index.dart';
import '../optimization/stroke_offset_index.dart';
import '../optimization/pdf_page_stub_manager.dart';

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
import '../../core/nodes/section_node.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../core/nodes/pdf_preview_card_node.dart';
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
import '../../core/nodes/function_graph_node.dart';
import '../scene_graph/tabular_renderer.dart';
import '../scene_graph/function_graph_renderer.dart';
import '../optimization/dirty_region_tracker.dart'; // 🎨 Phase 3: Incremental rendering
import '../optimization/tile_cache_manager.dart'; // 🧩 Tile caching
import '../optimization/stroke_paging_manager.dart'; // 🗂️ Stroke paging to disk
import '../../systems/spatial_index.dart' as si; // 🌲 R-Tree for render path
import '../shaders/shader_brush_service.dart'; // 🚀 Shader warm-up

part 'drawing_painter_helpers.dart';

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
  /// 🚀 STATIC: must persist across delegate instances so shouldRepaint
  /// doesn't always see -1 on the new delegate → infinite repaint loop.
  static int _cachedSceneVersion = -1;

  /// Viewport used when the current stroke cache was built.
  /// If the real viewport moves outside this area, the cache is invalidated
  /// so that newly-visible strokes are rendered.
  static Rect _cachedCacheViewport = Rect.zero;

  /// LOD tier when cache was built. Invalidate when tier changes.
  /// 0 = full quality (≥0.5), 1 = batched polylines (0.2-0.5),
  /// 2 = sections only (<0.2).
  static int _cachedLodTier = 0;

  /// 🚀 GOOGLE MAPS-STYLE LOD TRANSITION:
  /// On LOD change, save the old rendering as a snapshot Picture.
  /// During transition, draw the snapshot (old LOD, user sees no change)
  /// while silently rebuilding tiles at the new LOD in the background.
  /// When all tiles are done, cross-fade to new rendering. Zero frame skip.
  static bool _lodProgressiveMode = false;
  static ui.Picture? _lodSnapshotPicture;
  static double _lodCrossFadeProgress = 0.0; // 0.0 = snapshot, 1.0 = new cache
  static final ValueNotifier<int> _lodRepaintNotifier = ValueNotifier<int>(0);

  /// 🚀 LOD GRACE PERIOD: delays transition until zoom tier is stable for
  /// 2 consecutive frames. Prevents 20ms spike during rapid zoom.
  static int _lodGraceFrames = 0;
  static int _lodPendingTier = -1;

  /// 🚀 VIEWPORT PREDICTION: track pan direction to bias pre-warm tiles.
  /// Tiles in the direction the user is panning are pre-rendered first.
  static Offset _lastViewportCenter = Offset.zero;
  static Offset _panVelocity = Offset.zero; // normalized direction

  /// Inflated viewport used during the last paint() for PDF page rendering.
  /// When the real viewport exits this area, shouldRepaint returns true
  /// so that newly-visible PDF pages are rendered into the raster cache.
  static Rect _lastRenderedPdfViewport = Rect.zero;

  /// Widget size from the last paint() call, needed for viewport calculation
  /// in shouldRepaint (where the paint size parameter isn't available).
  static Size _lastPaintSize = Size.zero;

  /// Whether the previous shouldRepaint call was during a gesture.
  /// Used to detect gesture-end transition (isPanning true→false).
  static bool _wasGesturing = false;

  /// 🚀 Whether tiles were built with gesture-cheapened LOD.
  /// On gesture end, these tiles are marked stale for quality rebuild.
  static bool _gestureBuiltTiles = false;

  /// Scale at which the last paint() call rendered.
  /// Used to detect scale changes after gesture ends.
  static double _lastPaintedScale = 1.0;

  /// 🧩 Tile cache for regional invalidation.
  /// Shared across DrawingPainter instances via EngineScope or static fallback.
  static final TileCacheManager _tileCache = TileCacheManager();

  /// 🏎️ Last paint() duration in microseconds (for debug overlay).
  static int _lastPaintDurationUs = 0;

  /// Current LOD tier: 0 = full, 1 = batched, 2 = sections.
  static int get currentLodTier => _cachedLodTier;

  /// Tile cache hit rate (0-100%).
  static double get tileCacheHitRate => _tileCache.hitRate;

  /// Number of cached tiles.
  static int get tileCacheCount => _tileCache.tileCount;

  /// Tile cache hits since last reset.
  static int get tileCacheHits => _tileCache.cacheHits;

  /// Tile cache misses since last reset.
  static int get tileCacheMisses => _tileCache.cacheMisses;

  /// Reset tile cache stats (call periodically from monitor).
  static void resetTileCacheStats() => _tileCache.resetStats();

  /// Last paint() duration in microseconds.
  static int get lastPaintDurationUs => _lastPaintDurationUs;

  /// 🌲 R-Tree spatial index for O(log N) node lookup during tile rebuild.
  static final si.SpatialIndex _renderIndex = si.SpatialIndex();
  static int _renderIndexVersion = -1;
  static int _renderIndexNodeCount = 0;
  static List<ProStroke>? _lastMaterializedStrokes;

  /// 📊 Total stroke count (including stubs) for R-Tree sync.
  /// _materializedCache only holds loaded (non-stub) strokes;
  /// this tracks the REAL total for insert/remove diff detection.
  static int _totalStrokeCount = 0;

  /// 🌲 Persistent R*Tree index (SQLite) for 10M+ strokes.
  /// Dual-write with in-memory _renderIndex — fire-and-forget async.
  static final PersistentSpatialIndex _persistentIndex =
      PersistentSpatialIndex();

  /// 🌲 R-Tree spatial index for PDF pages — O(log N) viewport culling.
  /// Uses position-based bounds (matching _paintPdfPage), NOT worldBounds,
  /// because PdfPageNode.worldBounds double-counts the position.
  static rtree_lib.RTree<PdfPageNode> _pdfPageTree =
      rtree_lib.RTree<PdfPageNode>(_pdfPageBounds);
  static int _pdfPageIndexVersion = -1;

  /// Bounds extractor matching what _paintPdfPage uses for rendering.
  static Rect _pdfPageBounds(PdfPageNode page) {
    final pos = page.position;
    final sz = page.pageModel.originalSize;
    return Rect.fromLTWH(pos.dx, pos.dy, sz.width, sz.height);
  }

  /// Cached document nodes for O(1) parent lookup from PdfPageNode.
  static final Map<String, PdfDocumentNode> _pdfDocCache = {};

  /// 🗂️ PDF page stub manager for 100K+ page memory management.
  static final PdfPageStubManager _pdfStubManager = PdfPageStubManager();

  /// 🗂️ Stroke paging manager for memory-bounded 1M+ strokes.
  static final StrokePagingManager _pagingManager = StrokePagingManager();
  static bool _pagingInProgress = false;
  static Rect _lastPagingViewport = Rect.zero;

  /// 🛡️ SAVE GUARD: prevents paging from stubifying strokes while a save
  /// is in progress. Set by the save code before encoding, cleared after.
  static bool _saveGuardActive = false;

  /// 🛡️ Enable save guard — blocks paging from stubifying strokes.
  static void setSaveGuard(bool active) => _saveGuardActive = active;

  /// 📦 Stroke offset index for seekable binary access.
  static final StrokeOffsetIndex _offsetIndex = StrokeOffsetIndex();

  /// 📊 Loaded stroke IDs — O(1) lookup to avoid O(N) scene graph traversal.
  /// Only strokes with full data (non-stub, paged-in) are in this set.
  /// At 10M: set holds ~5000 IDs (~200KB) instead of traversing 10M nodes.
  static final Set<String> _loadedStrokeIds = {};

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
    this.isActivelyDrawing = false, // 🚀 suppress repaint during live drawing
  }) : _sceneGraphVersion = sceneGraph.version,
       super(
         repaint: _lodRepaintNotifier,
       ); // 🚀 Progressive LOD repaint trigger
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

    // Update total stroke count (including stubs) — O(L)
    _totalStrokeCount = _countStrokes();

    if (_materializedCache == null) {
      // First build — full traversal, skip stubs
      _materializedCache = _collectAllStrokes();
      _materializedVersion = sceneGraph.version;
      return _materializedCache!;
    }

    // Compare total stroke count (all strokes including stubs)
    // with renderIndex count to detect add/undo
    final currentTotal = _totalStrokeCount;
    final oldTotal = _renderIndexNodeCount;

    if (currentTotal > oldTotal) {
      // ADD: New strokes were added — rebuild loaded list
      _materializedCache = _collectAllStrokes();
    } else if (currentTotal < oldTotal) {
      // UNDO: Strokes were removed — rebuild loaded list
      _materializedCache = _collectAllStrokes();
    } else {
      // Same total count — paging event or property change
      // Rebuild to pick up newly paged-in strokes
      _materializedCache = _collectAllStrokes();
    }

    _materializedVersion = sceneGraph.version;
    return _materializedCache!;
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

  /// Collect all loaded (non-stub) strokes and rebuild _loadedStrokeIds.
  List<ProStroke> _collectAllStrokes() {
    _loadedStrokeIds.clear();
    final result = <ProStroke>[];
    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      _collectStrokes(layer, result);
    }
    return result;
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
    final newCount =
        _totalStrokeCount; // Use total (including stubs) for R-Tree sync
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

      // 🌲 Dual-write: persist R-Tree to SQLite (fire-and-forget)
      if (_persistentIndex.isInitialized) {
        final entries = <(String, Rect)>[];
        for (final node in nodes) {
          entries.add((node.id, node.worldBounds));
        }
        _persistentIndex.rebuild(entries).catchError((_) {});
      }
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
            // 🌲 Dual-write: remove from persistent R*Tree
            if (_persistentIndex.isInitialized) {
              _persistentIndex.remove(s.id).catchError((_) {});
            }
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
      // Guard: if indices exceed available strokes (stubs), do full rebuild.
      if (oldCount <= currentStrokes.length &&
          newCount <= currentStrokes.length) {
        for (int i = oldCount; i < newCount; i++) {
          final stroke = currentStrokes[i];
          _insertStrokeNode(stroke);
        }
        _renderIndexNodeCount = newCount;
      } else {
        // Indices out of range (stubs/paging) → full rebuild
        final nodes = <CanvasNode>[];
        for (final layer in sceneGraph.layers) {
          if (!layer.isVisible) continue;
          _collectLeafNodes(layer, nodes);
        }
        _renderIndex.rebuild(nodes);
        _renderIndexNodeCount = newCount;
      }
    } else if (newCount == oldCount) {
      // Version changed but stroke count same (e.g., section/shape added,
      // node visibility changed). Full rebuild to pick up non-stroke changes.
      final nodes = <CanvasNode>[];
      for (final layer in sceneGraph.layers) {
        if (!layer.isVisible) continue;
        _collectLeafNodes(layer, nodes);
      }
      _renderIndex.rebuild(nodes);
      _renderIndexNodeCount = newCount;
    } else {
      // Fallback: version changed, count changed but not simple add/remove.
      // Full rebuild is safest.
      final nodes = <CanvasNode>[];
      for (final layer in sceneGraph.layers) {
        if (!layer.isVisible) continue;
        _collectLeafNodes(layer, nodes);
      }
      _renderIndex.rebuild(nodes);
      _renderIndexNodeCount = newCount;
    }

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
        // 🌲 Dual-write: persist new node to SQLite R*Tree
        if (_persistentIndex.isInitialized) {
          _persistentIndex.insert(node.id, node.worldBounds).catchError((_) {});
        }
        return;
      }
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
    if (isViewportLevel) {
      _lastPaintSize = size;
      _lastPaintedScale = canvasScale;
    }

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

    // 🚀 VIEWPORT PREDICTION: track pan direction for pre-warm bias
    final currentCenter = viewport.center;
    if (_lastViewportCenter != Offset.zero) {
      final delta = currentCenter - _lastViewportCenter;
      final mag = delta.distance;
      if (mag > 10.0) {
        _panVelocity = Offset(delta.dx / mag, delta.dy / mag);
      }
    }
    _lastViewportCenter = currentCenter;

    // 🚀 LIGHTWEIGHT PDF DRAG: skip ALL heavy rendering, just replay
    // the existing stroke cache and draw simple page rectangles.
    if (isDraggingPdf) {
      // Replay cached strokes (O(1) drawPicture)
      _strokeCache.drawCached(canvas);

      // Draw lightweight page placeholders (static paints — zero alloc)
      _pdfDragBorderPaint.strokeWidth = 2.0 / effectiveScale;
      for (final rect in draggedPageRects) {
        canvas.drawRect(rect, _pdfDragFillPaint);
        canvas.drawRect(rect, _pdfDragBorderPaint);
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

    // 📈 Draw Function Graph nodes (outside tile cache — always visible)
    _paintFunctionGraphNodes(canvas, pdfViewport);

    // 🎨 Phase 3: Clear dirty regions after paint (prevents accumulation)
    dirtyRegionTracker?.clearDirty();

    // Clear per-frame skip set
    _pdfAnnotationIds = null;
    _delegateRenderer.skipStrokeIds = null;

    if (!isViewportLevel) {
      canvas.restore();
    }

    // 🏎️ PERFORMANCE MONITORING: end frame measurement
    _lastPaintDurationUs = _sw.elapsedMicroseconds;
    CanvasPerformanceMonitor.instance.endFrame(_effectiveStrokes.length);

    // 🔬 DIAGNOSTIC: print breakdown on frames > 5ms
    final totalUs = _sw.elapsedMicroseconds;
    // (Diagnostic removed — enable when needed)
    // if (totalUs > 5000) {
    //   final strokeMs = (_t1 / 1000).toStringAsFixed(1);
    //   final pdfMs = ((_t2 - _t1) / 1000).toStringAsFixed(1);
    //   final totalMs = (totalUs / 1000).toStringAsFixed(1);
    //   print('🔬 PAINT ${totalMs}ms → strokes:${strokeMs}ms pdf:${pdfMs}ms');
    // }
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

    // 🚀 GESTURE-END: tiles built with cheap LOD need rebuilding at full quality
    final isCurrentlyGesturing = controller?.isPanning ?? false;
    if (!isCurrentlyGesturing && _gestureBuiltTiles) {
      _gestureBuiltTiles = false;
      _tileCache.markAllStale(); // Keep as fallback, rebuild at correct LOD
      _strokeCache.invalidateCache();
    }

    final totalStrokes = _effectiveStrokes.length;
    final hasEraserPreview = eraserPreviewIds.isNotEmpty;

    // Cache invalidation: scene graph version changed
    if (_cachedSceneVersion != sceneGraph.version) {
      invalidateLayerCaches();
      // If stroke count hasn't changed, this is a non-stroke change
      // (section/shape added, visibility toggle) — invalidate caches
      // so the full render path picks up the new nodes.
      if (totalStrokes == _strokeCache.cachedStrokeCount) {
        _strokeCache.invalidateCache();
        _tileCache.invalidateAll();
      }
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
    // 🚀 ZOOM-AWARE: At low zoom, add tolerance so small pans don't
    // invalidate. At 30% zoom, tolerance = ~1500px canvas units.
    if (_strokeCache.isCacheValid(totalStrokes) &&
        _cachedCacheViewport != Rect.zero) {
      final _vpScale = controller?.scale ?? canvasScale;
      // 🚀 Tolerance scales inversely with zoom — always active.
      // 100%: ~360px, 80%: ~450px, 50%: ~720px, 30%: ~1200px
      final tolerance = viewport.longestSide * 0.1 / _vpScale;
      if (!(viewport.left >= _cachedCacheViewport.left - tolerance &&
          viewport.top >= _cachedCacheViewport.top - tolerance &&
          viewport.right <= _cachedCacheViewport.right + tolerance &&
          viewport.bottom <= _cachedCacheViewport.bottom + tolerance)) {
        _strokeCache.invalidateCache();
      }
    }

    // 🚀 LOD TIER TRANSITION: Google Maps-style approach.
    // Save current rendering as snapshot BEFORE invalidating caches.
    // During transition, user sees old snapshot (GPU-scaled, looks fine).
    final currentScale = controller?.scale ?? canvasScale;
    // 🚀 LOD HYSTERESIS: asymmetric boundaries prevent oscillation.
    // Going DOWN: transition at 0.45/0.18 (delay = user zooming fast)
    // Going UP: transition at 0.55/0.22 (early = restore quality sooner)
    final int currentTier;
    if (_cachedLodTier == 0) {
      // Currently full quality — go to tier 1 only at 0.45 (not 0.5)
      currentTier = currentScale < 0.18 ? 2 : (currentScale < 0.45 ? 1 : 0);
    } else if (_cachedLodTier == 1) {
      // Currently simplified — go to tier 0 at 0.55, tier 2 at 0.18
      currentTier = currentScale < 0.18 ? 2 : (currentScale >= 0.55 ? 0 : 1);
    } else {
      // Currently thumbnails — go to tier 1 at 0.22, tier 0 at 0.55
      currentTier = currentScale >= 0.55 ? 0 : (currentScale >= 0.22 ? 1 : 2);
    }

    // 🛡️ EDGE CASE: cancel progressive mode if scene changed (stroke added/removed)
    // or if zoom crossed ANOTHER tier boundary during the transition.
    if (_lodProgressiveMode) {
      final sceneChanged = sceneGraph.version != _cachedSceneVersion;
      final tierChangedAgain = currentTier != _cachedLodTier;
      if (sceneChanged || tierChangedAgain) {
        // 🚀 FIX: adopt snapshot back as cache so grace period gets O(1) replay
        // instead of falling into the expensive O(N) direct render fallback.
        if (_lodSnapshotPicture != null) {
          _strokeCache.adoptPicture(_lodSnapshotPicture!, totalStrokes);
          _lodSnapshotPicture = null;
        }
        _lodProgressiveMode = false;
        if (tierChangedAgain) _cachedLodTier = currentTier;
      }
    }

    // 🚀 LOD GRACE PERIOD: delay transition until tier is stable for 2 frames.
    // This prevents the expensive snapshot+invalidation during rapid zoom.
    if (currentTier != _cachedLodTier && !_lodProgressiveMode) {
      if (_lodPendingTier == currentTier) {
        _lodGraceFrames++;
      } else {
        // Tier changed — reset grace counter
        _lodPendingTier = currentTier;
        _lodGraceFrames = 1;
      }

      if (_lodGraceFrames >= 2) {
        // Tier stable for 2 frames — commit LOD transition
        // 1. Save snapshot of current cache (before invalidation)
        // 1. 🚀 STEAL the cache Picture directly (O(1), no PictureRecorder replay)
        _lodSnapshotPicture?.dispose();
        _lodSnapshotPicture = _strokeCache.stealPicture();
        // stealPicture() already empties the cache — no need for invalidateCache()
        // 🚀 Mark tiles stale (keep as fallback) instead of disposing
        _tileCache.markAllStale();
        _cachedLodTier = currentTier;
        _cachedSceneVersion = sceneGraph.version;
        _lodPendingTier = -1;
        _lodGraceFrames = 0;
        // 3. Enter progressive mode
        _lodProgressiveMode = true;
      } else {
        // 🚀 Grace period: reuse OLD cached Picture (O(1) drawPicture).
        // The old LOD is at wrong detail level but Flutter's transform
        // scales it — visually fine during active zoom (1-2 frames).
        if (_strokeCache.isCacheValid(totalStrokes) ||
            _strokeCache.hasCacheForStrokes(totalStrokes)) {
          _strokeCache.drawCached(canvas);
        } else {
          // No cache available (rare) — cheap direct render
          _ensureRenderIndex();
          _delegateRenderer.currentScale = currentScale;
          _delegateRenderer.skipPdfNodes = true;
          final cacheViewport = viewport.inflate(viewport.longestSide * 0.5);
          _delegateRenderer.render(
            canvas,
            sceneGraph,
            cacheViewport,
            scale: currentScale,
          );
          _delegateRenderer.skipPdfNodes = false;
        }
        _drawEraserPreviews(canvas);
        // Only schedule next frame when NOT gesturing — during gesture,
        // the gesture handler already schedules frames. Avoids rebuild loop.
        final isGracePeriodGesturing = controller?.isPanning ?? false;
        if (!isGracePeriodGesturing) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            _lodRepaintNotifier.value++;
          });
        }
        return;
      }
    } else if (currentTier == _cachedLodTier) {
      // Tier matches: reset pending state
      _lodPendingTier = -1;
      _lodGraceFrames = 0;
    }

    // 🚀 PROGRESSIVE LOD: rebuild tiles at new LOD progressively.
    // Uses stale tiles (old LOD) as fallback — new tiles appear as they're built.
    if (_lodProgressiveMode) {
      // 🚀 Dispose snapshot — stale tiles provide the visual fallback now
      if (_lodSnapshotPicture != null) {
        _lodSnapshotPicture!.dispose();
        _lodSnapshotPicture = null;
      }

      _ensureRenderIndex();

      // 🚀 Draw cached + stale tiles, collect missing for rebuild
      final missingTiles = _tileCache.drawAndCollectMissing(canvas, viewport);

      if (missingTiles.length > 1) {
        TileCacheManager.sortByDistanceToCenter(missingTiles, viewport);
      }

      if (missingTiles.isNotEmpty) {
        final sw = Stopwatch()..start();
        const budgetUs = 8000;
        final effectiveScale = controller?.scale ?? canvasScale;
        _delegateRenderer.currentScale = effectiveScale;

        for (final tileKey in missingTiles) {
          if (sw.elapsedMicroseconds > budgetUs) break;

          final tileBounds = TileCacheManager.tileBounds(tileKey);
          final visibleNodes = _renderIndex.queryRange(tileBounds);

          // 🚀 EMPTY TILE SKIP: no nodes → cache empty, zero cost
          if (visibleNodes.isEmpty) {
            final emptyRec = ui.PictureRecorder();
            Canvas(emptyRec);
            _tileCache.cacheTile(
              tileKey,
              emptyRec.endRecording(),
              sceneGraph.version,
            );
            continue;
          }

          final recorder = ui.PictureRecorder();
          final recCanvas = Canvas(recorder);

          if (effectiveScale < 0.2) {
            final thumbBatches = <int, ui.Path>{};
            for (final node in visibleNodes) {
              if (node is StrokeNode) {
                if (node.stroke.isStub || node.stroke.isFill) continue;
                final b = node.stroke.bounds;
                if (b.isEmpty || b.longestSide * effectiveScale < 3.0) continue;
                final r = (b.shortestSide * 0.08).clamp(2.0, 12.0);
                final colorKey = node.stroke.color.value;
                final path = thumbBatches.putIfAbsent(
                  colorKey,
                  () => ui.Path(),
                );
                path.addRRect(RRect.fromRectAndRadius(b, Radius.circular(r)));
                continue;
              }
              if (node is PdfDocumentNode || node is PdfPageNode || node is PdfPreviewCardNode || node is FunctionGraphNode) continue;
              _delegateRenderer.renderNode(recCanvas, node, tileBounds);
            }
            for (final entry in thumbBatches.entries) {
              final color = Color(entry.key);
              _lodThumbFillPaint.color = color.withValues(alpha: 0.15);
              recCanvas.drawPath(entry.value, _lodThumbFillPaint);
              _lodThumbStrokePaint.color = color.withValues(alpha: 0.30);
              recCanvas.drawPath(entry.value, _lodThumbStrokePaint);
            }
          } else if (effectiveScale < 0.5) {
            for (final node in visibleNodes) {
              if (node is PdfDocumentNode || node is PdfPageNode || node is PdfPreviewCardNode || node is FunctionGraphNode) continue;
              if (node is StrokeNode && node.stroke.isStub) continue;
              _delegateRenderer.renderNode(recCanvas, node, tileBounds);
            }
          } else {
            for (final node in visibleNodes) {
              if (node is PdfDocumentNode || node is PdfPageNode || node is PdfPreviewCardNode || node is FunctionGraphNode) continue;
              if (node is StrokeNode && node.stroke.isStub) continue;
              _delegateRenderer.renderNode(recCanvas, node, tileBounds);
            }
          }

          final picture = recorder.endRecording();
          // Draw immediately so user sees the update this frame
          canvas.drawPicture(picture);
          _tileCache.cacheTile(tileKey, picture, sceneGraph.version);
        }

        final remaining = _tileCache.collectMissing(viewport);
        if (remaining.isEmpty) {
          // All tiles rebuilt — finalize
          final globalRec = ui.PictureRecorder();
          _tileCache.drawCachedOnly(Canvas(globalRec), viewport);
          final globalPic = globalRec.endRecording();
          _strokeCache.adoptPicture(globalPic, totalStrokes);
          _cachedSceneVersion = sceneGraph.version;
          final lodInflate =
              viewport.longestSide * (1.5 / currentScale).clamp(1.5, 8.0);
          _cachedCacheViewport = viewport.inflate(lodInflate);
          _tileCache.markValid(totalStrokes, sceneGraph.version);
          _lodProgressiveMode = false;
        } else {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            _lodRepaintNotifier.value++;
          });
        }
      } else {
        // No missing tiles — complete
        _lodProgressiveMode = false;
        _tileCache.markValid(totalStrokes, sceneGraph.version);
      }

      _drawEraserPreviews(canvas);
      _triggerPagingIfNeeded(viewport);
      return; // Skip normal rendering path
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
      final cacheViewport = viewport.inflate(viewport.longestSide * 1.5);
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

    // 🎯 CENTER-FIRST: rebuild tiles closest to viewport center first
    if (missingTiles.length > 1) {
      TileCacheManager.sortByDistanceToCenter(missingTiles, viewport);
    }

    // 🚀 PROGRESSIVE FIRST LOAD: budget-cap tile rebuilds.
    // 🚀 GESTURE-AWARE: 2ms during gesture (fast frames), 4ms when idle.
    final isCurrentGesture = controller?.isPanning ?? false;
    final normalBudgetUs = isCurrentGesture ? 2000 : 4000;
    final Stopwatch? normalSw =
        missingTiles.length > 2 ? (Stopwatch()..start()) : null;

    // Rebuild missing tiles using R-Tree O(log N) query
    // 🚀 Set scale for LOD decisions in BrushEngine fast path
    final effectiveScale = controller?.scale ?? canvasScale;
    _delegateRenderer.currentScale = effectiveScale;
    // 🚀 GESTURE-AWARE LOD: during active pan/zoom, force cheapest rendering.
    final isGesturing = controller?.isPanning ?? false;
    final renderScale = isGesturing ? 0.1 : effectiveScale;

    int normalTilesRebuilt = 0;
    for (final tileKey in missingTiles) {
      // Budget check (skip for ≤2 tiles — not worth overhead)
      if (normalSw != null &&
          normalTilesRebuilt > 0 &&
          normalSw.elapsedMicroseconds > normalBudgetUs) {
        break;
      }
      final tileBounds = TileCacheManager.tileBounds(tileKey);

      // 🌲 R-TREE QUERY: O(log N) instead of O(N) scene graph traversal
      final visibleNodes = _renderIndex.queryRange(tileBounds);

      // 🚀 EMPTY TILE SKIP: no nodes → cache empty Picture, zero cost
      if (visibleNodes.isEmpty) {
        final emptyRec = ui.PictureRecorder();
        Canvas(emptyRec); // Must create Canvas to finalize recorder
        _tileCache.cacheTile(
          tileKey,
          emptyRec.endRecording(),
          sceneGraph.version,
        );
        normalTilesRebuilt++;
        continue;
      }

      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);

      // ─────────────────────────────────────────────────────────────
      // 🚀 3-TIER LOD RENDERING (with smooth transitions):
      // Tier 1 (zoom <0.2): SECTIONS + colored bounding boxes for strokes
      // Tier 2 (zoom 0.2-0.5): Color-batched simplified polylines
      // Tier 3 (zoom ≥0.5): Full quality per-node rendering
      //
      // 🚀 GESTURE-AWARE: during active pan/zoom, FORCE cheapest LOD
      // (bounding boxes) for all tiles. Rebuild at correct LOD on release.
      // ─────────────────────────────────────────────────────────────
      if (renderScale < 0.2) {
        // 🏷️ TIER 1: Sections + color-batched content thumbnails
        // O(colors) draw calls instead of O(N) per stroke.
        final thumbBatches = <int, ui.Path>{};

        for (final node in visibleNodes) {
          if (node is StrokeNode) {
            if (node.stroke.isStub || node.stroke.isFill) continue;
            final b = node.stroke.bounds;
            // Aggressive cull: skip strokes < 3px on screen
            if (b.isEmpty || b.longestSide * renderScale < 3.0) continue;
            final r = (b.shortestSide * 0.08).clamp(2.0, 12.0);
            final colorKey = node.stroke.color.value;
            final path = thumbBatches.putIfAbsent(colorKey, () => ui.Path());
            path.addRRect(RRect.fromRectAndRadius(b, Radius.circular(r)));
            continue;
          }
          if (node is PdfDocumentNode || node is PdfPageNode || node is PdfPreviewCardNode || node is FunctionGraphNode) continue;
          _delegateRenderer.renderNode(recCanvas, node, tileBounds);
        }

        // Draw batched thumbnails: 2 draw calls per color (fill + border)
        for (final entry in thumbBatches.entries) {
          final color = Color(entry.key);
          _lodThumbFillPaint.color = color.withValues(alpha: 0.15);
          recCanvas.drawPath(entry.value, _lodThumbFillPaint);
          _lodThumbStrokePaint.color = color.withValues(alpha: 0.30);
          recCanvas.drawPath(entry.value, _lodThumbStrokePaint);
        }
      } else if (renderScale < 0.5) {
        // 🎨 TIER 2: Color-batched simplified polylines
        // Smooth fade near the 0.2 boundary (0.2–0.3 = transition zone)
        final strokeOpacity =
            effectiveScale < 0.3
                ? ((effectiveScale - 0.2) / 0.1).clamp(0.0, 1.0)
                : 1.0;

        final batches = <int, _ColorBatch>{};
        final step = (1.0 / effectiveScale).ceil().clamp(3, 10);

        for (final node in visibleNodes) {
          if (node is! StrokeNode) continue;
          if (node.stroke.isStub) continue;
          if (node.stroke.isFill) continue;
          final stroke = node.stroke;
          final points = stroke.points;
          if (points.isEmpty) continue;

          // Skip tiny strokes
          final screenSize = stroke.bounds.longestSide * effectiveScale;
          if (screenSize < 4.0) continue;

          final colorKey = stroke.color.value;
          final batch = batches.putIfAbsent(
            colorKey,
            () => _ColorBatch(ui.Path(), stroke.color, stroke.baseWidth),
          );

          // Add simplified polyline to batch path
          bool first = true;
          for (int i = 0; i < points.length; i += step) {
            final pos = points[i].position;
            if (first) {
              batch.path.moveTo(pos.dx, pos.dy);
              first = false;
            } else {
              batch.path.lineTo(pos.dx, pos.dy);
            }
          }
          // Always include last point to close the stroke shape
          final lastPos = points.last.position;
          batch.path.lineTo(lastPos.dx, lastPos.dy);

          if (stroke.baseWidth > batch.maxWidth) {
            batch.maxWidth = stroke.baseWidth;
          }
        }

        // Draw one Path per color batch (with fade opacity)
        for (final batch in batches.values) {
          _lodBatchPaint
            ..color = batch.color.withValues(alpha: strokeOpacity)
            ..strokeWidth = (batch.maxWidth * effectiveScale * 2.0).clamp(
              0.5,
              batch.maxWidth,
            )
            ..isAntiAlias = true;
          recCanvas.drawPath(batch.path, _lodBatchPaint);
        }

        // Also render non-stroke nodes (shapes, images, etc.)
        for (final node in visibleNodes) {
          if (node is StrokeNode) continue;
          if (node is PdfDocumentNode || node is PdfPageNode || node is PdfPreviewCardNode || node is FunctionGraphNode) continue;
          _delegateRenderer.renderNode(recCanvas, node, tileBounds);
        }
      } else {
        // 🖌️ TIER 3: Full quality per-node rendering
        for (final node in visibleNodes) {
          if (node is PdfDocumentNode || node is PdfPageNode || node is PdfPreviewCardNode || node is FunctionGraphNode) continue;
          if (node is StrokeNode && node.stroke.isStub) continue;
          _delegateRenderer.renderNode(recCanvas, node, tileBounds);
        }
      }

      final picture = recorder.endRecording();
      canvas.drawPicture(picture);
      _tileCache.cacheTile(tileKey, picture, sceneGraph.version);
      if (isGesturing)
        _gestureBuiltTiles = true; // Only when tile ACTUALLY rebuilt
      normalTilesRebuilt++;
    }

    // Check if all tiles were rebuilt
    final allNormalTilesBuilt = normalTilesRebuilt >= missingTiles.length;

    // 🐛 FIX: ALWAYS mark tile cache as valid (even if partially built).
    // Without this, the next frame sees cachedStrokeCount != totalStrokes
    // and calls invalidateAll(), destroying all partially-built tiles.
    // This caused an infinite loop: build some → invalidate all → repeat.
    _tileCache.markValid(totalStrokes, sceneGraph.version);

    // 🚀 FIX: Update global stroke cache WITHOUT re-rendering all tiles.
    // Record the tiles we already drew into one Picture.
    if (normalTilesRebuilt > 0 && allNormalTilesBuilt) {
      final globalRecorder = ui.PictureRecorder();
      final globalCanvas = Canvas(globalRecorder);
      _tileCache.drawCachedOnly(globalCanvas, viewport);
      final globalPicture = globalRecorder.endRecording();
      _strokeCache.adoptPicture(globalPicture, totalStrokes);
      _cachedSceneVersion = sceneGraph.version;
      // 🚀 ZOOM-AWARE: inflate proportional to 1/scale — always active
      final cacheInflate =
          viewport.longestSide * (1.5 / effectiveScale).clamp(1.5, 8.0);
      _cachedCacheViewport = viewport.inflate(cacheInflate);
    }

    // 🚀 PROGRESSIVE FIRST LOAD: schedule remaining tiles for next frame
    if (!allNormalTilesBuilt) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _lodRepaintNotifier.value++;
      });
    } else if (normalSw != null &&
        normalSw.elapsedMicroseconds < normalBudgetUs) {
      // 🚀 PRE-WARM: all visible tiles built, use remaining budget for surrounding tiles.
      // Pre-renders 2-ring of tiles outside viewport so panning is instant.
      final preWarmTiles = _tileCache.collectMissingPreWarm(viewport);
      if (preWarmTiles.isNotEmpty) {
        TileCacheManager.sortByPanPrediction(
          preWarmTiles,
          viewport,
          _panVelocity,
        );
        for (final tileKey in preWarmTiles) {
          if (normalSw.elapsedMicroseconds > normalBudgetUs) break;
          final tileBounds = TileCacheManager.tileBounds(tileKey);
          final visibleNodes = _renderIndex.queryRange(tileBounds);

          // 🚀 EMPTY TILE SKIP: no content → cache empty, zero cost
          if (visibleNodes.isEmpty) {
            final emptyRec = ui.PictureRecorder();
            Canvas(emptyRec);
            _tileCache.cacheTile(
              tileKey,
              emptyRec.endRecording(),
              sceneGraph.version,
            );
            continue;
          }

          final recorder = ui.PictureRecorder();
          final recCanvas = Canvas(recorder);
          for (final node in visibleNodes) {
            if (node is PdfDocumentNode || node is PdfPageNode || node is PdfPreviewCardNode || node is FunctionGraphNode) continue;
            if (node is StrokeNode && node.stroke.isStub) continue;
            _delegateRenderer.renderNode(recCanvas, node, tileBounds);
          }
          _tileCache.cacheTile(
            tileKey,
            recorder.endRecording(),
            sceneGraph.version,
          );
        }
        // Pre-warm is OPPORTUNISTIC only — never schedules additional frames.
        // This prevents infinite repaint loops with LRU eviction.
      }
    }

    // Draw eraser previews on top
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
    if (_saveGuardActive) return; // 🛡️ Don't page during save
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

  /// Replace stub strokes with restored full strokes and ADD to layer.strokes.
  /// Also adds restored IDs to _loadedStrokeIds for O(K) lookup.
  static void _replaceStubs(CanvasNode node, Map<String, ProStroke> restored) {
    if (node is StrokeNode && restored.containsKey(node.stroke.id)) {
      node.stroke = restored[node.stroke.id]!;
      _loadedStrokeIds.add(node.stroke.id);
    } else if (node is GroupNode) {
      for (final child in node.children) {
        _replaceStubs(child, restored);
      }
    }
  }

  /// Remove paged-out strokes from layer.strokes entirely (not just stub).
  /// Removes their IDs from _loadedStrokeIds.
  /// At 10M: frees 640MB by not keeping stub objects in RAM.
  static void _stubifyStrokes(CanvasNode node, Set<String> pagedOutIds) {
    if (node is StrokeNode && pagedOutIds.contains(node.stroke.id)) {
      if (!node.stroke.isStub) {
        _loadedStrokeIds.remove(node.stroke.id);
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
      _layerCompositePaint
        ..blendMode = layer.blendMode
        ..color = Color.fromARGB((layer.opacity * 255).round(), 255, 255, 255);
      canvas.saveLayer(null, _layerCompositePaint);

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
      canvas.saveLayer(bounds, _debugLayerPaint);
      _renderStroke(canvas, stroke);
      canvas.drawRect(bounds, _debugBoundsPaint);
      canvas.restore();
    }
  }

  /// 📄 Paint all PDF document nodes found in the scene graph layers.
  ///
  /// Uses [PdfPagePainter] for LOD-aware progressive rendering with
  /// prefetching, LRU eviction, and debounced LOD upgrades.
  // --------------------------------------------------------------------------
  // 📄 PDF SPATIAL INDEX
  // --------------------------------------------------------------------------

  /// 🌲 Ensure PDF page R-Tree is synced with scene graph.
  /// Full rebuild on version change — PDF pages change rarely.
  void _ensurePdfIndex() {
    if (_pdfPageIndexVersion == sceneGraph.version) return;

    final pages = <PdfPageNode>[];
    _pdfDocCache.clear();

    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      _collectPdfNodesForIndex(layer, pages);
    }

    _pdfPageTree = rtree_lib.RTree<PdfPageNode>.fromItems(
      pages,
      _pdfPageBounds,
    );
    _pdfPageIndexVersion = sceneGraph.version;
  }

  /// Recursively collect PdfPageNodes and cache PdfDocumentNodes.
  void _collectPdfNodesForIndex(CanvasNode node, List<PdfPageNode> out) {
    if (node is PdfDocumentNode) {
      _pdfDocCache[node.id] = node;
      for (final child in node.children) {
        if (child is PdfPageNode && child.isVisible) {
          out.add(child);
        }
      }
    } else if (node is GroupNode) {
      for (final child in node.children) {
        if (child.isVisible) _collectPdfNodesForIndex(child, out);
      }
    }
  }

  void _paintPdfDocuments(Canvas canvas, Rect viewport) {
    // 🌲 Sync R-Tree with scene graph (no-op if version unchanged)
    _ensurePdfIndex();

    // 🚀 O(log N) viewport query instead of O(layers × children) scan
    final visibleNodes = _pdfPageTree.queryVisible(viewport, margin: 0);

    // Group visible pages by document for rendering + management
    final pagesPerDocument = <String, List<PdfPageNode>>{};

    for (final node in visibleNodes) {
      // Walk up to find parent PdfDocumentNode
      final parentNode = node.parent;
      if (parentNode is! PdfDocumentNode) continue;

      final docId = parentNode.id;
      final docPages = pagesPerDocument.putIfAbsent(docId, () => []);
      docPages.add(node);
    }

    // 🎨 Paint pages grouped by document (two-pass: locked first, unlocked on top)
    for (final entry in pagesPerDocument.entries) {
      final docId = entry.key;
      final pages = entry.value;
      final docNode = _pdfDocCache[docId];
      if (docNode == null) continue;

      final painter = pdfPainters[docId];
      // 🚀 Reset per-frame render budget for each document
      if (painter != null) painter.resetFrameBudget();

      // 🚀 VIEWPORT PRIORITY: Sort pages by distance to viewport center.
      // Center pages paint first → their renders enqueue first → processed
      // first by _drainQueue. Edge pages paint last with lower LOD.
      final vpCenter = viewport.center;
      pages.sort((a, b) {
        final aCenter = Offset(
          a.position.dx + a.pageModel.originalSize.width / 2,
          a.position.dy + a.pageModel.originalSize.height / 2,
        );
        final bCenter = Offset(
          b.position.dx + b.pageModel.originalSize.width / 2,
          b.position.dy + b.pageModel.originalSize.height / 2,
        );
        return (aCenter - vpCenter).distanceSquared.compareTo(
          (bCenter - vpCenter).distanceSquared,
        );
      });

      // 🚀 PERF: Check if ANY page is locked. If none are locked,
      // skip the two-pass split and paint all pages in one pass.
      final hasLockedPages = pages.any((p) => p.pageModel.isLocked);

      if (hasLockedPages) {
        // Two-pass: locked first (background), unlocked on top
        final unlockedPages = <PdfPageNode>[];
        for (final page in pages) {
          if (page.pageModel.isLocked) {
            _paintPdfPage(
              canvas,
              page,
              viewport,
              painter,
              watermarkText: docNode.documentModel.watermarkText,
              nightMode: docNode.documentModel.nightMode,
              documentId: docId,
            );
          } else {
            unlockedPages.add(page);
          }
        }
        for (final page in unlockedPages) {
          _paintPdfPage(
            canvas,
            page,
            viewport,
            painter,
            watermarkText: docNode.documentModel.watermarkText,
            nightMode: docNode.documentModel.nightMode,
            documentId: docId,
          );
        }
      } else {
        // 🚀 Single-pass: no locked pages → paint all in order (center-first)
        for (final page in pages) {
          _paintPdfPage(
            canvas,
            page,
            viewport,
            painter,
            watermarkText: docNode.documentModel.watermarkText,
            nightMode: docNode.documentModel.nightMode,
            documentId: docId,
          );
        }
      }
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

    // 🗂️ STUB-OUT: free heavy fields on far-from-viewport pages.
    // Collects ALL pages from cached document nodes (O(docs × pages_per_doc))
    // then runs throttled stub-out pass.
    if (_pdfStubManager.stubbedCount > 0 || _pdfDocCache.isNotEmpty) {
      final allPages = <PdfPageNode>[];
      for (final doc in _pdfDocCache.values) {
        for (final child in doc.children) {
          if (child is PdfPageNode) allPages.add(child);
        }
      }
      // Hydrate pages entering viewport
      _pdfStubManager.maybeHydrate(allPages, viewport);
      // Stub out pages far from viewport
      _pdfStubManager.maybeStubOut(allPages, viewport);
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

  /// Paint a single PDF page with professional styling.
  ///
  /// Features: drop shadow, white background, LOD-aware content via
  /// [PdfPagePainter], thin border. Falls back to a numbered placeholder
  /// if no [PdfPagePainter] is available for this document.

  // ---------------------------------------------------------------------------
  // 📈 FUNCTION GRAPH RENDERING (outside tile cache — always visible)
  // ---------------------------------------------------------------------------

  /// Render all FunctionGraphNodes across visible layers.
  ///
  /// Like PDF/Tabular rendering, this runs OUTSIDE the tile/stroke cache
  /// to avoid disappearing when caches are rebuilt without the graph node.
  void _paintFunctionGraphNodes(Canvas canvas, Rect viewport) {
    for (final layer in sceneGraph.layers) {
      if (!layer.isVisible) continue;
      _collectAndPaintFunctionGraphs(canvas, layer, viewport);
    }
  }

  /// Recursively find and paint FunctionGraphNodes in a subtree.
  void _collectAndPaintFunctionGraphs(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
  ) {
    if (node is FunctionGraphNode) {
      // Viewport culling
      final tx = node.localTransform.getTranslation();
      final nodeBounds = node.localBounds.translate(tx.x, tx.y);
      if (!viewport.overlaps(nodeBounds)) return;

      canvas.save();
      canvas.translate(tx.x, tx.y);
      // Apply scale from transform (for resize)
      final sx = node.localTransform.getColumn(0).length;
      final sy = node.localTransform.getColumn(1).length;
      if ((sx - 1.0).abs() > 0.001 || (sy - 1.0).abs() > 0.001) {
        canvas.scale(sx, sy);
      }
      final isDark = true; // Default to dark (renderer can't access Theme)
      FunctionGraphRenderer.drawFunctionGraphNode(canvas, node, isDark: isDark);
      canvas.restore();
    } else if (node is GroupNode) {
      for (final child in node.children) {
        if (child.isVisible) {
          _collectAndPaintFunctionGraphs(canvas, child, viewport);
        }
      }
    }
  }
  void _paintPdfPage(
    Canvas canvas,
    PdfPageNode pageNode,
    Rect viewport,
    PdfPagePainter? painter, {
    String? watermarkText,
    bool nightMode = false,
    String? documentId,
  }) {
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

    // 🚀 LOD DEGRADATION: At very low zoom, pages are tiny on screen.
    // Skip full PDF rendering and draw a colored rectangle instead
    // (matching strokes/images LOD behavior). Saves 8-13ms per page.
    final screenScale = controller?.scale ?? canvasScale;
    final screenHeight = size.height * screenScale;
    if (screenHeight < 80) {
      // Page is <80px tall on screen — draw LOD rectangle
      _pdfLodRectFill.color = const Color(0x20B71C1C); // red-grey fill
      canvas.drawRect(pageRect, _pdfLodRectFill);
      _pdfLodRectStroke.color = const Color(0x40B71C1C); // red-grey border
      canvas.drawRect(pageRect, _pdfLodRectStroke);
      return;
    }

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

    // 🚀 Quality tiers based on screen size — skip expensive GPU effects
    // Shadow (MaskFilter.blur) costs ~1-2ms per page on GPU.
    final isDetailVisible = screenHeight > 200;

    // 🎨 Drop shadow (professional paper look) — skip at low zoom
    if (isDetailVisible) {
      final shadowRect = pageRect.translate(0, 4);
      canvas.drawRect(shadowRect, _pdfShadowPaint);
    }

    // White page background
    canvas.drawRect(pageRect, _pdfPageBgPaint);

    // Draw page content via PdfPagePainter (LOD-aware) or fallback
    canvas.save();
    canvas.translate(pos.dx, pos.dy);

    if (painter != null) {
      // 🚀 VIEWPORT PRIORITY: pages whose center is outside the viewport
      // get a reduced LOD (50% zoom) — renders at lower quality first,
      // upgrades when user scrolls to them.
      final pageCenter = pageRect.center;
      final isEdgePage = !viewport.contains(pageCenter);
      final effectiveZoom = controller?.scale ?? canvasScale;
      final lodZoom = isEdgePage ? effectiveZoom * 0.5 : effectiveZoom;

      painter.paintPage(
        canvas,
        pageNode,
        currentZoom: lodZoom,
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

    // Thin border — skip at low zoom (sub-pixel anyway)
    if (isDetailVisible) {
      canvas.drawRect(pageRect, _pdfBorderPaint);
    }

    // 💧 Watermark overlay (rotated diagonal text)
    // 🚀 PERF: skip at low zoom (text invisible, saves TextPainter.layout cost)
    if (watermarkText != null && isDetailVisible) {
      canvas.save();
      final cx = pageRect.center.dx;
      final cy = pageRect.center.dy;
      canvas.translate(cx, cy);
      canvas.rotate(-0.5); // ~29°
      _wmTextPainter.text = TextSpan(
        text: watermarkText,
        style: TextStyle(
          color: const Color(0x18000000),
          fontSize: pageRect.width * 0.12,
          fontWeight: FontWeight.w900,
          letterSpacing: 8,
        ),
      );
      _wmTextPainter.layout();
      _wmTextPainter.paint(
        canvas,
        Offset(-_wmTextPainter.width / 2, -_wmTextPainter.height / 2),
      );
      canvas.restore();
    }

    // Close rotation transform — everything below is world-space
    if (rotation != 0) {
      canvas.restore();
    }

    // ─── WORLD-SPACE OVERLAYS ───────────────────────────────────────
    // Annotations (strokes) are in world coordinates and must NOT be rotated.
    // Clip to the effective rotated page bounds so they only appear on the
    // visible page area.
    // 🚀 PERF: skip at low zoom (annotations invisible at <200px)
    final annotations = pageNode.pageModel.annotations;
    if (isDetailVisible &&
        annotations.isNotEmpty &&
        pageNode.pageModel.showAnnotations) {
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
        scale: controller?.scale ?? canvasScale,
        cachedPath: stroke.cachedPath,
      );
    }
  }

  /// 🚀 When true, committed strokes haven't changed — skip repaint entirely.
  final bool isActivelyDrawing;

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) {
    // 🚀 HOT PATH: during active drawing, committed strokes don't change.
    // Only CurrentStrokePainter needs to repaint. Suppress ALL DrawingPainter
    // repaints to save 6-10ms of tile rebuild per frame.
    if (isActivelyDrawing) return false;

    // 🚀 GESTURE SUPPRESSION: during active pan/zoom, the Transform widget
    // handles visuals via GPU compositing (zero cost). Defer tile rebuilds
    // and LOD transitions until the gesture settles. This prevents:
    // - Tile cache thrashing during rapid zoom (300% → 10%)
    // - Viewport boundary repaints during fast dragging
    final isGesturing = controller?.isPanning ?? false;

    // 🔑 GESTURE-END DETECTION: when the gesture ends (isPanning goes
    // true→false), force a repaint so content re-renders at the new LOD
    // tier instead of staying as degraded rectangles.
    if (_wasGesturing && !isGesturing) {
      _wasGesturing = false;
      return true; // Force repaint at new LOD
    }
    _wasGesturing = isGesturing;

    // 🔑 SCALE-CHANGE DETECTION: if we're not gesturing and the scale
    // changed since the last paint, force a repaint for LOD transition.
    // This catches cases where gesture-end detection misses (e.g., fling).
    if (!isGesturing && canvasScale != _lastPaintedScale) {
      return true;
    }

    if (isGesturing) {
      // Allow repaints for content changes (stroke add/undo)
      if (oldDelegate._sceneGraphVersion != _sceneGraphVersion) return true;
      // 🚀 Allow LOD repaints during gesture — so LOD transitions
      // happen in real-time during pinch zoom, not just on release.
      if (_lodProgressiveMode) return true;
      if (controller != null) {
        final s = controller!.scale;
        final tier = s < 0.18 ? 2 : (s < 0.45 ? 1 : 0);
        if (tier != _cachedLodTier) return true;
      }
      return false;
    }

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
    // 🚀 LIVE VERSION CHECK: detect scene graph changes during in-flight
    // manipulations (section drag/resize, shape edit) where the widget
    // isn't rebuilt but sceneGraph.version IS bumped.
    // Compare against STATIC _cachedSceneVersion (updated in paint)
    // to avoid false positives from new delegate instances.
    if (_cachedSceneVersion >= 0 && sceneGraph.version != _cachedSceneVersion) {
      return true;
    }

    // 🚀 LOD TIER TRANSITION: trigger repaint when LOD changed.
    // Uses debounce from widget layer (300ms after zoom settles).
    if (controller != null) {
      final s = controller!.scale;
      final tier = s < 0.2 ? 2 : (s < 0.5 ? 1 : 0);
      if (tier != _cachedLodTier) {
        return true;
      }
    }

    // 🚀 Progressive LOD: keep repainting until transition completes.
    if (_lodProgressiveMode) {
      return true;
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

  /// Trigger a repaint of the DrawingPainter (increments the repaint notifier).
  /// Use when non-stroke nodes change (e.g., FunctionGraphNode drag/resize).
  static void triggerRepaint() {
    _lodRepaintNotifier.value++;
  }

  /// 🗂️ Initialize stroke paging manager with shared SQLite database.
  /// Call once during canvas setup to enable 1M+ stroke memory management.
  static Future<void> initializePaging(dynamic database) async {
    await _pagingManager.initialize(database);
    await _persistentIndex.initialize(database);
    await _offsetIndex.initialize(database);
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

  /// 📦 Build offset index after save for seekable binary on next load.
  static Future<void> buildOffsetIndex(
    String canvasId,
    Uint8List binaryData,
    List<CanvasLayer> layers,
  ) async {
    if (!_offsetIndex.isInitialized) return;
    await _offsetIndex.buildIndex(canvasId, binaryData, layers);
  }

  /// 📦 Read a single stroke by seeking to its byte offset in the binary.
  static Future<ProStroke?> readStrokeByOffset(
    String canvasId,
    String strokeId,
    Uint8List binaryData,
  ) async {
    if (!_offsetIndex.isInitialized) return null;
    return _offsetIndex.readStroke(canvasId, strokeId, binaryData);
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
