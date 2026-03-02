import 'dart:math' as math;
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
  // ── Drawing input handler ──────────────────────────────────────────────
  late final DrawingInputHandler _drawingHandler;

  // ── Live stroke preview ────────────────────────────────────────────────
  final ValueNotifier<List<ProDrawingPoint>> _strokeNotifier =
      ValueNotifier<List<ProDrawingPoint>>([]);

  // ── Shape drawing state ────────────────────────────────────────────────
  final ValueNotifier<GeometricShape?> _currentShapeNotifier =
      ValueNotifier<GeometricShape?>(null);

  // ── Zoom overlay ───────────────────────────────────────────────────────
  bool _showZoomIndicator = false;

  // ── Eraser ─────────────────────────────────────────────────────────────
  late final EraserTool _eraserTool;

  @override
  void initState() {
    super.initState();
    widget.canvasController.attachTicker(this);
    widget.canvasController.addListener(_onViewportChanged);

    _eraserTool = EraserTool(layerController: widget.layerController);

    _drawingHandler = DrawingInputHandler(
      onPointsUpdated: (points) {
        _strokeNotifier.value = List.of(points);
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
    widget.canvasController.removeListener(_onViewportChanged);
    _drawingHandler.dispose();
    _strokeNotifier.dispose();
    _currentShapeNotifier.dispose();
    widget.canvasController.detachTicker();
    super.dispose();
  }

  void _onViewportChanged() {
    // Show zoom indicator briefly when viewport changes
    if (!_showZoomIndicator) {
      setState(() => _showZoomIndicator = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showZoomIndicator = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTapDown: (_) => widget.onActivate(),
      onDoubleTap: widget.onDoubleTap,
      onLongPressStart:
          widget.onLongPress != null
              ? (details) => widget.onLongPress!(details.globalPosition)
              : null,
      behavior: HitTestBehavior.translucent,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color:
                widget.isActive
                    ? cs.primary
                    : cs.outlineVariant.withValues(alpha: 0.3),
            width: widget.isActive ? 2.0 : 0.5,
          ),
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
              if (!widget.isActive && widget.cursorPosition != null)
                Positioned.fill(
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

              // 🏷️ Panel indicator + zoom level (top-left)
              Positioned(
                top: 6,
                left: 6,
                child: IgnorePointer(child: _buildPanelBadge(cs)),
              ),

              // 🔍 Zoom indicator (bottom-right, animated)
              Positioned(
                bottom: 8,
                right: 8,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showZoomIndicator ? 0.8 : 0.0,
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
      child: Text(
        'Panel ${widget.panelIndex + 1}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
          color: widget.isActive ? cs.primary : cs.onSurfaceVariant,
          letterSpacing: 0.3,
        ),
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
    widget.onCursorMoved?.call(canvasPosition);
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
class _BrushEngineCanvasPainter extends CustomPainter {
  final InfiniteCanvasController controller;
  final LayerController layerController;
  final Color backgroundColor;

  _BrushEngineCanvasPainter({
    required this.controller,
    required this.layerController,
    required this.backgroundColor,
  }) : super(repaint: Listenable.merge([controller, layerController]));

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    // 2. Viewport transform
    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    if (controller.rotation != 0.0) {
      final center = Offset(size.width / 2, size.height / 2);
      canvas.translate(center.dx, center.dy);
      canvas.rotate(controller.rotation);
      canvas.translate(-center.dx, -center.dy);
    }

    // 3. Viewport bounds — use infinite rect (matching main canvas DrawingPainter).
    // The ClipRect widget on the panel already handles screen clipping.
    // Tight viewport culling was incorrectly hiding strokes during zoom.
    const viewportRect = Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6);

    // 4. Render layers with BrushEngine
    for (final layer in layerController.layers) {
      if (!layer.isVisible) continue;

      canvas.save();
      if (layer.opacity < 1.0) {
        canvas.saveLayer(
          null,
          Paint()..color = Color.fromRGBO(255, 255, 255, layer.opacity),
        );
      }

      // 🎨 Strokes — BrushEngine rendering (pressure, texture, brush effects)
      for (final stroke in layer.strokes) {
        if (stroke.points.isEmpty) continue;

        // Viewport culling — skip strokes outside visible area
        if (!viewportRect.overlaps(stroke.bounds)) continue;

        BrushEngine.renderStroke(
          canvas,
          stroke.points,
          stroke.color,
          stroke.baseWidth,
          stroke.penType,
          stroke.settings,
          engineVersion: stroke.engineVersion,
        );
      }

      // 📐 Shapes
      for (final shape in layer.shapes) {
        _paintShape(canvas, shape);
      }

      if (layer.opacity < 1.0) {
        canvas.restore(); // saveLayer
      }
      canvas.restore(); // layer save
    }

    canvas.restore(); // viewport transform
  }

  void _paintShape(Canvas canvas, GeometricShape shape) {
    final rect = Rect.fromPoints(shape.startPoint, shape.endPoint);
    final paint =
        Paint()
          ..color = shape.color
          ..strokeWidth = shape.strokeWidth
          ..style = shape.filled ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    switch (shape.type) {
      case ShapeType.rectangle:
        canvas.drawRect(rect, paint);
      case ShapeType.circle:
        canvas.drawOval(rect, paint);
      case ShapeType.line:
        canvas.drawLine(shape.startPoint, shape.endPoint, paint);
      case ShapeType.triangle:
        final path =
            Path()
              ..moveTo(rect.center.dx, rect.top)
              ..lineTo(rect.left, rect.bottom)
              ..lineTo(rect.right, rect.bottom)
              ..close();
        canvas.drawPath(path, paint);
      case ShapeType.arrow:
        _paintArrow(canvas, shape.startPoint, shape.endPoint, paint);
      case ShapeType.star:
        _paintStar(canvas, rect, paint);
      case ShapeType.diamond:
        final path =
            Path()
              ..moveTo(rect.center.dx, rect.top)
              ..lineTo(rect.right, rect.center.dy)
              ..lineTo(rect.center.dx, rect.bottom)
              ..lineTo(rect.left, rect.center.dy)
              ..close();
        canvas.drawPath(path, paint);
      default:
        canvas.drawRect(rect, paint);
    }
  }

  void _paintArrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    canvas.drawLine(from, to, paint);
    // Arrowhead
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

  void _paintStar(Canvas canvas, Rect rect, Paint paint) {
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
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BrushEngineCanvasPainter oldDelegate) => true;
}

// =============================================================================
// SHAPE PREVIEW PAINTER
// =============================================================================

class _ShapePreviewPainter extends CustomPainter {
  final GeometricShape shape;
  final InfiniteCanvasController controller;

  _ShapePreviewPainter({required this.shape, required this.controller});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    final rect = Rect.fromPoints(shape.startPoint, shape.endPoint);
    final paint =
        Paint()
          ..color = shape.color.withValues(alpha: 0.7)
          ..strokeWidth = shape.strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    switch (shape.type) {
      case ShapeType.rectangle:
        canvas.drawRect(rect, paint);
      case ShapeType.circle:
        canvas.drawOval(rect, paint);
      case ShapeType.line:
        canvas.drawLine(shape.startPoint, shape.endPoint, paint);
      case ShapeType.triangle:
        final path =
            Path()
              ..moveTo(rect.center.dx, rect.top)
              ..lineTo(rect.left, rect.bottom)
              ..lineTo(rect.right, rect.bottom)
              ..close();
        canvas.drawPath(path, paint);
      default:
        canvas.drawRect(rect, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShapePreviewPainter oldDelegate) => true;
}

// =============================================================================
// CROSSHAIR PAINTER — Shows active drawing position in other panels
// =============================================================================

class _CrosshairPainter extends CustomPainter {
  final Offset canvasPosition;
  final InfiniteCanvasController controller;

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
        screenY > size.height + 20)
      return;

    const crossSize = 12.0;
    final paint =
        Paint()
          ..color = const Color(0xFFFF5722)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

    // Crosshair lines
    canvas.drawLine(
      Offset(screenX - crossSize, screenY),
      Offset(screenX + crossSize, screenY),
      paint,
    );
    canvas.drawLine(
      Offset(screenX, screenY - crossSize),
      Offset(screenX, screenY + crossSize),
      paint,
    );

    // Small center dot
    canvas.drawCircle(
      Offset(screenX, screenY),
      3.0,
      paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xAAFF5722),
    );
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      canvasPosition != oldDelegate.canvasPosition;
}
