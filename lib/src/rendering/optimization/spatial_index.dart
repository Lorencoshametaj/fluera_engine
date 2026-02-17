import 'dart:ui';
import 'dart:math' as math;
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';

// ============================================================================
// Generic R-tree — Industry-standard spatial index
// ============================================================================

/// 🚀 Generic R-tree for O(log n) spatial queries.
///
/// PERFORMANCE with 10k+ items:
/// - Without R-tree: O(n) per frame → LAG
/// - With R-tree: O(log n) → SMOOTH ✨
///
/// ADVANTAGES over QuadTree:
/// - Items live in exactly ONE node (no duplication for overlapping bounds)
/// - Better worst-case for objects with large or overlapping bounds
/// - Bulk loading support: O(n log n) build time
/// - Industry standard (Figma, PostGIS, SQLite R*-tree)
///
/// Usage:
/// ```dart
/// final tree = RTree<MyItem>((item) => item.bounds);
/// tree.insert(item);
/// final visible = tree.queryVisible(viewport);
/// ```
class RTree<T> {
  /// Function to extract the bounding rect from an item.
  final Rect Function(T) _boundsOf;

  /// Maximum entries per node before split.
  final int _maxEntries;

  /// Minimum entries per node (typically maxEntries / 2).
  final int _minEntries;

  /// Root node of the tree.
  _RTreeNode<T>? _root;

  /// Total number of items in the tree.
  int _count = 0;

  RTree(this._boundsOf, {int maxEntries = 9})
    : _maxEntries = maxEntries,
      _minEntries = (maxEntries / 2).ceil();

  /// Number of items in the tree.
  int get count => _count;

  /// Whether the tree is empty.
  bool get isEmpty => _count == 0;

  // ─── Insert ──────────────────────────────────────────────────────

  /// ➕ Insert an item into the R-tree.
  void insert(T item) {
    final bounds = _boundsOf(item);
    if (bounds.isEmpty || !bounds.isFinite) return;

    final entry = _Entry<T>(item: item, bounds: bounds);

    if (_root == null) {
      _root = _RTreeNode<T>(isLeaf: true);
    }

    final splitNode = _insertEntry(_root!, entry);

    // If root was split, create a new root.
    if (splitNode != null) {
      final newRoot = _RTreeNode<T>(isLeaf: false);
      newRoot.children.add(_root!);
      newRoot.children.add(splitNode);
      newRoot.recalculateBounds();
      _root = newRoot;
    }

    _count++;
  }

  // ─── Remove ──────────────────────────────────────────────────────

  /// ➖ Remove an item from the R-tree.
  ///
  /// Uses identity comparison (identical()) for matching.
  bool remove(T item) {
    if (_root == null) return false;

    final bounds = _boundsOf(item);
    final orphans = <_Entry<T>>[];

    final found = _removeEntry(_root!, item, bounds, orphans);
    if (!found) return false;

    // Re-insert orphaned entries from underflowed nodes.
    for (final orphan in orphans) {
      final splitNode = _insertEntry(_root!, orphan);
      if (splitNode != null) {
        final newRoot = _RTreeNode<T>(isLeaf: false);
        newRoot.children.add(_root!);
        newRoot.children.add(splitNode);
        newRoot.recalculateBounds();
        _root = newRoot;
      }
    }

    // Shrink root if it has only one child.
    if (!_root!.isLeaf && _root!.children.length == 1) {
      _root = _root!.children.first;
    }

    // Clear root if empty.
    if (_root!.isLeaf && _root!.entries.isEmpty) {
      _root = null;
    }

    _count--;
    return true;
  }

  // ─── Bulk Load ───────────────────────────────────────────────────

  /// 🏗️ Factory: build an R-tree from a list of items using Sort-Tile-Recursive
  /// (STR) bulk loading for optimal tree structure.
  factory RTree.fromItems(
    List<T> items,
    Rect Function(T) boundsOf, {
    int maxEntries = 9,
  }) {
    final tree = RTree<T>(boundsOf, maxEntries: maxEntries);
    if (items.isEmpty) return tree;

    // For small lists, just insert one by one.
    if (items.length <= maxEntries) {
      for (final item in items) {
        tree.insert(item);
      }
      return tree;
    }

    // STR bulk load: sort by center X, partition into slices,
    // within each slice sort by center Y, then build leaf nodes.
    final entries =
        items
            .map((item) => _Entry<T>(item: item, bounds: boundsOf(item)))
            .where((e) => e.bounds.isFinite && !e.bounds.isEmpty)
            .toList();

    tree._root = tree._bulkLoad(entries);
    tree._count = entries.length;
    return tree;
  }

