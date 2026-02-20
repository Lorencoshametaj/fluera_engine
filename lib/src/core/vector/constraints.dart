import 'dart:ui';
import 'dart:math' as math;

import 'vector_network.dart';

// ---------------------------------------------------------------------------
// Geometric Constraint Types
// ---------------------------------------------------------------------------

/// Type of geometric constraint between vertices/segments.
enum ConstraintType {
  /// Constrains a segment to be horizontal (dy = 0).
  horizontal,

  /// Constrains a segment to be vertical (dx = 0).
  vertical,

  /// Constrains two segments to be parallel.
  parallel,

  /// Constrains two segments to be perpendicular.
  perpendicular,

  /// Constrains two segments to have equal length.
  equal,

  /// Constrains a vertex to lie on the tangent of another segment.
  tangent,

  /// Constrains two vertices to be at the same position.
  coincident,

  /// Constrains two vertices to be symmetric about a third vertex.
  symmetric,

  /// Constrains a segment to a fixed angle (in radians).
  fixedAngle,

  /// Constrains a segment to a fixed length.
  fixedLength,
}

// ---------------------------------------------------------------------------
// Geometric Constraint
// ---------------------------------------------------------------------------

/// A geometric constraint applied to vertices/segments in a [VectorNetwork].
///
/// ```dart
/// final c = GeometricConstraint(
///   type: ConstraintType.horizontal,
///   vertexIndices: [0, 1],
/// );
/// ```
class GeometricConstraint {
  /// The type of constraint.
  final ConstraintType type;

  /// Vertex indices involved in this constraint.
  final List<int> vertexIndices;

  /// Segment indices involved (for parallel, perpendicular, equal).
  final List<int> segmentIndices;

  /// Optional fixed value (angle in radians, or length in pixels).
  final double? value;

