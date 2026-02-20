import 'dart:ui';
import 'dart:math' as math;

import 'vector_network.dart';
import 'boolean_ops.dart';
import 'bezier_clipping.dart';

// ---------------------------------------------------------------------------
// Exact Boolean Operations on VectorNetwork
// ---------------------------------------------------------------------------

/// Performs boolean operations on [VectorNetwork]s while preserving the
/// original Bézier curve segments.
///
/// Unlike the sampling-based approach in [BooleanOps], this class:
/// 1. Finds exact intersection points via [BezierClipping]
/// 2. Splits segments at those intersections
/// 3. Labels segments as inside/outside/boundary
/// 4. Traces result contours based on the op type
/// 5. Builds output with the original curve geometry preserved
class ExactBooleanOps {
  ExactBooleanOps._();

  /// Execute a boolean operation on two [VectorNetwork]s, preserving curves.
  ///
  /// Falls back to [BooleanOps.executeOnNetworks] if one of the networks
  /// has no closed contours (boolean ops require closed shapes).
  static VectorNetwork execute(
    BooleanOpType operation,
    VectorNetwork a,
    VectorNetwork b,
  ) {
    // Convert both networks' segments to CubicBezier form.
    final curvesA = _networkToCubics(a);
    final curvesB = _networkToCubics(b);

    if (curvesA.isEmpty || curvesB.isEmpty) {
      // Fallback for empty/open networks.
      return BooleanOps.executeOnNetworks(operation, a, b);
    }

    // Step 1: Find all intersection points.
    final intersections = _findAllIntersections(curvesA, curvesB);

    // Step 2: Split segments at intersection points.
    final splitA = _splitAtIntersections(a, curvesA, intersections, true);
    final splitB = _splitAtIntersections(b, curvesB, intersections, false);

    // Step 3: Label segments.
    final labelsA = _labelSegments(splitA, curvesB, operation, true);
    final labelsB = _labelSegments(splitB, curvesA, operation, false);

    // Step 4: Build result network from kept segments.
    return _buildResult(splitA, splitB, labelsA, labelsB);
  }

  // -------------------------------------------------------------------------
  // Convert network segments to CubicBezier
  // -------------------------------------------------------------------------

  static List<_IndexedCubic> _networkToCubics(VectorNetwork network) {
    final cubics = <_IndexedCubic>[];
    for (int i = 0; i < network.segments.length; i++) {
      final seg = network.segments[i];
      final p0 = network.vertices[seg.start].position;
      final p3 = network.vertices[seg.end].position;

      CubicBezier cubic;
      if (seg.isStraight) {
        cubic = BezierClipping.lineToCubic(p0, p3);
      } else if (seg.tangentStart != null && seg.tangentEnd != null) {
        cubic = CubicBezier(p0, seg.tangentStart!, seg.tangentEnd!, p3);
      } else {
        final cp = seg.tangentStart ?? seg.tangentEnd ?? p3;
        cubic = BezierClipping.quadraticToCubic(p0, cp, p3);
      }
      cubics.add(_IndexedCubic(i, cubic));
    }
    return cubics;
  }

  // -------------------------------------------------------------------------
  // Find intersections between all pairs
  // -------------------------------------------------------------------------

