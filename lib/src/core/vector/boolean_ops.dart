import 'dart:ui';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart' show Matrix4;
import './vector_path.dart';
import './vector_network.dart';
import './exact_boolean_ops.dart';
import '../scene_graph/canvas_node.dart';
import '../nodes/path_node.dart';
import '../nodes/shape_node.dart';
import '../nodes/vector_network_node.dart';
import '../vector/shape_presets.dart';
import '../models/shape_type.dart';

/// Type of boolean operation.
enum BooleanOpType {
  /// Combine both shapes into one outline.
  union,

  /// Remove the second shape from the first.
  subtract,

  /// Keep only the overlapping area.
  intersect,

  /// Keep everything except the overlapping area (XOR).
  exclude,
}

/// Result of a boolean operation.
///
/// Contains the resulting [VectorPath] and metadata about
/// the source paths and operation type.
class BooleanResult {
  /// The resulting path after the boolean operation.
  final VectorPath resultPath;

  /// The type of operation that produced this result.
  final BooleanOpType operation;

  /// IDs of the source paths/nodes used in this operation.
  final String sourceAId;
  final String sourceBId;

  const BooleanResult({
    required this.resultPath,
    required this.operation,
    required this.sourceAId,
    required this.sourceBId,
  });

  Map<String, dynamic> toJson() => {
    'operation': operation.name,
    'sourceA': sourceAId,
    'sourceB': sourceBId,
    'resultPath': resultPath.toJson(),
  };
}

/// Performs boolean operations on [VectorPath] objects.
///
/// Uses Flutter's built-in `Path.combine` for the heavy lifting,
/// then converts back to [VectorPath] representation.
///
/// ```dart
/// final result = BooleanOps.execute(
///   BooleanOpType.subtract,
///   pathA,
///   pathB,
///   sourceAId: 'shape1',
///   sourceBId: 'shape2',
/// );
/// // result.resultPath is the subtracted shape
/// ```
class BooleanOps {
  BooleanOps._();

  // ---------------------------------------------------------------------------
  // Core operations
  // ---------------------------------------------------------------------------

  /// Execute a boolean operation on two vector paths.
  ///
  /// Converts both [VectorPath]s to Flutter `Path` objects,
  /// applies the boolean combination, and converts the result
  /// back to a [VectorPath].
  static BooleanResult execute(
    BooleanOpType operation,
    VectorPath pathA,
    VectorPath pathB, {
    required String sourceAId,
    required String sourceBId,
  }) {
    final flutterA = pathA.toFlutterPath();
    final flutterB = pathB.toFlutterPath();

    final flutterOp = _toPathOperation(operation);
    final resultFlutterPath = Path.combine(flutterOp, flutterA, flutterB);
    final resultVectorPath = flutterPathToVectorPath(resultFlutterPath);

    return BooleanResult(
      resultPath: resultVectorPath,
      operation: operation,
      sourceAId: sourceAId,
      sourceBId: sourceBId,
    );
  }

  /// Execute a boolean operation on a raw Flutter [Path] pair.
  ///
  /// Lower-level than [execute] — skips VectorPath conversion on input.
  /// Useful when you already have Flutter paths (e.g., from nodes).
  static VectorPath executeOnFlutterPaths(
    BooleanOpType operation,
    Path pathA,
    Path pathB,
  ) {
    final flutterOp = _toPathOperation(operation);
    final result = Path.combine(flutterOp, pathA, pathB);
    return flutterPathToVectorPath(result);
  }

  /// Chain the same operation across multiple [VectorPath]s.
  ///
  /// E.g., `multiExecute(BooleanOpType.union, [a, b, c])` produces
  /// `union(union(a, b), c)`.
  ///
  /// Returns an empty path if [paths] is empty.
  static VectorPath multiExecute(
    BooleanOpType operation,
    List<VectorPath> paths,
  ) {
    if (paths.isEmpty) return VectorPath(segments: []);
    if (paths.length == 1) return paths.first;

    final flutterOp = _toPathOperation(operation);
    Path result = paths.first.toFlutterPath();

    for (int i = 1; i < paths.length; i++) {
      result = Path.combine(flutterOp, result, paths[i].toFlutterPath());
    }

    return flutterPathToVectorPath(result);
  }

