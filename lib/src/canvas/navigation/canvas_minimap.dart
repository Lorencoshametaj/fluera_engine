import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../drawing/models/pro_drawing_point.dart';
import '../infinite_canvas_controller.dart';
import './content_bounds_tracker.dart';
import './minimap_painter.dart';
import './camera_actions.dart';
import '../../layers/layer_controller.dart';

/// 🗺️ Interactive minimap widget showing a bird's-eye view of the canvas.
///
/// DESIGN PRINCIPLES:
/// - Semi-transparent glassmorphism panel in the bottom-right corner.
/// - Dragging inside the minimap pans the canvas in real time.
/// - Clicking jumps to that location with a spring animation.
/// - **Double-tap** fits all content into viewport.
/// - **Auto-hides** during active drawing to reduce visual clutter.
/// - **Live stroke preview**: shows the current in-progress stroke in real time.
/// - Fades in/out with [AnimatedOpacity].
///
/// ARCHITECTURE (two-layer split):
/// - **Content layer** ([MinimapContentPainter]) wrapped in its own
///   [RepaintBoundary] — repaints only when regions/bounds change.
/// - **Viewport layer** ([MinimapViewportPainter]) repaints on every
///   controller update (pan/zoom) — lightweight (single rect draw).
/// - **Live stroke layer** — repaints with current stroke notifier.
/// - This split ensures panning/zooming doesn't repaint the content.
///
/// Usage:
/// ```dart
/// CanvasMinimap(
///   controller: canvasController,
///   boundsTracker: contentBoundsTracker,
///   layerController: layerController,
///   viewportSize: MediaQuery.of(context).size,
///   visible: _showMinimap,
///   isDrawing: _isDrawingNotifier,
///   currentStroke: _currentStrokeNotifier,
/// )
/// ```
class CanvasMinimap extends StatefulWidget {
  final InfiniteCanvasController controller;
  final ContentBoundsTracker boundsTracker;
  final LayerController layerController;
  final Size viewportSize;
  final bool visible;

  /// Canvas background color — used for adaptive panel styling.
  final Color canvasBackground;

  /// Whether the user is currently drawing. When true, the minimap
  /// fades to reduced opacity to minimize visual clutter.
  final ValueNotifier<bool>? isDrawing;

  /// Live current-stroke notifier for real-time stroke preview on the minimap.
  final ValueNotifier<List<ProDrawingPoint>>? currentStroke;

  /// Current stroke color (for live preview rendering).
  final Color currentStrokeColor;

  /// Remote collaborator cursor positions (for dot indicators on minimap).
  /// Null if no collaboration engine is active.
  final ValueNotifier<Map<String, Map<String, dynamic>>>? remoteCursors;

  /// Minimap dimensions.
  static const double kWidth = 180.0;
  static const double kHeight = 130.0;

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
  });

  @override
  State<CanvasMinimap> createState() => _CanvasMinimapState();
}

class _CanvasMinimapState extends State<CanvasMinimap> {
  bool _isDragging = false;

  /// Convert the current viewport to canvas-space rectangle.
  Rect _computeViewportInCanvas() {
    final c = widget.controller;
    final s = widget.viewportSize;
    final topLeft = c.screenToCanvas(Offset.zero);
    final bottomRight = c.screenToCanvas(Offset(s.width, s.height));
    return Rect.fromPoints(topLeft, bottomRight);
  }

  /// Convert a local minimap position to canvas world coordinates,
  /// then animate the camera there.
  void _onMinimapInteraction(Offset localPosition) {
    final contentBounds = widget.boundsTracker.bounds.value;
    if (contentBounds.isEmpty) return;

    final expandedBounds = contentBounds.inflate(
      contentBounds.shortestSide * 0.1,
    );

    const padding = 8.0;
    final drawArea = Rect.fromLTWH(
      padding,
      padding,
      CanvasMinimap.kWidth - padding * 2,
      CanvasMinimap.kHeight - padding * 2,
    );

    final scaleX = drawArea.width / expandedBounds.width;
    final scaleY = drawArea.height / expandedBounds.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final scaledW = expandedBounds.width * scale;
    final scaledH = expandedBounds.height * scale;
    final offsetX = drawArea.left + (drawArea.width - scaledW) / 2;
    final offsetY = drawArea.top + (drawArea.height - scaledH) / 2;

    final worldX = expandedBounds.left + (localPosition.dx - offsetX) / scale;
    final worldY = expandedBounds.top + (localPosition.dy - offsetY) / scale;

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
  }

