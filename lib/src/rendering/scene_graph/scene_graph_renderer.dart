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
import '../../core/nodes/vector_network_node.dart';
import '../../core/effects/shader_effect.dart';
import '../../core/nodes/latex_node.dart';
import '../../core/effects/paint_stack.dart';
import '../../core/models/shape_type.dart';
import '../../core/scene_graph/scene_graph.dart';
import '../../core/scene_graph/invalidation_graph.dart';
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
import './latex_renderer.dart';

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

      // Clear dirty flags after rendering.
      if (_invalidationGraph != null) {
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
    for (final child in group.children) {
      renderNode(canvas, child, viewport);
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

    // Adaptive LOD: skip sub-pixel strokes at low zoom.
    if (_currentScale < 0.5) {
      final bounds = stroke.bounds;
      final screenSize = math.max(
        bounds.width * _currentScale,
        bounds.height * _currentScale,
      );
      if (screenSize < 2.0) return;
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
      );
    }
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

  // ---------------------------------------------------------------------------
  // PDF Node rendering
  // ---------------------------------------------------------------------------

  /// Render a PDF document (group container) by rendering all page children.
  void _renderPdfDocument(Canvas canvas, PdfDocumentNode node, Rect viewport) {
    _renderChildren(canvas, node, viewport);
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
  void visitPdfPage(PdfPageNode node) => renderer._renderPdfPage(_canvas, node);

  @override
  void visitPdfDocument(PdfDocumentNode node) =>
      renderer._renderPdfDocument(_canvas, node, _viewport);

  @override
  void visitVectorNetwork(VectorNetworkNode node) =>
      renderer._renderVectorNetwork(_canvas, node);

  @override
  void visitLatex(LatexNode node) => renderer._renderLatex(_canvas, node);
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
      } else {
        debugPrint('[RenderInterceptor] ${interceptor.runtimeType} error: $e');
      }
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
