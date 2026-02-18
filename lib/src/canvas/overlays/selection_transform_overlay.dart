import 'dart:math';
import 'package:flutter/material.dart';
import '../../rendering/canvas/drawing_painter.dart';
import '../../tools/lasso/lasso_tool.dart';
import '../../reflow/content_cluster.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../drawing/brushes/brushes.dart';
import '../../core/models/shape_type.dart';
import '../infinite_canvas_controller.dart';

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

  const SelectionTransformOverlay({
    super.key,
    required this.lassoTool,
    required this.canvasController,
    required this.onTransformComplete,
    this.onEdgeAutoScroll,
    this.onEdgeAutoScrollEnd,
    this.isDark = false,
  });

  @override
  State<SelectionTransformOverlay> createState() =>
      _SelectionTransformOverlayState();
}

class _SelectionTransformOverlayState extends State<SelectionTransformOverlay>
    with SingleTickerProviderStateMixin {
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

  static const double _handleSize = 22.0;
  static const double _hitAreaSize = 48.0; // Minimum touch target
  static const double _rotationHandleOffset = 36.0;

  @override
  void initState() {
    super.initState();
    // 🚀 Follow canvas transform (zoom/pan/rotate) in real-time
    widget.canvasController.addListener(_onCanvasTransformChanged);
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
  }

  void _onCanvasTransformChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.canvasController.removeListener(_onCanvasTransformChanged);
    _settleController.dispose();
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
            onPanEnd: (_) {
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

      // Convert stable center from screen to canvas space for the lasso tool
      final canvasCenter = widget.canvasController.screenToCanvas(stableCenter);
      widget.lassoTool.rotateSelectedByAngle(angleDelta, center: canvasCenter);
      DrawingPainter.invalidateAllTiles();
      setState(() {});
      widget.onTransformComplete();
    } else {
      // Scala
      final currentDistance = (details.globalPosition - center).distance;
      if (_initialDistance > 0) {
        final scaleFactor = currentDistance / _initialDistance;
        // Clamp to avoid scale troppo estreme
        final clampedFactor = scaleFactor.clamp(0.5, 2.0);
        widget.lassoTool.scaleSelected(clampedFactor);
        _initialDistance = currentDistance;
        DrawingPainter.invalidateAllTiles();
        setState(() {});
        widget.onTransformComplete();
      }
    }
  }

  void _onHandleDragEnd() {
    _activeHandle = null;
    _dragStart = null;
    _rotationCenter = null;
    widget.onTransformComplete();
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
