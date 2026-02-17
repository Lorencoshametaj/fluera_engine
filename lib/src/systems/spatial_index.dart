import 'dart:ui';
import 'dart:math' as math;
import '../core/scene_graph/canvas_node.dart';

/// A 2D spatial index using an R-tree structure for fast spatial queries.
///
/// Provides O(log n) performance for:
/// - **Range queries**: find all nodes whose bounds intersect a rectangle
///   (viewport culling)
/// - **Point queries**: find all nodes at a specific point (hit testing)
///
/// The tree automatically rebalances when nodes are inserted/removed.
///
/// ```dart
/// final index = SpatialIndex();
/// index.insert(node);
/// final visible = index.queryRange(viewportRect); // O(log n) instead of O(n)
/// final hits = index.queryPoint(cursorPoint);
/// ```
class SpatialIndex {
  _RTreeNode? _root;
  final int _maxChildren;

  /// Map from node ID → leaf entry for fast removal/update.
  final Map<String, _LeafEntry> _entries = {};

  SpatialIndex({int maxChildren = 8}) : _maxChildren = maxChildren;

  // ---------------------------------------------------------------------------
  // Insert / Remove / Update
  // ---------------------------------------------------------------------------

  /// Insert a canvas node into the spatial index.
  void insert(CanvasNode node) {
    final bounds = node.worldBounds;
    if (bounds.isEmpty || !bounds.isFinite) return;

    final entry = _LeafEntry(nodeId: node.id, bounds: bounds, node: node);
    _entries[node.id] = entry;

    _root ??= _RTreeNode(isLeaf: true);

    _insert(_root!, entry);

    // Split if overflow.
    if (_root!.children.length > _maxChildren) {
      final newRoot = _RTreeNode(isLeaf: false);
      final (left, right) = _split(_root!);
      newRoot.children.add(left);
      newRoot.children.add(right);
      newRoot.recalculateBounds();
      _root = newRoot;
    }
  }

  /// Remove a canvas node from the spatial index.
  bool remove(String nodeId) {
    final entry = _entries.remove(nodeId);
    if (entry == null) return false;

    // Rebuild the tree without this entry.
    // For simplicity, we do a full collect-and-reinsert.
    // A production R-tree would do a targeted removal + reinsert orphans.
    final remaining = _entries.values.toList();
    _root = null;
    _entries.clear();

    for (final e in remaining) {
      insert(e.node);
    }
    return true;
  }

  /// Update a node's position in the index (after transform change).
  void update(CanvasNode node) {
    remove(node.id);
    insert(node);
  }

  /// Rebuild the entire index from a list of nodes.
  void rebuild(Iterable<CanvasNode> nodes) {
    _root = null;
    _entries.clear();
    for (final node in nodes) {
      insert(node);
    }
  }

  /// Clear the entire index.
  void clear() {
    _root = null;
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
    final results = <CanvasNode>[];
    if (_root == null) return results;
    _queryRange(_root!, range, results);
    return results;
  }

  /// Find all nodes that contain [point].
  ///
  /// Used for hit testing: pass the cursor position.
  List<CanvasNode> queryPoint(Offset point) {
    return queryRange(Rect.fromCenter(center: point, width: 1, height: 1));
  }

