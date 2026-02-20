import 'dart:ui';
import 'dart:typed_data';
import 'dart:math' as math;
import './vector_path.dart';
import './spatial_index.dart';
import './constraints.dart';

// =============================================================================
// 🕸️ VECTOR NETWORK — Graph-based path model
//
// Unlike VectorPath (ordered segment list), a VectorNetwork is a graph where
// each vertex can have 0..N connected edges. This enables T-junctions, forks,
// and complex topologies like Figma's pen tool.
//
// STRUCTURE:
//   VectorNetwork
//   ├── vertices: List<NetworkVertex>   (positions)
//   ├── segments: List<NetworkSegment>  (edges with Bézier handles)
//   └── regions:  List<NetworkRegion>   (filled closed loops)
// =============================================================================

// ---------------------------------------------------------------------------
// Validation types
// ---------------------------------------------------------------------------

/// Types of validation errors found by [VectorNetwork.validate].
enum NetworkErrorType {
  /// Segment references a vertex index that doesn't exist.
  danglingSegment,

  /// Segment connects a vertex to itself.
  selfLoop,

  /// Two segments connect the same pair of vertices.
  duplicateSegment,

  /// Region references a segment index that doesn't exist.
  invalidRegionRef,

  /// Vertex has no connected segments (degree 0).
  isolatedVertex,
}

/// A single validation error in a [VectorNetwork].
class NetworkValidationError {
  /// Error category.
  final NetworkErrorType type;

  /// Human-readable description.
  final String message;

  /// Index of the element (vertex, segment, or region) involved.
  final int index;

  const NetworkValidationError({
    required this.type,
    required this.message,
    required this.index,
  });

  @override
  String toString() => 'NetworkValidationError($type, $message)';
}

// ---------------------------------------------------------------------------
// NetworkVertex
// ---------------------------------------------------------------------------

/// A vertex (point) in a [VectorNetwork].
///
/// Each vertex stores its position and a unique index within the network.
/// Vertices can be connected to any number of segments.
class NetworkVertex {
  /// Position in local coordinate space.
  Offset position;

  NetworkVertex({required this.position});

  /// Deep copy.
  NetworkVertex clone() => NetworkVertex(position: position);

  Map<String, dynamic> toJson() => {'x': position.dx, 'y': position.dy};

