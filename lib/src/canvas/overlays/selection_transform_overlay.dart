import 'dart:math';
import 'package:flutter/material.dart';
import '../../tools/lasso/lasso_tool.dart';
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
  final bool isDark;

  const SelectionTransformOverlay({
    super.key,
    required this.lassoTool,
    required this.canvasController,
    required this.onTransformComplete,
    this.isDark = false,
  });

  @override
  State<SelectionTransformOverlay> createState() =>
      _SelectionTransformOverlayState();
}

class _SelectionTransformOverlayState extends State<SelectionTransformOverlay> {
  // Handle attualmente trascinato
  _HandleType? _activeHandle;
  Offset? _dragStart;
  Offset? _rotationCenter; // Stable center captured at gesture start
  double _initialAngle = 0;
  double _initialDistance = 0;

  static const double _handleSize = 22.0;
  static const double _hitAreaSize = 48.0; // Minimum touch target
  static const double _rotationHandleOffset = 36.0;

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

    return Stack(
      children: [
        // Bounding box tratteggiato
        Positioned(
          left: screenBounds.left,
          top: screenBounds.top,
          width: screenBounds.width,
          height: screenBounds.height,
          child: CustomPaint(
            painter: _DashedBorderPainter(isDark: widget.isDark),
          ),
        ),

        // Handle angoli (scala proporzionale)
        _buildHandle(screenBounds.topLeft, _HandleType.topLeft, center),
        _buildHandle(screenBounds.topRight, _HandleType.topRight, center),
        _buildHandle(screenBounds.bottomLeft, _HandleType.bottomLeft, center),
        _buildHandle(screenBounds.bottomRight, _HandleType.bottomRight, center),

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
