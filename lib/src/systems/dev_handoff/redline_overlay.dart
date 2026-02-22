/// 📏 REDLINE CALCULATOR — Dimension and spacing measurements for dev handoff.
///
/// Computes spacing lines, dimension annotations, and padding measurements
/// between nodes for design specification overlays.
library;

import 'dart:ui';
import '../../core/scene_graph/canvas_node.dart';
import '../../core/nodes/frame_node.dart';

/// A dimension annotation with label position.
class DimensionAnnotation {
  final String label;
  final Offset start;
  final Offset end;
  final bool isHorizontal;

  const DimensionAnnotation({
    required this.label,
    required this.start,
    required this.end,
    required this.isHorizontal,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'start': {'x': start.dx, 'y': start.dy},
    'end': {'x': end.dx, 'y': end.dy},
    'isHorizontal': isHorizontal,
  };
}

/// Spacing from a node to its parent edges.
class ParentSpacing {
  final double top;
  final double right;
  final double bottom;
  final double left;

  const ParentSpacing({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  Map<String, dynamic> toJson() => {
    'top': top,
    'right': right,
    'bottom': bottom,
    'left': left,
  };
}

/// Calculates dimension and spacing annotations for developer handoff.
class RedlineCalculator {
  const RedlineCalculator();

  /// Compute width and height annotations for a node.
  List<DimensionAnnotation> dimensionAnnotations(CanvasNode node) {
    final bounds = node.worldBounds;
    return [
      // Width annotation (below the node).
      DimensionAnnotation(
        label: '${bounds.width.toStringAsFixed(0)}',
        start: Offset(bounds.left, bounds.bottom + 8),
        end: Offset(bounds.right, bounds.bottom + 8),
        isHorizontal: true,
      ),
      // Height annotation (to the right of the node).
      DimensionAnnotation(
        label: '${bounds.height.toStringAsFixed(0)}',
        start: Offset(bounds.right + 8, bounds.top),
        end: Offset(bounds.right + 8, bounds.bottom),
        isHorizontal: false,
      ),
    ];
  }

  /// Measure spacing between two nodes along both axes.
  List<DimensionAnnotation> spacingAnnotations(CanvasNode a, CanvasNode b) {
    final boundsA = a.worldBounds;
    final boundsB = b.worldBounds;
    final annotations = <DimensionAnnotation>[];

    // Horizontal spacing.
    if (boundsA.right <= boundsB.left) {
      final gap = boundsB.left - boundsA.right;
      final midY = (boundsA.center.dy + boundsB.center.dy) / 2;
      annotations.add(
        DimensionAnnotation(
          label: '${gap.toStringAsFixed(0)}',
          start: Offset(boundsA.right, midY),
          end: Offset(boundsB.left, midY),
          isHorizontal: true,
        ),
      );
    } else if (boundsB.right <= boundsA.left) {
      final gap = boundsA.left - boundsB.right;
      final midY = (boundsA.center.dy + boundsB.center.dy) / 2;
      annotations.add(
        DimensionAnnotation(
          label: '${gap.toStringAsFixed(0)}',
          start: Offset(boundsB.right, midY),
          end: Offset(boundsA.left, midY),
          isHorizontal: true,
        ),
      );
    }

    // Vertical spacing.
    if (boundsA.bottom <= boundsB.top) {
      final gap = boundsB.top - boundsA.bottom;
      final midX = (boundsA.center.dx + boundsB.center.dx) / 2;
      annotations.add(
        DimensionAnnotation(
          label: '${gap.toStringAsFixed(0)}',
          start: Offset(midX, boundsA.bottom),
          end: Offset(midX, boundsB.top),
          isHorizontal: false,
        ),
      );
    } else if (boundsB.bottom <= boundsA.top) {
      final gap = boundsA.top - boundsB.bottom;
      final midX = (boundsA.center.dx + boundsB.center.dx) / 2;
      annotations.add(
        DimensionAnnotation(
          label: '${gap.toStringAsFixed(0)}',
          start: Offset(midX, boundsB.bottom),
          end: Offset(midX, boundsA.top),
          isHorizontal: false,
        ),
      );
    }

    return annotations;
  }

  /// Measure spacing from a node to its parent bounds.
  ParentSpacing? measureToParent(CanvasNode node) {
    final parent = node.parent;
    if (parent == null) return null;

    final childBounds = node.worldBounds;
    final parentBounds = parent.worldBounds;

    return ParentSpacing(
      top: childBounds.top - parentBounds.top,
      right: parentBounds.right - childBounds.right,
      bottom: parentBounds.bottom - childBounds.bottom,
      left: childBounds.left - parentBounds.left,
    );
  }

  /// Generate spacing annotations from a node to its parent edges.
  List<DimensionAnnotation> parentSpacingAnnotations(CanvasNode node) {
    final spacing = measureToParent(node);
    if (spacing == null) return [];

    final bounds = node.worldBounds;
    final parentBounds = node.parent!.worldBounds;
    final annotations = <DimensionAnnotation>[];

    if (spacing.top > 0) {
      annotations.add(
        DimensionAnnotation(
          label: '${spacing.top.toStringAsFixed(0)}',
          start: Offset(bounds.center.dx, parentBounds.top),
          end: Offset(bounds.center.dx, bounds.top),
          isHorizontal: false,
        ),
      );
    }
    if (spacing.bottom > 0) {
      annotations.add(
        DimensionAnnotation(
          label: '${spacing.bottom.toStringAsFixed(0)}',
          start: Offset(bounds.center.dx, bounds.bottom),
          end: Offset(bounds.center.dx, parentBounds.bottom),
          isHorizontal: false,
        ),
      );
    }
    if (spacing.left > 0) {
      annotations.add(
        DimensionAnnotation(
          label: '${spacing.left.toStringAsFixed(0)}',
          start: Offset(parentBounds.left, bounds.center.dy),
          end: Offset(bounds.left, bounds.center.dy),
          isHorizontal: true,
        ),
      );
    }
    if (spacing.right > 0) {
      annotations.add(
        DimensionAnnotation(
          label: '${spacing.right.toStringAsFixed(0)}',
          start: Offset(bounds.right, bounds.center.dy),
          end: Offset(parentBounds.right, bounds.center.dy),
          isHorizontal: true,
        ),
      );
    }

    return annotations;
  }
}