  factory NetworkVertex.fromJson(Map<String, dynamic> json) {
    return NetworkVertex(
      position: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkVertex && position == other.position;

  @override
  int get hashCode => position.hashCode;

  @override
  String toString() => 'NetworkVertex(${position.dx}, ${position.dy})';
}

// ---------------------------------------------------------------------------
// NetworkSegment
// ---------------------------------------------------------------------------

/// An edge connecting two vertices in a [VectorNetwork].
///
/// The segment connects `startVertex` to `endVertex` (indices into the
/// network's vertex list). Optional cubic Bézier tangent handles control
/// the curve shape.
///
/// ```
/// tangentStart ──→ ● startVertex
///                        ↘
///                          curve
///                        ↗
///   endVertex ● ←── tangentEnd
/// ```
class NetworkSegment {
  /// Index of the start vertex.
  final int start;

  /// Index of the end vertex.
  final int end;

  /// Outgoing tangent handle from start vertex (absolute position).
  /// Null → straight line from start.
  Offset? tangentStart;

  /// Incoming tangent handle at end vertex (absolute position).
  /// Null → straight line to end.
  Offset? tangentEnd;

  /// Per-segment stroke width override (null → use node default).
  double? segmentStrokeWidth;

  /// Per-segment stroke color override as ARGB32 (null → use node default).
  int? segmentStrokeColor;

  /// Per-segment stroke cap override (null → use node default).
  StrokeCap? segmentStrokeCap;

  NetworkSegment({
    required this.start,
    required this.end,
    this.tangentStart,
    this.tangentEnd,
    this.segmentStrokeWidth,
    this.segmentStrokeColor,
    this.segmentStrokeCap,
  });

  /// Whether this is a straight line (no tangent handles).
  bool get isStraight => tangentStart == null && tangentEnd == null;

  /// Whether this segment has any per-segment stroke overrides.
  bool get hasStrokeOverride =>
      segmentStrokeWidth != null ||
      segmentStrokeColor != null ||
      segmentStrokeCap != null;

  /// Deep copy.
  NetworkSegment clone() => NetworkSegment(
    start: start,
    end: end,
    tangentStart: tangentStart,
    tangentEnd: tangentEnd,
    segmentStrokeWidth: segmentStrokeWidth,
    segmentStrokeColor: segmentStrokeColor,
    segmentStrokeCap: segmentStrokeCap,
  );

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    if (tangentStart != null) 'tsx': tangentStart!.dx,
    if (tangentStart != null) 'tsy': tangentStart!.dy,
    if (tangentEnd != null) 'tex': tangentEnd!.dx,
    if (tangentEnd != null) 'tey': tangentEnd!.dy,
    if (segmentStrokeWidth != null) 'ssw': segmentStrokeWidth,
    if (segmentStrokeColor != null) 'ssc': segmentStrokeColor,
    if (segmentStrokeCap != null) 'sscp': segmentStrokeCap!.index,
  };

  factory NetworkSegment.fromJson(Map<String, dynamic> json) {
    return NetworkSegment(
      start: json['start'] as int,
      end: json['end'] as int,
      tangentStart:
          json.containsKey('tsx')
              ? Offset(
                (json['tsx'] as num).toDouble(),
                (json['tsy'] as num).toDouble(),
              )
              : null,
      tangentEnd:
          json.containsKey('tex')
              ? Offset(
                (json['tex'] as num).toDouble(),
                (json['tey'] as num).toDouble(),
              )
              : null,
      segmentStrokeWidth: (json['ssw'] as num?)?.toDouble(),
      segmentStrokeColor: json['ssc'] as int?,
      segmentStrokeCap:
          json['sscp'] != null ? StrokeCap.values[json['sscp'] as int] : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkSegment &&
          start == other.start &&
          end == other.end &&
          tangentStart == other.tangentStart &&
          tangentEnd == other.tangentEnd;

  @override
  int get hashCode => Object.hash(start, end, tangentStart, tangentEnd);

  @override
  String toString() => 'NetworkSegment($start → $end)';
}

// ---------------------------------------------------------------------------
// NetworkRegion
// ---------------------------------------------------------------------------

/// A closed loop in a [VectorNetwork] that defines a filled area.
///
/// Each entry is a `(segmentIndex, reversed)` pair. The `reversed` flag
/// indicates whether the segment should be traversed end→start instead
/// of start→end, to form a continuous loop.
class NetworkRegion {
  /// Ordered list of (segmentIndex, reversed) pairs forming a closed loop.
  final List<RegionLoop> loops;

  /// Optional wind rule (evenOdd or nonZero) for filling.
  final PathFillType fillType;

  NetworkRegion({required this.loops, this.fillType = PathFillType.evenOdd});

  /// Deep copy.
  NetworkRegion clone() => NetworkRegion(
    loops: loops.map((l) => l.clone()).toList(),
    fillType: fillType,
  );

  Map<String, dynamic> toJson() => {
    'loops': loops.map((l) => l.toJson()).toList(),
    'fillType': fillType.index,
  };

  factory NetworkRegion.fromJson(Map<String, dynamic> json) {
    return NetworkRegion(
      loops:
          (json['loops'] as List)
              .map((l) => RegionLoop.fromJson(l as Map<String, dynamic>))
              .toList(),
      fillType:
          json['fillType'] != null
              ? PathFillType.values[json['fillType'] as int]
              : PathFillType.evenOdd,
    );
  }

  @override
  String toString() => 'NetworkRegion(${loops.length} loops)';
}

/// A single loop within a [NetworkRegion].
///
/// Each loop is a list of segment references that form a closed path.
class RegionLoop {
  /// Ordered segment references forming the loop.
  final List<SegmentRef> segments;

  RegionLoop({required this.segments});

  /// Deep copy.
  RegionLoop clone() =>
      RegionLoop(segments: segments.map((s) => s.clone()).toList());

  Map<String, dynamic> toJson() => {
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  factory RegionLoop.fromJson(Map<String, dynamic> json) {
    return RegionLoop(
      segments:
          (json['segments'] as List)
              .map((s) => SegmentRef.fromJson(s as Map<String, dynamic>))
              .toList(),
    );
  }
}

/// Reference to a segment within a region loop.
class SegmentRef {
  /// Index into the network's segment list.
  final int index;

  /// Whether to traverse this segment in reverse (end → start).
  final bool reversed;

  const SegmentRef({required this.index, this.reversed = false});

  /// Deep copy.
  SegmentRef clone() => SegmentRef(index: index, reversed: reversed);

  Map<String, dynamic> toJson() => {'i': index, if (reversed) 'r': true};

  factory SegmentRef.fromJson(Map<String, dynamic> json) {
    return SegmentRef(index: json['i'] as int, reversed: json['r'] == true);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SegmentRef && index == other.index && reversed == other.reversed;

  @override
  int get hashCode => Object.hash(index, reversed);
}

// ---------------------------------------------------------------------------
// VectorNetwork
// ---------------------------------------------------------------------------

/// A graph-based vector path model.
///
/// Unlike [VectorPath] which is an ordered list of segments, a VectorNetwork
/// is a graph where each vertex can connect to any number of edges.
/// This enables complex topologies:
///
/// - **T-junctions**: a vertex connected to 3 segments
/// - **Forks**: a vertex branching into multiple paths
/// - **Complex shapes**: figure-8, overlapping loops, etc.
///
/// Regions define filled areas (closed loops within the graph).
///
/// ```dart
/// // Create a triangle
/// final network = VectorNetwork();
/// network.addVertex(NetworkVertex(position: Offset(0, 0)));    // 0
/// network.addVertex(NetworkVertex(position: Offset(100, 0)));  // 1
/// network.addVertex(NetworkVertex(position: Offset(50, 86)));  // 2
/// network.addSegment(NetworkSegment(start: 0, end: 1));        // 0
/// network.addSegment(NetworkSegment(start: 1, end: 2));        // 1
/// network.addSegment(NetworkSegment(start: 2, end: 0));        // 2
/// ```
class VectorNetwork {
  /// All vertices in the network.
  final List<NetworkVertex> vertices;

  /// All segments (edges) connecting vertices.
  final List<NetworkSegment> segments;

  /// Filled regions (closed loops).
  final List<NetworkRegion> regions;

  /// Geometric constraints.
  final List<GeometricConstraint> constraints;

  /// Monotonically increasing revision counter.
  ///
  /// Incremented on every structural mutation. Consumers (e.g. renderers)
  /// can compare against their cached revision to know when to rebuild.
  int get revision => _revision;
  int _revision = 0;

  /// Cached adjacency map: vertex index → list of segment indices.
  Map<int, List<int>>? _adjacencyMap;

  /// Cached spatial index for fast hit testing.
  NetworkSpatialIndex? _spatialIndex;

  VectorNetwork({
    List<NetworkVertex>? vertices,
    List<NetworkSegment>? segments,
    List<NetworkRegion>? regions,
    List<GeometricConstraint>? constraints,
  }) : vertices = vertices ?? [],
       segments = segments ?? [],
       regions = regions ?? [],
       constraints = constraints ?? [];

  /// Add a geometric constraint.
  void addConstraint(GeometricConstraint constraint) {
    constraints.add(constraint);
    _invalidate();
  }

  /// Remove a geometric constraint by index.
  void removeConstraint(int index) {
    constraints.removeAt(index);
    _invalidate();
  }

  /// Invalidate caches after any structural mutation.
  void _invalidate() {
    _revision++;
    _adjacencyMap = null;
    _spatialIndex = null;
  }

  /// Public cache invalidation for external command classes.
  void invalidate() => _invalidate();

  /// Build or return the cached adjacency map.
  Map<int, List<int>> _getAdjacencyMap() {
    if (_adjacencyMap != null) return _adjacencyMap!;
    final map = <int, List<int>>{};
    for (int i = 0; i < vertices.length; i++) {
      map[i] = <int>[];
    }
    for (int i = 0; i < segments.length; i++) {
      map[segments[i].start]!.add(i);
      map[segments[i].end]!.add(i);
    }
    _adjacencyMap = map;
    return map;
  }

  // -------------------------------------------------------------------------
  // Vertex operations
  // -------------------------------------------------------------------------

  /// Add a vertex and return its index.
  int addVertex(NetworkVertex vertex) {
    vertices.add(vertex);
    _invalidate();
    return vertices.length - 1;
  }

  /// Remove a vertex and all its connected segments.
  ///
  /// Adjusts all segment and region indices accordingly.
  /// Returns `true` if the vertex existed and was removed.
  bool removeVertex(int index) {
    if (index < 0 || index >= vertices.length) return false;

    // Remove segments connected to this vertex (in reverse order).
    for (int i = segments.length - 1; i >= 0; i--) {
      if (segments[i].start == index || segments[i].end == index) {
        _removeSegmentRaw(i);
      }
    }

    // Remove the vertex.
    vertices.removeAt(index);

    // Adjust segment indices.
    for (final seg in segments) {
      final newStart = seg.start > index ? seg.start - 1 : seg.start;
      final newEnd = seg.end > index ? seg.end - 1 : seg.end;
      _reindexSegment(seg, newStart, newEnd);
    }

    // Remove invalid regions and adjust region segment indices.
    _reindexRegionsAfterSegmentRemoval();

    _invalidate();
    return true;
  }

  // -------------------------------------------------------------------------
  // Segment operations
  // -------------------------------------------------------------------------

  /// Add a segment and return its index.
  ///
  /// Validates that both vertices exist. Throws [ArgumentError] in all modes.
  int addSegment(NetworkSegment segment) {
    if (segment.start < 0 || segment.start >= vertices.length) {
      throw ArgumentError(
        'Start vertex ${segment.start} out of range [0, ${vertices.length})',
      );
    }
    if (segment.end < 0 || segment.end >= vertices.length) {
      throw ArgumentError(
        'End vertex ${segment.end} out of range [0, ${vertices.length})',
      );
    }
    if (segment.start == segment.end) {
      throw ArgumentError('Self-loops are not allowed');
    }
    segments.add(segment);
    _invalidate();
    return segments.length - 1;
  }

  /// Remove a segment by index.
  ///
  /// Does NOT remove the connected vertices. Adjusts region indices.
  /// Returns `true` if the segment existed and was removed.
  bool removeSegment(int index) {
    if (index < 0 || index >= segments.length) return false;
    _removeSegmentRaw(index);
    _invalidate();
    return true;
  }

  /// Split a segment at parameter [t] (0..1).
  ///
  /// Inserts a new vertex at the interpolated position and replaces
  /// the original segment with two new segments.
  /// Returns the index of the new vertex.
  int splitSegment(int segIndex, double t) {
    assert(segIndex >= 0 && segIndex < segments.length);
    assert(t > 0.0 && t < 1.0, 't must be in (0, 1)');

    final seg = segments[segIndex];
    final p0 = vertices[seg.start].position;
    final p3 = vertices[seg.end].position;

    Offset midPoint;
    Offset? tan1End;
    Offset? tan2Start;

    if (seg.isStraight) {
      // Linear interpolation.
      midPoint = Offset.lerp(p0, p3, t)!;
    } else {
      // De Casteljau subdivision.
      final cp1 = seg.tangentStart ?? p0;
      final cp2 = seg.tangentEnd ?? p3;

      final a = Offset.lerp(p0, cp1, t)!;
      final b = Offset.lerp(cp1, cp2, t)!;
      final c = Offset.lerp(cp2, p3, t)!;
      final d = Offset.lerp(a, b, t)!;
      final e = Offset.lerp(b, c, t)!;
      midPoint = Offset.lerp(d, e, t)!;

      // Tangent handles for the two new segments.
      tan1End = d;
      tan2Start = e;
    }

    // Insert new vertex.
    final newVertexIdx = addVertex(NetworkVertex(position: midPoint));

    // Create two replacement segments.
    final seg1 = NetworkSegment(
      start: seg.start,
      end: newVertexIdx,
      tangentStart:
          seg.isStraight ? null : Offset.lerp(p0, seg.tangentStart!, t),
      tangentEnd: tan1End,
    );
    final seg2 = NetworkSegment(
      start: newVertexIdx,
      end: seg.end,
      tangentStart: tan2Start,
      tangentEnd: seg.isStraight ? null : Offset.lerp(seg.tangentEnd!, p3, t),
    );

    // Replace original segment.
    segments[segIndex] = seg1;
    final newSegIdx = segments.length;
    segments.add(seg2);

    // Update regions: any reference to segIndex needs to be expanded.
    _expandSegmentInRegions(segIndex, newSegIdx, newVertexIdx);

    _invalidate();
    return newVertexIdx;
  }

  /// Merge two vertices into one.
  ///
  /// All segments connected to [vertexB] are reconnected to [vertexA].
  /// The merged vertex position is the midpoint. [vertexB] is removed.
  void mergeVertices(int vertexA, int vertexB) {
    assert(vertexA != vertexB);
    assert(vertexA >= 0 && vertexA < vertices.length);
    assert(vertexB >= 0 && vertexB < vertices.length);

    // Set position to midpoint.
    final posA = vertices[vertexA].position;
    final posB = vertices[vertexB].position;
    vertices[vertexA].position = Offset(
      (posA.dx + posB.dx) / 2,
      (posA.dy + posB.dy) / 2,
    );

    // Reconnect segments from B to A.
    for (final seg in segments) {
      if (seg.start == vertexB) _reindexSegment(seg, vertexA, seg.end);
      if (seg.end == vertexB) _reindexSegment(seg, seg.start, vertexA);
    }

    // Remove self-loops created by the merge.
    segments.removeWhere((s) => s.start == s.end);

    // Remove duplicate segments.
    _removeDuplicateSegments();

    // Remove vertex B.
    removeVertex(vertexB);
  }

  // -------------------------------------------------------------------------
  // Region operations
  // -------------------------------------------------------------------------

  /// Add a region and return its index.
  int addRegion(NetworkRegion region) {
    regions.add(region);
    _invalidate();
    return regions.length - 1;
  }

  /// Remove a region by index.
  bool removeRegion(int index) {
    if (index < 0 || index >= regions.length) return false;
    regions.removeAt(index);
    _invalidate();
    return true;
  }

  /// Automatically detect closed regions in the network via cycle finding.
  ///
  /// Clears existing regions and rebuilds from scratch.
  /// Uses a minimal cycle basis algorithm.
  List<NetworkRegion> findRegions() {
    regions.clear();
    final cycles = _findMinimalCycles();
    for (final cycle in cycles) {
      regions.add(NetworkRegion(loops: [RegionLoop(segments: cycle)]));
    }
    return List.unmodifiable(regions);
  }

  // -------------------------------------------------------------------------
  // Topology queries
  // -------------------------------------------------------------------------

  /// Get all segment indices connected to a vertex.
  ///
  /// Uses a cached adjacency map for O(1) amortized lookups.
  List<int> adjacentSegments(int vertexIndex) {
    final map = _getAdjacencyMap();
    return List<int>.unmodifiable(map[vertexIndex] ?? const <int>[]);
  }

  /// Number of segments connected to a vertex.
  int degree(int vertexIndex) => adjacentSegments(vertexIndex).length;

  /// Get the vertex index on the other end of a segment from [vertexIndex].
  int oppositeVertex(int segmentIndex, int vertexIndex) {
    final seg = segments[segmentIndex];
    return seg.start == vertexIndex ? seg.end : seg.start;
  }

  /// Find all connected components as lists of vertex indices.
  List<List<int>> connectedComponents() {
    final visited = <int>{};
    final components = <List<int>>[];

    for (int v = 0; v < vertices.length; v++) {
      if (visited.contains(v)) continue;
      final component = <int>[];
      _dfs(v, visited, component);
      components.add(component);
    }
    return components;
  }

  /// Whether the entire network forms a single connected component.
  bool get isConnected {
    if (vertices.isEmpty) return true;
    final visited = <int>{};
    _dfs(0, visited, []);
    return visited.length == vertices.length;
  }

  /// Whether a vertex is a dead end (degree 1).
  bool isDeadEnd(int vertexIndex) => degree(vertexIndex) == 1;

  /// Whether a vertex is a junction (degree ≥ 3).
  bool isJunction(int vertexIndex) => degree(vertexIndex) >= 3;

  // -------------------------------------------------------------------------
  // Validation & Integrity
  // -------------------------------------------------------------------------

  /// Validate the integrity of the network graph.
  ///
  /// Returns a list of validation errors. An empty list means the network
  /// is well-formed.
  List<NetworkValidationError> validate() {
    final errors = <NetworkValidationError>[];

    for (int i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (s.start < 0 || s.start >= vertices.length) {
        errors.add(
          NetworkValidationError(
            type: NetworkErrorType.danglingSegment,
            message: 'Segment $i: start vertex ${s.start} out of range',
            index: i,
          ),
        );
      }
      if (s.end < 0 || s.end >= vertices.length) {
        errors.add(
          NetworkValidationError(
            type: NetworkErrorType.danglingSegment,
            message: 'Segment $i: end vertex ${s.end} out of range',
            index: i,
          ),
        );
      }
      if (s.start == s.end) {
        errors.add(
          NetworkValidationError(
            type: NetworkErrorType.selfLoop,
            message: 'Segment $i is a self-loop on vertex ${s.start}',
            index: i,
          ),
        );
      }
    }

    // Duplicate segments.
    final seen = <String>{};
    for (int i = 0; i < segments.length; i++) {
      final key1 = '${segments[i].start}-${segments[i].end}';
      final key2 = '${segments[i].end}-${segments[i].start}';
      if (seen.contains(key1) || seen.contains(key2)) {
        errors.add(
          NetworkValidationError(
            type: NetworkErrorType.duplicateSegment,
            message: 'Segment $i duplicates another segment',
            index: i,
          ),
        );
      }
      seen.add(key1);
    }

    // Region refs to removed segments.
    for (int r = 0; r < regions.length; r++) {
      for (final loop in regions[r].loops) {
        for (final ref in loop.segments) {
          if (ref.index < 0 || ref.index >= segments.length) {
            errors.add(
              NetworkValidationError(
                type: NetworkErrorType.invalidRegionRef,
                message:
                    'Region $r references segment ${ref.index} out of range',
                index: r,
              ),
            );
          }
        }
      }
    }

    // Isolated vertices (warning).
    for (int v = 0; v < vertices.length; v++) {
      if (degree(v) == 0) {
        errors.add(
          NetworkValidationError(
            type: NetworkErrorType.isolatedVertex,
            message: 'Vertex $v is isolated (degree 0)',
            index: v,
          ),
        );
      }
    }

    return errors;
  }

  /// Remove all isolated vertices (degree 0) and reindex.
  ///
  /// Returns the number of vertices removed.
  int compact() {
    int removed = 0;
    for (int i = vertices.length - 1; i >= 0; i--) {
      if (degree(i) == 0) {
        removeVertex(i);
        removed++;
      }
    }
    return removed;
  }

  // -------------------------------------------------------------------------
  // Hit Testing
  // -------------------------------------------------------------------------

  /// Returns the spatial index, building it lazily if needed.
  NetworkSpatialIndex get spatialIndex {
    if (_spatialIndex == null || _spatialIndex!.isStale) {
      _spatialIndex = NetworkSpatialIndex.build(this);
    }
    return _spatialIndex!;
  }

  /// Find the nearest vertex within [radius] of [point].
  ///
  /// Uses spatial index for O(1) average lookup on networks >50 vertices.
  /// Returns the vertex index, or null if none found.
  int? hitTestVertex(Offset point, double radius) {
    // Use spatial index for large networks.
    if (vertices.length > 50) {
      return spatialIndex.nearestVertex(point, radius);
    }
    int? bestIdx;
    double bestDist = radius;
    for (int i = 0; i < vertices.length; i++) {
      final d = (vertices[i].position - point).distance;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// Find the nearest segment within [tolerance] of [point].
  ///
  /// Uses spatial index for O(1) average lookup on networks >50 segments.
  /// Returns the segment index, or null if none found.
  int? hitTestSegment(Offset point, double tolerance) {
    // Use spatial index for large networks.
    if (segments.length > 50) {
      return spatialIndex.nearestSegment(point, tolerance);
    }
    int? bestIdx;
    double bestDist = tolerance;
    for (int i = 0; i < segments.length; i++) {
      final (nearest, _) = nearestPointOnSegment(i, point);
      final d = (nearest - point).distance;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// Find the region containing [point].
  ///
  /// Returns the region index, or null if point is outside all regions.
  /// Uses Flutter Path.contains() for accuracy.
  int? hitTestRegion(Offset point) {
    for (int i = 0; i < regions.length; i++) {
      final path = regionToFlutterPath(i);
      if (path.contains(point)) return i;
    }
    return null;
  }

  /// Find the nearest point on a segment to [point].
  ///
  /// Returns the nearest [Offset] and the parameter `t` ∈ [0, 1].
  /// Uses 40 subdivisions for cubic curves.
  (Offset nearest, double t) nearestPointOnSegment(int segIdx, Offset point) {
    final seg = segments[segIdx];
    final p0 = vertices[seg.start].position;
    final p3 = vertices[seg.end].position;

    const int steps = 40;
    double bestT = 0;
    double bestDist = double.infinity;
    Offset bestPoint = p0;

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final pt = _evaluateSegmentAt(seg, p0, p3, t);
      final d = (pt - point).distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        bestT = t;
        bestPoint = pt;
      }
    }

    return (bestPoint, bestT);
  }

  // -------------------------------------------------------------------------
  // Path Math
  // -------------------------------------------------------------------------

  /// Compute the arc length of a segment.
  ///
  /// Uses 20-point Gauss-Legendre quadrature for curves, exact for lines.
  double segmentLength(int segIdx) {
    final seg = segments[segIdx];
    final p0 = vertices[seg.start].position;
    final p3 = vertices[seg.end].position;

    if (seg.isStraight) return (p3 - p0).distance;

    // Numerical integration via Simpson's rule with 20 subdivisions.
    const int n = 20;
    double length = 0;
    Offset prev = p0;
    for (int i = 1; i <= n; i++) {
      final t = i / n;
      final pt = _evaluateSegmentAt(seg, p0, p3, t);
      length += (pt - prev).distance;
      prev = pt;
    }
    return length;
  }

  /// Evaluate a point on a segment at parameter [t] ∈ [0, 1].
  Offset pointOnSegment(int segIdx, double t) {
    final seg = segments[segIdx];
    final p0 = vertices[seg.start].position;
    final p3 = vertices[seg.end].position;
    return _evaluateSegmentAt(seg, p0, p3, t);
  }

  /// Compute the tangent direction at parameter [t] on a segment.
  ///
  /// Returns a non-normalized direction vector.
  Offset tangentAtPoint(int segIdx, double t) {
    final seg = segments[segIdx];
    final p0 = vertices[seg.start].position;
    final p3 = vertices[seg.end].position;

    if (seg.isStraight) return p3 - p0;

    final cp1 = seg.tangentStart ?? p0;
    final cp2 = seg.tangentEnd ?? p3;

    if (cp1 != p0 && cp2 != p3) {
      // Cubic Bézier derivative: B'(t) = 3(1-t)²(P1-P0) + 6(1-t)t(P2-P1) + 3t²(P3-P2)
      final mt = 1.0 - t;
      final a = (cp1 - p0) * (3 * mt * mt);
      final b = (cp2 - cp1) * (6 * mt * t);
      final c = (p3 - cp2) * (3 * t * t);
      return a + b + c;
    } else {
      // Quadratic Bézier derivative: B'(t) = 2(1-t)(P1-P0) + 2t(P2-P1)
      final cp = cp1 != p0 ? cp1 : cp2;
      final mt = 1.0 - t;
      return (cp - p0) * (2 * mt) + (p3 - cp) * (2 * t);
    }
  }

  /// Sum of all segment lengths.
  double totalLength() {
    double sum = 0;
    for (int i = 0; i < segments.length; i++) {
      sum += segmentLength(i);
    }
    return sum;
  }

  /// Remove redundant vertices on collinear segments.
  ///
  /// A vertex is redundant if:
  /// - Its degree is exactly 2
  /// - Both connected segments are straight
  /// - The three points are collinear within [tolerance]
  ///
  /// Returns the number of vertices removed.
  int simplify(double tolerance) {
    int removed = 0;
    for (int v = vertices.length - 1; v >= 0; v--) {
      if (degree(v) != 2) continue;
      final adj = adjacentSegments(v);
      final seg0 = segments[adj[0]];
      final seg1 = segments[adj[1]];
      if (!seg0.isStraight || !seg1.isStraight) continue;

      // Check collinearity via cross product.
      final a = vertices[oppositeVertex(adj[0], v)].position;
      final b = vertices[v].position;
      final c = vertices[oppositeVertex(adj[1], v)].position;

      final cross =
          (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
      if (cross.abs() > tolerance) continue;

      // Replace two segments with one.
      final otherA = oppositeVertex(adj[0], v);
      final otherB = oppositeVertex(adj[1], v);
      removeSegment(adj[0] > adj[1] ? adj[0] : adj[1]);
      removeSegment(adj[0] > adj[1] ? adj[1] : adj[0]);
      removeVertex(v);
      addSegment(
        NetworkSegment(
          start: otherA > v ? otherA - 1 : otherA,
          end: otherB > v ? otherB - 1 : otherB,
        ),
      );
      removed++;
    }
    return removed;
  }

  /// Auto-generate smooth tangent handles for sharp corners.
  ///
  /// For each vertex with degree 2 and two straight segments,
  /// converts them to cubic Bézier curves with tangent handles
  /// placed at [tension] × distance from the vertex.
  void smooth(double tension) {
    for (int v = 0; v < vertices.length; v++) {
      if (degree(v) != 2) continue;
      final adj = adjacentSegments(v);
      final seg0 = segments[adj[0]];
      final seg1 = segments[adj[1]];
      if (!seg0.isStraight || !seg1.isStraight) continue;

      final pos = vertices[v].position;
      final other0 = vertices[oppositeVertex(adj[0], v)].position;
      final other1 = vertices[oppositeVertex(adj[1], v)].position;

      final dir0 = other0 - pos;
      final dir1 = other1 - pos;
      final len0 = dir0.distance * tension;
      final len1 = dir1.distance * tension;

      if (len0 == 0 || len1 == 0) continue;

      // Set tangent handles toward vertex position.
      final norm0 = dir0 / dir0.distance;
      final norm1 = dir1 / dir1.distance;

      // For seg0: the handle should be on the vertex end.
      if (seg0.start == v) {
        seg0.tangentStart = pos + norm0 * len0;
      } else {
        seg0.tangentEnd = pos + norm0 * len0;
      }

      if (seg1.start == v) {
        seg1.tangentStart = pos + norm1 * len1;
      } else {
        seg1.tangentEnd = pos + norm1 * len1;
      }
    }
    _invalidate();
  }

  // -------------------------------------------------------------------------
  // Snap & Grid
  // -------------------------------------------------------------------------

  /// Snap all vertex positions to a grid.
  void snapToGrid(double gridSize) {
    if (gridSize <= 0) return;
    for (final v in vertices) {
      v.position = Offset(
        (v.position.dx / gridSize).roundToDouble() * gridSize,
        (v.position.dy / gridSize).roundToDouble() * gridSize,
      );
    }
    _invalidate();
  }

  /// Find the nearest existing vertex to [vertexIdx] within [radius].
  ///
  /// Returns the nearest vertex index, or null if none found (excluding self).
  int? snapVertexToNearest(int vertexIdx, double radius) {
    final pos = vertices[vertexIdx].position;
    int? bestIdx;
    double bestDist = radius;
    for (int i = 0; i < vertices.length; i++) {
      if (i == vertexIdx) continue;
      final d = (vertices[i].position - pos).distance;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// Merge all vertices within [tolerance] distance of each other.
  ///
  /// Returns the number of merges performed.
  int weldVertices(double tolerance) {
    int merges = 0;
    for (int i = 0; i < vertices.length; i++) {
      for (int j = i + 1; j < vertices.length; j++) {
        if ((vertices[i].position - vertices[j].position).distance <=
            tolerance) {
          mergeVertices(i, j);
          merges++;
          j--; // Recheck since indices shifted.
        }
      }
    }
    return merges;
  }

  // -------------------------------------------------------------------------
  // Private: segment evaluation
  // -------------------------------------------------------------------------

  /// Evaluate point on a segment curve at parameter t.
  static Offset _evaluateSegmentAt(
    NetworkSegment seg,
    Offset p0,
    Offset p3,
    double t,
  ) {
    if (seg.isStraight) return Offset.lerp(p0, p3, t)!;

    final cp1 = seg.tangentStart ?? p0;
    final cp2 = seg.tangentEnd ?? p3;

    if (cp1 != p0 && cp2 != p3) {
      // Cubic Bézier.
      final mt = 1.0 - t;
      final mt2 = mt * mt;
      final t2 = t * t;
      return p0 * (mt2 * mt) +
          cp1 * (3 * mt2 * t) +
          cp2 * (3 * mt * t2) +
          p3 * (t2 * t);
    } else {
      // Quadratic Bézier.
      final cp = cp1 != p0 ? cp1 : cp2;
      final mt = 1.0 - t;
      return p0 * (mt * mt) + cp * (2 * mt * t) + p3 * (t * t);
    }
  }

  // -------------------------------------------------------------------------
  // Conversion
  // -------------------------------------------------------------------------

  /// Convert the network to a list of [VectorPath]s.
  ///
  /// Each connected chain of segments becomes a separate path.
  /// Regions are not encoded — use [regionToPath] for fills.
  List<VectorPath> toVectorPaths() {
    if (segments.isEmpty) return [];

    final usedSegments = <int>{};
    final paths = <VectorPath>[];

    // Find chains starting from dead-end or junction vertices.
    // For simple cycles, start from any unused segment.
    for (int v = 0; v < vertices.length; v++) {
      if (isDeadEnd(v) || isJunction(v)) {
        final adj = adjacentSegments(v);
        for (final segIdx in adj) {
          if (usedSegments.contains(segIdx)) continue;
          final chain = _traceChain(v, segIdx, usedSegments);
          paths.add(_chainToVectorPath(chain));
        }
      }
    }

    // Handle remaining segments (isolated cycles).
    for (int i = 0; i < segments.length; i++) {
      if (usedSegments.contains(i)) continue;
      final chain = _traceChain(segments[i].start, i, usedSegments);
      paths.add(_chainToVectorPath(chain));
    }

    return paths;
  }

  /// Convert the entire network to a single Flutter [Path].
  ///
  /// Traces connected chains of segments, producing proper closed contours.
  /// Useful for boolean operations and hit testing.
  Path toFlutterPath() {
    final path = Path();
    if (segments.isEmpty) return path;

    final usedSegments = <int>{};

    void addChain(int startVertex, int firstSegIdx) {
      final chain = _traceChain(startVertex, firstSegIdx, usedSegments);
      if (chain.isEmpty) return;

      // MoveTo the start vertex.
      path.moveTo(
        vertices[startVertex].position.dx,
        vertices[startVertex].position.dy,
      );

      int currentVertex = startVertex;
      for (final (segIdx, reversed) in chain) {
        final seg = segments[segIdx];
        final nextVertex = reversed ? seg.start : seg.end;
        final endPos = vertices[nextVertex].position;

        if (seg.isStraight) {
          path.lineTo(endPos.dx, endPos.dy);
        } else if (seg.tangentStart != null && seg.tangentEnd != null) {
          if (!reversed) {
            path.cubicTo(
              seg.tangentStart!.dx,
              seg.tangentStart!.dy,
              seg.tangentEnd!.dx,
              seg.tangentEnd!.dy,
              endPos.dx,
              endPos.dy,
            );
          } else {
            path.cubicTo(
              seg.tangentEnd!.dx,
              seg.tangentEnd!.dy,
              seg.tangentStart!.dx,
              seg.tangentStart!.dy,
              endPos.dx,
              endPos.dy,
            );
          }
        } else {
          final cp = seg.tangentStart ?? seg.tangentEnd ?? endPos;
          path.quadraticBezierTo(cp.dx, cp.dy, endPos.dx, endPos.dy);
        }

        currentVertex = nextVertex;
      }

      // Close if the chain returns to the start vertex.
      if (currentVertex == startVertex && chain.length > 1) {
        path.close();
      }
    }

    // Trace from dead-ends and junctions first.
    for (int v = 0; v < vertices.length; v++) {
      if (isDeadEnd(v) || isJunction(v)) {
        for (final segIdx in adjacentSegments(v)) {
          if (!usedSegments.contains(segIdx)) {
            addChain(v, segIdx);
          }
        }
      }
    }

    // Handle remaining isolated cycles.
    for (int i = 0; i < segments.length; i++) {
      if (!usedSegments.contains(i)) {
        addChain(segments[i].start, i);
      }
    }

    return path;
  }

  /// Create a [VectorNetwork] from a Flutter [Path].
  ///
  /// Uses [Path.computeMetrics] to sample each contour and builds
  /// vertices and straight-line segments. Applies collinear merging
  /// to reduce vertex count on straight edges.
  static VectorNetwork fromFlutterPath(Path flutterPath) {
    final network = VectorNetwork();

    for (final metric in flutterPath.computeMetrics()) {
      final length = metric.length;
      if (length == 0) continue;

      final sampleCount = math.max(12, (length / 2).ceil());
      final points = <Offset>[];

      for (int i = 0; i <= sampleCount; i++) {
        final dist = (i / sampleCount) * length;
        final tangent = metric.getTangentForOffset(dist);
        if (tangent == null) continue;
        points.add(tangent.position);
      }

      if (points.isEmpty) continue;

      // Merge collinear points.
      final merged = <Offset>[points.first];
      for (int i = 1; i < points.length; i++) {
        if (i >= 2) {
          final a = merged[merged.length - 1];
          final b = points[i];
          final prev = merged.length >= 2 ? merged[merged.length - 2] : a;
          final cross =
              (a.dx - prev.dx) * (b.dy - prev.dy) -
              (a.dy - prev.dy) * (b.dx - prev.dx);
          if (cross.abs() < 0.8) {
            merged[merged.length - 1] = b;
            continue;
          }
        }
        merged.add(points[i]);
      }

      // Build vertices and segments.
      final firstIdx = network.vertices.length;
      for (final p in merged) {
        network.addVertex(NetworkVertex(position: p));
      }
      for (int i = 0; i < merged.length - 1; i++) {
        network.addSegment(
          NetworkSegment(start: firstIdx + i, end: firstIdx + i + 1),
        );
      }

      // Close if contour is closed.
      if (metric.isClosed && merged.length > 1) {
        final first = merged.first;
        final last = merged.last;
        if ((last - first).distance > 0.5) {
          network.addSegment(
            NetworkSegment(start: firstIdx + merged.length - 1, end: firstIdx),
          );
        }
      }
    }

    return network;
  }

  /// Convert a single region to a Flutter [Path] for filling.
  Path regionToFlutterPath(int regionIndex) {
    assert(regionIndex >= 0 && regionIndex < regions.length);
    final region = regions[regionIndex];
    final path = Path();
    path.fillType = region.fillType;

    for (final loop in region.loops) {
      if (loop.segments.isEmpty) continue;

      // Determine the start vertex of the first segment.
      final firstRef = loop.segments.first;
      final firstSeg = segments[firstRef.index];
      final startVtx = firstRef.reversed ? firstSeg.end : firstSeg.start;
      path.moveTo(
        vertices[startVtx].position.dx,
        vertices[startVtx].position.dy,
      );

      for (final ref in loop.segments) {
        _addSegmentToPath(path, ref);
      }
      path.close();
    }

    return path;
  }

  /// Convert a single region to a [VectorPath].
  VectorPath regionToVectorPath(int regionIndex) {
    assert(regionIndex >= 0 && regionIndex < regions.length);
    final region = regions[regionIndex];

    final flutterPath = regionToFlutterPath(regionIndex);
    // Use VectorPath's moveTo and segment builders.
    final vectorPath = VectorPath(segments: []);

    for (final loop in region.loops) {
      if (loop.segments.isEmpty) continue;

      final firstRef = loop.segments.first;
      final firstSeg = segments[firstRef.index];
      final startVtx = firstRef.reversed ? firstSeg.end : firstSeg.start;
      vectorPath.segments.add(
        MoveSegment(endPoint: vertices[startVtx].position),
      );

      for (final ref in loop.segments) {
        final seg = segments[ref.index];
        final fromIdx = ref.reversed ? seg.end : seg.start;
        final toIdx = ref.reversed ? seg.start : seg.end;
        final toPos = vertices[toIdx].position;

        if (seg.isStraight) {
          vectorPath.lineTo(toPos.dx, toPos.dy);
        } else {
          final cp1 = ref.reversed ? seg.tangentEnd : seg.tangentStart;
          final cp2 = ref.reversed ? seg.tangentStart : seg.tangentEnd;
          if (cp1 != null && cp2 != null) {
            vectorPath.cubicTo(
              cp1.dx,
              cp1.dy,
              cp2.dx,
              cp2.dy,
              toPos.dx,
              toPos.dy,
            );
          } else {
            final cp = cp1 ?? cp2 ?? toPos;
            vectorPath.quadTo(cp.dx, cp.dy, toPos.dx, toPos.dy);
          }
        }
      }
      vectorPath.close();
    }

    return vectorPath;
  }

  /// Create a VectorNetwork from a [VectorPath].
  ///
  /// Each segment endpoint becomes a vertex, each segment becomes an edge.
  factory VectorNetwork.fromVectorPath(VectorPath path) {
    final network = VectorNetwork();
    if (path.segments.isEmpty) return network;

    int? firstVertexInContour;
    int? lastVertex;

    for (final seg in path.segments) {
      if (seg is MoveSegment) {
        firstVertexInContour = network.addVertex(
          NetworkVertex(position: seg.endPoint),
        );
        lastVertex = firstVertexInContour;
      } else if (seg is LineSegment) {
        final newVertex = network.addVertex(
          NetworkVertex(position: seg.endPoint),
        );
        if (lastVertex != null) {
          network.addSegment(NetworkSegment(start: lastVertex, end: newVertex));
        }
        lastVertex = newVertex;
      } else if (seg is CubicSegment) {
        final newVertex = network.addVertex(
          NetworkVertex(position: seg.endPoint),
        );
        if (lastVertex != null) {
          network.addSegment(
            NetworkSegment(
              start: lastVertex,
              end: newVertex,
              tangentStart: seg.controlPoint1,
              tangentEnd: seg.controlPoint2,
            ),
          );
        }
        lastVertex = newVertex;
      } else if (seg is QuadSegment) {
        final newVertex = network.addVertex(
          NetworkVertex(position: seg.endPoint),
        );
        if (lastVertex != null) {
          network.addSegment(
            NetworkSegment(
              start: lastVertex,
              end: newVertex,
              tangentStart: seg.controlPoint,
              tangentEnd: seg.controlPoint,
            ),
          );
        }
        lastVertex = newVertex;
      }
    }

    // Close the path by connecting last vertex back to first.
    if (path.isClosed &&
        lastVertex != null &&
        firstVertexInContour != null &&
        lastVertex != firstVertexInContour) {
      network.addSegment(
        NetworkSegment(start: lastVertex, end: firstVertexInContour),
      );
    }

    return network;
  }

  // -------------------------------------------------------------------------
  // Bounds
  // -------------------------------------------------------------------------

  /// Compute the bounding box of all vertices.
  Rect computeBounds() {
    if (vertices.isEmpty) return Rect.zero;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final v in vertices) {
      minX = math.min(minX, v.position.dx);
      minY = math.min(minY, v.position.dy);
      maxX = math.max(maxX, v.position.dx);
      maxY = math.max(maxY, v.position.dy);
    }

    // Also include tangent handles.
    for (final s in segments) {
      if (s.tangentStart != null) {
        minX = math.min(minX, s.tangentStart!.dx);
        minY = math.min(minY, s.tangentStart!.dy);
        maxX = math.max(maxX, s.tangentStart!.dx);
        maxY = math.max(maxY, s.tangentStart!.dy);
      }
      if (s.tangentEnd != null) {
        minX = math.min(minX, s.tangentEnd!.dx);
        minY = math.min(minY, s.tangentEnd!.dy);
        maxX = math.max(maxX, s.tangentEnd!.dx);
        maxY = math.max(maxY, s.tangentEnd!.dy);
      }
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'vertices': vertices.map((v) => v.toJson()).toList(),
    'segments': segments.map((s) => s.toJson()).toList(),
    if (regions.isNotEmpty) 'regions': regions.map((r) => r.toJson()).toList(),
    if (constraints.isNotEmpty)
      'constraints': constraints.map((c) => c.toJson()).toList(),
  };

  factory VectorNetwork.fromJson(Map<String, dynamic> json) {
    return VectorNetwork(
      vertices:
          (json['vertices'] as List)
              .map((v) => NetworkVertex.fromJson(v as Map<String, dynamic>))
              .toList(),
      segments:
          (json['segments'] as List)
              .map((s) => NetworkSegment.fromJson(s as Map<String, dynamic>))
              .toList(),
      regions:
          json['regions'] != null
              ? (json['regions'] as List)
                  .map((r) => NetworkRegion.fromJson(r as Map<String, dynamic>))
                  .toList()
              : [],
      constraints:
          json['constraints'] != null
              ? (json['constraints'] as List)
                  .map(
                    (c) =>
                        GeometricConstraint.fromJson(c as Map<String, dynamic>),
                  )
                  .toList()
              : [],
    );
  }

  /// Deep copy of the entire network.
  VectorNetwork clone() => VectorNetwork(
    vertices: vertices.map((v) => v.clone()).toList(),
    segments: segments.map((s) => s.clone()).toList(),
    regions: regions.map((r) => r.clone()).toList(),
    constraints:
        constraints
            .map(
              (c) => GeometricConstraint(
                type: c.type,
                vertexIndices: List.of(c.vertexIndices),
                segmentIndices: List.of(c.segmentIndices),
                value: c.value,
              ),
            )
            .toList(),
  );

  /// Create a transformed copy with a 4x4 matrix.
  VectorNetwork transformed(Float64List matrix) {
    final clone = this.clone();
    for (final v in clone.vertices) {
      v.position = _transformPoint(v.position, matrix);
    }
    for (final s in clone.segments) {
      if (s.tangentStart != null) {
        s.tangentStart = _transformPoint(s.tangentStart!, matrix);
      }
      if (s.tangentEnd != null) {
        s.tangentEnd = _transformPoint(s.tangentEnd!, matrix);
      }
    }
    return clone;
  }

  @override
  String toString() =>
      'VectorNetwork(${vertices.length} vertices, ${segments.length} segments, ${regions.length} regions)';

  // =========================================================================
  // PRIVATE HELPERS
  // =========================================================================

  /// Transform a point using a 4x4 matrix (column-major).
  static Offset _transformPoint(Offset point, Float64List m) {
    final x = m[0] * point.dx + m[4] * point.dy + m[12];
    final y = m[1] * point.dx + m[5] * point.dy + m[13];
    return Offset(x, y);
  }

  /// Reindex a segment's start/end (mutable workaround for final fields).
  void _reindexSegment(NetworkSegment seg, int newStart, int newEnd) {
    // Since start/end are final, we replace in-list.
    final idx = segments.indexOf(seg);
    if (idx == -1) return;
    segments[idx] = NetworkSegment(
      start: newStart,
      end: newEnd,
      tangentStart: seg.tangentStart,
      tangentEnd: seg.tangentEnd,
    );
  }

  /// Remove a segment and adjust region references.
  void _removeSegmentRaw(int index) {
    segments.removeAt(index);

    // Adjust region segment indices.
    for (int r = regions.length - 1; r >= 0; r--) {
      final region = regions[r];
      bool invalid = false;
      for (final loop in region.loops) {
        loop.segments.removeWhere((ref) {
          if (ref.index == index) {
            invalid = true;
            return true;
          }
          return false;
        });
        // Decrement indices above the removed one.
        for (int s = 0; s < loop.segments.length; s++) {
          final ref = loop.segments[s];
          if (ref.index > index) {
            loop.segments[s] = SegmentRef(
              index: ref.index - 1,
              reversed: ref.reversed,
            );
          }
        }
      }
      // Remove empty/broken regions.
      if (invalid) {
        regions.removeAt(r);
      }
    }
  }

  /// Rebuild region indices after segment removal.
  void _reindexRegionsAfterSegmentRemoval() {
    // Remove regions referencing out-of-range segments.
    regions.removeWhere((region) {
      for (final loop in region.loops) {
        for (final ref in loop.segments) {
          if (ref.index >= segments.length) return true;
        }
      }
      return false;
    });
  }

  /// Remove duplicate segments (same start+end pair).
  void _removeDuplicateSegments() {
    final seen = <String>{};
    for (int i = segments.length - 1; i >= 0; i--) {
      final s = segments[i];
      final key1 = '${s.start}-${s.end}';
      final key2 = '${s.end}-${s.start}';
      if (seen.contains(key1) || seen.contains(key2)) {
        _removeSegmentRaw(i);
      } else {
        seen.add(key1);
      }
    }
  }

  /// Expand a split segment in all region references.
  void _expandSegmentInRegions(
    int originalIdx,
    int newSegIdx,
    int midVertexIdx,
  ) {
    for (final region in regions) {
      for (final loop in region.loops) {
        for (int i = 0; i < loop.segments.length; i++) {
          final ref = loop.segments[i];
          if (ref.index == originalIdx) {
            // Replace single ref with two refs.
            if (ref.reversed) {
              loop.segments[i] = SegmentRef(index: newSegIdx, reversed: true);
              loop.segments.insert(
                i,
                SegmentRef(index: originalIdx, reversed: true),
              );
            } else {
              loop.segments.insert(
                i + 1,
                SegmentRef(index: newSegIdx, reversed: false),
              );
            }
            break; // Each ref appears at most once per loop.
          }
        }
      }
    }
  }

  /// DFS traversal for connected components.
  void _dfs(int vertex, Set<int> visited, List<int> component) {
    visited.add(vertex);
    component.add(vertex);
    for (final segIdx in adjacentSegments(vertex)) {
      final other = oppositeVertex(segIdx, vertex);
      if (!visited.contains(other)) {
        _dfs(other, visited, component);
      }
    }
  }

  /// Trace a chain of segments starting from [startVertex] along [firstSegIdx].
  ///
  /// Follows degree-2 vertices until hitting a dead end, junction, or cycle.
  List<(int segIdx, bool reversed)> _traceChain(
    int startVertex,
    int firstSegIdx,
    Set<int> usedSegments,
  ) {
    final chain = <(int, bool)>[];
    usedSegments.add(firstSegIdx);

    final seg = segments[firstSegIdx];
    final reversed = seg.end == startVertex;
    chain.add((firstSegIdx, reversed));

    var current = reversed ? seg.start : seg.end;

    // Follow the chain while current vertex has degree 2.
    while (degree(current) == 2 && current != startVertex) {
      final adj = adjacentSegments(current);
      final nextSegIdx = adj.firstWhere(
        (i) => !usedSegments.contains(i),
        orElse: () => -1,
      );
      if (nextSegIdx == -1) break;

      usedSegments.add(nextSegIdx);
      final nextSeg = segments[nextSegIdx];
      final nextReversed = nextSeg.end == current;
      chain.add((nextSegIdx, nextReversed));
      current = nextReversed ? nextSeg.start : nextSeg.end;
    }

    return chain;
  }

  /// Convert a chain of segment references to a [VectorPath].
  VectorPath _chainToVectorPath(List<(int segIdx, bool reversed)> chain) {
    if (chain.isEmpty) return VectorPath(segments: []);

    // Determine start vertex.
    final firstSeg = segments[chain.first.$1];
    final startIdx = chain.first.$2 ? firstSeg.end : firstSeg.start;
    final path = VectorPath.moveTo(vertices[startIdx].position);

    for (final (segIdx, reversed) in chain) {
      final seg = segments[segIdx];
      final toIdx = reversed ? seg.start : seg.end;
      final toPos = vertices[toIdx].position;

      if (seg.isStraight) {
        path.lineTo(toPos.dx, toPos.dy);
      } else {
        final cp1 = reversed ? seg.tangentEnd : seg.tangentStart;
        final cp2 = reversed ? seg.tangentStart : seg.tangentEnd;
        if (cp1 != null && cp2 != null) {
          path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, toPos.dx, toPos.dy);
        } else {
          final cp = cp1 ?? cp2 ?? toPos;
          path.quadTo(cp.dx, cp.dy, toPos.dx, toPos.dy);
        }
      }
    }

    return path;
  }

  /// Add a segment reference to a Flutter Path.
  void _addSegmentToPath(Path path, SegmentRef ref) {
    final seg = segments[ref.index];
    final toIdx = ref.reversed ? seg.start : seg.end;
    final toPos = vertices[toIdx].position;

    if (seg.isStraight) {
      path.lineTo(toPos.dx, toPos.dy);
    } else {
      final cp1 = ref.reversed ? seg.tangentEnd : seg.tangentStart;
      final cp2 = ref.reversed ? seg.tangentStart : seg.tangentEnd;
      if (cp1 != null && cp2 != null) {
        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, toPos.dx, toPos.dy);
      } else {
        final cp = cp1 ?? cp2 ?? toPos;
        path.quadraticBezierTo(cp.dx, cp.dy, toPos.dx, toPos.dy);
      }
    }
  }

  /// Find minimal cycles in the network graph.
  ///
  /// Uses a simplified approach: for each vertex with degree ≥ 2,
  /// attempt to find short cycles by walking adjacent segments.
  List<List<SegmentRef>> _findMinimalCycles() {
    final cycles = <List<SegmentRef>>[];
    final foundCycleKeys = <String>{};

    for (int startV = 0; startV < vertices.length; startV++) {
      if (degree(startV) < 2) continue;

      final adj = adjacentSegments(startV);
      // Try each pair of adjacent segments.
      for (int i = 0; i < adj.length; i++) {
        for (int j = i + 1; j < adj.length; j++) {
          final cycle = _findCycleBetween(startV, adj[i], adj[j]);
          if (cycle != null) {
            // Normalize cycle key to avoid duplicates.
            final key = _cycleKey(cycle);
            if (!foundCycleKeys.contains(key)) {
              foundCycleKeys.add(key);
              cycles.add(cycle);
            }
          }
        }
      }
    }

    return cycles;
  }

  /// Try to find a cycle starting from [startV] using segments [segA] and [segB].
  List<SegmentRef>? _findCycleBetween(int startV, int segA, int segB) {
    // BFS from segA's other end to segB's other end, avoiding startV.
    final otherA = oppositeVertex(segA, startV);
    final otherB = oppositeVertex(segB, startV);

    if (otherA == otherB) {
      // Triangle-like: startV → otherA → startV via two segments.
      // This is only a valid cycle if otherA != startV.
      return [
        SegmentRef(index: segA, reversed: segments[segA].end != otherA),
        SegmentRef(index: segB, reversed: segments[segB].end != startV),
      ];
    }

    // BFS from otherA to otherB, avoiding startV, max depth 20.
    final queue = <(int vertex, List<SegmentRef> path)>[];
    final visited = <int>{startV}; // Exclude startV from search.

    queue.add((
      otherA,
      [SegmentRef(index: segA, reversed: segments[segA].end != otherA)],
    ));
    visited.add(otherA);

    while (queue.isNotEmpty) {
      final (current, currentPath) = queue.removeAt(0);

      if (currentPath.length > 20) continue; // Limit search depth.

      for (final nextSeg in adjacentSegments(current)) {
        final next = oppositeVertex(nextSeg, current);

        if (next == otherB) {
          // Found path! Complete the cycle.
          final cycle = List<SegmentRef>.from(currentPath);
          cycle.add(
            SegmentRef(
              index: nextSeg,
              reversed: segments[nextSeg].end != otherB,
            ),
          );
          cycle.add(
            SegmentRef(index: segB, reversed: segments[segB].end != startV),
          );
          return cycle;
        }

        if (!visited.contains(next)) {
          visited.add(next);
          final newPath = List<SegmentRef>.from(currentPath);
          newPath.add(
            SegmentRef(index: nextSeg, reversed: segments[nextSeg].end != next),
          );
          queue.add((next, newPath));
        }
      }
    }

    return null; // No cycle found.
  }

  /// Create a normalized key for a cycle to detect duplicates.
  String _cycleKey(List<SegmentRef> cycle) {
    final indices = cycle.map((r) => r.index).toList()..sort();
    return indices.join(',');
  }
}
