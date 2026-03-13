part of 'lasso_tool.dart';

// =============================================================================
// Transform Modes
// =============================================================================

/// Mode for handle-based transforms.
enum TransformMode {
  /// Uniform scale — corner handles scale proportionally.
  uniform,

  /// Freeform scale — corner handles scale independently on X and Y.
  freeform,

  /// Distort — corner handles move independently (perspective deformation).
  distort,
}

// =============================================================================
// LassoTool — Transforms (professional-grade)
// =============================================================================

extension LassoTransforms on LassoTool {
  /// Rotate selected elements 90° clockwise.
  void _rotateSelected90() {
    if (!hasSelection) return;
    selectionManager.rotateAll(pi / 2);
    _calculateSelectionBounds();
  }

  /// Rotate selected elements by an arbitrary angle in radians.
  void _rotateSelectedByAngle(double radians, {Offset? center}) {
    if (!hasSelection) return;
    selectionManager.rotateAll(radians);
    _calculateSelectionBounds();
  }

  /// Scale selected elements by a uniform factor.
  void _scaleSelected(double factor, {Offset? center}) {
    if (!hasSelection) return;
    selectionManager.scaleAll(factor, factor);
    _calculateSelectionBounds();
  }

  /// Flip selected elements horizontally around the selection center.
  void _flipHorizontal() {
    if (!hasSelection) return;
    selectionManager.flipHorizontal();
    _calculateSelectionBounds();
  }

  /// Flip selected elements vertically around the selection center.
  void _flipVertical() {
    if (!hasSelection) return;
    selectionManager.flipVertical();
    _calculateSelectionBounds();
  }

  // ===========================================================================
  // Freeform Scale (non-uniform)
  // ===========================================================================

  /// Scale selected elements non-uniformly by [sx] and [sy].
  ///
  /// For StrokeNodes, this scales the actual point data independently per axis.
  /// For other nodes, this uses localTransform-based scaling.
  void _freeformScale(double sx, double sy, {Offset? anchor}) {
    if (!hasSelection) return;

    final pivot = anchor ?? selectionManager.aggregateCenter;

    for (final node in selectionManager.selectedNodes) {
      if (node.isLocked) continue;

      if (node is StrokeNode) {
        // Scale stroke points independently per axis
        final scaledPoints = node.stroke.points.map((p) {
          final dx = pivot.dx + (p.position.dx - pivot.dx) * sx;
          final dy = pivot.dy + (p.position.dy - pivot.dy) * sy;
          return p.copyWith(position: Offset(dx, dy));
        }).toList();

        // Scale width by the average of sx/sy for reasonable stroke thickness
        final avgScale = (sx.abs() + sy.abs()) / 2;
        final scaledWidth = node.stroke.baseWidth * avgScale;

        node.stroke = node.stroke.copyWith(
          points: scaledPoints,
          baseWidth: scaledWidth.clamp(0.5, 200.0),
        );
        node.localTransform = Matrix4.identity();
        node.invalidateTransformCache();
      } else {
        node.scaleFrom(sx, sy, pivot);
      }
    }
    _selectionBounds = null;
  }

  // ===========================================================================
  // Distort (4-corner perspective deformation)
  // ===========================================================================

  /// Distort the selection by mapping it to a new quadrilateral defined
  /// by [corners] (TL, TR, BR, BL in canvas space).
  ///
  /// This computes a perspective transform from the current selection
  /// bounding box to the destination quad and applies it to all selected
  /// elements.
  void _distort(List<Offset> corners) {
    if (!hasSelection || corners.length != 4) return;

    final bounds = selectionManager.aggregateBounds;
    if (bounds == Rect.zero || bounds.isEmpty) return;

    // Source quad: the current selection bounding box
    final src = [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ];

    for (final node in selectionManager.selectedNodes) {
      if (node.isLocked) continue;

      if (node is StrokeNode) {
        // Map each point from source rect to destination quad
        final distortedPoints = node.stroke.points.map((p) {
          final mapped = _bilinearMap(p.position, bounds, corners);
          return p.copyWith(position: mapped);
        }).toList();

        node.stroke = node.stroke.copyWith(points: distortedPoints);
        node.localTransform = Matrix4.identity();
        node.invalidateTransformCache();
      } else {
        // For non-stroke nodes, compute an affine approximation
        // Map node center from source space to destination space
        final nodeCenter = node.worldBounds.center;
        final mapped = _bilinearMap(nodeCenter, bounds, corners);
        final dx = mapped.dx - nodeCenter.dx;
        final dy = mapped.dy - nodeCenter.dy;

        // Approximate scale from the diagonal ratios
        final srcDiag = (src[2] - src[0]).distance;
        final dstDiag = (corners[2] - corners[0]).distance;
        final scaleFactor = srcDiag > 0 ? dstDiag / srcDiag : 1.0;

        node.translate(dx, dy);
        if ((scaleFactor - 1.0).abs() > 0.01) {
          node.scaleFrom(scaleFactor, scaleFactor, mapped);
        }
      }
    }
    _selectionBounds = null;
  }