  GeometricConstraint({
    required this.type,
    this.vertexIndices = const [],
    this.segmentIndices = const [],
    this.value,
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'vertexIndices': vertexIndices,
    'segmentIndices': segmentIndices,
    if (value != null) 'value': value,
  };

  /// Deserialize from JSON.
  factory GeometricConstraint.fromJson(Map<String, dynamic> json) {
    return GeometricConstraint(
      type: ConstraintType.values.firstWhere((e) => e.name == json['type']),
      vertexIndices: (json['vertexIndices'] as List).cast<int>(),
      segmentIndices: (json['segmentIndices'] as List?)?.cast<int>() ?? [],
      value: (json['value'] as num?)?.toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// Constraint Solver
// ---------------------------------------------------------------------------

/// Iterative constraint solver for [VectorNetwork] using Gauss-Seidel
/// relaxation.
///
/// Each constraint projects affected vertices to satisfy it. The solver
/// iterates until all constraints are satisfied within tolerance or
/// max iterations are reached.
///
/// ```dart
/// final solver = ConstraintSolver(
///   network: myNetwork,
///   constraints: [horizontalConstraint, fixedLengthConstraint],
/// );
/// solver.solve();
/// ```
class ConstraintSolver {
  final VectorNetwork network;
  final List<GeometricConstraint> constraints;

  ConstraintSolver({required this.network, required this.constraints});

  /// Solve all constraints iteratively.
  ///
  /// Returns `true` if all constraints converged within [tolerance].
  bool solve({int maxIterations = 50, double tolerance = 0.01}) {
    for (int iter = 0; iter < maxIterations; iter++) {
      double maxError = 0;

      for (final c in constraints) {
        final error = _applyConstraint(c);
        maxError = math.max(maxError, error);
      }

      if (maxError < tolerance) {
        network.invalidate();
        return true;
      }
    }

    network.invalidate();
    return false;
  }

  /// Check which constraints are not satisfied within [tolerance].
  ///
  /// Returns indices of unsatisfied constraints.
  List<int> unsatisfiedConstraints({double tolerance = 0.1}) {
    final result = <int>[];
    for (int i = 0; i < constraints.length; i++) {
      if (_measureError(constraints[i]) > tolerance) {
        result.add(i);
      }
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Constraint application (projection)
  // -------------------------------------------------------------------------

  double _applyConstraint(GeometricConstraint c) {
    switch (c.type) {
      case ConstraintType.horizontal:
        return _applyHorizontal(c);
      case ConstraintType.vertical:
        return _applyVertical(c);
      case ConstraintType.parallel:
        return _applyParallel(c);
      case ConstraintType.perpendicular:
        return _applyPerpendicular(c);
      case ConstraintType.equal:
        return _applyEqual(c);
      case ConstraintType.coincident:
        return _applyCoincident(c);
      case ConstraintType.symmetric:
        return _applySymmetric(c);
      case ConstraintType.fixedAngle:
        return _applyFixedAngle(c);
      case ConstraintType.fixedLength:
        return _applyFixedLength(c);
      case ConstraintType.tangent:
        return _applyTangent(c);
    }
  }

  double _measureError(GeometricConstraint c) {
    switch (c.type) {
      case ConstraintType.horizontal:
        return _horizontalError(c);
      case ConstraintType.vertical:
        return _verticalError(c);
      case ConstraintType.coincident:
        return _coincidentError(c);
      case ConstraintType.fixedLength:
        return _fixedLengthError(c);
      case ConstraintType.fixedAngle:
        return _fixedAngleError(c);
      default:
        // For complex constraints, apply and check displacement.
        return _applyConstraint(c);
    }
  }

  // --- Horizontal: vertices share same Y ---

  double _applyHorizontal(GeometricConstraint c) {
    if (c.vertexIndices.length < 2) return 0;
    final v0 = network.vertices[c.vertexIndices[0]];
    final v1 = network.vertices[c.vertexIndices[1]];
    final avgY = (v0.position.dy + v1.position.dy) / 2;
    final error = (v0.position.dy - v1.position.dy).abs();
    v0.position = Offset(v0.position.dx, avgY);
    v1.position = Offset(v1.position.dx, avgY);
    return error;
  }

  double _horizontalError(GeometricConstraint c) {
    if (c.vertexIndices.length < 2) return 0;
    return (network.vertices[c.vertexIndices[0]].position.dy -
            network.vertices[c.vertexIndices[1]].position.dy)
        .abs();
  }

  // --- Vertical: vertices share same X ---

  double _applyVertical(GeometricConstraint c) {
    if (c.vertexIndices.length < 2) return 0;
    final v0 = network.vertices[c.vertexIndices[0]];
    final v1 = network.vertices[c.vertexIndices[1]];
    final avgX = (v0.position.dx + v1.position.dx) / 2;
    final error = (v0.position.dx - v1.position.dx).abs();
    v0.position = Offset(avgX, v0.position.dy);
    v1.position = Offset(avgX, v1.position.dy);
    return error;
  }

  double _verticalError(GeometricConstraint c) {
    if (c.vertexIndices.length < 2) return 0;
    return (network.vertices[c.vertexIndices[0]].position.dx -
            network.vertices[c.vertexIndices[1]].position.dx)
        .abs();
  }

  // --- Coincident: two vertices at same position ---

  double _applyCoincident(GeometricConstraint c) {
    if (c.vertexIndices.length < 2) return 0;
    final v0 = network.vertices[c.vertexIndices[0]];
    final v1 = network.vertices[c.vertexIndices[1]];
    final mid = Offset(
      (v0.position.dx + v1.position.dx) / 2,
      (v0.position.dy + v1.position.dy) / 2,
    );
    final error = (v0.position - v1.position).distance;
    v0.position = mid;
    v1.position = mid;
    return error;
  }

  double _coincidentError(GeometricConstraint c) {
    if (c.vertexIndices.length < 2) return 0;
    return (network.vertices[c.vertexIndices[0]].position -
            network.vertices[c.vertexIndices[1]].position)
        .distance;
  }

  // --- Fixed length: segment between two vertices has exact length ---

  double _applyFixedLength(GeometricConstraint c) {
    if (c.vertexIndices.length < 2 || c.value == null) return 0;
    final v0 = network.vertices[c.vertexIndices[0]];
    final v1 = network.vertices[c.vertexIndices[1]];
    final delta = v1.position - v0.position;
    final currentLen = delta.distance;
    if (currentLen < 1e-10) return c.value!;

    final targetLen = c.value!;
    final error = (currentLen - targetLen).abs();
    final scale = targetLen / currentLen;
    final mid = Offset(
      (v0.position.dx + v1.position.dx) / 2,
      (v0.position.dy + v1.position.dy) / 2,
    );
    v0.position = Offset(
      mid.dx - delta.dx * scale / 2,
      mid.dy - delta.dy * scale / 2,
    );
    v1.position = Offset(
      mid.dx + delta.dx * scale / 2,
      mid.dy + delta.dy * scale / 2,
    );
    return error;
  }

  double _fixedLengthError(GeometricConstraint c) {
    if (c.vertexIndices.length < 2 || c.value == null) return 0;
    final d =
        (network.vertices[c.vertexIndices[0]].position -
                network.vertices[c.vertexIndices[1]].position)
            .distance;
    return (d - c.value!).abs();
  }

  // --- Fixed angle: segment has specific angle ---

  double _applyFixedAngle(GeometricConstraint c) {
    if (c.vertexIndices.length < 2 || c.value == null) return 0;
    final v0 = network.vertices[c.vertexIndices[0]];
    final v1 = network.vertices[c.vertexIndices[1]];
    final delta = v1.position - v0.position;
    final currentAngle = math.atan2(delta.dy, delta.dx);
    final targetAngle = c.value!;
    final error = _angleDiff(currentAngle, targetAngle).abs();

    final len = delta.distance;
    if (len < 1e-10) return error;

    final mid = Offset(
      (v0.position.dx + v1.position.dx) / 2,
      (v0.position.dy + v1.position.dy) / 2,
    );
    v0.position = Offset(
      mid.dx - math.cos(targetAngle) * len / 2,
      mid.dy - math.sin(targetAngle) * len / 2,
    );
    v1.position = Offset(
      mid.dx + math.cos(targetAngle) * len / 2,
      mid.dy + math.sin(targetAngle) * len / 2,
    );
    return error;
  }

  double _fixedAngleError(GeometricConstraint c) {
    if (c.vertexIndices.length < 2 || c.value == null) return 0;
    final delta =
        network.vertices[c.vertexIndices[1]].position -
        network.vertices[c.vertexIndices[0]].position;
    return _angleDiff(math.atan2(delta.dy, delta.dx), c.value!).abs();
  }

  // --- Parallel: two segments have same direction ---

  double _applyParallel(GeometricConstraint c) {
    if (c.segmentIndices.length < 2) return 0;
    final seg0 = network.segments[c.segmentIndices[0]];
    final seg1 = network.segments[c.segmentIndices[1]];
    final d0 =
        network.vertices[seg0.end].position -
        network.vertices[seg0.start].position;
    final d1 =
        network.vertices[seg1.end].position -
        network.vertices[seg1.start].position;

    final angle0 = math.atan2(d0.dy, d0.dx);
    final angle1 = math.atan2(d1.dy, d1.dx);
    final diff = _angleDiff(angle0, angle1);

    if (diff.abs() < 0.001) return 0;

    // Rotate segment 1 to match segment 0's angle.
    final v0 = network.vertices[seg1.start];
    final v1 = network.vertices[seg1.end];
    final mid = Offset(
      (v0.position.dx + v1.position.dx) / 2,
      (v0.position.dy + v1.position.dy) / 2,
    );
    final len1 = d1.distance;
    v0.position = Offset(
      mid.dx - math.cos(angle0) * len1 / 2,
      mid.dy - math.sin(angle0) * len1 / 2,
    );
    v1.position = Offset(
      mid.dx + math.cos(angle0) * len1 / 2,
      mid.dy + math.sin(angle0) * len1 / 2,
    );
    return diff.abs();
  }

  // --- Perpendicular: two segments at 90° ---

  double _applyPerpendicular(GeometricConstraint c) {
    if (c.segmentIndices.length < 2) return 0;
    final seg0 = network.segments[c.segmentIndices[0]];
    final seg1 = network.segments[c.segmentIndices[1]];
    final d0 =
        network.vertices[seg0.end].position -
        network.vertices[seg0.start].position;
    final d1 =
        network.vertices[seg1.end].position -
        network.vertices[seg1.start].position;

    final angle0 = math.atan2(d0.dy, d0.dx);
    final targetAngle = angle0 + math.pi / 2;
    final angle1 = math.atan2(d1.dy, d1.dx);
    final diff = _angleDiff(angle1, targetAngle);

    if (diff.abs() < 0.001) return 0;

    final v0 = network.vertices[seg1.start];
    final v1 = network.vertices[seg1.end];
    final mid = Offset(
      (v0.position.dx + v1.position.dx) / 2,
      (v0.position.dy + v1.position.dy) / 2,
    );
    final len1 = d1.distance;
    v0.position = Offset(
      mid.dx - math.cos(targetAngle) * len1 / 2,
      mid.dy - math.sin(targetAngle) * len1 / 2,
    );
    v1.position = Offset(
      mid.dx + math.cos(targetAngle) * len1 / 2,
      mid.dy + math.sin(targetAngle) * len1 / 2,
    );
    return diff.abs();
  }

  // --- Equal: two segments have same length ---

  double _applyEqual(GeometricConstraint c) {
    if (c.segmentIndices.length < 2) return 0;
    final seg0 = network.segments[c.segmentIndices[0]];
    final seg1 = network.segments[c.segmentIndices[1]];
    final len0 =
        (network.vertices[seg0.end].position -
                network.vertices[seg0.start].position)
            .distance;
    final d1 =
        network.vertices[seg1.end].position -
        network.vertices[seg1.start].position;
    final len1 = d1.distance;

    if (len1 < 1e-10) return len0;

    final error = (len0 - len1).abs();
    final scale = len0 / len1;
    final v0 = network.vertices[seg1.start];
    final v1 = network.vertices[seg1.end];
    final mid = Offset(
      (v0.position.dx + v1.position.dx) / 2,
      (v0.position.dy + v1.position.dy) / 2,
    );
    final angle1 = math.atan2(d1.dy, d1.dx);
    v0.position = Offset(
      mid.dx - math.cos(angle1) * len0 * scale / (scale + 1),
      mid.dy - math.sin(angle1) * len0 * scale / (scale + 1),
    );
    v1.position = Offset(
      mid.dx + math.cos(angle1) * len0 / (scale + 1),
      mid.dy + math.sin(angle1) * len0 / (scale + 1),
    );
    return error;
  }

  // --- Symmetric: v0 and v2 are symmetric about v1 ---

  double _applySymmetric(GeometricConstraint c) {
    if (c.vertexIndices.length < 3) return 0;
    final v0 = network.vertices[c.vertexIndices[0]];
    final v1 = network.vertices[c.vertexIndices[1]]; // center
    final v2 = network.vertices[c.vertexIndices[2]];

    final mirror = Offset(
      2 * v1.position.dx - v0.position.dx,
      2 * v1.position.dy - v0.position.dy,
    );
    final error = (v2.position - mirror).distance;
    v2.position = mirror;
    return error;
  }

  // --- Tangent: vertex lies on tangent line of a segment ---

  double _applyTangent(GeometricConstraint c) {
    if (c.vertexIndices.isEmpty || c.segmentIndices.isEmpty) return 0;
    final vertex = network.vertices[c.vertexIndices[0]];
    final seg = network.segments[c.segmentIndices[0]];
    final segStart = network.vertices[seg.start].position;
    final segEnd = network.vertices[seg.end].position;
    final segDir = segEnd - segStart;
    final segLen = segDir.distance;
    if (segLen < 1e-10) return 0;

    // Project vertex onto segment's line.
    final toVertex = vertex.position - segStart;
    final t =
        (toVertex.dx * segDir.dx + toVertex.dy * segDir.dy) / (segLen * segLen);
    final projected = Offset(
      segStart.dx + t * segDir.dx,
      segStart.dy + t * segDir.dy,
    );
    final error = (vertex.position - projected).distance;
    vertex.position = projected;
    return error;
  }

  // -------------------------------------------------------------------------
  // Angle utility
  // -------------------------------------------------------------------------

  /// Compute the shortest angular difference, normalized to [-π, π].
  static double _angleDiff(double a, double b) {
    var diff = a - b;
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    while (diff < -math.pi) {
      diff += 2 * math.pi;
    }
    return diff;
  }
}
