import 'dart:ui';
import 'dart:math' as math;
import './vector_path.dart';

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

    final PathOperation flutterOp;
    switch (operation) {
      case BooleanOpType.union:
        flutterOp = PathOperation.union;
      case BooleanOpType.subtract:
        flutterOp = PathOperation.difference;
      case BooleanOpType.intersect:
        flutterOp = PathOperation.intersect;
      case BooleanOpType.exclude:
        flutterOp = PathOperation.xor;
    }

    final resultFlutterPath = Path.combine(flutterOp, flutterA, flutterB);
    final resultVectorPath = _flutterPathToVectorPath(resultFlutterPath);

    return BooleanResult(
      resultPath: resultVectorPath,
      operation: operation,
      sourceAId: sourceAId,
      sourceBId: sourceBId,
    );
  }

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

  /// Check whether two paths overlap at all.
  ///
  /// Useful for validating before performing boolean ops.
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
    if (paths.isEmpty) return VectorPath(segments: []);
    if (paths.length == 1) return paths.first;

    Path result = paths.first.toFlutterPath();
    for (int i = 1; i < paths.length; i++) {
      result = Path.combine(
        PathOperation.union,
        result,
        paths[i].toFlutterPath(),
      );
    }
    return _flutterPathToVectorPath(result);
  }

  // ---------------------------------------------------------------------------
  // Flutter Path → VectorPath conversion
  // ---------------------------------------------------------------------------

  /// Convert a Flutter [Path] back to a [VectorPath].
  ///
  /// Uses [Path.computeMetrics] to extract contours and samples
  /// points along each contour to reconstruct line segments.
  static VectorPath _flutterPathToVectorPath(Path flutterPath) {
    final segments = <PathSegment>[];

    for (final metric in flutterPath.computeMetrics()) {
      final length = metric.length;
      if (length == 0) continue;

      // Sample the contour at regular intervals to create line segments.
      final sampleCount = math.max(8, (length / 4).ceil());
      Offset? firstPoint;
      Offset? prevPoint;

      for (int i = 0; i <= sampleCount; i++) {
        final t = i / sampleCount;
        final tangent = metric.getTangentForOffset(t * length);
        if (tangent == null) continue;

        final point = tangent.position;

        if (prevPoint == null) {
          // First point: emit a MoveSegment.
          segments.add(MoveSegment(endPoint: point));
          firstPoint = point;
        } else {
          // Subsequent points: emit LineSegments.
          segments.add(LineSegment(endPoint: point));
        }
        prevPoint = point;
      }

      // Close the contour if needed.
      if (metric.isClosed && firstPoint != null && prevPoint != null) {
        if ((prevPoint - firstPoint).distance > 1.0) {
          segments.add(LineSegment(endPoint: firstPoint));
        }
      }
    }

    return VectorPath(segments: segments, isClosed: true);
  }
}
