import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../canvas/infinite_canvas_controller.dart';
import '../canvas/infinite_canvas_gesture_detector.dart';
import '../layers/layer_controller.dart';
import '../tools/unified_tool_controller.dart';
import '../drawing/input/drawing_input_handler.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../drawing/models/pro_brush_settings.dart';
import '../drawing/brushes/brushes.dart';
import '../rendering/canvas/current_stroke_painter.dart';
import '../core/models/shape_type.dart';
import '../tools/eraser/eraser_tool.dart';
import '../utils/uid.dart';

// =============================================================================
// MULTIVIEW PANEL — Full-featured canvas view with BrushEngine rendering
// =============================================================================

/// Release cached ui.Picture GPU resources for multiview panels.
/// Called from the orchestrator on dispose/layout change.
void invalidateMultiviewPanelCache() => _BrushEngineCanvasPainter.invalidateCache();

/// A single canvas panel within the multiview grid.
///
/// Architecture:
/// - **BrushEngine rendering** for completed strokes (pressure, texture, brush effects)
/// - **CurrentStrokePainter** for live preview during drawing
/// - **Batch updates** via [onDrawBatchUpdate] for 120Hz performance
/// - **Shape drawing** with live preview (rectangle, circle, triangle, line)
/// - **Zoom indicator** overlay showing current scale
class MultiviewPanel extends StatefulWidget {
  /// Shared layer data (single instance across all panels).
  final LayerController layerController;

  /// Shared tool state (single instance across all panels).
  final UnifiedToolController toolController;

  /// Per-panel viewport controller (independent per panel).
  final InfiniteCanvasController canvasController;

  /// Panel index within the multiview grid.
  final int panelIndex;

  /// Whether this panel currently receives drawing input.
  final bool isActive;

  /// Callback when user taps this panel to activate it.
  final VoidCallback onActivate;

  /// Canvas background color.
  final Color backgroundColor;

  /// Cross-panel cursor position (canvas coords from active panel).
  final ValueNotifier<Offset?>? cursorPosition;

  /// Callback when cursor moves during drawing.
  final ValueChanged<Offset?>? onCursorMoved;

  /// Callback for double-tap (fit to content).
  final VoidCallback? onDoubleTap;

  /// Callback for long-press (context menu).
  final void Function(Offset globalPosition)? onLongPress;

  const MultiviewPanel({
    super.key,
    required this.layerController,
    required this.toolController,
    required this.canvasController,
    required this.panelIndex,
    required this.isActive,
    required this.onActivate,
    this.backgroundColor = Colors.white,
    this.cursorPosition,
    this.onCursorMoved,
    this.onDoubleTap,
    this.onLongPress,
  });

  @override
  State<MultiviewPanel> createState() => _MultiviewPanelState();
}