  _RTreeNode<T> _bulkLoad(List<_Entry<T>> entries) {
    if (entries.length <= _maxEntries) {
      final node = _RTreeNode<T>(isLeaf: true);
      node.entries.addAll(entries);
      node.recalculateBounds();
      return node;
    }

    // Sort by center X.
    entries.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));

    // Number of leaf nodes needed.
    final leafCount = (entries.length / _maxEntries).ceil();
    // Number of slices = sqrt(leafCount).
    final sliceCount = math.sqrt(leafCount.toDouble()).ceil();
    final sliceSize = (entries.length / sliceCount).ceil();

    final childNodes = <_RTreeNode<T>>[];

    for (int i = 0; i < entries.length; i += sliceSize) {
      final sliceEnd =
          (i + sliceSize) < entries.length ? (i + sliceSize) : entries.length;
      final slice = entries.sublist(i, sliceEnd);

      // Sort slice by center Y.
      slice.sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));

      // Create leaf nodes from the slice.
      for (int j = 0; j < slice.length; j += _maxEntries) {
        final nodeEnd =
            (j + _maxEntries) < slice.length ? (j + _maxEntries) : slice.length;
        final node = _RTreeNode<T>(isLeaf: true);
        node.entries.addAll(slice.sublist(j, nodeEnd));
        node.recalculateBounds();
        childNodes.add(node);
      }
    }

    // Recursively build internal nodes.
    return _buildInternalNodes(childNodes);
  }

  _RTreeNode<T> _buildInternalNodes(List<_RTreeNode<T>> nodes) {
    if (nodes.length <= _maxEntries) {
      final parent = _RTreeNode<T>(isLeaf: false);
      parent.children.addAll(nodes);
      parent.recalculateBounds();
      return parent;
    }

    // Group into chunks of _maxEntries.
    final parents = <_RTreeNode<T>>[];
    for (int i = 0; i < nodes.length; i += _maxEntries) {
      final end =
          (i + _maxEntries) < nodes.length ? (i + _maxEntries) : nodes.length;
      final parent = _RTreeNode<T>(isLeaf: false);
      parent.children.addAll(nodes.sublist(i, end));
      parent.recalculateBounds();
      parents.add(parent);
    }

    return _buildInternalNodes(parents);
  }

  // ─── Queries ─────────────────────────────────────────────────────

  /// 🔍 Query: returns items whose bounds intersect the viewport.
  ///
  /// PERFORMANCE: O(log n) instead of O(n).
  List<T> queryVisible(Rect viewport, {double margin = 1000.0}) {
    if (_root == null) return const [];

    final expandedViewport = viewport.inflate(margin);
    final results = <T>[];
    _queryRange(_root!, expandedViewport, results);
    return results;
  }

  /// 📊 Statistics for debugging.
  Map<String, int> get stats {
    if (_root == null) {
      return {'totalItems': 0, 'totalNodes': 0, 'leafNodes': 0, 'height': 0};
    }
    return _collectStats(_root!);
  }

  /// 🧹 Clear and reset the tree.
  void clear() {
    _root = null;
    _count = 0;
  }

  // ─── Internal: Insert ────────────────────────────────────────────

  /// Insert an entry, returning a split node if the node overflows.
  _RTreeNode<T>? _insertEntry(_RTreeNode<T> node, _Entry<T> entry) {
    if (node.isLeaf) {
      node.entries.add(entry);
      node.expandBounds(entry.bounds);

      if (node.entries.length > _maxEntries) {
        return _splitLeaf(node);
      }
      return null;
    }

    // Choose the child that needs least area enlargement.
    final bestChild = _chooseBestChild(node, entry.bounds);
    final splitChild = _insertEntry(bestChild, entry);

    node.recalculateBounds();

    if (splitChild != null) {
      node.children.add(splitChild);
      if (node.children.length > _maxEntries) {
        return _splitInternal(node);
      }
    }

    return null;
  }

  /// Choose the child node that requires the least area enlargement.
  _RTreeNode<T> _chooseBestChild(_RTreeNode<T> node, Rect entryBounds) {
    _RTreeNode<T>? best;
    double bestEnlargement = double.infinity;
    double bestArea = double.infinity;

    for (final child in node.children) {
      final merged = child.bounds.expandToInclude(entryBounds);
      final enlargement =
          (merged.width * merged.height) -
          (child.bounds.width * child.bounds.height);
      final area = child.bounds.width * child.bounds.height;

      // Prefer least enlargement; tie-break by smallest area.
      if (enlargement < bestEnlargement ||
          (enlargement == bestEnlargement && area < bestArea)) {
        bestEnlargement = enlargement;
        bestArea = area;
        best = child;
      }
    }

    return best!;
  }

  // ─── Internal: Split ─────────────────────────────────────────────

  /// Split a leaf node by sorting entries by center X and splitting in half.
  _RTreeNode<T> _splitLeaf(_RTreeNode<T> node) {
    final entries = node.entries.toList();
    entries.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));

    final mid = entries.length ~/ 2;
    node.entries.clear();
    node.entries.addAll(entries.sublist(0, mid));

    final sibling = _RTreeNode<T>(isLeaf: true);
    sibling.entries.addAll(entries.sublist(mid));

    node.recalculateBounds();
    sibling.recalculateBounds();
    return sibling;
  }

  /// Split an internal node by sorting children by center X.
  _RTreeNode<T> _splitInternal(_RTreeNode<T> node) {
    final children = node.children.toList();
    children.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));

    final mid = children.length ~/ 2;
    node.children.clear();
    node.children.addAll(children.sublist(0, mid));

    final sibling = _RTreeNode<T>(isLeaf: false);
    sibling.children.addAll(children.sublist(mid));

    node.recalculateBounds();
    sibling.recalculateBounds();
    return sibling;
  }

  // ─── Internal: Remove ────────────────────────────────────────────

  bool _removeEntry(
    _RTreeNode<T> node,
    T item,
    Rect bounds,
    List<_Entry<T>> orphans,
  ) {
    if (!node.bounds.overlaps(bounds)) return false;

    if (node.isLeaf) {
      final idx = node.entries.indexWhere((e) => identical(e.item, item));
      if (idx < 0) return false;
      node.entries.removeAt(idx);
      node.recalculateBounds();
      return true;
    }

    for (int i = node.children.length - 1; i >= 0; i--) {
      final child = node.children[i];
      if (_removeEntry(child, item, bounds, orphans)) {
        // Check for underflow.
        if (child.isLeaf && child.entries.length < _minEntries) {
          // Collect orphan entries and remove this child.
          orphans.addAll(child.entries);
          node.children.removeAt(i);
        } else if (!child.isLeaf && child.children.length < _minEntries) {
          // Collect all leaf entries from this subtree.
          _collectEntries(child, orphans);
          node.children.removeAt(i);
        }
        node.recalculateBounds();
        return true;
      }
    }
    return false;
  }

  void _collectEntries(_RTreeNode<T> node, List<_Entry<T>> result) {
    if (node.isLeaf) {
      result.addAll(node.entries);
    } else {
      for (final child in node.children) {
        _collectEntries(child, result);
      }
    }
  }

  // ─── Internal: Query ─────────────────────────────────────────────

  void _queryRange(_RTreeNode<T> node, Rect range, List<T> results) {
    if (!node.bounds.overlaps(range)) return;

    if (node.isLeaf) {
      for (final entry in node.entries) {
        if (entry.bounds.overlaps(range)) {
          results.add(entry.item);
        }
      }
    } else {
      for (final child in node.children) {
        _queryRange(child, range, results);
      }
    }
  }

  // ─── Internal: Stats ─────────────────────────────────────────────

  Map<String, int> _collectStats(_RTreeNode<T> node) {
    if (node.isLeaf) {
      return {
        'totalItems': node.entries.length,
        'totalNodes': 1,
        'leafNodes': 1,
        'height': 1,
      };
    }

    int totalItems = 0;
    int totalNodes = 1;
    int leafNodes = 0;
    int maxHeight = 0;

    for (final child in node.children) {
      final s = _collectStats(child);
      totalItems += s['totalItems']!;
      totalNodes += s['totalNodes']!;
      leafNodes += s['leafNodes']!;
      final h = s['height']!;
      if (h > maxHeight) maxHeight = h;
    }

    return {
      'totalItems': totalItems,
      'totalNodes': totalNodes,
      'leafNodes': leafNodes,
      'height': maxHeight + 1,
    };
  }
}

