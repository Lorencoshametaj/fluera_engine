import 'dart:math' as math;
import 'dart:ui';
import '../core/scene_graph/canvas_node.dart';

/// Type of snap guide.
enum SnapGuideType {
  /// Edge-to-edge alignment with another node.
  edgeAlignment,

  /// Center-to-center alignment.
  centerAlignment,

  /// Equal spacing between 3+ nodes.
  equalSpacing,

  /// Grid line snap.
  gridSnap,

  /// Rotation constrained to fixed increments.
  angleSnap,

  /// Size matches another node's dimension.
  sizeMatch,
}

/// Axis of the snap guide.
enum SnapAxis { horizontal, vertical }

/// A single alignment guide produced by the snap engine.
class SnapGuide {
  /// Position of the guide line (in canvas coordinates).
  final double position;

  /// Axis of the guide.
  final SnapAxis axis;

  /// Type of snap this guide represents.
  final SnapGuideType type;

  /// ID of the reference node that generated this guide, if any.
  final String? referenceNodeId;

  const SnapGuide({
    required this.position,
    required this.axis,
    required this.type,
    this.referenceNodeId,
  });
}

/// Result from [SmartSnapEngine.calculateSnaps].
///
/// Contains the suggested offset adjustment and any active guide lines
/// that the UI should render as visual feedback.
class SnapResult {
  /// Horizontal guide lines (snap to vertical positions).
  final List<SnapGuide> horizontalGuides;

  /// Vertical guide lines (snap to horizontal positions).
  final List<SnapGuide> verticalGuides;

  /// Equal-spacing distribution guides.
  final List<SnapGuide> distributionGuides;

  /// Suggested offset to apply to the dragged node's position
  /// to achieve snapping. (0,0) if no snap is active.
  final Offset snapOffset;

  const SnapResult({
    this.horizontalGuides = const [],
    this.verticalGuides = const [],
    this.distributionGuides = const [],
    this.snapOffset = Offset.zero,
  });

  /// Whether any snapping is active.
  bool get hasSnap =>
      horizontalGuides.isNotEmpty ||
      verticalGuides.isNotEmpty ||
      distributionGuides.isNotEmpty;

  /// All guides combined.
  List<SnapGuide> get allGuides => [
    ...horizontalGuides,
    ...verticalGuides,
    ...distributionGuides,
  ];
}

// ---------------------------------------------------------------------------
// SmartSnapEngine
// ---------------------------------------------------------------------------

/// Calculates alignment and distribution snaps during interactive editing.
///
/// Usage:
/// ```dart
/// final engine = SmartSnapEngine();
/// final result = engine.calculateSnaps(draggedNode, otherNodes);
/// // Apply result.snapOffset to the node
/// // Draw result.allGuides as visual feedback
/// ```
class SmartSnapEngine {
  /// Distance threshold for snapping (in canvas pixels).
  /// Mutable so Conscious Architecture can adjust it at runtime without
  /// recreating the engine (avoids GC churn).
  double threshold;

  /// Grid spacing (0 = grid snap disabled).
  final double gridSpacing;

  /// Angle snap increment in degrees (0 = disabled).
  final double angleIncrement;

  SmartSnapEngine({
    this.threshold = 8.0,
    this.gridSpacing = 0.0,
    this.angleIncrement = 15.0,
  });