  /// Double-tap → fit all content into the viewport.
  void _onDoubleTap() {
    CameraActions.fitAllContent(
      widget.controller,
      widget.layerController.sceneGraph,
      widget.viewportSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── Auto-hide during drawing ───────────────────────────────────────────
    Widget minimapContent = _buildMinimapStack();

    if (widget.isDrawing != null) {
      minimapContent = ValueListenableBuilder<bool>(
        valueListenable: widget.isDrawing!,
        builder: (context, isDrawing, child) {
          return AnimatedOpacity(
            opacity: widget.visible ? (isDrawing ? 0.25 : 1.0) : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !widget.visible || isDrawing,
              child: child,
            ),
          );
        },
        child: minimapContent,
      );
    } else {
      minimapContent = AnimatedOpacity(
        opacity: widget.visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(ignoring: !widget.visible, child: minimapContent),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0, right: 16.0),
      child: minimapContent,
    );
  }

  Widget _buildMinimapStack() {
    return GestureDetector(
      onPanStart: (details) {
        _isDragging = true;
        _onMinimapInteraction(details.localPosition);
      },
      onPanUpdate: (details) {
        _onMinimapInteraction(details.localPosition);
      },
      onPanEnd: (_) {
        _isDragging = false;
      },
      onTapDown: (details) {
        _onMinimapInteraction(details.localPosition);
      },
      onDoubleTap: _onDoubleTap,
      child: SizedBox(
        width: CanvasMinimap.kWidth,
        height: CanvasMinimap.kHeight,
        child: Stack(
          children: [
            // ── Layer 1: Content (strokes, shapes, etc.) ────────────────
            RepaintBoundary(
              child: ValueListenableBuilder<List<ContentRegion>>(
                valueListenable: widget.boundsTracker.regions,
                builder: (context, regions, _) {
                  return ValueListenableBuilder<Rect>(
                    valueListenable: widget.boundsTracker.bounds,
                    builder: (context, contentBounds, _) {
                      return CustomPaint(
                        size: const Size(
                          CanvasMinimap.kWidth,
                          CanvasMinimap.kHeight,
                        ),
                        painter: MinimapContentPainter(
                          regions: regions,
                          contentBounds: contentBounds,
                          minimapWidth: CanvasMinimap.kWidth,
                          minimapHeight: CanvasMinimap.kHeight,
                          canvasBackground: widget.canvasBackground,
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // ── Layer 2: Viewport indicator ─────────────────────────────
            // 🚀 RepaintBoundary: isolate viewport repaints (every pan/zoom
            // frame) from content layer — prevents cascading repaint.
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: widget.controller,
                builder: (context, _) {
                  return ValueListenableBuilder<Rect>(
                    valueListenable: widget.boundsTracker.bounds,
                    builder: (context, contentBounds, _) {
                      return CustomPaint(
                        size: const Size(
                          CanvasMinimap.kWidth,
                          CanvasMinimap.kHeight,
                        ),
                        painter: MinimapViewportPainter(
                          contentBounds: contentBounds,
                          viewportInCanvas: _computeViewportInCanvas(),
                          minimapWidth: CanvasMinimap.kWidth,
                          minimapHeight: CanvasMinimap.kHeight,
                          canvasBackground: widget.canvasBackground,
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // ── Layer 3: Live current-stroke preview ────────────────────
            // 🚀 RepaintBoundary: isolate live stroke repaints (every
            // point) from viewport and content layers.
            if (widget.currentStroke != null)
              RepaintBoundary(
                child: ValueListenableBuilder<List<ProDrawingPoint>>(
                  valueListenable: widget.currentStroke!,
                  builder: (context, strokePoints, _) {
                    if (strokePoints.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return ValueListenableBuilder<Rect>(
                      valueListenable: widget.boundsTracker.bounds,
                      builder: (context, contentBounds, _) {
                        return CustomPaint(
                          size: const Size(
                            CanvasMinimap.kWidth,
                            CanvasMinimap.kHeight,
                          ),
                          painter: MinimapLiveStrokePainter(
                            strokePoints: strokePoints,
                            contentBounds: contentBounds,
                            minimapWidth: CanvasMinimap.kWidth,
                            minimapHeight: CanvasMinimap.kHeight,
                            strokeColor: widget.currentStrokeColor,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

            // ── Layer 4: Collaborator cursor dots ──────────────────────
            if (widget.remoteCursors != null)
              ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
                valueListenable: widget.remoteCursors!,
                builder: (context, cursors, _) {
                  if (cursors.isEmpty) return const SizedBox.shrink();
                  return ValueListenableBuilder<Rect>(
                    valueListenable: widget.boundsTracker.bounds,
                    builder: (context, contentBounds, _) {
                      return CustomPaint(
                        size: const Size(
                          CanvasMinimap.kWidth,
                          CanvasMinimap.kHeight,
                        ),
                        painter: MinimapCursorsPainter(
                          remoteCursors: cursors,
                          contentBounds: contentBounds,
                          minimapWidth: CanvasMinimap.kWidth,
                          minimapHeight: CanvasMinimap.kHeight,
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
