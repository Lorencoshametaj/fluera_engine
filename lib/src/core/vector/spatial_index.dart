import 'dart:ui';
import 'dart:math' as math;

import 'vector_network.dart';

// ---------------------------------------------------------------------------
// R-tree spatial index for VectorNetwork
// ---------------------------------------------------------------------------

/// R-tree spatial index for efficient vertex/segment lookup in a
/// [VectorNetwork].
///
/// Uses Sort-Tile-Recursive (STR) bulk loading for optimal tree structure.
/// Supports O(log N) region queries and nearest-neighbor search, making it
/// suitable for networks with 100k+ elements.
///
/// ```dart
/// final index = NetworkSpatialIndex.build(network);
/// final nearbyVerts = index.queryVertices(Rect.fromLTWH(0, 0, 100, 100));
/// final nearestSeg = index.nearestSegment(Offset(50, 50), 10.0);
/// ```
class NetworkSpatialIndex {
  /// Max entries per R-tree leaf node.
  static const int _maxLeafSize = 16;

  /// The network this index was built from.
  final VectorNetwork _network;

  /// Revision at which this index was built.
  final int _builtRevision;

  /// R-tree root for vertices.
  final _RTreeNode? _vertexRoot;

  /// R-tree root for segments.
  final _RTreeNode? _segmentRoot;

  /// Cached bounding boxes for each segment.
  final List<Rect> _segmentBounds;

  NetworkSpatialIndex._(
    this._network,
    this._builtRevision,
    this._vertexRoot,
    this._segmentRoot,
    this._segmentBounds,
  );

  /// Build a spatial index for the given [network] using STR bulk loading.
  factory NetworkSpatialIndex.build(
    VectorNetwork network, {
    double cellSize = 64.0,
  }) {
    // Build vertex entries.
    final vertexEntries = <_RTreeEntry>[];
    for (int i = 0; i < network.vertices.length; i++) {
      final pos = network.vertices[i].position;
      vertexEntries.add(
        _RTreeEntry(Rect.fromCenter(center: pos, width: 0.1, height: 0.1), i),
      );
    }

    // Build segment entries with AABB.
    final segBounds = <Rect>[];
    final segmentEntries = <_RTreeEntry>[];
    for (int i = 0; i < network.segments.length; i++) {
      final seg = network.segments[i];
      final p0 = network.vertices[seg.start].position;
      final p1 = network.vertices[seg.end].position;

      double minX = math.min(p0.dx, p1.dx);
      double minY = math.min(p0.dy, p1.dy);
      double maxX = math.max(p0.dx, p1.dx);
      double maxY = math.max(p0.dy, p1.dy);

      if (seg.tangentStart != null) {
        minX = math.min(minX, seg.tangentStart!.dx);
        minY = math.min(minY, seg.tangentStart!.dy);
        maxX = math.max(maxX, seg.tangentStart!.dx);
        maxY = math.max(maxY, seg.tangentStart!.dy);
      }
      if (seg.tangentEnd != null) {
        minX = math.min(minX, seg.tangentEnd!.dx);
        minY = math.min(minY, seg.tangentEnd!.dy);
        maxX = math.max(maxX, seg.tangentEnd!.dx);
        maxY = math.max(maxY, seg.tangentEnd!.dy);
      }

      final bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
      segBounds.add(bounds);
      segmentEntries.add(_RTreeEntry(bounds, i));
    }

    final vertexRoot = _buildSTR(vertexEntries);
    final segmentRoot = _buildSTR(segmentEntries);

    return NetworkSpatialIndex._(
      network,
      network.revision,
      vertexRoot,
      segmentRoot,
      segBounds,
    );
  }

  /// The revision of the [VectorNetwork] when this index was built.
  int get revision => _builtRevision;

  /// Whether this index is stale (network has been mutated since build).
  bool get isStale => _network.revision != _builtRevision;

  // -------------------------------------------------------------------------
  // Queries
  // -------------------------------------------------------------------------

  /// Find all vertex indices within the given [region].
  List<int> queryVertices(Rect region) {
    if (_vertexRoot == null) return [];
    final results = <int>[];
    _queryNode(_vertexRoot, region, results, (idx) {
      if (idx < _network.vertices.length) {
        return region.contains(_network.vertices[idx].position);
      }
      return false;
    });
    return results;
  }

  /// Find all segment indices whose bounding box overlaps the given [region].
  List<int> querySegments(Rect region) {
    if (_segmentRoot == null) return [];
    final results = <int>[];
    _queryNode(_segmentRoot, region, results, (idx) {
      return idx < _segmentBounds.length &&
          _segmentBounds[idx].overlaps(region);
    });
    return results;
  }