  /// Calculatate all active snaps for [dragged] relative to [others].
  SnapResult calculateSnaps(CanvasNode dragged, List<CanvasNode> others) {
    final dragBounds = dragged.worldBounds;
    final hGuides = <SnapGuide>[];
    final vGuides = <SnapGuide>[];
    final dGuides = <SnapGuide>[];
    double snapDx = 0;
    double snapDy = 0;

    // Track best distances to pick the closest snap.
    double bestHDist = threshold + 1;
    double bestVDist = threshold + 1;

    for (final other in others) {
      if (other.id == dragged.id || !other.isVisible) continue;
      final otherBounds = other.worldBounds;

      // --- Horizontal edge alignment ---
      final hEdges = _edgeSnaps(
        dragBounds,
        otherBounds,
        SnapAxis.horizontal,
        other.id,
      );
      for (final (guide, dist) in hEdges) {
        if (dist < bestHDist) {
          bestHDist = dist;
          snapDy = guide.position - _edgeValue(dragBounds, guide);
          hGuides
            ..clear()
            ..add(guide);
        } else if ((dist - bestHDist).abs() < 0.5) {
          hGuides.add(guide);
        }
      }

      // --- Vertical edge alignment ---
      final vEdges = _edgeSnaps(
        dragBounds,
        otherBounds,
        SnapAxis.vertical,
        other.id,
      );
      for (final (guide, dist) in vEdges) {
        if (dist < bestVDist) {
          bestVDist = dist;
          snapDx = guide.position - _edgeValue(dragBounds, guide);
          vGuides
            ..clear()
            ..add(guide);
        } else if ((dist - bestVDist).abs() < 0.5) {
          vGuides.add(guide);
        }
      }

      // --- Center alignment ---
      final cSnaps = _centerSnaps(dragBounds, otherBounds, other.id);
      for (final (guide, dist, axis) in cSnaps) {
        if (axis == SnapAxis.horizontal && dist < bestHDist) {
          bestHDist = dist;
          snapDy = guide.position - dragBounds.center.dy;
          hGuides
            ..clear()
            ..add(guide);
        } else if (axis == SnapAxis.vertical && dist < bestVDist) {
          bestVDist = dist;
          snapDx = guide.position - dragBounds.center.dx;
          vGuides
            ..clear()
            ..add(guide);
        }
      }
    }

    // --- Grid snap ---
    if (gridSpacing > 0) {
      final gridResult = _gridSnap(dragBounds);
      if (bestHDist > threshold && gridResult.dy.abs() <= threshold) {
        snapDy = gridResult.dy;
      }
      if (bestVDist > threshold && gridResult.dx.abs() <= threshold) {
        snapDx = gridResult.dx;
      }
    }

    // --- Equal spacing ---
    final eqResult = _findEqualSpacing(dragged, others);
    dGuides.addAll(eqResult);

    return SnapResult(
      horizontalGuides: hGuides,
      verticalGuides: vGuides,
      distributionGuides: dGuides,
      snapOffset: Offset(snapDx, snapDy),
    );
  }

  /// Snap a rotation angle to the nearest increment.
  double snapAngle(double radians) {
    if (angleIncrement <= 0) return radians;
    final degrees = radians * 180 / math.pi;
    final snapped = (degrees / angleIncrement).round() * angleIncrement;
    return snapped * math.pi / 180;
  }

