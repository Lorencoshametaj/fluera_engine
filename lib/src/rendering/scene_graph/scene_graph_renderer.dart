import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/engine_scope.dart';
import '../../core/engine_error.dart';
import '../../core/scene_graph/canvas_node.dart';
import '../../core/nodes/group_node.dart';
import '../../core/nodes/layer_node.dart';
import '../../core/nodes/stroke_node.dart';
import '../../core/nodes/shape_node.dart';
import '../../core/nodes/text_node.dart';
import '../../core/nodes/image_node.dart';
import '../../core/nodes/clip_group_node.dart';
import '../../core/nodes/path_node.dart';
import '../../core/effects/node_effect.dart';
import '../../core/nodes/rich_text_node.dart';
import '../../core/nodes/symbol_system.dart';
import '../../core/nodes/frame_node.dart';
import '../../core/nodes/advanced_mask_node.dart';
import '../../core/nodes/boolean_group_node.dart';
import '../../core/nodes/pdf_page_node.dart';
import '../../core/nodes/pdf_document_node.dart';
import '../../core/nodes/pdf_preview_card_node.dart';
import '../../core/nodes/vector_network_node.dart';
import '../../core/effects/shader_effect.dart';
import '../../core/nodes/latex_node.dart';
import '../../core/nodes/tabular_node.dart';
import '../../core/nodes/material_zone_node.dart';
import '../../core/nodes/section_node.dart';
import '../../core/nodes/adjustment_layer_node.dart';
import '../../core/nodes/function_graph_node.dart';
import '../../core/effects/paint_stack.dart';
import '../../core/models/shape_type.dart';
import '../../core/scene_graph/scene_graph.dart';
import '../../core/scene_graph/invalidation_graph.dart';
import '../../drawing/models/pro_drawing_point.dart';
import './render_plan.dart';
import '../../core/scene_graph/node_visitor.dart';
import '../../drawing/brushes/brushes.dart';
import './vector_network_renderer.dart';
import '../../systems/layout_engine.dart';
import '../canvas/shape_painter.dart';
import './path_renderer.dart';
import './rich_text_renderer.dart';
import './render_interceptor.dart';
import './render_batch.dart';
import './tabular_renderer.dart';
import './latex_renderer.dart';
import './function_graph_renderer.dart';
import '../optimization/layer_picture_cache.dart';
import '../optimization/snapshot_cache_manager.dart';
import '../optimization/optimization.dart';
import '../shaders/adjustment_shader_service.dart';

/// Renders a [SceneGraph] by recursively traversing the node tree.
///
/// Each node's `localTransform`, `opacity`, and `blendMode` are
/// applied via Canvas save/restore and `saveLayer` compositing.
///
/// This renderer is designed to be used alongside (or eventually
/// replace) the flat-list rendering in `DrawingPainter`. During the
/// transition, it can be called for specific subtrees or layers.
///
/// Usage:
/// ```dart
/// final renderer = SceneGraphRenderer();
/// renderer.render(canvas, sceneGraph, viewport);
/// ```
class SceneGraphRenderer {
  // ---------------------------------------------------------------------------
  // Render Interceptors
  // ---------------------------------------------------------------------------

  final List<RenderInterceptor> _interceptors = [];

  /// The internal visitor used for O(1) type-safe dispatch.
  late final _RendererVisitor _visitor;

  /// Batch renderer for material-sorted draw call coalescing.
  final BatchRenderer batchRenderer = BatchRenderer();

  /// Symbol registry for resolving [SymbolInstanceNode]s.
  SymbolRegistry? _symbolRegistry;

  /// Current zoom scale — used for LOD decisions in stroke rendering.
  /// Set per frame in [render()].
  double _currentScale = 1.0;

  /// Set the current zoom scale for LOD decisions.
  /// Call before [renderNode] when rendering tiles outside of [render].
  set currentScale(double s) => _currentScale = s;

  /// Stroke IDs to skip during the global render pass.
  ///
  /// Set per frame by [DrawingPainter] to exclude PDF-linked annotation
  /// strokes from the global pass (they are rendered clipped inside
  /// [DrawingPainter._paintPdfPage] instead).
  Set<String>? skipStrokeIds;

  /// 🧠 Recall mode: stroke IDs to completely hide during recall.
  ///
  /// Unlike [skipStrokeIds] (per-frame, cleared after paint), this persists
  /// for the duration of recall mode. Strokes in this set are not rendered.
  Set<String>? recallHiddenIds;

  /// When true, PDF page and document nodes are skipped during rendering.
  ///
  /// Set by [DrawingPainter] to prevent PDF pages from being baked into
  /// the stroke cache Picture. PDF pages are rendered separately in
  /// [DrawingPainter._paintPdfDocuments], so including them in the cache
  /// causes ghost pages when pages are dragged (stale cached positions).
  bool skipPdfNodes = false;

  // ---------------------------------------------------------------------------
  // Compiled Render Plan (GAP 1)
  // ---------------------------------------------------------------------------

  /// Cached compiled render plan — reused when the scene graph hasn't changed.
  RenderPlan? _cachedPlan;

  /// Compiler for building render plans from the scene graph.
  final RenderPlanCompiler _planCompiler = RenderPlanCompiler();

  /// Whether to use the compiled render plan path.
  ///
  /// Enabled by default. Disable for debugging or when interceptors
  /// need per-node control (interceptors bypass the plan).
  bool useRenderPlan = true;

  // ---------------------------------------------------------------------------
  // Invalidation Graph (GAP 2)
  // ---------------------------------------------------------------------------

  /// Optional invalidation graph for dirty-driven plan invalidation.
  InvalidationGraph? _invalidationGraph;

  /// Connect an invalidation graph for incremental rendering.
  set invalidationGraph(InvalidationGraph? graph) {
    _invalidationGraph = graph;
  }

  // ---------------------------------------------------------------------------
  // Layer Picture Cache (GAP C wiring)
  // ---------------------------------------------------------------------------

  /// Per-layer Picture cache for zero re-traversal rendering.
  final LayerPictureCache layerPictureCache = LayerPictureCache();

  // ---------------------------------------------------------------------------
  // Snapshot Cache (GAP E wiring)
  // ---------------------------------------------------------------------------

  /// Optional snapshot cache for node-based image caching.
  SnapshotCacheManager? _snapshotCache;

  /// Connect a snapshot cache manager for node-based snapshot invalidation.
  set snapshotCache(SnapshotCacheManager? cache) {
    _snapshotCache = cache;
  }

  /// Adjustment layer GPU shader service.
  final AdjustmentShaderService adjustmentShaderService =
      AdjustmentShaderService();

  SceneGraphRenderer() {
    _visitor = _RendererVisitor(this);
  }

  /// Cache for instanced symbol definitions.
  final Map<String, ui.Picture> _symbolPictureCache = {};

  /// Set the symbol registry used to resolve component instances.
  set symbolRegistry(SymbolRegistry? registry) => _symbolRegistry = registry;

  /// Register an interceptor to the render chain.
  void addInterceptor(RenderInterceptor interceptor) =>
      _interceptors.add(interceptor);

  /// Remove a previously registered interceptor.
  void removeInterceptor(RenderInterceptor interceptor) =>
      _interceptors.remove(interceptor);

  /// Remove all interceptors.
  void clearInterceptors() => _interceptors.clear();

  /// Clear any cached resources like symbol stamping pictures.
  void clearCache() {
    for (final p in _symbolPictureCache.values) {
      p.dispose();
    }
    _symbolPictureCache.clear();
  }

