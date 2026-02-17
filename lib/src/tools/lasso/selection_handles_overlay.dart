import 'package:flutter/material.dart';

/// The 8 handle positions on a bounding box.
enum HandlePosition {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Visual resize handles drawn on the corners and edge midpoints
/// of a selection bounding box.
///
/// The caller is responsible for converting handle drags into
/// scale/move operations on the [LassoTool].
class SelectionHandlesOverlay extends StatelessWidget {
  /// The selection bounding rectangle.
  final Rect bounds;

  /// Called when a handle drag starts.
  final void Function(HandlePosition position)? onDragStart;

  /// Called during handle drag with the delta.
  final void Function(HandlePosition position, Offset delta)? onDragUpdate;

  /// Called when a handle drag ends.
  final void Function(HandlePosition position)? onDragEnd;

  /// Size of each handle in logical pixels.
  final double handleSize;

  /// Handle fill color.
  final Color fillColor;

  /// Handle border color.
  final Color borderColor;

  const SelectionHandlesOverlay({
    super.key,
    required this.bounds,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.handleSize = 10.0,
    this.fillColor = Colors.white,
    this.borderColor = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children:
          HandlePosition.values.map((pos) {
            final offset = _handleOffset(pos);
            return Positioned(
              left: offset.dx - handleSize / 2,
              top: offset.dy - handleSize / 2,
              child: GestureDetector(
                onPanStart: (_) => onDragStart?.call(pos),
                onPanUpdate:
                    (details) => onDragUpdate?.call(pos, details.delta),
                onPanEnd: (_) => onDragEnd?.call(pos),
                child: Container(
                  width: handleSize,
                  height: handleSize,
                  decoration: BoxDecoration(
                    color: fillColor,
                    border: Border.all(color: borderColor, width: 1.5),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  Offset _handleOffset(HandlePosition pos) {
    switch (pos) {
      case HandlePosition.topLeft:
        return bounds.topLeft;
      case HandlePosition.topCenter:
        return Offset(bounds.center.dx, bounds.top);
      case HandlePosition.topRight:
        return bounds.topRight;
      case HandlePosition.middleLeft:
        return Offset(bounds.left, bounds.center.dy);
      case HandlePosition.middleRight:
        return Offset(bounds.right, bounds.center.dy);
      case HandlePosition.bottomLeft:
        return bounds.bottomLeft;
      case HandlePosition.bottomCenter:
        return Offset(bounds.center.dx, bounds.bottom);
      case HandlePosition.bottomRight:
        return bounds.bottomRight;
    }
  }

  /// Convert a handle drag delta into a scale factor relative to the
  /// selection bounds. Returns (scaleX, scaleY, newCenter).
  static ({double sx, double sy, Offset anchor}) deltaToScale(
    HandlePosition position,
    Offset delta,
    Rect bounds,
  ) {
    final w = bounds.width;
    final h = bounds.height;

    switch (position) {
      case HandlePosition.topLeft:
        return (
          sx: (w - delta.dx) / w,
          sy: (h - delta.dy) / h,
          anchor: bounds.bottomRight,
        );
      case HandlePosition.topCenter:
        return (
          sx: 1.0,
          sy: (h - delta.dy) / h,
          anchor: Offset(bounds.center.dx, bounds.bottom),
        );
      case HandlePosition.topRight:
        return (
          sx: (w + delta.dx) / w,
          sy: (h - delta.dy) / h,
          anchor: bounds.bottomLeft,
        );
      case HandlePosition.middleLeft:
        return (
          sx: (w - delta.dx) / w,
          sy: 1.0,
          anchor: Offset(bounds.right, bounds.center.dy),
        );
      case HandlePosition.middleRight:
        return (
          sx: (w + delta.dx) / w,
          sy: 1.0,
          anchor: Offset(bounds.left, bounds.center.dy),
        );
      case HandlePosition.bottomLeft:
        return (
          sx: (w - delta.dx) / w,
          sy: (h + delta.dy) / h,
          anchor: bounds.topRight,
        );
      case HandlePosition.bottomCenter:
        return (
          sx: 1.0,
          sy: (h + delta.dy) / h,
          anchor: Offset(bounds.center.dx, bounds.top),
        );
      case HandlePosition.bottomRight:
        return (
          sx: (w + delta.dx) / w,
          sy: (h + delta.dy) / h,
          anchor: bounds.topLeft,
        );
    }
  }
}