  // ---------------------------------------------------------------------------
  // Convenience shortcuts
  // ---------------------------------------------------------------------------

  /// Union: combine both shapes into one outline.
  static BooleanResult union(
    VectorPath a,
    VectorPath b, {
    required String sourceAId,
    required String sourceBId,
  }) => execute(
    BooleanOpType.union,
    a,
    b,
    sourceAId: sourceAId,
    sourceBId: sourceBId,
  );

  /// Subtract: remove shape B from shape A.
  static BooleanResult subtract(
    VectorPath a,
    VectorPath b, {
    required String sourceAId,
    required String sourceBId,
  }) => execute(
    BooleanOpType.subtract,
    a,
    b,
    sourceAId: sourceAId,
    sourceBId: sourceBId,
  );

  /// Intersect: keep only the overlapping area.
  static BooleanResult intersect(
    VectorPath a,
    VectorPath b, {
    required String sourceAId,
    required String sourceBId,
  }) => execute(
    BooleanOpType.intersect,
    a,
    b,
    sourceAId: sourceAId,
    sourceBId: sourceBId,
  );

  /// Exclude: keep everything except the overlapping area (XOR).
  static BooleanResult exclude(
    VectorPath a,
    VectorPath b, {
    required String sourceAId,
    required String sourceBId,
  }) => execute(
    BooleanOpType.exclude,
    a,
    b,
    sourceAId: sourceAId,
    sourceBId: sourceBId,
  );

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  /// Check whether two paths overlap at all.
  ///
  /// Performs a fast bounding-box check first, then a precise path
  /// intersection check.
  static bool pathsOverlap(VectorPath a, VectorPath b) {
    final boundsA = a.computeBounds();
    final boundsB = b.computeBounds();
    if (!boundsA.overlaps(boundsB)) return false;

    // If bounding boxes overlap, check if intersection produces a non-empty path.
    final intersection = Path.combine(
      PathOperation.intersect,
      a.toFlutterPath(),
      b.toFlutterPath(),
    );
    return intersection.computeMetrics().any((m) => m.length > 0);
  }

  /// Flatten a list of paths into a single union path.
  ///
  /// Useful for merging multiple shapes into one outline.
  static VectorPath flattenUnion(List<VectorPath> paths) {
    return multiExecute(BooleanOpType.union, paths);
  }

  /// Convert any supported [CanvasNode] to a [VectorPath].
  ///
  /// Applies the node's world transform so the path is in scene coordinates.
  /// Supports [PathNode], [ShapeNode], and [VectorNetworkNode].
  ///
  /// Returns `null` for unsupported node types.
  static VectorPath? nodeToVectorPath(CanvasNode node) {
    VectorPath? local;

    if (node is PathNode) {
      local = node.path;
    } else if (node is ShapeNode) {
      local = _shapeToVectorPath(node.shape);
    } else if (node is VectorNetworkNode) {
      local = flutterPathToVectorPath(node.network.toFlutterPath());
    }

    if (local == null) return null;

    // Apply the node's world transform so path is in scene coordinates.
    final worldMatrix = node.worldTransform;
    final identity = Matrix4.identity();
    if (worldMatrix == identity) return local;
    return local.transformed(Float64List.fromList(worldMatrix.storage));
  }

  /// Execute a boolean operation on two [VectorNetwork]s.
  ///
  /// Uses [ExactBooleanOps] to preserve original Bézier curves where possible,
  /// falling back to sampling-based [Path.combine] for degenerate cases.
  static VectorNetwork executeOnNetworks(
    BooleanOpType operation,
    VectorNetwork a,
    VectorNetwork b,
  ) {
    return ExactBooleanOps.execute(operation, a, b);
  }