  /// Currently registered interceptors (read-only view).
  List<RenderInterceptor> get interceptors => List.unmodifiable(_interceptors);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Render the entire scene graph.
  ///
  /// Only nodes whose world bounds intersect [viewport] are rendered.
  /// [scale] is the current zoom level, used for adaptive LOD (sub-pixel
  /// stroke skipping at low zoom).
  ///
  /// When [useRenderPlan] is enabled and no interceptors are registered,
  /// the renderer uses a compiled [RenderPlan] that avoids recursive
  /// traversal on unchanged frames.
  void render(
    Canvas canvas,
    SceneGraph sceneGraph,
    Rect viewport, {
    double scale = 1.0,
  }) {
    _currentScale = scale;

    for (final i in _interceptors) {
      i.onFrameStart();
    }

    // --- Compiled Render Plan path (GAP 1) ---
    // Use the plan when: (1) enabled, (2) no interceptors (interceptors
    // need per-node hooks that the flat plan can't provide).
    if (useRenderPlan && _interceptors.isEmpty) {
      final planValid =
          _cachedPlan != null &&
          _cachedPlan!.isValid(
            currentGraphVersion: sceneGraph.version,
            currentViewport: viewport,
            currentScale: scale,
            invalidationGraph: _invalidationGraph,
          );

      if (!planValid) {
        _cachedPlan = _planCompiler.compile(sceneGraph, viewport, scale: scale);
      }

      _cachedPlan!.execute(canvas, this);

      // Clear dirty flags after rendering and propagate to caches.
      if (_invalidationGraph != null) {
        if (_invalidationGraph!.hasDirty) {
          final dirtyIds = _invalidationGraph!.collectAllDirty();
          // GAP C: invalidate layer pictures for dirty nodes.
          layerPictureCache.invalidateDirty(dirtyIds);
          // GAP E: invalidate node-based snapshots for dirty nodes.
          _snapshotCache?.onDirtyNodes(dirtyIds);
        }
        _invalidationGraph!.clearAll();
      }
    } else {
      // --- Legacy recursive path (with interceptor support) ---
      for (final layer in sceneGraph.layers) {
        if (!layer.isVisible) continue;
        renderNode(canvas, layer, viewport);
      }
    }

    // Flush any accumulated batched draw calls.
    batchRenderer.flushAll(canvas);

    for (final i in _interceptors) {
      i.onFrameEnd();
    }
  }

  /// Invalidate the cached render plan, forcing recompilation next frame.
  ///
  /// Call this when the scene graph changes in a way not tracked by
  /// the invalidation graph (e.g., external property mutations).
  void invalidatePlan() {
    _cachedPlan?.markDirty();
    _cachedPlan = null;
  }

  /// Render a single node and its subtree.
  ///
  /// This is the core recursive dispatch method. It handles:
  /// 1. Visibility & viewport culling
  /// 2. Transform application
  /// 3. Compositing (opacity / blendMode)
  /// 4. Clip masks
  /// 5. Type-specific rendering
  void renderNode(Canvas canvas, CanvasNode node, Rect viewport) {
    // Interceptor chain — zero overhead when empty.
    if (_interceptors.isNotEmpty) {
      _runInterceptorChain(canvas, node, viewport);
      return;
    }
    _renderNodeDirect(canvas, node, viewport);
  }

  /// Run the interceptor chain for a single node.
  ///
  /// Uses a zero-allocation iterative approach: a single persistent
  /// [_InterceptorChainRunner] walks the interceptor list via an index.
  /// No closures are allocated per node — the runner is reused across all
  /// nodes in the frame. Each interceptor is wrapped in try/catch so a
  /// failing interceptor cannot crash the entire frame.
  void _runInterceptorChain(Canvas canvas, CanvasNode node, Rect viewport) {
    _chainRunner ??= _InterceptorChainRunner(this);
    _chainRunner!.run(canvas, node, viewport, _interceptors);
  }

  /// Reusable chain runner — allocated once, zero per-node overhead.
  _InterceptorChainRunner? _chainRunner;

