import 'dart:math';
import 'package:flutter/material.dart';
import '../../rendering/canvas/drawing_painter.dart';
import '../../tools/lasso/lasso_tool.dart';
import '../../reflow/content_cluster.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../drawing/brushes/brushes.dart';
import '../../core/models/shape_type.dart';
import '../infinite_canvas_controller.dart';
import '../spring_animation_controller.dart';
import '../liquid_canvas_config.dart';
import 'package:flutter/services.dart';

/// 🔲 Selection Transform Overlay
///
/// Shows handle interattivi attorno alla selezione lasso:
/// - 4 handle angolo → scala proporzionale
/// - 4 side handles → scale on one axis
/// - 1 rotation handle (above the box) → free rotation
/// - Drag interno → spostamento (delegato a LassoTool)
///
/// The callbacks are called during drag to update
/// gli selected elements in tempo reale.
class SelectionTransformOverlay extends StatefulWidget {
  final LassoTool lassoTool;
  final InfiniteCanvasController canvasController;
  final VoidCallback onTransformComplete;
  final void Function(Offset screenPosition)? onEdgeAutoScroll;
  final VoidCallback? onEdgeAutoScrollEnd;
  final bool isDark;

  /// 🌊 SNAP: Callback to compute smart guide snap offset for a given bounds.
  /// Returns the correction offset to apply (Offset.zero if no snap).
  final Offset Function(Rect bounds)? onComputeSnap;

  const SelectionTransformOverlay({
    super.key,
    required this.lassoTool,
    required this.canvasController,
    required this.onTransformComplete,
    this.onEdgeAutoScroll,
    this.onEdgeAutoScrollEnd,
    this.isDark = false,
    this.onComputeSnap,
  });

  @override
  State<SelectionTransformOverlay> createState() =>
      _SelectionTransformOverlayState();
}