  /// Convert a [GeometricShape] to a [VectorPath] using [ShapePresets].
  static VectorPath _shapeToVectorPath(GeometricShape shape) {
    final bounds = Rect.fromPoints(shape.startPoint, shape.endPoint);
    switch (shape.type) {
      case ShapeType.rectangle:
        return ShapePresets.rectangle(bounds);
      case ShapeType.circle:
        return ShapePresets.ellipse(bounds);
      case ShapeType.triangle:
        return ShapePresets.triangle(bounds);
      case ShapeType.diamond:
        return ShapePresets.diamond(bounds);
      case ShapeType.pentagon:
        return ShapePresets.pentagon(bounds);
      case ShapeType.hexagon:
        return ShapePresets.hexagon(bounds);
      case ShapeType.star:
        return ShapePresets.star(bounds);
      case ShapeType.heart:
        return ShapePresets.heart(bounds);
      case ShapeType.arrow:
        return ShapePresets.arrow(shape.startPoint, shape.endPoint);
      case ShapeType.line:
        return ShapePresets.line(shape.startPoint, shape.endPoint);
      case ShapeType.freehand:
        // Freehand shapes don't have a preset — use bounding rect as fallback.
        return ShapePresets.rectangle(bounds);
    }
  }

  // ---------------------------------------------------------------------------
  // Flutter Path → VectorPath conversion (adaptive sampling)
  // ---------------------------------------------------------------------------

  /// Convert a Flutter [Path] back to a [VectorPath].
  ///
  /// Uses dense sampling along each contour via [Path.computeMetrics].
  /// Handles compound paths (multiple contours) by emitting a [MoveSegment]
  /// at the start of each contour.
  ///
  /// Applies collinear-point merging to reduce segment count for straight edges.
  static VectorPath flutterPathToVectorPath(Path flutterPath) {
    final segments = <PathSegment>[];

    for (final metric in flutterPath.computeMetrics()) {
      final length = metric.length;
      if (length == 0) continue;

      // Dense sampling — enough points for smooth curves, merged for lines.
      final sampleCount = math.max(12, (length / 2).ceil());
      final points = <Offset>[];

      for (int i = 0; i <= sampleCount; i++) {
        final dist = (i / sampleCount) * length;
        final tangent = metric.getTangentForOffset(dist);
        if (tangent == null) continue;
        points.add(tangent.position);
      }

      if (points.isEmpty) continue;

      // Emit segments with collinear merging.
      segments.add(MoveSegment(endPoint: points.first));

      for (int i = 1; i < points.length; i++) {
        final p = points[i];

        // Merge near-collinear consecutive segments.
        if (i >= 2) {
          final prev = points[i - 1];
          final prevPrev = points[i - 2];
          if (_isCollinear(prevPrev, prev, p, tolerance: 0.8)) {
            if (segments.isNotEmpty && segments.last is LineSegment) {
              segments[segments.length - 1] = LineSegment(endPoint: p);
              continue;
            }
          }
        }

        segments.add(LineSegment(endPoint: p));
      }

      // Close contour.
      if (metric.isClosed && points.length > 1) {
        final first = points.first;
        final last = points.last;
        if ((last - first).distance > 0.5) {
          segments.add(LineSegment(endPoint: first));
        }
      }
    }

    return VectorPath(segments: segments, isClosed: true);
  }

  /// Check if three points are approximately collinear.
  static bool _isCollinear(
    Offset a,
    Offset b,
    Offset c, {
    double tolerance = 1.0,
  }) {
    // Cross-product magnitude — 0 means perfectly collinear.
    final cross = (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
    return cross.abs() < tolerance;
  }

  /// Map [BooleanOpType] to Flutter's [PathOperation].
  static PathOperation _toPathOperation(BooleanOpType op) {
    switch (op) {
      case BooleanOpType.union:
        return PathOperation.union;
      case BooleanOpType.subtract:
        return PathOperation.difference;
      case BooleanOpType.intersect:
        return PathOperation.intersect;
      case BooleanOpType.exclude:
        return PathOperation.xor;
    }
  }
}