  /// The actual node rendering logic (no interceptors).
  void _renderNodeDirect(Canvas canvas, CanvasNode node, Rect viewport) {
    if (!node.isVisible) return;

    // Viewport culling — skip nodes entirely outside the viewport.
    final bounds = node.worldBounds;
    if (bounds.isFinite && !bounds.overlaps(viewport)) return;

    // Save canvas state for this node's transform.
    canvas.save();

    // Apply local transform.
    if (!node.isIdentityTransform) {
      canvas.transform(node.localTransform.storage);
    }

    // Apply pre-effects (shadows, glow) — drawn BEFORE the node.
    _applyPreEffects(canvas, node, viewport);

    // Compositing layer (opacity / blendMode).
    final needsCompositing = shouldComposite(node);
    if (needsCompositing) {
      canvas.saveLayer(null, createCompositingPaint(node));
    }

    // Post-effects that need saveLayer wrapping (blur, color overlay).
    final postLayers = _beginPostEffects(canvas, node);

    // Dispatch by node type using O(1) visitor instead of O(N) 17-branch if/else.
    _visitor.setContext(canvas, viewport);
    node.accept(_visitor);

    // End post-effect layers.
    _endPostEffects(canvas, postLayers);

    // Pop compositing layer.
    if (needsCompositing) {
      canvas.restore();
    }

    // Pop transform.
    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // Render Plan leaf dispatch
  // ---------------------------------------------------------------------------

  /// Render a leaf node directly, used by [RenderPlan.execute].
  ///
  /// Unlike [_renderNodeDirect], this does NOT handle save/restore,
  /// transforms, or compositing — those are already in the plan.
  /// It only dispatches the node-type-specific drawing.
  void renderNodeLeaf(Canvas canvas, CanvasNode node) {
    // For complex nodes that need full traversal (ClipGroup, Frame,
    // AdvancedMask), we delegate to the full recursive path.
    if (node is ClipGroupNode) {
      _renderClipGroup(canvas, node, const Rect.fromLTWH(-1e9, -1e9, 2e9, 2e9));
      return;
    }
    if (node is FrameNode) {
      _renderFrame(canvas, node, const Rect.fromLTWH(-1e9, -1e9, 2e9, 2e9));
      return;
    }
    if (node is SectionNode) {
      _renderSection(canvas, node, const Rect.fromLTWH(-1e9, -1e9, 2e9, 2e9));
      return;
    }
    if (node is AdvancedMaskNode) {
      _renderAdvancedMask(
        canvas,
        node,
        const Rect.fromLTWH(-1e9, -1e9, 2e9, 2e9),
      );
      return;
    }
    if (node is GroupNode) {
      // Groups in the plan path just render their children recursively.
      for (final child in node.children) {
        renderNode(canvas, child, const Rect.fromLTWH(-1e9, -1e9, 2e9, 2e9));
      }
      return;
    }

    // Standard leaf dispatch via visitor.
    _visitor.setContext(canvas, const Rect.fromLTWH(-1e9, -1e9, 2e9, 2e9));
    node.accept(_visitor);
  }

  // -------------------------------------------------------------------------
  // Private rendering methods
  // -------------------------------------------------------------------------

  /// Render all children of a GroupNode.
  void _renderChildren(Canvas canvas, GroupNode group, Rect viewport) {
    // Pass 1: Render SectionNodes first (always behind strokes/images).
    for (final child in group.children) {
      if (child is SectionNode) renderNode(canvas, child, viewport);
    }
    // Pass 2: Render everything else on top.
    for (final child in group.children) {
      if (child is! SectionNode) renderNode(canvas, child, viewport);
    }
  }

  /// Render a ClipGroupNode with its mask.
  void _renderClipGroup(Canvas canvas, ClipGroupNode clipNode, Rect viewport) {
    final applied = applyClipMask(canvas, clipNode);
    if (!applied) return;

    // Render the masked content (all children except the mask source).
    for (final child in clipNode.maskedContent) {
      renderNode(canvas, child, viewport);
    }

    if (clipNode.clipMode == ClipMode.alphaMask) {
      // Finalize alpha mask compositing.
      finalizeAlphaMask(
        canvas,
        clipNode,
        (c, node) => renderNode(c, node, viewport),
      );
    } else {
      // Pop the clip save.
      canvas.restore();
    }
  }

  /// Render a single stroke via BrushEngine.
  ///
  /// Applies adaptive LOD: at zoom < 0.5, strokes whose on-screen size
  /// would be smaller than 2px are skipped entirely. This matches the
  /// logic in [ViewportCuller.applyAdaptiveLOD].
  void _renderStroke(Canvas canvas, StrokeNode node) {
    final stroke = node.stroke;
    if (stroke.points.isEmpty) return;

    // Skip strokes that belong to a PDF page — they are rendered
    // clipped inside _paintPdfPage instead of the global pass.
    if (skipStrokeIds != null && skipStrokeIds!.contains(stroke.id)) return;

    // 🧠 Recall mode: completely hide original strokes.
    if (recallHiddenIds != null && recallHiddenIds!.contains(stroke.id)) return;

    // Adaptive LOD: skip sub-pixel strokes at low zoom.
    if (_currentScale < 0.5) {
      final bounds = stroke.bounds;
      final screenSize = math.max(
        bounds.width * _currentScale,
        bounds.height * _currentScale,
      );
      if (screenSize < 4.0) return;
    }

    if (stroke.isFill) {
      _drawFillOverlay(canvas, stroke);
      return;
    }

    // ─────────────────────────────────────────────────────────────────
    // 🚀 ULTRA-FAST PATH: bypass entire BrushEngine pipeline for
    // simple committed strokes at normal zoom. Conditions:
    // - Has cachedPath (committed, not decimated)
    // - Normal zoom (≥ 0.5, no LOD decimation)
    // - Simple pen (ballpoint with default settings)
    // - No blend mode, no texture, no stamp
    // Saves: EngineScope lookup, pressure curve, surface material,
    // 15+ conditional checks per stroke.
    // ─────────────────────────────────────────────────────────────────
    if (_currentScale >= 0.5 &&
        stroke.penType == ProPenType.ballpoint &&
        stroke.settings.textureType == 'none' &&
        stroke.settings.pressureCurve.isLinear &&
        !stroke.settings.stampEnabled) {
      BallpointBrush.drawStrokeWithSettings(
        canvas,
        stroke.points,
        stroke.color,
        stroke.baseWidth,
        minPressure: stroke.settings.ballpointMinPressure,
        maxPressure: stroke.settings.ballpointMaxPressure,
        cachedPath: stroke.cachedPath,
      );
      return;
    }

    // 🚀 RASTER LOD: decimate points at low zoom to reduce GPU path
    // complexity. Missing points are sub-pixel on screen → invisible.
    var points = stroke.points;
    final isDecimated = _currentScale < 0.5 && points.length > 10;
    if (isDecimated) {
      final step = (1.0 / _currentScale).ceil().clamp(2, 8);
      final decimated = <ProDrawingPoint>[];
      for (int i = 0; i < points.length; i += step) {
        decimated.add(points[i]);
      }
      if (decimated.last != points.last) {
        decimated.add(points.last);
      }
      points = decimated;
    }
    BrushEngine.renderStroke(
      canvas,
      points,
      stroke.color,
      stroke.baseWidth,
      stroke.penType,
      stroke.settings,
      scale: _currentScale,
      // O(1) cached path only when points aren't decimated
      cachedPath: isDecimated ? null : stroke.cachedPath,
    );
  }

  /// Render a shape via the paint stack, or legacy ShapePainter.
  void _renderShape(Canvas canvas, ShapeNode node) {
    if (node.fills.isEmpty && node.strokes.isEmpty) {
      // Legacy path — delegate to ShapePainter which reads GeometricShape.
      ShapePainter.drawShape(canvas, node.shape);
      return;
    }

    // Stack-based rendering: build the shape path, then draw fills + strokes.
    final shapePath = _buildShapePath(node.shape);
    if (shapePath == null) {
      // Unsupported shape type — fall back to legacy.
      ShapePainter.drawShape(canvas, node.shape);
      return;
    }

    final bounds = node.localBounds;

    // Draw fill stack.
    for (final fill in node.fills) {
      if (!fill.isVisible) continue;
      // Gradient + opacity < 1 needs a saveLayer for correct compositing.
      if (fill.type == FillType.gradient &&
          fill.gradient != null &&
          fill.opacity < 1.0) {
        canvas.saveLayer(
          null,
          Paint()
            ..color = Color.fromARGB(
              (fill.opacity * 255).round(),
              255,
              255,
              255,
            ),
        );
        final paint =
            Paint()
              ..style = PaintingStyle.fill
              ..isAntiAlias = true
              ..shader = fill.gradient!.toShader(bounds)
              ..blendMode = fill.blendMode;
        canvas.drawPath(shapePath, paint);
        canvas.restore();
      } else {
        final paint = fill.toPaint(bounds);
        if (paint != null) {
          canvas.drawPath(shapePath, paint);
        }
      }
    }

    // Draw stroke stack.
    for (final stroke in node.strokes) {
      if (!stroke.isVisible) continue;
      if (stroke.color == null && stroke.gradient == null) continue;

      final paint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.width
            ..strokeCap = stroke.cap
            ..strokeJoin = stroke.join
            ..strokeMiterLimit = 4.0
            ..isAntiAlias = true
            ..blendMode = stroke.blendMode;

      final needsOpacityLayer = stroke.opacity < 1.0 && stroke.gradient != null;
      if (stroke.gradient != null && bounds.isFinite && !bounds.isEmpty) {
        paint.shader = stroke.gradient!.toShader(bounds);
      } else if (stroke.color != null) {
        paint.color = stroke.color!.withValues(
          alpha: stroke.color!.a * stroke.opacity,
        );
      } else {
        continue;
      }

      // Apply dash pattern.
      final drawPath =
          stroke.dashPattern != null && stroke.dashPattern!.isNotEmpty
              ? PathRenderer.applyDashPattern(shapePath, stroke.dashPattern!)
              : shapePath;

      if (needsOpacityLayer) {
        canvas.saveLayer(
          null,
          Paint()
            ..color = Color.fromARGB(
              (stroke.opacity * 255).round(),
              255,
              255,
              255,
            ),
        );
      }

      switch (stroke.position) {
        case StrokePosition.center:
          canvas.drawPath(drawPath, paint);
          break;
        case StrokePosition.inside:
          canvas.save();
          canvas.clipPath(shapePath);
          paint.strokeWidth = stroke.width * 2;
          canvas.drawPath(drawPath, paint);
          canvas.restore();
          break;
        case StrokePosition.outside:
          canvas.saveLayer(null, Paint());
          paint.strokeWidth = stroke.width * 2;
          canvas.drawPath(drawPath, paint);
          canvas.drawPath(
            shapePath,
            Paint()
              ..style = PaintingStyle.fill
              ..blendMode = BlendMode.dstOut,
          );
          canvas.restore();
          break;
      }

      if (needsOpacityLayer) {
        canvas.restore();
      }
    }
  }

  /// Build a Flutter [Path] from a [GeometricShape].
  ///
  /// Returns null only for freehand (which has no geometric definition).
  Path? _buildShapePath(GeometricShape shape) {
    final s = shape.startPoint;
    final e = shape.endPoint;
    final left = s.dx < e.dx ? s.dx : e.dx;
    final right = s.dx > e.dx ? s.dx : e.dx;
    final top = s.dy < e.dy ? s.dy : e.dy;
    final bottom = s.dy > e.dy ? s.dy : e.dy;
    final cx = (left + right) / 2;
    final cy = (top + bottom) / 2;
    final w = (right - left) / 2;
    final h = (bottom - top) / 2;

    switch (shape.type) {
      case ShapeType.line:
        return Path()
          ..moveTo(s.dx, s.dy)
          ..lineTo(e.dx, e.dy);

      case ShapeType.rectangle:
        return Path()..addRect(Rect.fromPoints(s, e));

      case ShapeType.circle:
        return Path()..addOval(
          Rect.fromCenter(center: Offset(cx, cy), width: w * 2, height: h * 2),
        );

      case ShapeType.triangle:
        return Path()
          ..moveTo(cx, top)
          ..lineTo(right, bottom)
          ..lineTo(left, bottom)
          ..close();

      case ShapeType.diamond:
        return Path()
          ..moveTo(cx, cy - h)
          ..lineTo(cx + w, cy)
          ..lineTo(cx, cy + h)
          ..lineTo(cx - w, cy)
          ..close();

      case ShapeType.pentagon:
        return _buildRegularPolygon(cx, cy, w < h ? w : h, 5);

      case ShapeType.hexagon:
        return _buildRegularPolygon(cx, cy, w < h ? w : h, 6);

      case ShapeType.star:
        return _buildStar(cx, cy, w < h ? w : h, 5);

      case ShapeType.heart:
        return _buildHeart(cx, cy, w, h);

      case ShapeType.arrow:
        return _buildArrow(left, top, right, bottom);

      case ShapeType.freehand:
        // Freehand doesn't have a geometric path definition.
        return null;
    }
  }

  /// Build a regular polygon path with [sides] vertices.
  Path _buildRegularPolygon(double cx, double cy, double r, int sides) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = -3.14159265358979 / 2 + (2 * 3.14159265358979 * i / sides);
      final x = cx + r * _cos(angle);
      final y = cy + r * _sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  /// Build a 5-pointed star path.
  Path _buildStar(double cx, double cy, double outerR, int points) {
    final innerR = outerR * 0.4;
    final path = Path();
    for (int i = 0; i < points * 2; i++) {
      final angle = -3.14159265358979 / 2 + (3.14159265358979 * i / points);
      final r = i.isEven ? outerR : innerR;
      final x = cx + r * _cos(angle);
      final y = cy + r * _sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  /// Build a heart shape using cubic Bézier curves.
  Path _buildHeart(double cx, double cy, double w, double h) {
    final path = Path();
    path.moveTo(cx, cy + h * 0.3);
    // Left side
    path.cubicTo(cx - w, cy - h * 0.3, cx - w, cy - h, cx, cy - h * 0.4);
    // Right side
    path.cubicTo(cx + w, cy - h, cx + w, cy - h * 0.3, cx, cy + h * 0.3);
    path.close();
    return path;
  }

  /// Build a right-pointing arrow shape.
  Path _buildArrow(double left, double top, double right, double bottom) {
    final w = right - left;
    final h = bottom - top;
    final cy = (top + bottom) / 2;
    final shaftTop = top + h * 0.3;
    final shaftBottom = bottom - h * 0.3;
    final headStart = left + w * 0.6;

    return Path()
      ..moveTo(left, shaftTop)
      ..lineTo(headStart, shaftTop)
      ..lineTo(headStart, top)
      ..lineTo(right, cy)
      ..lineTo(headStart, bottom)
      ..lineTo(headStart, shaftBottom)
      ..lineTo(left, shaftBottom)
      ..close();
  }

  // Trig helpers using dart:math.
  static double _cos(double rad) => math.cos(rad);
  static double _sin(double rad) => math.sin(rad);

  /// Render a vector path via PathRenderer.
  void _renderPath(Canvas canvas, PathNode node) {
    PathRenderer.drawPathNode(canvas, node);
  }

  /// Render a rich text node via RichTextRenderer.
  void _renderRichText(Canvas canvas, RichTextNode node) {
    RichTextRenderer.drawRichTextNode(canvas, node);
  }

  /// Render a symbol instance by looking up its definition.
  ///
  /// When a [SymbolRegistry] is set on the renderer, this method
  /// resolves the definition, applies variant selections, and renders
  /// the resolved [GroupNode] subtree.
  void _renderSymbolInstance(
    Canvas canvas,
    SymbolInstanceNode node,
    Rect viewport,
  ) {
    if (_symbolRegistry == null) return;

    final resolvedContent = _symbolRegistry!.resolveInstance(node);
    if (resolvedContent == null) return;

    // Cache bounds for hit testing and viewport culling.
    node.resolvedBounds = resolvedContent.worldBounds;

    // Symbol Instance Stamping: render definition once, stamp with transforms
    final picture = _symbolPictureCache.putIfAbsent(
      resolvedContent.id.value,
      () {
        final recorder = ui.PictureRecorder();
        final pbCanvas = Canvas(recorder);

        final infiniteRect = const Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6);
        _renderChildren(pbCanvas, resolvedContent, infiniteRect);

        return recorder.endRecording();
      },
    );

    canvas.drawPicture(picture);
  }

  /// Render a text element.
  ///
  /// Caches the [TextPainter] per node to avoid expensive [TextPainter.layout()]
  /// calls every frame. Only re-layouts when text properties change (detected
  /// via content hash).
  void _renderText(Canvas canvas, TextNode node) {
    final text = node.textElement;
    final contentHash = Object.hash(
      text.text,
      text.fontFamily,
      text.fontSize,
      text.color,
      text.fontWeight,
      text.scale,
    );

    final cached = _textPainterCache[node.id.value];
    TextPainter painter;
    if (cached != null && cached.contentHash == contentHash) {
      // Cache hit — skip layout.
      painter = cached.painter;
    } else {
      // Cache miss — create, layout, and cache.
      final textSpan = TextSpan(
        text: text.text,
        style: TextStyle(
          fontFamily: text.fontFamily,
          fontSize: text.fontSize * text.scale,
          color: text.color,
          fontWeight: text.fontWeight,
        ),
      );
      painter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
        ..layout();
      _textPainterCache[node.id.value] = _CachedTextPainter(
        painter,
        contentHash,
      );
      // Update cached size for hit testing.
      node.cachedTextSize = painter.size;
    }

    painter.paint(canvas, text.position);
  }

  /// Cached [TextPainter]s keyed by node ID. Only re-layout on property change.
  final Map<String, _CachedTextPainter> _textPainterCache = {};

  /// Render an image element.
  ///
  /// Note: actual image decoding/loading is handled externally by the
  /// pipeline. This method applies the transform
  /// and draws the image if already decoded and cached.
  void _renderImage(Canvas canvas, ImageNode node) {
    if (!EngineScope.hasScope) return;

    final image = EngineScope.current.imageCacheService.getCachedImage(
      node.imageElement.imagePath,
    );
    if (image == null) return;

    // Source rect is the full original image size
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    // Destination rect matches the node's local bounds
    final destRect = node.localBounds;

    final paint =
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromARGB((node.opacity * 255).round(), 255, 255, 255)
          ..blendMode = node.blendMode;

    canvas.drawImageRect(image, srcRect, destRect, paint);
  }

  /// Draw a fill overlay (bucket fill) for a stroke.
  void _drawFillOverlay(Canvas canvas, dynamic stroke) {
    if (stroke.fillOverlayImage == null) return;
    final src = Rect.fromLTWH(
      0,
      0,
      stroke.fillOverlayImage!.width.toDouble(),
      stroke.fillOverlayImage!.height.toDouble(),
    );
    final dst = stroke.bounds;
    canvas.drawImageRect(stroke.fillOverlayImage!, src, dst, Paint());
  }

  // -------------------------------------------------------------------------
  // Effect stack helpers
  // -------------------------------------------------------------------------

  /// Apply pre-effects (shadows, glow) — these draw BEFORE the node.
  void _applyPreEffects(Canvas canvas, CanvasNode node, Rect viewport) {
    for (final fx in node.effects) {
      if (!fx.isEnabled || !fx.isPre) continue;

      if (fx is DropShadowEffect) {
        canvas.save();
        canvas.translate(fx.offset.dx, fx.offset.dy);
        canvas.saveLayer(null, fx.createShadowPaint());
        // Draw the node's silhouette for the shadow
        _visitor.setContext(canvas, viewport);
        node.accept(_visitor);
        canvas.restore(); // saveLayer
        canvas.restore(); // translate
      } else if (fx is OuterGlowEffect) {
        canvas.saveLayer(null, fx.createGlowPaint());
        // Draw the node's silhouette for the glow
        _visitor.setContext(canvas, viewport);
        node.accept(_visitor);
        canvas.restore();
      }
    }
  }

  /// Begin post-effects by opening saveLayer(s). Returns the count of
  /// layers opened so [_endPostEffects] can close them.
  int _beginPostEffects(Canvas canvas, CanvasNode node) {
    int layerCount = 0;

    for (final fx in node.effects) {
      if (!fx.isEnabled || !fx.isPost) continue;

      if (fx is BlurEffect) {
        canvas.saveLayer(null, fx.createPaint());
        layerCount++;
      } else if (fx is ColorOverlayEffect) {
        canvas.saveLayer(null, fx.createPaint());
        layerCount++;
      } else if (fx is InnerShadowEffect) {
        // Inner shadow uses a dedicated saveLayer for dstOut compositing.
        canvas.saveLayer(null, Paint());
        layerCount++;
      }
    }

    return layerCount;
  }

  /// Close the post-effect saveLayer(s) opened by [_beginPostEffects].
  void _endPostEffects(Canvas canvas, int layerCount) {
    for (int i = 0; i < layerCount; i++) {
      canvas.restore();
    }
  }

  // -------------------------------------------------------------------------
  // Compositing helpers
  // -------------------------------------------------------------------------

  /// Whether a node needs a separate compositing layer.
  ///
  /// A compositing layer is needed when the node has non-default
  /// opacity or blend mode that must be applied atomically to
  /// the entire subtree.
  bool shouldComposite(CanvasNode node) {
    return node.opacity < 1.0 || node.blendMode != BlendMode.srcOver;
  }

  /// Create a [Paint] for compositing (opacity + blend mode).
  Paint createCompositingPaint(CanvasNode node) {
    return Paint()
      ..color = Color.fromRGBO(255, 255, 255, node.opacity)
      ..blendMode = node.blendMode;
  }

  /// Apply a clip mask from a [ClipGroupNode].
  ///
  /// Returns true if the clip was successfully applied.
  bool applyClipMask(Canvas canvas, ClipGroupNode clipNode) {
    final maskSource = clipNode.maskSource;
    if (maskSource == null) return false;

    if (clipNode.clipMode == ClipMode.alphaMask) {
      // Alpha mask: use saveLayer with dstIn blend to mask content.
      canvas.saveLayer(null, Paint());
      return true;
    } else {
      // Path clip: clip to the mask source's bounds.
      canvas.save();
      canvas.clipRect(maskSource.localBounds);
      return true;
    }
  }

  /// Finalize alpha mask compositing.
  ///
  /// After the masked content has been rendered, this draws the
  /// mask source with DstIn blend mode to produce the alpha mask effect.
  void finalizeAlphaMask(
    Canvas canvas,
    ClipGroupNode clipNode,
    void Function(Canvas, CanvasNode) renderCallback,
  ) {
    final maskSource = clipNode.maskSource;
    if (maskSource == null) return;

    // Draw the mask with DstIn: keeps only the content where the mask is opaque.
    canvas.saveLayer(null, Paint()..blendMode = BlendMode.dstIn);
    renderCallback(canvas, maskSource);
    canvas.restore(); // DstIn layer
    canvas.restore(); // Content layer
  }

  // ---------------------------------------------------------------------------
  // Adjustment Layer rendering (GPU post-processing)
  // ---------------------------------------------------------------------------

  /// Render an [AdjustmentLayerNode] via GPU fragment shader.
  ///
  /// Captures the current layer content into a [Picture] → [Image], then
  /// draws a full-viewport rect with the adjustment shader applied,
  /// producing the color-transformed output.
  ///
  /// Falls back to no-op if the shader is not loaded.
  void _renderAdjustmentLayer(
    Canvas canvas,
    AdjustmentLayerNode node,
    Rect viewport,
  ) {
    if (!adjustmentShaderService.isAvailable) return;
    if (node.adjustmentStack.layers.isEmpty) return;

    // Determine the area to apply the adjustment.
    // Use the viewport bounds (the adjustment affects the full layer).
    final width = viewport.width;
    final height = viewport.height;
    if (width <= 0 || height <= 0) return;

    // Apply the adjustment as a saveLayer with a shader-based paint.
    // The shader reads the content from the saveLayer's backing texture
    // and transforms each pixel in-place.
    //
    // We create a snapshot of the current content, apply the shader, and
    // composite the result. This is the standard post-processing pattern.
    final recorder = ui.PictureRecorder();
    final offscreenCanvas = Canvas(recorder, viewport);

    // Render all sibling content that was drawn before this adjustment node
    // into the offscreen buffer. The parent LayerNode handles this via
    // z-order — content below the adjustment was already rendered to `canvas`.
    // We need to capture it.
    //
    // Strategy: use canvas saveLayer + drawRect with the shader.
    // The adjustment node acts as a color filter over existing content.
    offscreenCanvas.drawPaint(Paint()..color = const ui.Color(0x00000000));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width.ceil(), height.ceil());
    picture.dispose();

    final paint = adjustmentShaderService.createPaint(
      node.adjustmentStack,
      image,
      width,
      height,
    );

    if (paint != null) {
      // Draw the shader-transformed content
      canvas.save();
      canvas.translate(viewport.left, viewport.top);
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height), paint);
      canvas.restore();
    }

