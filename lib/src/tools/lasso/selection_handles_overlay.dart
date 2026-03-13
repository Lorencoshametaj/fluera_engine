import 'dart:math';
import 'package:flutter/material.dart';
import 'lasso_tool.dart';


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
/// of a selection bounding box, with optional rotation handle and
/// transform mode support.
///
/// The caller is responsible for converting handle drags into
/// scale/move operations on the [LassoTool].
class SelectionHandlesOverlay extends StatelessWidget {
  /// The selection bounding rectangle.
  final Rect bounds;

  /// Current transform mode (affects handle behavior).
  final TransformMode transformMode;

  /// Called when a handle drag starts.
  final void Function(HandlePosition position)? onDragStart;

  /// Called during handle drag with the delta.
  final void Function(HandlePosition position, Offset delta)? onDragUpdate;

  /// Called when a handle drag ends.
  final void Function(HandlePosition position)? onDragEnd;

  /// Called during rotation drag with the angle delta in radians.
  final void Function(double angleDelta)? onRotate;

  /// Called when rotation drag starts.
  final VoidCallback? onRotateStart;

  /// Called when rotation drag ends.
  final VoidCallback? onRotateEnd;

  /// Size of each handle in logical pixels.
  final double handleSize;

  /// Handle fill color.
  final Color fillColor;

  /// Handle border color.
  final Color borderColor;

  /// Whether to show the rotation handle.
  final bool showRotationHandle;

  const SelectionHandlesOverlay({
    super.key,
    required this.bounds,
    this.transformMode = TransformMode.uniform,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onRotate,
    this.onRotateStart,
    this.onRotateEnd,
    this.handleSize = 10.0,
    this.fillColor = Colors.white,
    this.borderColor = Colors.blue,
    this.showRotationHandle = true,
  });

  @override
  Widget build(BuildContext context) {
    final handles = <Widget>[];

    // Determine which handles to show based on transform mode
    final positions = transformMode == TransformMode.distort
        ? _cornerPositions  // Distort mode: only corners
        : HandlePosition.values; // All 8 handles

    for (final pos in positions) {
      final offset = _handleOffset(pos);
      final isCorner = _cornerPositions.contains(pos);
      final cursor = _cursorForPosition(pos);

      handles.add(
        Positioned(
          left: offset.dx - handleSize / 2,
          top: offset.dy - handleSize / 2,
          child: MouseRegion(
            cursor: cursor,
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
                  borderRadius: isCorner
                      ? BorderRadius.circular(2)
                      : BorderRadius.circular(handleSize / 2),
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
          ),
        ),
      );
    }

    // Rotation handle (circular button above top-center)
    if (showRotationHandle) {
      handles.add(_buildRotationHandle());
    }

    return Stack(children: handles);
  }

  /// Build the rotation handle — positioned above the top-center of bounds.
  Widget _buildRotationHandle() {
    const rotationHandleDistance = 28.0;
    final centerX = bounds.center.dx;
    final top = bounds.top - rotationHandleDistance;
    final rotHandleSize = handleSize + 4;

    return Positioned(
      left: centerX - rotHandleSize / 2,
      top: top - rotHandleSize / 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Connecting line from bounding box to rotation handle
          // (painted via the overlay painter, not here)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onPanStart: (_) => onRotateStart?.call(),
              onPanUpdate: (details) {
                if (onRotate == null) return;
                // Compute angle delta from the center of the selection
                final center = bounds.center;
                final prevPos = Offset(centerX, top) - details.delta;
                final currPos = Offset(centerX, top);
                final prevAngle = atan2(
                  prevPos.dy - center.dy,
                  prevPos.dx - center.dx,
                );
                final currAngle = atan2(
                  currPos.dy - center.dy,
                  currPos.dx - center.dx,
                );
                onRotate!(currAngle - prevAngle);
              },
              onPanEnd: (_) => onRotateEnd?.call(),
              child: Container(
                width: rotHandleSize,
                height: rotHandleSize,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.rotate_right_rounded,
                  size: rotHandleSize - 6,
                  color: borderColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _cornerPositions = [
    HandlePosition.topLeft,
    HandlePosition.topRight,
    HandlePosition.bottomLeft,
    HandlePosition.bottomRight,
  ];

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

  /// Get the appropriate mouse cursor for each handle position.
  MouseCursor _cursorForPosition(HandlePosition pos) {
    switch (pos) {
      case HandlePosition.topLeft:
      case HandlePosition.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case HandlePosition.topRight:
      case HandlePosition.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
      case HandlePosition.topCenter:
      case HandlePosition.bottomCenter:
        return SystemMouseCursors.resizeUpDown;
      case HandlePosition.middleLeft:
      case HandlePosition.middleRight:
        return SystemMouseCursors.resizeLeftRight;
    }
  }

  /// Convert a handle drag delta into a scale factor relative to the
  /// selection bounds. Returns (scaleX, scaleY, newCenter).
  ///
  /// When [mode] is [TransformMode.uniform], corner handles enforce
  /// proportional scaling. When [TransformMode.freeform], each axis
  /// scales independently.
  static ({double sx, double sy, Offset anchor}) deltaToScale(
    HandlePosition position,
    Offset delta,
    Rect bounds, {
    TransformMode mode = TransformMode.uniform,
  }) {
    final w = bounds.width;
    final h = bounds.height;

    double sx, sy;
    Offset anchor;

    switch (position) {
      case HandlePosition.topLeft:
        sx = (w - delta.dx) / w;
        sy = (h - delta.dy) / h;
        anchor = bounds.bottomRight;
      case HandlePosition.topCenter:
        sx = 1.0;
        sy = (h - delta.dy) / h;
        anchor = Offset(bounds.center.dx, bounds.bottom);
      case HandlePosition.topRight:
        sx = (w + delta.dx) / w;
        sy = (h - delta.dy) / h;
        anchor = bounds.bottomLeft;
      case HandlePosition.middleLeft:
        sx = (w - delta.dx) / w;
        sy = 1.0;
        anchor = Offset(bounds.right, bounds.center.dy);
      case HandlePosition.middleRight:
        sx = (w + delta.dx) / w;
        sy = 1.0;
        anchor = Offset(bounds.left, bounds.center.dy);
      case HandlePosition.bottomLeft:
        sx = (w - delta.dx) / w;
        sy = (h + delta.dy) / h;
        anchor = bounds.topRight;
      case HandlePosition.bottomCenter:
        sx = 1.0;
        sy = (h + delta.dy) / h;
        anchor = Offset(bounds.center.dx, bounds.top);
      case HandlePosition.bottomRight:
        sx = (w + delta.dx) / w;
        sy = (h + delta.dy) / h;
        anchor = bounds.topLeft;
    }

    // Enforce uniform scaling for corner handles in uniform mode
    if (mode == TransformMode.uniform &&
        _isCorner(position)) {
      final uniformScale = (sx + sy) / 2;
      sx = uniformScale;
      sy = uniformScale;
    }

    return (sx: sx, sy: sy, anchor: anchor);
  }

  static bool _isCorner(HandlePosition pos) {
    return pos == HandlePosition.topLeft ||
        pos == HandlePosition.topRight ||
        pos == HandlePosition.bottomLeft ||
        pos == HandlePosition.bottomRight;
  }
}