  /// Find the nearest vertex to [point] within [maxRadius].
  int? nearestVertex(Offset point, double maxRadius) {
    final region = Rect.fromCenter(
      center: point,
      width: maxRadius * 2,
      height: maxRadius * 2,
    );
    final candidates = queryVertices(region);
    if (candidates.isEmpty) return null;

    int? bestIdx;
    double bestDist = maxRadius;
    for (final vi in candidates) {
      final d = (_network.vertices[vi].position - point).distance;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = vi;
      }
    }
    return bestIdx;
  }

  /// Find the nearest segment to [point] within [maxTolerance].
  ///
  /// Uses [VectorNetwork.nearestPointOnSegment] for precise distance.
  int? nearestSegment(Offset point, double maxTolerance) {
    final region = Rect.fromCenter(
      center: point,
      width: maxTolerance * 2,
      height: maxTolerance * 2,
    );
    final candidates = querySegments(region);
    if (candidates.isEmpty) return null;

    int? bestIdx;
    double bestDist = maxTolerance;
    for (final si in candidates) {
      final (nearest, _) = _network.nearestPointOnSegment(si, point);
      final d = (nearest - point).distance;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = si;
      }
    }
    return bestIdx;
  }

  // -------------------------------------------------------------------------
  // R-tree query traversal
  // -------------------------------------------------------------------------

  void _queryNode(
    _RTreeNode node,
    Rect region,
    List<int> results,
    bool Function(int index) preciseCheck,
  ) {
    if (!node.bounds.overlaps(region)) return;

    if (node.isLeaf) {
      for (final entry in node.entries!) {
        if (entry.bounds.overlaps(region) && preciseCheck(entry.index)) {
          results.add(entry.index);
        }
      }
    } else {
      for (final child in node.children!) {
        _queryNode(child, region, results, preciseCheck);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Sort-Tile-Recursive (STR) bulk loading
  // -------------------------------------------------------------------------

  /// Build an R-tree from a list of entries using STR.
  static _RTreeNode? _buildSTR(List<_RTreeEntry> entries) {
    if (entries.isEmpty) return null;
    if (entries.length <= _maxLeafSize) {
      return _RTreeNode.leaf(entries);
    }

    // Number of leaf nodes needed.
    final leafCount = (entries.length / _maxLeafSize).ceil();
    // Number of slices along X axis.
    final sliceCount = math.sqrt(leafCount).ceil();
    final sliceSize = (entries.length / sliceCount).ceil();

    // Sort by X center.
    entries.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));

    final childNodes = <_RTreeNode>[];

    for (int s = 0; s < sliceCount; s++) {
      final sliceStart = s * sliceSize;
      final sliceEnd = math.min(sliceStart + sliceSize, entries.length);
      if (sliceStart >= entries.length) break;

      final slice = entries.sublist(sliceStart, sliceEnd);

      // Sort slice by Y center.
      slice.sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));

      // Pack into leaf nodes.
      for (int i = 0; i < slice.length; i += _maxLeafSize) {
        final end = math.min(i + _maxLeafSize, slice.length);
        childNodes.add(_RTreeNode.leaf(slice.sublist(i, end)));
      }
    }

    // Recursively build internal levels.
    return _buildInternalLevel(childNodes);
  }

  /// Recursively group child nodes into internal nodes.
  static _RTreeNode _buildInternalLevel(List<_RTreeNode> nodes) {
    if (nodes.length <= _maxLeafSize) {
      return _RTreeNode.internal(nodes);
    }

    final sliceCount = math.sqrt((nodes.length / _maxLeafSize).ceil()).ceil();
    final sliceSize = (nodes.length / sliceCount).ceil();

    // Sort by X center of bounds.
    nodes.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));

    final parentNodes = <_RTreeNode>[];

    for (int s = 0; s < sliceCount; s++) {
      final sliceStart = s * sliceSize;
      final sliceEnd = math.min(sliceStart + sliceSize, nodes.length);
      if (sliceStart >= nodes.length) break;

      final slice = nodes.sublist(sliceStart, sliceEnd);
      slice.sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));

      for (int i = 0; i < slice.length; i += _maxLeafSize) {
        final end = math.min(i + _maxLeafSize, slice.length);
        parentNodes.add(_RTreeNode.internal(slice.sublist(i, end)));
      }
    }

    return _buildInternalLevel(parentNodes);
  }
}

// ---------------------------------------------------------------------------
// R-tree node structure
// ---------------------------------------------------------------------------

/// A node in the R-tree. Either a leaf (contains entries) or internal
/// (contains child nodes).
class _RTreeNode {
  final Rect bounds;
  final List<_RTreeEntry>? entries; // Non-null for leaf nodes.
  final List<_RTreeNode>? children; // Non-null for internal nodes.

  _RTreeNode._(this.bounds, this.entries, this.children);

  bool get isLeaf => entries != null;

  /// Create a leaf node from a list of entries.
  factory _RTreeNode.leaf(List<_RTreeEntry> entries) {
    Rect bounds = entries.first.bounds;
    for (int i = 1; i < entries.length; i++) {
      bounds = bounds.expandToInclude(entries[i].bounds);
    }
    return _RTreeNode._(bounds, entries, null);
  }

  /// Create an internal node from child nodes.
  factory _RTreeNode.internal(List<_RTreeNode> children) {
    Rect bounds = children.first.bounds;
    for (int i = 1; i < children.length; i++) {
      bounds = bounds.expandToInclude(children[i].bounds);
    }
    return _RTreeNode._(bounds, null, children);
  }
}

/// An entry in a leaf node: bounding box + element index.
class _RTreeEntry {
  final Rect bounds;
  final int index;

  _RTreeEntry(this.bounds, this.index);
}