  /// Check if [size] matches another node's dimension within threshold.
  SnapGuide? matchSize(Size size, CanvasNode other, SnapAxis axis) {
    final otherBounds = other.worldBounds;
    final otherSize =
        axis == SnapAxis.horizontal ? otherBounds.height : otherBounds.width;
    final mySize = axis == SnapAxis.horizontal ? size.height : size.width;

    if ((mySize - otherSize).abs() <= threshold) {
      return SnapGuide(
        position: otherSize,
        axis: axis,
        type: SnapGuideType.sizeMatch,
        referenceNodeId: other.id,
      );
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Find edge-to-edge alignment snaps between two bounding rects.
  List<(SnapGuide, double)> _edgeSnaps(
    Rect drag,
    Rect other,
    SnapAxis axis,
    String otherId,
  ) {
    final results = <(SnapGuide, double)>[];

    if (axis == SnapAxis.horizontal) {
      // Top-to-top, top-to-bottom, bottom-to-top, bottom-to-bottom
      _tryEdge(results, drag.top, other.top, axis, otherId);
      _tryEdge(results, drag.top, other.bottom, axis, otherId);
      _tryEdge(results, drag.bottom, other.top, axis, otherId);
      _tryEdge(results, drag.bottom, other.bottom, axis, otherId);
    } else {
      // Left-to-left, left-to-right, right-to-left, right-to-right
      _tryEdge(results, drag.left, other.left, axis, otherId);
      _tryEdge(results, drag.left, other.right, axis, otherId);
      _tryEdge(results, drag.right, other.left, axis, otherId);
      _tryEdge(results, drag.right, other.right, axis, otherId);
    }

    return results;
  }

  void _tryEdge(
    List<(SnapGuide, double)> results,
    double dragEdge,
    double otherEdge,
    SnapAxis axis,
    String otherId,
  ) {
    final dist = (dragEdge - otherEdge).abs();
    if (dist <= threshold) {
      results.add((
        SnapGuide(
          position: otherEdge,
          axis: axis,
          type: SnapGuideType.edgeAlignment,
          referenceNodeId: otherId,
        ),
        dist,
      ));
    }
  }

  double _edgeValue(Rect drag, SnapGuide guide) {
    if (guide.axis == SnapAxis.horizontal) {
      // Return the closest drag edge to the guide position.
      final topDist = (drag.top - guide.position).abs();
      final bottomDist = (drag.bottom - guide.position).abs();
      return topDist < bottomDist ? drag.top : drag.bottom;
    } else {
      final leftDist = (drag.left - guide.position).abs();
      final rightDist = (drag.right - guide.position).abs();
      return leftDist < rightDist ? drag.left : drag.right;
    }
  }

  /// Find center-to-center alignment snaps.
  List<(SnapGuide, double, SnapAxis)> _centerSnaps(
    Rect drag,
    Rect other,
    String otherId,
  ) {
    final results = <(SnapGuide, double, SnapAxis)>[];
    final hDist = (drag.center.dy - other.center.dy).abs();
    final vDist = (drag.center.dx - other.center.dx).abs();

    if (hDist <= threshold) {
      results.add((
        SnapGuide(
          position: other.center.dy,
          axis: SnapAxis.horizontal,
          type: SnapGuideType.centerAlignment,
          referenceNodeId: otherId,
        ),
        hDist,
        SnapAxis.horizontal,
      ));
    }
    if (vDist <= threshold) {
      results.add((
        SnapGuide(
          position: other.center.dx,
          axis: SnapAxis.vertical,
          type: SnapGuideType.centerAlignment,
          referenceNodeId: otherId,
        ),
        vDist,
        SnapAxis.vertical,
      ));
    }

    return results;
  }

  /// Grid snap — returns offset to nearest grid intersection.
  Offset _gridSnap(Rect drag) {
    final cx = drag.center.dx;
    final cy = drag.center.dy;
    final snappedX = (cx / gridSpacing).round() * gridSpacing;
    final snappedY = (cy / gridSpacing).round() * gridSpacing;
    return Offset(snappedX - cx, snappedY - cy);
  }

  /// Find equal-spacing distribution guides among nodes.
  List<SnapGuide> _findEqualSpacing(
    CanvasNode dragged,
    List<CanvasNode> others,
  ) {
    final guides = <SnapGuide>[];
    if (others.length < 2) return guides;

    final dragBounds = dragged.worldBounds;

    // Collect visible nodes sorted by center X and Y.
    final visibleOthers =
        others.where((n) => n.id != dragged.id && n.isVisible).toList();

    // Check horizontal distribution (left-to-right).
    _checkDistribution(
      guides,
      dragBounds,
      visibleOthers,
      SnapAxis.vertical,
      (r) => r.center.dx,
      (r) => r.width,
    );

    // Check vertical distribution (top-to-bottom).
    _checkDistribution(
      guides,
      dragBounds,
      visibleOthers,
      SnapAxis.horizontal,
      (r) => r.center.dy,
      (r) => r.height,
    );

    return guides;
  }

  void _checkDistribution(
    List<SnapGuide> guides,
    Rect drag,
    List<CanvasNode> others,
    SnapAxis axis,
    double Function(Rect) getCenter,
    double Function(Rect) getSize,
  ) {
    // Simplified: check if dragged node is between two others with equal gap.
    for (int i = 0; i < others.length; i++) {
      for (int j = i + 1; j < others.length; j++) {
        final a = others[i].worldBounds;
        final b = others[j].worldBounds;
        final ac = getCenter(a);
        final bc = getCenter(b);
        final dc = getCenter(drag);

        // Check if drag center is approximately midpoint of a and b.
        final midpoint = (ac + bc) / 2;
        final dist = (dc - midpoint).abs();

        if (dist <= threshold) {
          guides.add(
            SnapGuide(
              position: midpoint,
              axis: axis,
              type: SnapGuideType.equalSpacing,
            ),
          );
        }
      }
    }
  }
}
