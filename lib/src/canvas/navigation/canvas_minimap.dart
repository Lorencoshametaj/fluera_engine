import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../infinite_canvas_controller.dart';
import './content_bounds_tracker.dart';
import './minimap_painter.dart';
import './camera_actions.dart';

/// 🗺️ Interactive minimap widget showing a bird's-eye view of the canvas.
///
/// DESIGN PRINCIPLES:
/// - Semi-transparent glassmorphism panel in the bottom-right corner.
/// - Dragging inside the minimap pans the canvas in real time.
/// - Clicking jumps to that location with a spring animation.
/// - Fades in/out with [AnimatedOpacity].
///
/// Usage:
/// ```dart
/// CanvasMinimap(
///   controller: canvasController,
///   boundsTracker: contentBoundsTracker,
///   viewportSize: MediaQuery.of(context).size,
///   visible: _showMinimap,
/// )
/// ```
class CanvasMinimap extends StatefulWidget {
  final InfiniteCanvasController controller;
  final ContentBoundsTracker boundsTracker;
  final Size viewportSize;
  final bool visible;

  /// Canvas background color — used for adaptive panel styling.
  final Color canvasBackground;

  /// Minimap dimensions.
  static const double kWidth = 180.0;
  static const double kHeight = 130.0;

  const CanvasMinimap({
    super.key,
    required this.controller,
    required this.boundsTracker,
    required this.viewportSize,
    this.visible = true,
    this.canvasBackground = Colors.white,
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
    // Top-left and bottom-right corners in canvas space.
    final topLeft = c.screenToCanvas(Offset.zero);
    final bottomRight = c.screenToCanvas(Offset(s.width, s.height));
    return Rect.fromPoints(topLeft, bottomRight);
  }

  /// Convert a local minimap position to canvas world coordinates,
  /// then animate the camera there.
  void _onMinimapInteraction(Offset localPosition) {
    final contentBounds = widget.boundsTracker.bounds.value;
    if (contentBounds.isEmpty) return;

    // Expand bounds the same way the painter does.
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

    // Inverse transform: minimap → world.
    final worldX = expandedBounds.left + (localPosition.dx - offsetX) / scale;
    final worldY = expandedBounds.top + (localPosition.dy - offsetY) / scale;

    // Set the camera so the clicked world point is centered.
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

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16.0, right: 16.0),
          child: GestureDetector(
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
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                return ValueListenableBuilder<List<ContentRegion>>(
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
                          painter: MinimapPainter(
                            regions: regions,
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