    image.dispose();
  }

  // ---------------------------------------------------------------------------
  // Shader Node rendering
  // ---------------------------------------------------------------------------

  /// Render a shader node with preset-aware procedural fallback.
  ///
  /// When runtime [FragmentProgram] compilation is available, this will
  /// load and bind the SPIR-V shader. Until then, each [ShaderPreset]
  /// gets a recognizable procedural gradient so the node is visually
  /// distinguishable in the scene graph (rather than a flat purple rect).
  void _renderShaderNode(Canvas canvas, ShaderNode node) {
    if (!node.effect.isEnabled) return;

    final rect = node.localBounds;
    if (rect.isEmpty) return;

    final alpha = (node.effect.opacity * 255).round();

    // Map each preset to a distinctive gradient so designers see the intent.
    final List<Color> gradientColors;
    switch (node.effect.preset) {
      case ShaderPreset.noise:
        gradientColors = [
          Color.fromARGB(alpha, 80, 80, 80),
          Color.fromARGB(alpha, 200, 200, 200),
        ];
      case ShaderPreset.voronoi:
        gradientColors = [
          Color.fromARGB(alpha, 30, 120, 180),
          Color.fromARGB(alpha, 180, 230, 255),
        ];
      case ShaderPreset.chromaticAberration:
        gradientColors = [
          Color.fromARGB(alpha, 255, 80, 80),
          Color.fromARGB(alpha, 80, 80, 255),
        ];
      case ShaderPreset.glitch:
        gradientColors = [
          Color.fromARGB(alpha, 0, 255, 100),
          Color.fromARGB(alpha, 255, 0, 200),
        ];
      case ShaderPreset.gradientMap:
        gradientColors = [
          Color.fromARGB(alpha, 255, 200, 50),
          Color.fromARGB(alpha, 200, 50, 100),
        ];
      case ShaderPreset.pixelate:
        gradientColors = [
          Color.fromARGB(alpha, 100, 200, 100),
          Color.fromARGB(alpha, 50, 100, 50),
        ];
      case ShaderPreset.vignette:
        gradientColors = [
          Color.fromARGB(alpha, 0, 0, 0),
          Color.fromARGB(alpha, 80, 80, 80),
        ];
      case ShaderPreset.custom:
        gradientColors = [
          Color.fromARGB(alpha, 128, 128, 255),
          Color.fromARGB(alpha, 200, 100, 255),
        ];
    }

    final paint =
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topLeft,
            rect.bottomRight,
            gradientColors,
          )
          ..blendMode = node.effect.blendMode;

    canvas.drawRect(rect, paint);
  }

  // ---------------------------------------------------------------------------
  // Advanced Mask rendering
  // ---------------------------------------------------------------------------

  /// Render an advanced mask node with its compositing.
  ///
  /// The mask node contains children (mask source) and applies
  /// its mask type as a compositing blend mode.
  void _renderAdvancedMask(
    Canvas canvas,
    AdvancedMaskNode node,
    Rect viewport,
  ) {
    if (node.children.isEmpty) return;

    final bounds = node.localBounds;
    if (bounds.isEmpty) return;

    // The first child is the mask source, remaining are masked content.
    final maskChild = node.children.first;
    final contentChildren = node.children.skip(1);

    // Determine blend mode from mask type.
    BlendMode maskBlend;
    switch (node.maskType) {
      case MaskType.alpha:
      case MaskType.luminance:
      case MaskType.silhouette:
        maskBlend = BlendMode.dstIn;
      case MaskType.intersection:
        maskBlend = BlendMode.srcIn;
      case MaskType.exclusion:
        maskBlend = BlendMode.dstOut;
      case MaskType.invertedLuminance:
        maskBlend = BlendMode.dstOut;
    }

    // Draw content first, then apply mask.
    canvas.saveLayer(null, Paint());
    for (final child in contentChildren) {
      renderNode(canvas, child, viewport);
    }

    // Apply mask with compositing blend.
    canvas.saveLayer(null, Paint()..blendMode = maskBlend);
    renderNode(canvas, maskChild, viewport);
    canvas.restore(); // mask layer
    canvas.restore(); // content layer
  }

  // ---------------------------------------------------------------------------
  // Frame Node rendering
  // ---------------------------------------------------------------------------

  /// Render a frame (auto-layout container) with fill, border, clip, and children.
  void _renderFrame(Canvas canvas, FrameNode node, Rect viewport) {
    // Resolve layout if dirty before rendering.
    if (node.needsLayout) {
      LayoutEngine.resolveFrame(node);
    }

    final bounds = node.localBounds;

    // Draw fill background.
    if (node.fillColor != null) {
      final fillPaint = Paint()..color = node.fillColor!;
      if (node.borderRadius > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(bounds, Radius.circular(node.borderRadius)),
          fillPaint,
        );
      } else {
        canvas.drawRect(bounds, fillPaint);
      }
    }

    // Clip children to frame bounds if enabled.
    if (node.overflow == OverflowBehavior.hidden) {
      canvas.save();
      if (node.borderRadius > 0) {
        canvas.clipRRect(
          RRect.fromRectAndRadius(bounds, Radius.circular(node.borderRadius)),
        );
      } else {
        canvas.clipRect(bounds);
      }
    }

    // Render children.
    _renderChildren(canvas, node, viewport);

    // Pop clip.
    if (node.overflow == OverflowBehavior.hidden) {
      canvas.restore();
    }

    // Draw stroke/border.
    if (node.strokeColor != null && node.strokeWidth > 0) {
      final strokePaint =
          Paint()
            ..color = node.strokeColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = node.strokeWidth;
      if (node.borderRadius > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(bounds, Radius.circular(node.borderRadius)),
          strokePaint,
        );
      } else {
        canvas.drawRect(bounds, strokePaint);
      }
    }
  }

  /// Render a section (named canvas area) with background, label, border,
  /// optional grid, and children.
  void _renderSection(Canvas canvas, SectionNode node, Rect viewport) {
    final bounds = node.localBounds;

    // All sizes are FIXED world-space, proportional to the section.
    // NO zoom-adaptive invScale — avoids stale values baked into tile cache.
    final sectionScale = (bounds.width / 400.0).clamp(0.3, 2.0);

    // ── 1. Drop shadow for depth (paper-on-desk effect) ──
    final cr = node.cornerRadius;
    final shadowShift = 3.0 * sectionScale;
    final shadowRect = bounds.shift(Offset(shadowShift, shadowShift));
    final shadowPaint =
        Paint()
          ..color = const Color(0x28000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8.0 * sectionScale);
    if (cr > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(shadowRect, Radius.circular(cr)),
        shadowPaint,
      );
    } else {
      canvas.drawRect(shadowRect, shadowPaint);
    }

    // ── 2. Background fill ──
    if (node.backgroundColor != null) {
      final fillPaint = Paint()..color = node.backgroundColor!;
      if (cr > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(bounds, Radius.circular(cr)),
          fillPaint,
        );
      } else {
        canvas.drawRect(bounds, fillPaint);
      }
    }

    // ── 3. Internal grid ──
    if (node.showGrid && node.gridSpacing > 0) {
      if (node.gridType == 'ruled') {
        // 📓 RULED: Horizontal lines only + red left margin (notebook style)
        final linePaint =
            Paint()
              ..color = const Color(0x22448AFF) // Subtle blue
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.5;
        for (
          double y = node.gridSpacing;
          y < bounds.height;
          y += node.gridSpacing
        ) {
          canvas.drawLine(Offset(0, y), Offset(bounds.width, y), linePaint);
        }
        // Red left margin line
        final marginPaint =
            Paint()
              ..color = const Color(0x44FF5252) // Subtle red
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0;
        final marginX = node.gridSpacing * 2; // 2 grid widths from left
        canvas.drawLine(
          Offset(marginX, 0),
          Offset(marginX, bounds.height),
          marginPaint,
        );
      } else if (node.gridType == 'dotted') {
        // 🔵 DOTTED: Dot grid (bullet journal style)
        final dotPaint =
            Paint()
              ..color = const Color(0x1A000000)
              ..style = PaintingStyle.fill;
        final dotRadius = 1.0;
        for (
          double y = node.gridSpacing;
          y < bounds.height;
          y += node.gridSpacing
        ) {
          for (
            double x = node.gridSpacing;
            x < bounds.width;
            x += node.gridSpacing
          ) {
            canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
          }
        }
      } else {
        // ▦ GRID: Classic square grid
        final gridPaint =
            Paint()
              ..color = const Color(0x1A000000)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.5;

        for (
          double x = node.gridSpacing;
          x < bounds.width;
          x += node.gridSpacing
        ) {
          canvas.drawLine(Offset(x, 0), Offset(x, bounds.height), gridPaint);
        }
        for (
          double y = node.gridSpacing;
          y < bounds.height;
          y += node.gridSpacing
        ) {
          canvas.drawLine(Offset(0, y), Offset(bounds.width, y), gridPaint);
        }
      }
    }

    // ── 3b. Subdivision dividers (notebook-style) ──
    if (node.subdivisionRows > 1 || node.subdivisionColumns > 1) {
      final divPaint =
          Paint()
            ..color = node.subdivisionColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 * sectionScale;

      // Horizontal dividers
      if (node.subdivisionRows > 1) {
        final cellH = bounds.height / node.subdivisionRows;
        for (int r = 1; r < node.subdivisionRows; r++) {
          final y = cellH * r;
          _drawDashedLine(
            canvas,
            Offset(0, y),
            Offset(bounds.width, y),
            divPaint,
            8.0 * sectionScale,
            4.0 * sectionScale,
          );
        }
      }

      // Vertical dividers
      if (node.subdivisionColumns > 1) {
        final cellW = bounds.width / node.subdivisionColumns;
        for (int c = 1; c < node.subdivisionColumns; c++) {
          final x = cellW * c;
          _drawDashedLine(
            canvas,
            Offset(x, 0),
            Offset(x, bounds.height),
            divPaint,
            8.0 * sectionScale,
            4.0 * sectionScale,
          );
        }
      }
    }

    // ── 4. Clip children ──
    if (node.clipContent) {
      canvas.save();
      if (cr > 0) {
        canvas.clipRRect(RRect.fromRectAndRadius(bounds, Radius.circular(cr)));
      } else {
        canvas.clipRect(bounds);
      }
    }

    // Render children.
    _renderChildren(canvas, node, viewport);

    if (node.clipContent) {
      canvas.restore();
    }

    // ── 5. Border ──
    if (node.borderWidth > 0) {
      final borderPaint =
          Paint()
            ..color = node.borderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = node.borderWidth;
      if (cr > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(bounds, Radius.circular(cr)),
          borderPaint,
        );
      } else {
        canvas.drawRect(bounds, borderPaint);
      }
    }

    // ── 5b. Subdivision cell labels (A1, B2, etc.) ──
    if (node.subdivisionRows > 1 || node.subdivisionColumns > 1) {
      final cellW =
          bounds.width /
          (node.subdivisionColumns < 1 ? 1 : node.subdivisionColumns);
      final cellH =
          bounds.height / (node.subdivisionRows < 1 ? 1 : node.subdivisionRows);
      final cellScale = (cellW / 100.0).clamp(0.3, 2.0);
      final cellFontSize = 10.0 * cellScale;
      final cellLabelColor = node.subdivisionColor.withValues(alpha: 0.6);

      for (int r = 0; r < node.subdivisionRows; r++) {
        for (int c = 0; c < node.subdivisionColumns; c++) {
          // Generate label: A1, A2, B1, B2, ...
          final rowLabel = String.fromCharCode(65 + r); // A, B, C, ...
          final colLabel = '${c + 1}'; // 1, 2, 3, ...
          final cellLabel = '$rowLabel$colLabel';

          final tp = TextPainter(
            text: TextSpan(
              text: cellLabel,
              style: TextStyle(
                color: cellLabelColor,
                fontSize: cellFontSize,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          tp.paint(
            canvas,
            Offset(c * cellW + 4 * cellScale, r * cellH + 2 * cellScale),
          );
        }
      }
    }

    // ── 6. Fixed world-space label badge ──
    // Labels use FIXED world sizes proportional to the section, NOT zoom-adaptive.
    // This ensures: (a) labels scale naturally with zoom (like Figma/Sketch),
    // (b) labels don't overflow at extreme dezoom (no invScale explosion).
    final labelScale = (bounds.width / 400.0).clamp(0.3, 2.0);
    final fontSize = 12.0 * labelScale;
    final dimsFontSize = 10.0 * labelScale;
    final labelPadH = 8.0 * labelScale;
    final labelPadV = 4.0 * labelScale;
    final iconSize = 14.0 * labelScale;
    final labelGap = 4.0 * labelScale;
    final badgeRadius = 6.0 * labelScale;
    final labelY = -(28.0 * labelScale) + 2 * labelScale;

    // Main label text
    final namePainter = TextPainter(
      text: TextSpan(
        text: node.sectionName,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: bounds.width * 0.5);

    // Dimensions badge
    final dimsText =
        '${node.sectionSize.width.round()} × ${node.sectionSize.height.round()}';
    final dimsPainter = TextPainter(
      text: TextSpan(
        text: dimsText,
        style: TextStyle(
          color: const Color(0x99FFFFFF),
          fontSize: dimsFontSize,
          fontWeight: FontWeight.w400,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final rawLabelW =
        iconSize +
        labelGap +
        namePainter.width +
        labelGap * 2 +
        dimsPainter.width +
        labelPadH * 2;
    // Clamp label width to section width so nearby labels don't overlap.
    final totalLabelW = rawLabelW.clamp(0.0, bounds.width);
    final labelH = namePainter.height + labelPadV * 2;

    // Badge background
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, labelY, totalLabelW, labelH),
      Radius.circular(badgeRadius),
    );
    canvas.drawRRect(labelRect, Paint()..color = const Color(0xDD1E1E2E));

    // Icon (section dashboard icon approximation — draw a small grid)
    final iconX = labelPadH;
    final iconY = labelY + (labelH - iconSize) / 2;
    _drawSectionIcon(canvas, Offset(iconX, iconY), iconSize, labelScale);

    // Clip to badge area so text doesn't overflow
    canvas.save();
    canvas.clipRRect(labelRect);

    // Name text
    namePainter.paint(
      canvas,
      Offset(iconX + iconSize + labelGap, labelY + labelPadV),
    );

    // Separator dot
    final dotX = iconX + iconSize + labelGap + namePainter.width + labelGap;
    final dotY = labelY + labelH / 2;
    canvas.drawCircle(
      Offset(dotX, dotY),
      1.5 * labelScale,
      Paint()..color = const Color(0x66FFFFFF),
    );

    // Dimensions text
    dimsPainter.paint(
      canvas,
      Offset(
        dotX + labelGap,
        labelY + labelPadV + (namePainter.height - dimsPainter.height) / 2,
      ),
    );

    canvas.restore();

    // ── 7. Corner resize handles (subtle dots) ──
    final handleRadius = 3.0 * sectionScale;
    final handlePaint = Paint()..color = const Color(0xAA2196F3);
    final handleStroke =
        Paint()
          ..color = const Color(0x44FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 * sectionScale;
    for (final corner in [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ]) {
      canvas.drawCircle(corner, handleRadius, handlePaint);
      canvas.drawCircle(corner, handleRadius, handleStroke);
    }
  }

  /// Draw a small section icon (2×2 grid squares).
  void _drawSectionIcon(
    Canvas canvas,
    Offset topLeft,
    double size,
    double invScale,
  ) {
    final paint =
        Paint()
          ..color = const Color(0xFF64B5F6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 * invScale
          ..strokeCap = StrokeCap.round;

    final half = size / 2;
    final gap = 1.5 * invScale;
    final r = 1.5 * invScale;

    // Top-left rect
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(topLeft.dx, topLeft.dy, half - gap, half - gap),
        Radius.circular(r),
      ),
      paint,
    );
    // Top-right rect
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          topLeft.dx + half + gap,
          topLeft.dy,
          half - gap,
          half - gap,
        ),
        Radius.circular(r),
      ),
      paint,
    );
    // Bottom-left rect
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          topLeft.dx,
          topLeft.dy + half + gap,
          half - gap,
          half - gap,
        ),
        Radius.circular(r),
      ),
      paint,
    );
    // Bottom-right rect
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          topLeft.dx + half + gap,
          topLeft.dy + half + gap,
          half - gap,
          half - gap,
        ),
        Radius.circular(r),
      ),
      paint,
    );
  }

  /// Draw a dashed line between two points.
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

  // ---------------------------------------------------------------------------
  // PDF Node rendering
  // ---------------------------------------------------------------------------

  /// Render a PDF document (group container) by rendering all page children.
  void _renderPdfDocument(Canvas canvas, PdfDocumentNode node, Rect viewport) {
    _renderChildren(canvas, node, viewport);
  }

  /// Render a PDF preview card — single-page thumbnail with title badge.
  void _renderPdfPreviewCard(Canvas canvas, PdfPreviewCardNode node) {
    final bounds = node.localBounds;
    final cardRadius = 12.0;

    // 1. Drop shadow
    final shadowPaint = Paint()
      ..color = const Color(0x20000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.shift(const Offset(2, 3)),
        Radius.circular(cardRadius),
      ),
      shadowPaint,
    );

    // 2. White card background
    final cardPaint = Paint()..color = const Color(0xFFFFFFFF);
    final cardRRect = RRect.fromRectAndRadius(
      bounds,
      Radius.circular(cardRadius),
    );
    canvas.drawRRect(cardRRect, cardPaint);

    // 3. Thumbnail image area (top portion, minus badge)
    final badgeHeight = 40.0;
    final imageRect = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.width,
      bounds.height - badgeHeight,
    );

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndCorners(
      imageRect,
      topLeft: Radius.circular(cardRadius),
      topRight: Radius.circular(cardRadius),
    ));

    if (node.thumbnailImage != null) {
      final img = node.thumbnailImage!;
      try {
        final srcRect = Rect.fromLTWH(
          0, 0, img.width.toDouble(), img.height.toDouble(),
        );
        canvas.drawImageRect(img, srcRect, imageRect, Paint());
      } catch (_) {
        canvas.drawRect(imageRect, Paint()..color = const Color(0xFFF5F5F5));
      }
    } else {
      // Placeholder
      canvas.drawRect(imageRect, Paint()..color = const Color(0xFFF5F5F5));
      // PDF icon (simple rectangle with fold)
      final iconSize = 40.0;
      final iconRect = Rect.fromCenter(
        center: imageRect.center,
        width: iconSize * 0.8,
        height: iconSize,
      );
      canvas.drawRect(
        iconRect,
        Paint()
          ..color = const Color(0xFFBBBBBB)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();

    // 4. Bottom badge (dark background with name + page count)
    final badgeRect = Rect.fromLTWH(
      bounds.left,
      bounds.bottom - badgeHeight,
      bounds.width,
      badgeHeight,
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndCorners(
      badgeRect,
      bottomLeft: Radius.circular(cardRadius),
      bottomRight: Radius.circular(cardRadius),
    ));
    canvas.drawRect(badgeRect, Paint()..color = const Color(0xE61E1E2E));

    // PDF name
    final displayName = node.name.isNotEmpty
        ? node.name
        : 'PDF (${node.documentModel.totalPages} pages)';
    final namePainter = TextPainter(
      text: TextSpan(
        text: displayName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: bounds.width - 16);
    namePainter.paint(
      canvas,
      Offset(badgeRect.left + 8, badgeRect.top + 5),
    );

    // Page count badge
    final countText = '${node.documentModel.totalPages} pages';
    final countPainter = TextPainter(
      text: TextSpan(
        text: countText,
        style: const TextStyle(
          color: Color(0x99FFFFFF),
          fontSize: 10,
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    countPainter.paint(
      canvas,
      Offset(badgeRect.left + 8, badgeRect.top + 22),
    );

    canvas.restore();

    // 5. Subtle border
    final borderPaint = Paint()
      ..color = const Color(0x22000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(cardRRect, borderPaint);
  }

  /// Render a single PDF page from its raster cache or a placeholder.
  ///
  /// Uses the pre-decoded [PdfPageNode.cachedImage] if available.
  /// When the cache is empty (page not yet decoded), draws a light-gray
  /// rectangle with the page number as a placeholder. The actual async
  /// decode is triggered externally by the rendering pipeline.
  void _renderPdfPage(Canvas canvas, PdfPageNode node) {
    final bounds = node.pageModel.originalSize;
    final rect = Rect.fromLTWH(0, 0, bounds.width, bounds.height);

    // 🔄 Apply page rotation around center (matches DrawingPainter)
    final rotation = node.pageModel.rotation;
    if (rotation != 0) {
      canvas.save();
      final cx = rect.center.dx;
      final cy = rect.center.dy;
      canvas.translate(cx, cy);
      canvas.rotate(rotation);
      canvas.translate(-cx, -cy);
    }

    if (node.cachedImage != null) {
      // Draw the cached raster tile, scaled to fill the page bounds.
      final srcRect = Rect.fromLTWH(
        0,
        0,
        node.cachedImage!.width.toDouble(),
        node.cachedImage!.height.toDouble(),
      );
      canvas.drawImageRect(node.cachedImage!, srcRect, rect, Paint());
    } else {
      // Placeholder: light gray fill with page number.
      canvas.drawRect(rect, Paint()..color = const Color(0xFFF0F0F0));

      // Page number text
      final pageNum = '${node.pageModel.pageIndex + 1}';
      final tp = TextPainter(
        text: TextSpan(
          text: pageNum,
          style: const TextStyle(
            color: Color(0xFFAAAAAA),
            fontSize: 32,
            fontWeight: FontWeight.w300,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset((rect.width - tp.width) / 2, (rect.height - tp.height) / 2),
      );
    }

    // Close rotation transform
    if (rotation != 0) {
      canvas.restore();
    }
  }

  // ---------------------------------------------------------------------------
  // Boolean Group rendering
  // ---------------------------------------------------------------------------

  /// Render a [BooleanGroupNode] by painting its computed boolean path.
  void _renderBooleanGroup(Canvas canvas, BooleanGroupNode node) {
    final flutterPath = node.computedPath.toFlutterPath();

    // Draw fill.
    if (node.fillColor != null) {
      final paint =
          Paint()
            ..color = node.fillColor!
            ..style = PaintingStyle.fill;
      canvas.drawPath(flutterPath, paint);
    }

    // Draw stroke.
    if (node.strokeColor != null) {
      final paint =
          Paint()
            ..color = node.strokeColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = node.strokeWidth
            ..strokeCap = node.strokeCap
            ..strokeJoin = node.strokeJoin;
      canvas.drawPath(flutterPath, paint);
    }
  }

  /// Render a vector network node via VectorNetworkRenderer.
  void _renderVectorNetwork(Canvas canvas, VectorNetworkNode node) {
    VectorNetworkRenderer.drawVectorNetworkNode(canvas, node);
  }

  /// Render a LaTeX mathematical expression via LatexRenderer.
  void _renderLatex(Canvas canvas, LatexNode node) {
    LatexRenderer.drawLatexNode(canvas, node);
  }

  /// Render a tabular (spreadsheet) node via TabularRenderer.
  void _renderTabular(Canvas canvas, TabularNode node) {
    TabularRenderer.drawTabularNode(
      canvas,
      node,
      visibleRect: _visitor._viewport,
    );
  }

  // ---------------------------------------------------------------------------
  // Function Graph rendering
  // ---------------------------------------------------------------------------

  /// Render a function graph node via FunctionGraphRenderer.
  void _renderFunctionGraph(Canvas canvas, FunctionGraphNode node) {
    FunctionGraphRenderer.drawFunctionGraphNode(canvas, node);
  }

  // ---------------------------------------------------------------------------
  // Internal Visitor
  // ---------------------------------------------------------------------------
}

// ---------------------------------------------------------------------------
// Internal Visitor
// ---------------------------------------------------------------------------

/// Internal visitor that delegates type-safe dispatch back to [SceneGraphRenderer].
///
/// Converts O(n) type checking into O(1) virtual method dispatch.
class _RendererVisitor implements NodeVisitor<void> {
  final SceneGraphRenderer renderer;

  late Canvas _canvas;
  late Rect _viewport;

  _RendererVisitor(this.renderer);

  void setContext(Canvas canvas, Rect viewport) {
    _canvas = canvas;
    _viewport = viewport;
  }

  @override
  void visitGroup(GroupNode node) =>
      renderer._renderChildren(_canvas, node, _viewport);

  @override
  void visitLayer(LayerNode node) =>
      renderer._renderChildren(_canvas, node, _viewport);

  @override
  void visitShape(ShapeNode node) => renderer._renderShape(_canvas, node);

  @override
  void visitStroke(StrokeNode node) => renderer._renderStroke(_canvas, node);

  @override
  void visitText(TextNode node) => renderer._renderText(_canvas, node);

  @override
  void visitImage(ImageNode node) => renderer._renderImage(_canvas, node);

  @override
  void visitClipGroup(ClipGroupNode node) =>
      renderer._renderClipGroup(_canvas, node, _viewport);

  @override
  void visitPath(PathNode node) => renderer._renderPath(_canvas, node);

  @override
  void visitRichText(RichTextNode node) =>
      renderer._renderRichText(_canvas, node);

  @override
  void visitSymbolInstance(SymbolInstanceNode node) =>
      renderer._renderSymbolInstance(_canvas, node, _viewport);

  @override
  void visitFrame(FrameNode node) =>
      renderer._renderFrame(_canvas, node, _viewport);

  @override
  void visitAdvancedMask(AdvancedMaskNode node) =>
      renderer._renderAdvancedMask(_canvas, node, _viewport);

  @override
  void visitBooleanGroup(BooleanGroupNode node) =>
      renderer._renderBooleanGroup(_canvas, node);

  @override
  void visitShader(ShaderNode node) =>
      renderer._renderShaderNode(_canvas, node);

  @override
  void visitPdfPage(PdfPageNode node) {
    if (renderer.skipPdfNodes) return;
    renderer._renderPdfPage(_canvas, node);
  }

  @override
  void visitPdfDocument(PdfDocumentNode node) {
    if (renderer.skipPdfNodes) return;
    renderer._renderPdfDocument(_canvas, node, _viewport);
  }

  @override
  void visitPdfPreviewCard(PdfPreviewCardNode node) {
    renderer._renderPdfPreviewCard(_canvas, node);
  }

  @override
  void visitVectorNetwork(VectorNetworkNode node) =>
      renderer._renderVectorNetwork(_canvas, node);

  @override
  void visitLatex(LatexNode node) => renderer._renderLatex(_canvas, node);

  @override
  void visitTabular(TabularNode node) => renderer._renderTabular(_canvas, node);

  @override
  void visitMaterialZone(MaterialZoneNode node) =>
      renderer._renderChildren(_canvas, node, _viewport);

  @override
  void visitSection(SectionNode node) =>
      renderer._renderSection(_canvas, node, _viewport);

  @override
  void visitAdjustmentLayer(AdjustmentLayerNode node) {
    renderer._renderAdjustmentLayer(_canvas, node, _viewport);
  }

  @override
  void visitFunctionGraph(FunctionGraphNode node) =>
      renderer._renderFunctionGraph(_canvas, node);
}

// ---------------------------------------------------------------------------
// Zero-allocation interceptor chain runner
// ---------------------------------------------------------------------------

/// Walks the interceptor chain using an index instead of closures.
///
/// A single instance is reused across all nodes in a frame, eliminating
/// the previous O(interceptors × nodes) closure allocations per frame.
class _InterceptorChainRunner {
  final SceneGraphRenderer _renderer;

  /// Current position in the interceptor list.
  int _index = 0;

  /// The interceptors for the current run (set per call to [run]).
  late List<RenderInterceptor> _interceptors;

  _InterceptorChainRunner(this._renderer);

  /// Run the full interceptor chain for a single node.
  void run(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
    List<RenderInterceptor> interceptors,
  ) {
    _interceptors = interceptors;
    _index = 0;
    _next(canvas, node, viewport);
  }

  /// Advance to the next interceptor or fall through to direct rendering.
  ///
  /// This method is passed as [RenderNext] to each interceptor's `intercept`.
  /// When the interceptor calls `next(c, n, v)`, it re-enters this method
  /// with `_index` already advanced to the next slot — zero closures.
  void _next(Canvas canvas, CanvasNode node, Rect viewport) {
    if (_index >= _interceptors.length) {
      // End of chain — render the node directly.
      _renderer._renderNodeDirect(canvas, node, viewport);
      return;
    }

    final interceptor = _interceptors[_index];
    _index++;
    try {
      interceptor.intercept(canvas, node, viewport, _next);
    } catch (e, stack) {
      // Never let a single interceptor crash the frame.
      if (EngineScope.hasScope) {
        EngineScope.current.errorRecovery.reportError(
          EngineError(
            original: e,
            stack: stack,
            source: 'RenderInterceptor:${interceptor.runtimeType}',
            domain: ErrorDomain.rendering,
            severity: ErrorSeverity.transient,
          ),
        );
      } else {}
      // Skip this interceptor, continue with next in chain.
      _next(canvas, node, viewport);
    }
  }
}

/// Pairs a cached [TextPainter] with a content hash for invalidation.
class _CachedTextPainter {
  final TextPainter painter;
  final int contentHash;
  const _CachedTextPainter(this.painter, this.contentHash);
}