  static List<_Intersection> _findAllIntersections(
    List<_IndexedCubic> curvesA,
    List<_IndexedCubic> curvesB,
  ) {
    final result = <_Intersection>[];

    for (final ca in curvesA) {
      for (final cb in curvesB) {
        // Quick AABB check.
        if (!ca.cubic.bounds.overlaps(cb.cubic.bounds)) continue;

        final hits = BezierClipping.intersectCubics(ca.cubic, cb.cubic);
        for (final (tA, tB) in hits) {
          result.add(
            _Intersection(
              segIdxA: ca.segmentIndex,
              segIdxB: cb.segmentIndex,
              tA: tA,
              tB: tB,
              point: ca.cubic.pointAt(tA),
            ),
          );
        }
      }
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Split segments at intersection parameters
  // -------------------------------------------------------------------------

  static VectorNetwork _splitAtIntersections(
    VectorNetwork network,
    List<_IndexedCubic> cubics,
    List<_Intersection> intersections,
    bool isNetworkA,
  ) {
    // Collect split parameters per segment.
    final splitParams = <int, List<double>>{};
    for (final ix in intersections) {
      final segIdx = isNetworkA ? ix.segIdxA : ix.segIdxB;
      final t = isNetworkA ? ix.tA : ix.tB;
      (splitParams[segIdx] ??= []).add(t);
    }

    // Sort parameters per segment.
    for (final params in splitParams.values) {
      params.sort();
    }

    // Build new network with split segments.
    final result = VectorNetwork();

    // Copy all vertices.
    for (final v in network.vertices) {
      result.addVertex(NetworkVertex(position: v.position));
    }

    for (int i = 0; i < network.segments.length; i++) {
      final params = splitParams[i];
      if (params == null || params.isEmpty) {
        // No splits — copy segment as-is.
        final seg = network.segments[i];
        result.addSegment(
          NetworkSegment(
            start: seg.start,
            end: seg.end,
            tangentStart: seg.tangentStart,
            tangentEnd: seg.tangentEnd,
          ),
        );
        continue;
      }

      // Split this segment at the collected parameters.
      final seg = network.segments[i];
      final cubic = cubics.firstWhere((c) => c.segmentIndex == i).cubic;

      // Remap t values relative to remaining curve after each split.
      var currentCubic = cubic;
      var currentStart = seg.start;

      for (int j = 0; j < params.length; j++) {
        // Remap t relative to current sub-curve.
        double remappedT;
        if (j == 0) {
          remappedT = params[j];
        } else {
          final prevT = params[j - 1];
          remappedT = (params[j] - prevT) / (1.0 - prevT);
        }
        remappedT = remappedT.clamp(0.01, 0.99);

        final (left, right) = BezierClipping.splitAt(currentCubic, remappedT);

        // Add intersection vertex.
        final midPoint = left.p3;
        final midIdx = result.addVertex(NetworkVertex(position: midPoint));

        // Add left sub-segment.
        result.addSegment(
          NetworkSegment(
            start: currentStart,
            end: midIdx,
            tangentStart: _isStraight(left) ? null : left.p1,
            tangentEnd: _isStraight(left) ? null : left.p2,
          ),
        );

        currentCubic = right;
        currentStart = midIdx;
      }

      // Add final sub-segment.
      result.addSegment(
        NetworkSegment(
          start: currentStart,
          end: seg.end,
          tangentStart: _isStraight(currentCubic) ? null : currentCubic.p1,
          tangentEnd: _isStraight(currentCubic) ? null : currentCubic.p2,
        ),
      );
    }

    return result;
  }

  // -------------------------------------------------------------------------
  // Label segments as inside/outside
  // -------------------------------------------------------------------------

  static List<bool> _labelSegments(
    VectorNetwork splitNetwork,
    List<_IndexedCubic> otherCubics,
    BooleanOpType operation,
    bool isA,
  ) {
    final otherBoundary = otherCubics.map((c) => c.cubic).toList();
    final labels = <bool>[];

    for (int i = 0; i < splitNetwork.segments.length; i++) {
      final seg = splitNetwork.segments[i];
      final midPoint =
          Offset.lerp(
            splitNetwork.vertices[seg.start].position,
            splitNetwork.vertices[seg.end].position,
            0.5,
          )!;

      // Check if midpoint is inside the other polygon.
      final winding = BezierClipping.windingNumber(midPoint, otherBoundary);
      final isInside = winding != 0;

      // Decide whether to keep this segment based on the operation.
      bool keep;
      switch (operation) {
        case BooleanOpType.union:
          keep = !isInside; // Keep segments outside the other shape
          break;
        case BooleanOpType.intersect:
          keep = isInside; // Keep segments inside the other shape
          break;
        case BooleanOpType.subtract:
          keep = isA ? !isInside : isInside;
          break;
        case BooleanOpType.exclude:
          keep = true; // Keep all segments (XOR keeps everything)
          break;
      }

      labels.add(keep);
    }

    return labels;
  }

  // -------------------------------------------------------------------------
  // Build result VectorNetwork
  // -------------------------------------------------------------------------

  static VectorNetwork _buildResult(
    VectorNetwork splitA,
    VectorNetwork splitB,
    List<bool> labelsA,
    List<bool> labelsB,
  ) {
    final result = VectorNetwork();

    // Map: old vertex index → new vertex index.
    final vertexMapA = <int, int>{};
    final vertexMapB = <int, int>{};

    // Add kept segments from A.
    for (int i = 0; i < splitA.segments.length; i++) {
      if (!labelsA[i]) continue;
      final seg = splitA.segments[i];
      final startIdx = _getOrAddVertex(
        result,
        vertexMapA,
        seg.start,
        splitA.vertices[seg.start].position,
      );
      final endIdx = _getOrAddVertex(
        result,
        vertexMapA,
        seg.end,
        splitA.vertices[seg.end].position,
      );

      result.addSegment(
        NetworkSegment(
          start: startIdx,
          end: endIdx,
          tangentStart: seg.tangentStart,
          tangentEnd: seg.tangentEnd,
        ),
      );
    }

    // Add kept segments from B (offset indices).
    for (int i = 0; i < splitB.segments.length; i++) {
      if (!labelsB[i]) continue;
      final seg = splitB.segments[i];

      // Check if vertex already exists (merge at intersection points).
      final startPos = splitB.vertices[seg.start].position;
      final endPos = splitB.vertices[seg.end].position;

      final startIdx = _findOrAddVertex(
        result,
        vertexMapB,
        seg.start + 1000000,
        startPos,
      ); // offset to avoid collision
      final endIdx = _findOrAddVertex(
        result,
        vertexMapB,
        seg.end + 1000000,
        endPos,
      );

      result.addSegment(
        NetworkSegment(
          start: startIdx,
          end: endIdx,
          tangentStart: seg.tangentStart,
          tangentEnd: seg.tangentEnd,
        ),
      );
    }

    return result;
  }

  static int _getOrAddVertex(
    VectorNetwork network,
    Map<int, int> map,
    int oldIdx,
    Offset position,
  ) {
    if (map.containsKey(oldIdx)) return map[oldIdx]!;
    final newIdx = network.addVertex(NetworkVertex(position: position));
    map[oldIdx] = newIdx;
    return newIdx;
  }

  static int _findOrAddVertex(
    VectorNetwork network,
    Map<int, int> map,
    int key,
    Offset position,
  ) {
    if (map.containsKey(key)) return map[key]!;

    // Check if a vertex already exists at this position (intersection merge).
    const mergeTolerance = 0.5;
    for (int i = 0; i < network.vertices.length; i++) {
      if ((network.vertices[i].position - position).distance < mergeTolerance) {
        map[key] = i;
        return i;
      }
    }

    final newIdx = network.addVertex(NetworkVertex(position: position));
    map[key] = newIdx;
    return newIdx;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static bool _isStraight(CubicBezier c) {
    // A cubic is "straight" if control points are collinear with endpoints.
    final d1 = _crossProduct(c.p0, c.p1, c.p3);
    final d2 = _crossProduct(c.p0, c.p2, c.p3);
    return d1.abs() < 1.0 && d2.abs() < 1.0;
  }

  static double _crossProduct(Offset a, Offset b, Offset c) {
    return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  }
}

// ---------------------------------------------------------------------------
// Internal data types
// ---------------------------------------------------------------------------

class _IndexedCubic {
  final int segmentIndex;
  final CubicBezier cubic;

  _IndexedCubic(this.segmentIndex, this.cubic);
}

class _Intersection {
  final int segIdxA;
  final int segIdxB;
  final double tA;
  final double tB;
  final Offset point;

  _Intersection({
    required this.segIdxA,
    required this.segIdxB,
    required this.tA,
    required this.tB,
    required this.point,
  });
}