class _MultiviewPanelState extends State<MultiviewPanel>
    with TickerProviderStateMixin {
  // 🚀 P99 FIX: Static const border avoids per-build allocation
  static const _kInactiveBorder = Border.fromBorderSide(
    BorderSide(color: Color(0x4D79747E), width: 0.5), // outlineVariant ~alpha 0.3
  );

  // ── Drawing input handler ──────────────────────────────────────────────
  late final DrawingInputHandler _drawingHandler;

  // ── Live stroke preview ────────────────────────────────────────────────
  final ValueNotifier<List<ProDrawingPoint>> _strokeNotifier =
      ValueNotifier<List<ProDrawingPoint>>([]);

  // ── Shape drawing state ────────────────────────────────────────────────
  final ValueNotifier<GeometricShape?> _currentShapeNotifier =
      ValueNotifier<GeometricShape?>(null);

  // ── Zoom overlay (ValueNotifier — avoids setState on every pan frame) ──
  final ValueNotifier<bool> _zoomIndicatorVisible = ValueNotifier<bool>(false);

  // ── Eraser ─────────────────────────────────────────────────────────────
  late final EraserTool _eraserTool;

  // ── Zoom indicator debounce timer ──────────────────────────────────────────
  Timer? _zoomHideTimer;

  // 🚀 P99 FIX: Throttle cursor broadcasts to ~30fps (33ms)
  int _lastCursorBroadcastUs = 0;
  static const int _cursorThrottleUs = 33000; // 33ms = ~30fps

  // ── OPT #1: Cached Listenable.merge (avoids re-allocation per frame) ──
  late final Listenable _canvasRepaintListenable;

  @override
  void initState() {
    super.initState();
    _canvasRepaintListenable = Listenable.merge([
      widget.canvasController,
      widget.layerController,
    ]);
    widget.canvasController.attachTicker(this);
    widget.canvasController.addListener(_onViewportChanged);

    _eraserTool = EraserTool(layerController: widget.layerController);

    _drawingHandler = DrawingInputHandler(
      onPointsUpdated: (points) {
        // OPT: List.unmodifiable wraps without copying (lighter at 120Hz)
        _strokeNotifier.value = List.unmodifiable(points);
      },
      onStrokeCompleted: (finalPoints) {
        // 🎯 SNAP FIX: Trim finalPoints to the count actually rendered on-screen.
        // Without this, PointerMoveEvent + PointerUpEvent arriving in the same
        // event batch add points never visible in the live preview — causing the
        // committed stroke to extend/shift beyond its live position.
        // (Matching _drawing_end.dart behavior)
        var trimmedPoints = finalPoints;
        final renderedCount = CurrentStrokePainter.lastRenderedCount;
        if (renderedCount > 2 && renderedCount < finalPoints.length) {
          trimmedPoints = List.unmodifiable(
            finalPoints.sublist(0, renderedCount),
          );
        }

        if (trimmedPoints.length >= 2) {
          final stroke = ProStroke(
            id: generateUid(),
            points: trimmedPoints,
            color: widget.toolController.color,
            baseWidth: widget.toolController.width,
            penType: widget.toolController.penType,
            createdAt: DateTime.now(),
            settings: const ProBrushSettings(),
          );
          widget.layerController.addStroke(stroke);
        }
        _strokeNotifier.value = [];
      },
    );
  }

  @override
  void dispose() {
    _zoomHideTimer?.cancel();
    _zoomIndicatorVisible.dispose();
    widget.canvasController.removeListener(_onViewportChanged);
    _drawingHandler.dispose();
    _strokeNotifier.dispose();
    _currentShapeNotifier.dispose();
    widget.canvasController.detachTicker();
    super.dispose();
  }

  void _onViewportChanged() {
    // 🚀 P99 FIX: Use ValueNotifier — no setState on every pan/zoom frame.
    _zoomHideTimer?.cancel();
    _zoomIndicatorVisible.value = true;
    _zoomHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _zoomIndicatorVisible.value = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTapDown: (_) => widget.onActivate(),
      onDoubleTap: widget.onDoubleTap,
      // Long-press is handled by InfiniteCanvasGestureDetector below
      // (it wins the gesture arena over this outer detector)
      behavior: HitTestBehavior.translucent,
      child: Container(
        decoration: BoxDecoration(
          border: widget.isActive
              ? Border.all(color: cs.primary, width: 2.0)
              : _kInactiveBorder,
        ),
        child: ClipRect(
          child: Stack(
            children: [
              // 🎨 Canvas area with gesture detection
              Positioned.fill(
                child: InfiniteCanvasGestureDetector(
                  controller: widget.canvasController,
                  enableSingleFingerPan:
                      !widget.isActive || widget.toolController.isPanMode,
                  onDrawStart: widget.isActive ? _onDrawStart : null,
                  onDrawUpdate: widget.isActive ? _onDrawUpdate : null,
                  onDrawBatchUpdate:
                      widget.isActive ? _onDrawBatchUpdate : null,
                  onDrawEnd: widget.isActive ? _onDrawEnd : null,
                  onDrawCancel: widget.isActive ? _onDrawCancel : null,
                  // 🎡 Long-press → toolwheel/context menu (must be on inner
                  // detector because it owns the gesture arena)
                  onLongPress: widget.onLongPress != null
                      ? (canvasPos) {
                          // Convert canvas coords to global (screen) coords
                          final renderBox = context.findRenderObject() as RenderBox;
                          final globalPos = renderBox.localToGlobal(
                            widget.canvasController.canvasToScreen(canvasPos),
                          );
                          widget.onLongPress!(globalPos);
                        }
                      : null,
                  child: Stack(
                    children: [
                      // Layer 1: Completed strokes (BrushEngine rendering)
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _BrushEngineCanvasPainter(
                              controller: widget.canvasController,
                              layerController: widget.layerController,
                              backgroundColor: widget.backgroundColor,
                              repaintListenable: _canvasRepaintListenable,
                              panelId: widget.panelIndex,
                            ),
                            isComplex: true,
                            willChange: true,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),

                      // Layer 2: Current stroke (live preview)
                      if (widget.isActive)
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: ListenableBuilder(
                              listenable: widget.toolController,
                              builder: (context, _) {
                                return CustomPaint(
                                  painter: CurrentStrokePainter(
                                    strokeNotifier: _strokeNotifier,
                                    penType: widget.toolController.penType,
                                    color: widget.toolController.color,
                                    width: widget.toolController.width,
                                    settings: const ProBrushSettings(),
                                    controller: widget.canvasController,
                                  ),
                                  child: const SizedBox.expand(),
                                );
                              },
                            ),
                          ),
                        ),

                      // Layer 3: Shape preview (live)
                      if (widget.isActive)
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: ValueListenableBuilder<GeometricShape?>(
                              valueListenable: _currentShapeNotifier,
                              builder: (context, shape, _) {
                                if (shape == null) {
                                  return const SizedBox.shrink();
                                }
                                return CustomPaint(
                                  painter: _ShapePreviewPainter(
                                    shape: shape,
                                    controller: widget.canvasController,
                                  ),
                                  child: const SizedBox.expand(),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // 🎯 Cross-panel cursor (shown on inactive panels)
              // 🚀 P99 FIX: RepaintBoundary isolates crosshair repaints
              // from the panel's canvas layers (fires per drawing point)
              if (!widget.isActive && widget.cursorPosition != null)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<Offset?>(
                        valueListenable: widget.cursorPosition!,
                        builder: (context, pos, _) {
                          if (pos == null) return const SizedBox.shrink();
                          return CustomPaint(
                            painter: _CrosshairPainter(
                              canvasPosition: pos,
                              controller: widget.canvasController,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

              // 🏷️ Panel indicator + tool state (top-left)
              Positioned(
                top: 6,
                left: 6,
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: widget.toolController,
                    builder: (context, _) => _buildPanelBadge(cs),
                  ),
                ),
              ),

              // 🔍 Zoom indicator (bottom-right)
              // 🚀 P99 FIX: ValueListenableBuilder toggles Visibility
              // (Positioned must be direct Stack child)
              Positioned(
                bottom: 8,
                right: 8,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _zoomIndicatorVisible,
                  builder: (context, visible, child) {
                    return Visibility(
                      visible: visible,
                      child: child!,
                    );
                  },
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: 0.8,
                      duration: const Duration(milliseconds: 300),
                      child: ListenableBuilder(
                        listenable: widget.canvasController,
                        builder: (context, _) {
                          final percent =
                              (widget.canvasController.scale * 100).round();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cs.inverseSurface.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$percent%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onInverseSurface,
                                letterSpacing: -0.3,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // PANEL BADGE
  // ============================================================================

  Widget _buildPanelBadge(ColorScheme cs) {
    // OPT #5: Show active tool icon for visual feedback (esp. in wheel mode)
    final toolIcon = widget.toolController.isEraserMode
        ? Icons.auto_fix_high_rounded
        : widget.toolController.isPanMode
        ? Icons.pan_tool_rounded
        : widget.toolController.isLassoMode
        ? Icons.content_cut_rounded
        : widget.toolController.shapeRecognitionEnabled
        ? Icons.hexagon_rounded
        : Icons.edit_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:
            widget.isActive
                ? cs.primary.withValues(alpha: 0.15)
                : cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color:
              widget.isActive
                  ? cs.primary.withValues(alpha: 0.4)
                  : cs.outlineVariant.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            toolIcon,
            size: 10,
            color: widget.isActive ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            'Panel ${widget.panelIndex + 1}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
              color: widget.isActive ? cs.primary : cs.onSurfaceVariant,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // DRAWING HANDLERS
  // ============================================================================

  void _onDrawStart(
    Offset canvasPosition,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    // Eraser mode
    if (widget.toolController.isEraserMode) {
      _eraserTool.beginGesture();
      _eraserTool.eraseAt(canvasPosition);
      return;
    }

    // Shape drawing mode
    final shapeType = widget.toolController.shapeType;
    if (shapeType != ShapeType.freehand) {
      _currentShapeNotifier.value = GeometricShape(
        id: generateUid(),
        type: shapeType,
        startPoint: canvasPosition,
        endPoint: canvasPosition,
        color: widget.toolController.color,
        strokeWidth: widget.toolController.width,
        filled: false,
        createdAt: DateTime.now(),
      );
      return;
    }

    // Freehand drawing
    CurrentStrokePainter.resetForNewStroke();
    _drawingHandler.startStroke(
      position: canvasPosition,
      pressure: pressure,
      tiltX: tiltX,
      tiltY: tiltY,
      orientation: 0.0,
    );
    widget.onCursorMoved?.call(canvasPosition);
  }

  void _onDrawUpdate(
    Offset canvasPosition,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    // Eraser update
    if (widget.toolController.isEraserMode) {
      _eraserTool.eraseAt(canvasPosition);
      return;
    }

    final currentShape = _currentShapeNotifier.value;
    if (currentShape != null) {
      _currentShapeNotifier.value = currentShape.copyWith(
        endPoint: canvasPosition,
      );
      return;
    }

    _drawingHandler.updateStroke(
      position: canvasPosition,
      pressure: pressure,
      tiltX: tiltX,
      tiltY: tiltY,
      orientation: 0.0,
    );
    // 🚀 P99 FIX: Throttle cursor broadcast to ~30fps
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    if (nowUs - _lastCursorBroadcastUs >= _cursorThrottleUs) {
      _lastCursorBroadcastUs = nowUs;
      widget.onCursorMoved?.call(canvasPosition);
    }
  }

  /// 🚀 Batch update for 120Hz performance — processes N points in one frame
  void _onDrawBatchUpdate(
    List<Offset> positions,
    List<double> pressures,
    List<double> tiltsX,
    List<double> tiltsY,
  ) {
    if (_currentShapeNotifier.value != null) {
      // Shape mode — just use last position
      if (positions.isNotEmpty) {
        _currentShapeNotifier.value = _currentShapeNotifier.value!.copyWith(
          endPoint: positions.last,
        );
      }
      return;
    }

    _drawingHandler.addPointsBatch(
      positions: positions,
      pressures: pressures,
      tiltsX: tiltsX,
      tiltsY: tiltsY,
    );
  }

  void _onDrawEnd(Offset canvasPosition) {
    // Eraser end
    if (widget.toolController.isEraserMode) {
      _eraserTool.endGesture();
      return;
    }

    final currentShape = _currentShapeNotifier.value;
    if (currentShape != null) {
      final finalShape = currentShape.copyWith(endPoint: canvasPosition);
      widget.layerController.addShape(finalShape);
      _currentShapeNotifier.value = null;
      return;
    }

    _drawingHandler.endStroke();
    widget.onCursorMoved?.call(null);
  }

  void _onDrawCancel() {
    widget.onCursorMoved?.call(null);
    _currentShapeNotifier.value = null;
    _strokeNotifier.value = [];
    if (_drawingHandler.hasStroke) {
      _drawingHandler.endStroke();
    }
  }
}

// =============================================================================
// BRUSH ENGINE CANVAS PAINTER — High-fidelity rendering with BrushEngine
// =============================================================================

/// Renders completed strokes using [BrushEngine.renderStroke] for full
/// visual fidelity: pressure sensitivity, brush textures, ink simulation.
///
/// 🚀 PICTURE CACHE: On pan/zoom frames where the scene hasn't changed,
/// replay a cached [ui.Picture] via drawPicture (O(1) GPU blit) instead
/// of re-iterating all strokes through BrushEngine.
class _BrushEngineCanvasPainter extends CustomPainter {
  final InfiniteCanvasController controller;
  final LayerController layerController;
  final Color backgroundColor;

  // Pre-allocated paint to avoid per-frame allocation
  late final Paint _bgPaint;

  // OPT #7: Pre-allocated Paint for layer opacity (replaces saveLayer)
  late final Paint _alphaPaint;

  // 🚀 PICTURE CACHE — keyed by scene version
  // Static because CustomPainter instances are recreated on widget rebuild,
  // but the cache should persist across those rebuilds.
  // Map<panelId, _PanelPictureCache> to support multiple panels.
  static final Map<int, _PanelPictureCache> _caches = {};

  /// Force-invalidate cache for all panels (called on undo/redo, stroke delete, etc.)
  static void invalidateCache() {
    for (final c in _caches.values) {
      c.picture?.dispose();
    }
    _caches.clear();
  }

  // Identity key to distinguish panels
  final int _panelId;

  _BrushEngineCanvasPainter({
    required this.controller,
    required this.layerController,
    required this.backgroundColor,
    required Listenable repaintListenable,
    required int panelId,
  }) : _panelId = panelId,
       _bgPaint = (Paint()..color = backgroundColor),
       _alphaPaint = Paint(),
       super(repaint: repaintListenable);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _bgPaint);

    // 2. Viewport transform: translate → rotate → scale
    // Must match InfiniteCanvasController.screenToCanvas() transform order:
    // screenToCanvas undoes: translate → rotate(origin) → scale
    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);

    if (controller.rotation != 0.0) {
      canvas.rotate(controller.rotation);
    }

    canvas.scale(controller.scale);

    // 3. Compute real viewport bounds for stroke culling.
    // When the canvas is rotated, the visible area in canvas space is a
    // rotated rectangle. Transform all 4 screen corners via screenToCanvas
    // and take the axis-aligned bounding box to avoid culling visible strokes.
    final Rect viewportRect;
    final scale = controller.scale;
    if (scale <= 0) {
      viewportRect = const Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6);
    } else if (controller.rotation == 0.0) {
      // Fast path: no rotation — simple formula
      viewportRect = Rect.fromLTWH(
        -controller.offset.dx / scale,
        -controller.offset.dy / scale,
        size.width / scale,
        size.height / scale,
      ).inflate(50);
    } else {
      // Rotation-aware: transform 4 screen corners to canvas space
      // 🚀 P99 FIX: inline min/max avoids 8 temporary List allocations
      final tl = controller.screenToCanvas(Offset.zero);
      final tr = controller.screenToCanvas(Offset(size.width, 0));
      final bl = controller.screenToCanvas(Offset(0, size.height));
      final br = controller.screenToCanvas(Offset(size.width, size.height));
      double minX = tl.dx, maxX = tl.dx, minY = tl.dy, maxY = tl.dy;
      for (final p in [tr, bl, br]) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      viewportRect = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(50);
    }

    // 🚀 PICTURE CACHE: check if we can replay cached picture
    final sceneVersion = layerController.sceneGraph.version;
    final cache = _caches[_panelId];

    if (cache != null &&
        cache.sceneVersion == sceneVersion &&
        cache.picture != null &&
        cache.viewport.contains(viewportRect.topLeft) &&
        cache.viewport.contains(viewportRect.bottomRight)) {
      // Cache HIT — replay O(1) GPU blit
      canvas.drawPicture(cache.picture!);
      canvas.restore();
      return;
    }

    // Cache MISS — render all strokes and record into Picture
    final recorder = ui.PictureRecorder();
    final recCanvas = Canvas(recorder);

    // 4. Render layers with BrushEngine
    // OPT #7: Avoid saveLayer for opacity — apply alpha directly to stroke/shape colors
    for (final layer in layerController.layers) {
      if (!layer.isVisible) continue;

      recCanvas.save();
      final layerAlpha = layer.opacity;

      // 🎨 Strokes — BrushEngine rendering (pressure, texture, brush effects)
      for (final stroke in layer.strokes) {
        if (stroke.points.isEmpty) continue;

        // Viewport culling — skip strokes outside visible area
        // Use inflated viewport for cache (render wider to support panning)
        if (!viewportRect.overlaps(stroke.bounds)) continue;

        // Apply layer opacity directly to stroke color (avoids saveLayer GPU flush)
        final effectiveColor = layerAlpha < 1.0
            ? stroke.color.withValues(alpha: stroke.color.a * layerAlpha)
            : stroke.color;

        BrushEngine.renderStroke(
          recCanvas,
          stroke.points,
          effectiveColor,
          stroke.baseWidth,
          stroke.penType,
          stroke.settings,
          engineVersion: stroke.engineVersion,
        );
      }

      // 📐 Shapes — OPT #8: Use shared helper
      for (final shape in layer.shapes) {
        final effectiveColor = layerAlpha < 1.0
            ? shape.color.withValues(alpha: shape.color.a * layerAlpha)
            : shape.color;
        ShapePaintHelper.paintShape(recCanvas, shape, overrideColor: effectiveColor);
      }

      recCanvas.restore(); // layer save
    }

    // Record and cache the picture
    final picture = recorder.endRecording();

    // Dispose old cache for this panel
    _caches[_panelId]?.picture?.dispose();

    // Cache with inflated viewport so small pans still hit the cache
    _caches[_panelId] = _PanelPictureCache(
      sceneVersion: sceneVersion,
      picture: picture,
      viewport: viewportRect.inflate(200), // extra margin for pan headroom
    );

    // Draw the recorded picture (also paints on current frame)
    canvas.drawPicture(picture);

    canvas.restore(); // viewport transform
  }

  @override
  bool shouldRepaint(covariant _BrushEngineCanvasPainter oldDelegate) =>
      controller != oldDelegate.controller ||
      layerController != oldDelegate.layerController ||
      backgroundColor != oldDelegate.backgroundColor;
}

/// Lightweight cache entry for a panel's rendered picture.
class _PanelPictureCache {
  final int sceneVersion;
  final ui.Picture? picture;
  final Rect viewport;

  const _PanelPictureCache({
    required this.sceneVersion,
    required this.picture,
    required this.viewport,
  });
}

// =============================================================================
// OPT #8: SHARED SHAPE PAINT HELPER — DRY shape rendering
// =============================================================================

class ShapePaintHelper {
  // Pre-allocated, reused across calls (single-threaded UI)
  static final Paint _paint = Paint()..strokeCap = StrokeCap.round;

  static void paintShape(Canvas canvas, GeometricShape shape, {
    Color? overrideColor,
    double alphaOverride = 1.0,
    bool forceStroke = false,
  }) {
    final rect = Rect.fromPoints(shape.startPoint, shape.endPoint);
    final color = overrideColor ?? shape.color;
    final effectiveColor = alphaOverride < 1.0
        ? color.withValues(alpha: color.a * alphaOverride)
        : color;

    _paint
      ..color = effectiveColor
      ..strokeWidth = shape.strokeWidth
      ..style = forceStroke || !shape.filled
          ? PaintingStyle.stroke
          : PaintingStyle.fill;

    switch (shape.type) {
      case ShapeType.rectangle:
        canvas.drawRect(rect, _paint);
      case ShapeType.circle:
        canvas.drawOval(rect, _paint);
      case ShapeType.line:
        canvas.drawLine(shape.startPoint, shape.endPoint, _paint);
      case ShapeType.triangle:
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.left, rect.bottom)
          ..lineTo(rect.right, rect.bottom)
          ..close();
        canvas.drawPath(path, _paint);
      case ShapeType.arrow:
        _paintArrow(canvas, shape.startPoint, shape.endPoint, _paint);
      case ShapeType.star:
        _paintStar(canvas, rect, _paint);
      case ShapeType.diamond:
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
        canvas.drawPath(path, _paint);
      default:
        canvas.drawRect(rect, _paint);
    }
  }

  static void _paintArrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    canvas.drawLine(from, to, paint);
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = Offset(dx, dy).distance;
    if (len < 1) return;
    const headLen = 15.0;
    const headAngle = 0.5;
    final ux = dx / len;
    final uy = dy / len;
    final p1 = Offset(
      to.dx - headLen * (ux * 0.866 - uy * headAngle),
      to.dy - headLen * (uy * 0.866 + ux * headAngle),
    );
    final p2 = Offset(
      to.dx - headLen * (ux * 0.866 + uy * headAngle),
      to.dy - headLen * (uy * 0.866 - ux * headAngle),
    );
    canvas.drawLine(to, p1, paint);
    canvas.drawLine(to, p2, paint);
  }

  static void _paintStar(Canvas canvas, Rect rect, Paint paint) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final outerR = rect.shortestSide / 2;
    final innerR = outerR * 0.4;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final r = i.isEven ? outerR : innerR;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, _paint);
  }
}

// =============================================================================
// SHAPE PREVIEW PAINTER
// =============================================================================

/// OPT #8: Uses shared [ShapePaintHelper] — no duplicated shape logic.
class _ShapePreviewPainter extends CustomPainter {
  final GeometricShape shape;
  final InfiniteCanvasController controller;

  _ShapePreviewPainter({required this.shape, required this.controller});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    ShapePaintHelper.paintShape(
      canvas, shape,
      alphaOverride: 0.7,
      forceStroke: true,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShapePreviewPainter oldDelegate) =>
      shape.id != oldDelegate.shape.id ||
      shape.endPoint != oldDelegate.shape.endPoint;
}

// =============================================================================
// CROSSHAIR PAINTER — Shows active drawing position in other panels
// =============================================================================

/// OPT #2: Pre-allocated Paint objects to avoid per-frame allocation.
class _CrosshairPainter extends CustomPainter {
  final Offset canvasPosition;
  final InfiniteCanvasController controller;

  // Pre-allocated paints (single-threaded UI, safe to reuse)
  static final Paint _linePaint = Paint()
    ..color = const Color(0xFFFF5722)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  static final Paint _dotPaint = Paint()
    ..color = const Color(0xAAFF5722)
    ..style = PaintingStyle.fill;

  _CrosshairPainter({required this.canvasPosition, required this.controller});

  @override
  void paint(Canvas canvas, Size size) {
    // Convert canvas coords to screen coords via viewport transform
    final screenX = canvasPosition.dx * controller.scale + controller.offset.dx;
    final screenY = canvasPosition.dy * controller.scale + controller.offset.dy;

    // Skip if outside visible area
    if (screenX < -20 ||
        screenX > size.width + 20 ||
        screenY < -20 ||
        screenY > size.height + 20) {
      return;
    }

    const crossSize = 12.0;

    // Crosshair lines
    canvas.drawLine(
      Offset(screenX - crossSize, screenY),
      Offset(screenX + crossSize, screenY),
      _linePaint,
    );
    canvas.drawLine(
      Offset(screenX, screenY - crossSize),
      Offset(screenX, screenY + crossSize),
      _linePaint,
    );

    // Small center dot
    canvas.drawCircle(Offset(screenX, screenY), 3.0, _dotPaint);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      canvasPosition != oldDelegate.canvasPosition;
}