class _SelectionTransformOverlayState extends State<SelectionTransformOverlay>
    with TickerProviderStateMixin {
  // Handle attualmente trascinato
  _HandleType? _activeHandle;
  Offset? _dragStart;
  Offset? _rotationCenter; // Stable center captured at gesture start
  double _initialAngle = 0;
  double _initialDistance = 0;

  // 🌊 REFLOW: Settle animation
  late final AnimationController _settleController;
  Map<String, Offset> _settleDisplacements = {};
  double _settleOpacity = 0.0;

  // 🌊 FLING: Spring controller for node drag inertia
  late final SpringAnimationController _flingController;
  Offset _flingPreviousOffset = Offset.zero;
  bool _isFlingActive = false;

  // 🌊 SNAP SPRING: Post-fling snap-to-guide spring animation
  bool _isSnapSpringActive = false;
  Offset _snapSpringPreviousOffset = Offset.zero;

  // 🌊 TIER 4: Mid-fling snap throttle + edge bounce
  int _flingFrameCount = 0;

  // 🌊 TIER 4: Handle velocity tracking for spring-eased scale/rotate
  double _lastHandleScaleDelta = 0.0;
  double _lastHandleRotationDelta = 0.0;
  int _lastHandleTimestamp = 0;

  static const double _handleSize = 22.0;
  static const double _hitAreaSize = 48.0; // Minimum touch target
  static const double _rotationHandleOffset = 36.0;

  @override
  void initState() {
    super.initState();
    // 🚀 Follow canvas transform (zoom/pan/rotate) in real-time
    widget.canvasController.addListener(_onCanvasTransformChanged);
    // 🚀 PERF: Listen to drag updates for smooth handle positioning
    widget.lassoTool.dragNotifier.addListener(_onDragUpdate);
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _settleController.addListener(() {
      _settleOpacity =
          1.0 - Curves.easeOutCubic.transform(_settleController.value);
      setState(() {});
    });
    _settleController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _settleDisplacements = {};
        _settleOpacity = 0.0;
      }
    });

    // 🌊 FLING: Initialize spring controller for drag inertia
    _flingController = SpringAnimationController();
    _flingController.attachTicker(this);
    _flingController.onOffsetUpdate = _onFlingOrSnapUpdate;
    _flingController.onComplete = _onAnimationComplete;
  }

  void _onCanvasTransformChanged() {
    if (mounted) setState(() {});
  }

  void _onDragUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.canvasController.removeListener(_onCanvasTransformChanged);
    widget.lassoTool.dragNotifier.removeListener(_onDragUpdate);
    _settleController.dispose();
    _flingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.lassoTool.hasSelection) {
      return const SizedBox.shrink();
    }

    final bounds = widget.lassoTool.getSelectionBounds();
    if (bounds == null) return const SizedBox.shrink();

    // Convert bounds canvas → screen coordinates
    final topLeft = widget.canvasController.canvasToScreen(bounds.topLeft);
    final bottomRight = widget.canvasController.canvasToScreen(
      bounds.bottomRight,
    );
    final screenBounds = Rect.fromPoints(topLeft, bottomRight);
    final center = screenBounds.center;

    // Determine active displacements (live drag or settle animation)
    final activeDisplacements =
        widget.lassoTool.reflowGhostDisplacements.isNotEmpty
            ? widget.lassoTool.reflowGhostDisplacements
            : _settleDisplacements;
    final activeOpacity =
        widget.lassoTool.reflowGhostDisplacements.isNotEmpty
            ? 1.0
            : _settleOpacity;
    final activeLayer = widget.lassoTool.layerController.activeLayer;

    return Stack(
      children: [
        // 🌊 REFLOW: Ghost preview — always in tree to avoid gesture disruption
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ReflowGhostPainter(
                clusters: widget.lassoTool.clusterCache,
                displacements: activeDisplacements,
                canvasController: widget.canvasController,
                strokes: activeLayer?.strokes ?? [],
                shapes: activeLayer?.shapes ?? [],
                globalOpacity: activeOpacity,
              ),
            ),
          ),
        ),

        // 🔧 FIX: Drag area — captures pan inside selection bounds for move
        Positioned(
          left: screenBounds.left,
          top: screenBounds.top,
          width: screenBounds.width,
          height: screenBounds.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              // 🌊 FLING/SNAP: Cancel any active animation on new touch
              if (_isFlingActive || _isSnapSpringActive) {
                _flingController.stop();
                _isFlingActive = false;
                _isSnapSpringActive = false;
              }
              final canvasPos = widget.canvasController.screenToCanvas(
                details.globalPosition,
              );
              widget.lassoTool.startDrag(canvasPos);
            },
            onPanUpdate: (details) {
              final canvasPos = widget.canvasController.screenToCanvas(
                details.globalPosition,
              );
              widget.lassoTool.updateDrag(canvasPos);
              DrawingPainter.invalidateAllTiles();
              // 🏀️ Edge auto-scroll during selection drag
              widget.onEdgeAutoScroll?.call(details.globalPosition);
              setState(() {});
            },
            onPanEnd: (details) {
              // 🏀️ Stop edge auto-scroll
              widget.onEdgeAutoScrollEnd?.call();

              // 🌊 REFLOW: Snapshot displacements for settle animation
              final ghostSnap = Map<String, Offset>.from(
                widget.lassoTool.reflowGhostDisplacements,
              );

              widget.lassoTool.endDrag();
              DrawingPainter.invalidateAllTiles();
              widget.onTransformComplete();

              // 🌊 REFLOW: Trigger settle fade-out animation
              if (ghostSnap.isNotEmpty) {
                _settleDisplacements = ghostSnap;
                _settleOpacity = 1.0;
                _settleController.forward(from: 0.0);
              }

              // 🌊 FLING: Launch friction fling if velocity exceeds threshold
              final rawVelocity = widget.lassoTool.lastDragVelocity;
              final config = widget.canvasController.liquidConfig;
              if (rawVelocity.distance > config.nodeDragFlingThreshold &&
                  widget.lassoTool.hasSelection) {
                // 🚀 T4: Velocity clamping
                final velocity =
                    rawVelocity.distance > config.nodeDragMaxFlingVelocity
                        ? rawVelocity *
                            (config.nodeDragMaxFlingVelocity /
                                rawVelocity.distance)
                        : rawVelocity;

                // ⚖️ T4: Adaptive friction — heavier selections decelerate faster
                final adaptiveFriction =
                    config.nodeDragFlingFriction +
                    config.nodeDragAdaptiveFrictionFactor *
                        widget.lassoTool.selectionCount;

                _flingPreviousOffset = Offset.zero;
                _flingController.snapOffsetTo(Offset.zero);
                _flingController.fling(velocity, friction: adaptiveFriction);
                _isFlingActive = true;
                _flingFrameCount = 0;
              }
            },
            child: CustomPaint(
              painter: _DashedBorderPainter(isDark: widget.isDark),
            ),
          ),
        ),

        // Hide transform handles during drag-move for cleaner UX
        if (!widget.lassoTool.isDragging) ...[
          // Handle angoli (scala proporzionale)
          _buildHandle(screenBounds.topLeft, _HandleType.topLeft, center),
          _buildHandle(screenBounds.topRight, _HandleType.topRight, center),
          _buildHandle(screenBounds.bottomLeft, _HandleType.bottomLeft, center),
          _buildHandle(
            screenBounds.bottomRight,
            _HandleType.bottomRight,
            center,
          ),

          // Handle lati (scala su un asse)
          _buildHandle(
            Offset(screenBounds.center.dx, screenBounds.top),
            _HandleType.topCenter,
            center,
          ),
          _buildHandle(
            Offset(screenBounds.center.dx, screenBounds.bottom),
            _HandleType.bottomCenter,
            center,
          ),
          _buildHandle(
            Offset(screenBounds.left, screenBounds.center.dy),
            _HandleType.middleLeft,
            center,
          ),
          _buildHandle(
            Offset(screenBounds.right, screenBounds.center.dy),
            _HandleType.middleRight,
            center,
          ),

          // Handle rotation (above the box)
          _buildRotationHandle(
            Offset(
              screenBounds.center.dx,
              screenBounds.top - _rotationHandleOffset,
            ),
            center,
          ),

          // Linea connettore al rotation handle
          Positioned(
            left: screenBounds.center.dx - 0.5,
            top: screenBounds.top - _rotationHandleOffset,
            child: CustomPaint(
              size: Size(1, _rotationHandleOffset),
              painter: _ConnectorLinePainter(isDark: widget.isDark),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHandle(Offset position, _HandleType type, Offset center) {
    return Positioned(
      left: position.dx - _hitAreaSize / 2,
      top: position.dy - _hitAreaSize / 2,
      child: GestureDetector(
        onPanStart: (details) => _onHandleDragStart(details, type, center),
        onPanUpdate: (details) => _onHandleDragUpdate(details, type, center),
        onPanEnd: (_) => _onHandleDragEnd(),
        child: Container(
          width: _hitAreaSize,
          height: _hitAreaSize,
          color: Colors.transparent, // Invisible hit area
          alignment: Alignment.center,
          child: Container(
            width: _handleSize,
            height: _handleSize,
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.white : Colors.white,
              border: Border.all(color: Colors.blue, width: 2),
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRotationHandle(Offset position, Offset center) {
    return Positioned(
      left: position.dx - _hitAreaSize / 2,
      top: position.dy - _hitAreaSize / 2,
      child: GestureDetector(
        onPanStart:
            (details) =>
                _onHandleDragStart(details, _HandleType.rotation, center),
        onPanUpdate:
            (details) =>
                _onHandleDragUpdate(details, _HandleType.rotation, center),
        onPanEnd: (_) => _onHandleDragEnd(),
        child: Container(
          width: _hitAreaSize,
          height: _hitAreaSize,
          color: Colors.transparent, // Invisible hit area
          alignment: Alignment.center,
          child: Container(
            width: _handleSize + 2,
            height: _handleSize + 2,
            decoration: BoxDecoration(
              color: Colors.green,
              border: Border.all(color: Colors.green.shade700, width: 2),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onHandleDragStart(
    DragStartDetails details,
    _HandleType type,
    Offset center,
  ) {
    _activeHandle = type;
    _dragStart = details.globalPosition;
    _rotationCenter = center; // Capture stable center at gesture start

    if (type == _HandleType.rotation) {
      // Calculate angolo iniziale rispetto al centro (fisso per tutta la gesture)
      final delta = details.globalPosition - _rotationCenter!;
      _initialAngle = atan2(delta.dy, delta.dx);
    } else {
      // Calculate distanza iniziale per scala
      _initialDistance = (details.globalPosition - center).distance;
    }
  }

  void _onHandleDragUpdate(
    DragUpdateDetails details,
    _HandleType type,
    Offset center,
  ) {
    if (_activeHandle == null || _dragStart == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    if (type == _HandleType.rotation) {
      // Use the stable center captured at drag start (not the live one)
      final stableCenter = _rotationCenter ?? center;
      final delta = details.globalPosition - stableCenter;
      final currentAngle = atan2(delta.dy, delta.dx);
      var angleDelta = currentAngle - _initialAngle;

      // Normalize to [-pi, pi] to avoid jumps at the ±pi boundary
      while (angleDelta > pi) angleDelta -= 2 * pi;
      while (angleDelta < -pi) angleDelta += 2 * pi;

      // Skip micro-movements (touch noise)
      if (angleDelta.abs() < 0.001) return;

      _initialAngle = currentAngle;

      // 🌊 T4: Track rotation velocity for spring overshoot
      _lastHandleRotationDelta = angleDelta;
      _lastHandleTimestamp = now;

      // Convert stable center from screen to canvas space for the lasso tool
      final canvasCenter = widget.canvasController.screenToCanvas(stableCenter);
      widget.lassoTool.rotateSelectedByAngle(angleDelta, center: canvasCenter);
      // 🚀 PERF: Only invalidate layer caches (not tile + stroke caches)
      DrawingPainter.invalidateLayerCaches();
      widget.lassoTool.dragNotifier.value++;
      widget.onTransformComplete();
    } else {
      // Scala
      final currentDistance = (details.globalPosition - center).distance;
      if (_initialDistance > 0) {
        final scaleFactor = currentDistance / _initialDistance;
        // Clamp to avoid scale troppo estreme
        final clampedFactor = scaleFactor.clamp(0.5, 2.0);

        // 🌊 T4: Track scale velocity for spring overshoot
        _lastHandleScaleDelta = clampedFactor - 1.0;
        _lastHandleTimestamp = now;

        widget.lassoTool.scaleSelected(clampedFactor);
        _initialDistance = currentDistance;
        // 🚀 PERF: Only invalidate layer caches (not tile + stroke caches)
        DrawingPainter.invalidateLayerCaches();
        widget.lassoTool.dragNotifier.value++;
        widget.onTransformComplete();
      }
    }
  }

  void _onHandleDragEnd() {
    // 🌊 REFLOW: Bake ghost displacements on gesture end (same as drag end)
    if (widget.lassoTool.isReflowEnabled &&
        widget.lassoTool.reflowGhostDisplacements.isNotEmpty) {
      // Capture ghost displacements for settle fade-out animation
      _settleDisplacements = Map<String, Offset>.from(
        widget.lassoTool.reflowGhostDisplacements,
      );
      _settleOpacity = 1.0;

      // Bake displacements into actual positions
      widget.lassoTool.bakeReflowDisplacements();
      widget.lassoTool.reflowGhostDisplacements = {};

      // Trigger settle fade-out animation
      _settleController.forward(from: 0);
    }

    // 🌊 T4: Spring overshoot for scale/rotate handles
    // If the last handle gesture had momentum, apply a tiny spring continuation
    final timeSinceLastHandle =
        DateTime.now().millisecondsSinceEpoch - _lastHandleTimestamp;
    if (timeSinceLastHandle < 100 &&
        !_isFlingActive &&
        !_isSnapSpringActive &&
        widget.lassoTool.hasSelection) {
      final bounds = widget.lassoTool.getSelectionBounds();
      if (bounds != null) {
        // Convert rotation/scale momentum into a small translate overshoot
        Offset overshoot = Offset.zero;
        if (_lastHandleRotationDelta.abs() > 0.01) {
          // Rotation momentum → tangential overshoot from center
          final radius = bounds.shortestSide / 2;
          overshoot = Offset(
            -_lastHandleRotationDelta * radius * 0.3,
            _lastHandleRotationDelta * radius * 0.15,
          );
        } else if (_lastHandleScaleDelta.abs() > 0.02) {
          // Scale momentum → radial overshoot from center
          final magnitude = _lastHandleScaleDelta * 8.0;
          overshoot = Offset(magnitude, magnitude);
        }

        if (overshoot.distance > 1.0) {
          _isSnapSpringActive = true;
          _snapSpringPreviousOffset = Offset.zero;
          _flingController.snapOffsetTo(Offset.zero);
          // Animate to overshoot, then spring back to zero
          _flingController.animateOffsetTo(
            overshoot,
            spring: SpringAnimationController.bouncy,
          );
        }
      }
    }

    // Reset handle tracking
    _lastHandleScaleDelta = 0.0;
    _lastHandleRotationDelta = 0.0;
    _lastHandleTimestamp = 0;

    // 🚀 PERF: Full cache invalidation at gesture end (lightweight during gesture)
    DrawingPainter.invalidateAllTiles();

    _activeHandle = null;
    _dragStart = null;
    _rotationCenter = null;
    widget.onTransformComplete();
  }

  // ==========================================================================
  // 🌊 FLING & SNAP CALLBACKS
  // ==========================================================================

  /// Called each frame during friction fling or snap spring with accumulated offset.
  void _onFlingOrSnapUpdate(Offset currentOffset) {
    if (!(_isFlingActive || _isSnapSpringActive) ||
        !widget.lassoTool.hasSelection) {
      return;
    }

    // Compute incremental delta from last frame
    final previousOffset =
        _isSnapSpringActive ? _snapSpringPreviousOffset : _flingPreviousOffset;
    final delta = currentOffset - previousOffset;

    if (_isSnapSpringActive) {
      _snapSpringPreviousOffset = currentOffset;
    } else {
      _flingPreviousOffset = currentOffset;
    }

    // Apply to selected elements
    widget.lassoTool.moveSelected(delta);
    DrawingPainter.invalidateLayerCaches();
    widget.lassoTool.dragNotifier.value++;

    // 🧲 T4: Mid-fling magnetic catch — check for snap guides every 4 frames
    if (_isFlingActive) {
      _flingFrameCount++;
      if (_flingFrameCount % 4 == 0) {
        final computeSnap = widget.onComputeSnap;
        if (computeSnap != null) {
          final bounds = widget.lassoTool.getSelectionBounds();
          if (bounds != null) {
            final config = widget.canvasController.liquidConfig;
            final snapOffset = computeSnap(bounds);
            if (snapOffset != Offset.zero &&
                snapOffset.distance < config.nodeDragMidFlingSnapDistance) {
              // Caught! Stop fling and snap-spring to guide
              _flingController.stop();
              _isFlingActive = false;
              HapticFeedback.selectionClick();
              _isSnapSpringActive = true;
              _snapSpringPreviousOffset = Offset.zero;
              _flingController.snapOffsetTo(Offset.zero);
              _flingController.animateOffsetTo(
                snapOffset,
                spring: SpringAnimationController.snappy,
              );
              return;
            }
          }
        }
      }

      // 🏔️ T4: Edge bounce-back — if selection leaves viewport, spring back
      final bounds = widget.lassoTool.getSelectionBounds();
      if (bounds != null && mounted) {
        final viewportSize = MediaQuery.of(context).size;
        final screenCenter = widget.canvasController.canvasToScreen(
          bounds.center,
        );
        const edgePadding = 60.0;
        if (screenCenter.dx < -edgePadding ||
            screenCenter.dx > viewportSize.width + edgePadding ||
            screenCenter.dy < -edgePadding ||
            screenCenter.dy > viewportSize.height + edgePadding) {
          // Selection flew off-screen → stop fling and spring back
          _flingController.stop();
          _isFlingActive = false;

          // Compute bounce-back offset to bring center to nearest edge
          final targetScreenX = screenCenter.dx.clamp(
            edgePadding,
            viewportSize.width - edgePadding,
          );
          final targetScreenY = screenCenter.dy.clamp(
            edgePadding,
            viewportSize.height - edgePadding,
          );
          final targetCanvas = widget.canvasController.screenToCanvas(
            Offset(targetScreenX, targetScreenY),
          );
          final bounceBack = targetCanvas - bounds.center;

          HapticFeedback.mediumImpact();
          _isSnapSpringActive = true;
          _snapSpringPreviousOffset = Offset.zero;
          _flingController.snapOffsetTo(Offset.zero);
          _flingController.animateOffsetTo(
            bounceBack,
            spring: SpringAnimationController.bouncy,
          );
          return;
        }
      }
    }

    if (mounted) setState(() {});
  }

  /// Called when either fling or snap spring animation finishes.
  void _onAnimationComplete() {
    if (_isFlingActive) {
      // Fling just ended — check for post-fling snap
      _isFlingActive = false;
      _tryPostFlingSnap();
      return;
    }

    if (_isSnapSpringActive) {
      _isSnapSpringActive = false;
    }

    // Final cleanup
    DrawingPainter.invalidateAllTiles();
    widget.onTransformComplete();
  }

  /// After fling settles, check if selection is near a snap guide and spring to it.
  void _tryPostFlingSnap() {
    final computeSnap = widget.onComputeSnap;
    if (computeSnap == null || !widget.lassoTool.hasSelection) {
      // No snap callback — just finalize
      DrawingPainter.invalidateAllTiles();
      widget.onTransformComplete();
      return;
    }

    final bounds = widget.lassoTool.getSelectionBounds();
    if (bounds == null) {
      DrawingPainter.invalidateAllTiles();
      widget.onTransformComplete();
      return;
    }

    final snapOffset = computeSnap(bounds);
    if (snapOffset == Offset.zero || snapOffset.distance < 0.5) {
      // No meaningful snap nearby
      DrawingPainter.invalidateAllTiles();
      widget.onTransformComplete();
      return;
    }

    // 🌊 SNAP: Spring-animate to snapped position
    HapticFeedback.selectionClick();
    _isSnapSpringActive = true;
    _snapSpringPreviousOffset = Offset.zero;
    _flingController.snapOffsetTo(Offset.zero);
    _flingController.animateOffsetTo(
      snapOffset,
      spring: SpringAnimationController.snappy,
    );
  }
}

/// Type of handle per il trascinamento
enum _HandleType {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
  rotation,
}

/// Painter for the dashed border of the bounding box
class _DashedBorderPainter extends CustomPainter {
  final bool isDark;

  _DashedBorderPainter({this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

    const dashLength = 6.0;
    const gapLength = 4.0;

    // Top
    _drawDashedLine(
      canvas,
      Offset.zero,
      Offset(size.width, 0),
      paint,
      dashLength,
      gapLength,
    );
    // Right
    _drawDashedLine(
      canvas,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      paint,
      dashLength,
      gapLength,
    );
    // Bottom
    _drawDashedLine(
      canvas,
      Offset(0, size.height),
      Offset(size.width, size.height),
      paint,
      dashLength,
      gapLength,
    );
    // Left
    _drawDashedLine(
      canvas,
      Offset.zero,
      Offset(0, size.height),
      paint,
      dashLength,
      gapLength,
    );
  }

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
    final length = sqrt(dx * dx + dy * dy);
    final unitX = dx / length;
    final unitY = dy / length;

    double distance = 0;
    bool draw = true;

    while (distance < length) {
      final segLen = draw ? dashLen : gapLen;
      final endDist = (distance + segLen).clamp(0.0, length);

      if (draw) {
        canvas.drawLine(
          Offset(start.dx + unitX * distance, start.dy + unitY * distance),
          Offset(start.dx + unitX * endDist, start.dy + unitY * endDist),
          paint,
        );
      }

      distance = endDist;
      draw = !draw;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}

/// Painter per la linea connettore al rotation handle
class _ConnectorLinePainter extends CustomPainter {
  final bool isDark;

  _ConnectorLinePainter({this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ConnectorLinePainter oldDelegate) => false;
}

/// 🌊 Painter for reflow ghost previews.
///
/// Renders displaced cluster content with:
/// - Distance-based opacity (farther = more transparent)
/// - Stroke, shape, and text/image ghost rendering
/// - Direction arrows showing displacement direction
/// - Global opacity for settle animation fade-out
class _ReflowGhostPainter extends CustomPainter {
  final List<ContentCluster> clusters;
  final Map<String, Offset> displacements;
  final InfiniteCanvasController canvasController;
  final List<ProStroke> strokes;
  final List<GeometricShape> shapes;
  final double globalOpacity;

  static const double _maxDisplacementForOpacity = 300.0;
  static const double _arrowSize = 8.0;

  _ReflowGhostPainter({
    required this.clusters,
    required this.displacements,
    required this.canvasController,
    required this.strokes,
    required this.shapes,
    this.globalOpacity = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (displacements.isEmpty || globalOpacity <= 0.01) return;

    // Build O(1) lookup maps (avoid O(n) .where() per element)
    final clusterMap = {for (final c in clusters) c.id: c};
    final strokeMap = {for (final s in strokes) s.id: s};
    final shapeMap = {for (final s in shapes) s.id: s};

    // Apply viewport transform (overlay is in screen space)
    canvas.save();
    canvas.translate(canvasController.offset.dx, canvasController.offset.dy);
    if (canvasController.rotation != 0.0) {
      canvas.rotate(canvasController.rotation);
    }
    canvas.scale(canvasController.scale);

    for (final entry in displacements.entries) {
      final cluster = clusterMap[entry.key];
      if (cluster == null) continue;

      final displacement = entry.value;

      // Skip tiny displacements (visual noise)
      if (displacement.distance < 2.0) continue;

      // 🎨 Distance-based opacity: closer = more opaque, farther = more transparent
      final distanceRatio = (displacement.distance / _maxDisplacementForOpacity)
          .clamp(0.0, 1.0);
      final clusterOpacity =
          (0.6 - distanceRatio * 0.4).clamp(0.1, 0.6) * globalOpacity;
      final amberColor = Color.fromRGBO(255, 152, 0, clusterOpacity);

      canvas.save();
      canvas.translate(displacement.dx, displacement.dy);

      // 🖊️ Render strokes
      for (final strokeId in cluster.strokeIds) {
        final stroke = strokeMap[strokeId];
        if (stroke == null) continue;

        BrushEngine.renderStroke(
          canvas,
          stroke.points,
          amberColor,
          stroke.baseWidth,
          stroke.penType,
          stroke.settings,
        );
      }

      // 🔷 Render shapes as outlined rectangles
      for (final shapeId in cluster.shapeIds) {
        final shape = shapeMap[shapeId];
        if (shape == null) continue;

        final shapeBounds = Rect.fromPoints(shape.startPoint, shape.endPoint);
        final shapePaint =
            Paint()
              ..color = amberColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;
        canvas.drawRect(shapeBounds, shapePaint);
      }

      // 📝 Render text/image clusters as dashed bound outlines
      if (cluster.textIds.isNotEmpty || cluster.imageIds.isNotEmpty) {
        final boundPaint =
            Paint()
              ..color = amberColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5;
        final rrect = RRect.fromRectAndRadius(
          cluster.bounds,
          const Radius.circular(4),
        );
        canvas.drawRRect(rrect, boundPaint);
      }

      canvas.restore();

      // ➡️ Direction arrow at cluster bounds edge
      _drawDirectionArrow(canvas, cluster.bounds, displacement, amberColor);
    }

    canvas.restore();
  }

  /// Draws a small arrow from the cluster center pointing in the
  /// displacement direction, showing where the cluster will move.
  void _drawDirectionArrow(
    Canvas canvas,
    Rect clusterBounds,
    Offset displacement,
    Color color,
  ) {
    final center = clusterBounds.center;
    final direction = displacement / displacement.distance;
    final arrowStart = center;
    final arrowEnd =
        center + direction * (displacement.distance * 0.5).clamp(10.0, 40.0);

    final arrowPaint =
        Paint()
          ..color = color.withValues(
            alpha: color.a * 1.5,
          ) // Slightly more visible
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;

    // Shaft
    canvas.drawLine(arrowStart, arrowEnd, arrowPaint);

    // Arrowhead
    final angle = atan2(direction.dy, direction.dx);
    final headA =
        arrowEnd -
        Offset(cos(angle - 0.5) * _arrowSize, sin(angle - 0.5) * _arrowSize);
    final headB =
        arrowEnd -
        Offset(cos(angle + 0.5) * _arrowSize, sin(angle + 0.5) * _arrowSize);
    canvas.drawLine(arrowEnd, headA, arrowPaint);
    canvas.drawLine(arrowEnd, headB, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _ReflowGhostPainter oldDelegate) {
    return displacements != oldDelegate.displacements ||
        globalOpacity != oldDelegate.globalOpacity;
  }
}