  /// Bilinear interpolation mapping a point from [srcRect] to a
  /// destination quadrilateral [dstCorners] (TL, TR, BR, BL).
  ///
  /// This is the standard bilinear quad mapping used in texture mapping.
  Offset _bilinearMap(Offset point, Rect srcRect, List<Offset> dst) {
    // Normalize the point within the source rect to [0,1] × [0,1]
    final u = srcRect.width > 0
        ? (point.dx - srcRect.left) / srcRect.width
        : 0.0;
    final v = srcRect.height > 0
        ? (point.dy - srcRect.top) / srcRect.height
        : 0.0;

    // Bilinear interpolation:
    // P = (1-u)(1-v)*TL + u*(1-v)*TR + u*v*BR + (1-u)*v*BL
    final tl = dst[0]; // top-left
    final tr = dst[1]; // top-right
    final br = dst[2]; // bottom-right
    final bl = dst[3]; // bottom-left

    final x = (1 - u) * (1 - v) * tl.dx +
        u * (1 - v) * tr.dx +
        u * v * br.dx +
        (1 - u) * v * bl.dx;
    final y = (1 - u) * (1 - v) * tl.dy +
        u * (1 - v) * tr.dy +
        u * v * br.dy +
        (1 - u) * v * bl.dy;

    return Offset(x, y);
  }

  // ===========================================================================
  // Rotation Snapping (Procreate-style 15°/45°/90° detents)
  // ===========================================================================

  /// Standard rotation detents in radians.
  static const List<double> _rotationDetents = [
    0,
    pi / 12,     // 15°
    pi / 6,      // 30°
    pi / 4,      // 45°
    pi / 3,      // 60°
    5 * pi / 12, // 75°
    pi / 2,      // 90°
    7 * pi / 12, // 105°
    2 * pi / 3,  // 120°
    3 * pi / 4,  // 135°
    5 * pi / 6,  // 150°
    11 * pi / 12,// 165°
    pi,          // 180°
  ];

  /// Snap angle threshold in radians (~3°).
  static const double _snapThreshold = pi / 60;

  /// Snap an angle to the nearest rotation detent if within threshold.
  ///
  /// Returns the snapped angle, or the original if no detent is close enough.
  /// Covers the full ±π range by checking both positive and negative detents.
  double _snapRotation(double radians) {
    // Normalize to [-π, π]
    double normalized = radians % (2 * pi);
    if (normalized > pi) normalized -= 2 * pi;
    if (normalized < -pi) normalized += 2 * pi;

    for (final detent in _rotationDetents) {
      // Check positive and negative
      if ((normalized - detent).abs() < _snapThreshold) return detent;
      if ((normalized + detent).abs() < _snapThreshold) return -detent;
    }
    return radians;
  }

  /// Rotate selected elements with snap-to-detent support.
  ///
  /// When [snap] is true, the angle is snapped to 15° detents.
  void _rotateWithSnap(double radians, {bool snap = true}) {
    if (!hasSelection) return;
    final finalAngle = snap ? _snapRotation(radians) : radians;
    selectionManager.rotateAll(finalAngle);
    _calculateSelectionBounds();
  }

  // ===========================================================================
  // Transform Edge Magnetics (snap to canvas edges / center)
  // ===========================================================================

  /// Magnetic snap threshold in canvas points.
  static const double _magneticThreshold = 8.0;

  /// Snap a movement delta to align with canvas edges or center.
  ///
  /// Returns the adjusted delta with snapping applied. The [canvasSize]
  /// is the size of the visible canvas area. [selectionBounds] are the
  /// current screen-space bounds of the selection.
  Offset _snapToEdges(
    Offset delta,
    Rect selectionBounds,
    Size canvasSize,
  ) {
    double adjustedDx = delta.dx;
    double adjustedDy = delta.dy;

    final newBounds = selectionBounds.shift(delta);
    final centerX = canvasSize.width / 2;
    final centerY = canvasSize.height / 2;

    // Horizontal snapping
    if ((newBounds.left).abs() < _magneticThreshold) {
      adjustedDx = -selectionBounds.left;
    } else if ((newBounds.right - canvasSize.width).abs() < _magneticThreshold) {
      adjustedDx = canvasSize.width - selectionBounds.right;
    } else if ((newBounds.center.dx - centerX).abs() < _magneticThreshold) {
      adjustedDx = centerX - selectionBounds.center.dx;
    }

    // Vertical snapping
    if ((newBounds.top).abs() < _magneticThreshold) {
      adjustedDy = -selectionBounds.top;
    } else if ((newBounds.bottom - canvasSize.height).abs() < _magneticThreshold) {
      adjustedDy = canvasSize.height - selectionBounds.bottom;
    } else if ((newBounds.center.dy - centerY).abs() < _magneticThreshold) {
      adjustedDy = centerY - selectionBounds.center.dy;
    }

    return Offset(adjustedDx, adjustedDy);
  }
}