  /// Find the K nearest nodes to [point].
  List<CanvasNode> queryNearest(Offset point, {int k = 1}) {
    final all = queryRange(
      Rect.fromCenter(
        center: point,
        width: double.infinity,
        height: double.infinity,
      ),
    );

    // Sort by distance to point.
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
  // R-tree internals
  // ---------------------------------------------------------------------------

  void _insert(_RTreeNode node, _LeafEntry entry) {
    if (node.isLeaf) {
      node.entries.add(entry);
      node.expandBounds(entry.bounds);
      return;
    }

    // Choose the child that needs least enlargement.
    _RTreeNode? bestChild;
    double bestEnlargement = double.infinity;

    for (final child in node.children) {
      final enlargement = _enlargementNeeded(child.bounds, entry.bounds);
      if (enlargement < bestEnlargement) {
        bestEnlargement = enlargement;
        bestChild = child;
      }
    }

    if (bestChild == null) {
      // No children yet, create a leaf.
      final leaf = _RTreeNode(isLeaf: true);
      leaf.entries.add(entry);
      leaf.expandBounds(entry.bounds);
      node.children.add(leaf);
      node.expandBounds(entry.bounds);
      return;
    }

    _insert(bestChild, entry);

    // Split child if overflow.
    if (bestChild.isLeaf && bestChild.entries.length > _maxChildren) {
      node.children.remove(bestChild);
      final (left, right) = _splitLeaf(bestChild);
      node.children.add(left);
      node.children.add(right);
    } else if (!bestChild.isLeaf && bestChild.children.length > _maxChildren) {
      node.children.remove(bestChild);
      final (left, right) = _split(bestChild);
      node.children.add(left);
      node.children.add(right);
    }

    node.recalculateBounds();
  }

  void _queryRange(_RTreeNode node, Rect range, List<CanvasNode> results) {
    if (!node.bounds.overlaps(range)) return;

    if (node.isLeaf) {
      for (final entry in node.entries) {
        if (entry.bounds.overlaps(range)) {
          results.add(entry.node);
        }
      }
    } else {
      for (final child in node.children) {
        _queryRange(child, range, results);
      }
    }
  }

  (_RTreeNode, _RTreeNode) _split(_RTreeNode node) {
    final left = _RTreeNode(isLeaf: node.isLeaf);
    final right = _RTreeNode(isLeaf: node.isLeaf);

    final List<_RTreeNode> items = node.isLeaf ? [] : node.children.toList();

    // Linear split: pick two seeds farthest apart.
    if (items.length < 2) {
      left.children.addAll(items);
    } else {
      // Simple split: first half / second half.
      final mid = items.length ~/ 2;
      left.children.addAll(items.sublist(0, mid).cast<_RTreeNode>());
      right.children.addAll(items.sublist(mid).cast<_RTreeNode>());
    }

    left.recalculateBounds();
    right.recalculateBounds();
    return (left, right);
  }

  (_RTreeNode, _RTreeNode) _splitLeaf(_RTreeNode node) {
    final left = _RTreeNode(isLeaf: true);
    final right = _RTreeNode(isLeaf: true);

    final entries = node.entries.toList();
    // Sort by center X for a simple spatial split.
    entries.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));

    final mid = entries.length ~/ 2;
    left.entries.addAll(entries.sublist(0, mid));
    right.entries.addAll(entries.sublist(mid));

    left.recalculateBounds();
    right.recalculateBounds();
    return (left, right);
  }

  double _enlargementNeeded(Rect current, Rect addition) {
    final merged = current.expandToInclude(addition);
    return (merged.width * merged.height) - (current.width * current.height);
  }

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

// ---------------------------------------------------------------------------
// Internal R-tree data structures
// ---------------------------------------------------------------------------

class _RTreeNode {
  final bool isLeaf;
  Rect bounds;

  /// Child nodes (for internal nodes).
  final List<_RTreeNode> children = [];

  /// Leaf entries (for leaf nodes).
  final List<_LeafEntry> entries = [];

  _RTreeNode({required this.isLeaf}) : bounds = Rect.zero;

  void expandBounds(Rect rect) {
    if (bounds == Rect.zero) {
      bounds = rect;
    } else {
      bounds = bounds.expandToInclude(rect);
    }
  }

  void recalculateBounds() {
    if (isLeaf) {
      if (entries.isEmpty) {
        bounds = Rect.zero;
        return;
      }
      bounds = entries.first.bounds;
      for (int i = 1; i < entries.length; i++) {
        bounds = bounds.expandToInclude(entries[i].bounds);
      }
    } else {
      if (children.isEmpty) {
        bounds = Rect.zero;
        return;
      }
      bounds = children.first.bounds;
      for (int i = 1; i < children.length; i++) {
        bounds = bounds.expandToInclude(children[i].bounds);
      }
    }
  }
}

class _LeafEntry {
  final String nodeId;
  final Rect bounds;
  final CanvasNode node;

  _LeafEntry({required this.nodeId, required this.bounds, required this.node});
}
