import 'dart:ui';
import 'dart:math' as math;
import '../core/scene_graph/canvas_node.dart';
import '../rendering/optimization/spatial_index.dart' as rtree;

/// A 2D spatial index using an R-tree structure for fast spatial queries.
///
/// Provides O(log n) performance for:
/// - **Range queries**: find all nodes whose bounds intersect a rectangle
///   (viewport culling)
/// - **Point queries**: find all nodes at a specific point (hit testing)
///
/// Backed by the optimized [rtree.RTree] with:
/// - **STR bulk-loading**: O(N log N) optimal tree construction
/// - **Lazy deletion**: O(1) remove via tombstones
/// - **Short-circuit query**: flat collect for fully-contained nodes
/// - **Auto-compaction**: periodic STR rebuild after mutation threshold
///
/// ```dart
/// final index = SpatialIndex();
/// index.insert(node);
/// final visible = index.queryRange(viewportRect); // O(log n) instead of O(n)
/// final hits = index.queryPoint(cursorPoint);
/// ```
class SpatialIndex {
  /// Optimized R-Tree backing store.
  rtree.RTree<CanvasNode> _tree;

  /// Map from node ID → CanvasNode for fast lookup by ID.
  /// Needed because `remove()` takes a String ID, not a CanvasNode reference.
  final Map<String, CanvasNode> _entries = {};

  SpatialIndex({int maxChildren = 16})
    : _tree = rtree.RTree<CanvasNode>(
        (node) => node.worldBounds,
        maxEntries: maxChildren,
      );

  // ---------------------------------------------------------------------------
  // Insert / Remove / Update
  // ---------------------------------------------------------------------------

  /// Insert a canvas node into the spatial index.
  void insert(CanvasNode node) {
    final bounds = node.worldBounds;
    if (bounds.isEmpty || !bounds.isFinite) return;

    _entries[node.id] = node;
    _tree.insert(node);

    // Auto-compact if mutation threshold reached.
    if (_tree.needsCompaction()) {
      _tree.compact();
    }
  }

  /// Remove a canvas node from the spatial index.
  ///
  /// O(1): uses lazy deletion (tombstone). The entry remains physically
  /// in the tree but is excluded from all query results.
  bool remove(String nodeId) {
    final node = _entries.remove(nodeId);
    if (node == null) return false;

    _tree.remove(node);

    // Auto-compact if tombstone threshold reached.
    if (_tree.needsCompaction()) {
      _tree.compact();
    }
    return true;
  }

  /// Update a node's position in the index (after transform change).
  void update(CanvasNode node) {
    remove(node.id);
    insert(node);
  }

  /// Rebuild the entire index from a list of nodes using STR bulk-loading.
  ///
  /// This creates an optimal tree structure in O(N log N) time,
  /// much faster than N sequential inserts for large datasets.
  void rebuild(Iterable<CanvasNode> nodes) {
    _entries.clear();

    final nodeList = <CanvasNode>[];
    for (final node in nodes) {
      final bounds = node.worldBounds;
      if (bounds.isEmpty || !bounds.isFinite) continue;
      _entries[node.id] = node;
      nodeList.add(node);
    }

    _tree = rtree.RTree<CanvasNode>.fromItems(
      nodeList,
      (node) => node.worldBounds,
      maxEntries: 16,
    );
  }

  /// Clear the entire index.
  void clear() {
    _tree.clear();
    _entries.clear();
  }

  /// Number of nodes in the index.
  int get nodeCount => _entries.length;

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Find all nodes whose bounds intersect [range].
  ///
  /// Used for viewport culling: pass the visible viewport rect
  /// to get only the nodes that need rendering.
  List<CanvasNode> queryRange(Rect range) {
    return _tree.queryVisible(range, margin: 0);
  }

  /// Find all nodes that contain [point].
  ///
  /// Used for hit testing: pass the cursor position.
  List<CanvasNode> queryPoint(Offset point) {
    return queryRange(Rect.fromCenter(center: point, width: 1, height: 1));
  }

  /// Find the K nearest nodes to [point].
  List<CanvasNode> queryNearest(Offset point, {int k = 1}) {
    // Use a large search area, then sort by distance.
    final all = _tree.queryVisible(
      Rect.fromCenter(
        center: point,
        width: double.infinity,
        height: double.infinity,
      ),
      margin: 0,
    );

    all.sort((a, b) {
      final distA = _distanceToBounds(point, a.worldBounds);
      final distB = _distanceToBounds(point, b.worldBounds);
      return distA.compareTo(distB);
    });

    return all.take(k).toList();
  }

  /// Number of nodes in the index.
  int get count => _entries.length;

  /// Whether the index is empty.
  bool get isEmpty => _entries.isEmpty;

  /// Whether a node is in the index.
  bool contains(String nodeId) => _entries.containsKey(nodeId);

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  double _distanceToBounds(Offset point, Rect bounds) {
    final dx = math.max(
      0,
      math.max(bounds.left - point.dx, point.dx - bounds.right),
    );
    final dy = math.max(
      0,
      math.max(bounds.top - point.dy, point.dy - bounds.bottom),
    );
    return math.sqrt(dx * dx + dy * dy);
  }
}