// ============================================================================
// Internal R-tree data structures
// ============================================================================

class _RTreeNode<T> {
  final bool isLeaf;
  Rect bounds;

  /// Child nodes (for internal nodes).
  final List<_RTreeNode<T>> children = [];

  /// Leaf entries (for leaf nodes).
  final List<_Entry<T>> entries = [];

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

class _Entry<T> {
  final T item;
  final Rect bounds;

  _Entry({required this.item, required this.bounds});
}

// ============================================================================
// Type aliases for backward compatibility
// ============================================================================

/// R-tree specialized for strokes (replaces StrokeQuadTree).
typedef StrokeQuadTree = RTree<ProStroke>;

/// R-tree specialized for geometric shapes (replaces ShapeQuadTree).
typedef ShapeQuadTree = RTree<GeometricShape>;

// ============================================================================
// Spatial Index Manager
// ============================================================================

/// 🎯 Manages R-trees for per-layer viewport culling.
///
/// Maintains one R-tree per element type (strokes, shapes),
/// updated incrementally as elements are added/removed.
class SpatialIndexManager {
  /// R-tree for strokes.
  RTree<ProStroke>? _strokeTree;

  /// R-tree for shapes.
  RTree<GeometricShape>? _shapeTree;

  /// 🏗️ Build the index from lists of strokes and shapes.
  void build({
    required List<ProStroke> strokes,
    required List<GeometricShape> shapes,
    Rect canvasBounds = const Rect.fromLTWH(0, 0, 100000, 100000),
  }) {
    _strokeTree = RTree<ProStroke>.fromItems(strokes, (s) => s.bounds);
    _shapeTree = RTree<GeometricShape>.fromItems(shapes, _getShapeBounds);
  }

  /// ➕ Add a stroke to the index.
  void addStroke(ProStroke stroke) {
    _strokeTree?.insert(stroke);
  }

  /// ➖ Remove a stroke from the index.
  void removeStroke(ProStroke stroke) {
    _strokeTree?.remove(stroke);
  }

  /// ➕ Add a shape to the index.
  void addShape(GeometricShape shape) {
    _shapeTree?.insert(shape);
  }

  /// ➖ Remove a shape from the index.
  void removeShape(GeometricShape shape) {
    _shapeTree?.remove(shape);
  }

  /// 🔍 Query visible strokes in the viewport.
  List<ProStroke> queryVisibleStrokes(Rect viewport, {double margin = 1000.0}) {
    return _strokeTree?.queryVisible(viewport, margin: margin) ?? const [];
  }

  /// 🔍 Query visible shapes in the viewport.
  List<GeometricShape> queryVisibleShapes(
    Rect viewport, {
    double margin = 1000.0,
  }) {
    return _shapeTree?.queryVisible(viewport, margin: margin) ?? const [];
  }

  /// 📊 Statistics for debugging.
  Map<String, dynamic> get stats => {
    'strokes': _strokeTree?.stats ?? {},
    'shapes': _shapeTree != null ? 'active' : 'inactive',
  };

  /// 🧹 Clear the index.
  void clear() {
    _strokeTree?.clear();
    _shapeTree?.clear();
    _strokeTree = null;
    _shapeTree = null;
  }

  /// Whether the index has been built.
  bool get isBuilt => _strokeTree != null;

  /// Compute bounds for a geometric shape.
  static Rect _getShapeBounds(GeometricShape shape) {
    final padding = shape.strokeWidth * 2;
    return Rect.fromPoints(shape.startPoint, shape.endPoint).inflate(padding);
  }
}
