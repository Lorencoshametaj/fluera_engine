import 'dart:ui';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';

// ============================================================================
// Generic QuadTree
// ============================================================================

/// 🚀 Generic QuadTree for O(log n) spatial queries.
///
/// PERFORMANCE with 10k+ items:
/// - Without QuadTree: O(n) per frame → LAG
/// - With QuadTree: O(log n) → SMOOTH ✨
///
/// DESIGN:
/// The canvas (default 100k × 100k) is recursively divided into 4 quadrants.
/// Each item is inserted into the smallest quadrant that contains it.
/// Viewport queries return only items in visible quadrants.
///
/// Usage:
/// ```dart
/// final tree = QuadTree<MyItem>(canvasBounds, (item) => item.bounds);
/// tree.insert(item);
/// final visible = tree.queryVisible(viewport);
/// ```
class QuadTree<T> {
  /// Bounds of this quadtree node.
  final Rect bounds;

  /// Items stored in this node (leaf only).
  final List<T> _items = [];

  /// Child nodes (NW, NE, SW, SE) — null until subdivision.
  List<QuadTree<T>>? _children;

  /// Function to extract the bounding rect from an item.
  final Rect Function(T) _boundsOf;

  /// Maximum items per node before subdivision.
  static const int maxItemsPerNode = 16;

  /// Maximum tree depth.
  static const int maxDepth = 10;

  /// Current depth of this node.
  final int _depth;

  QuadTree(this.bounds, this._boundsOf, [this._depth = 0]);

  /// 🏗️ Factory: build a QuadTree from a list of items.
  factory QuadTree.fromItems(
    List<T> items,
    Rect canvasBounds,
    Rect Function(T) boundsOf,
  ) {
    final tree = QuadTree<T>(canvasBounds, boundsOf);
    for (final item in items) {
      tree.insert(item);
    }
    return tree;
  }

  /// ➕ Insert an item into the quadtree.
  void insert(T item) {
    final itemBounds = _boundsOf(item);

    // If the item does not intersect this node, ignore it.
    if (!bounds.overlaps(itemBounds)) return;

    // If we have children, delegate insertion.
    if (_children != null) {
      for (final child in _children!) {
        if (child.bounds.overlaps(itemBounds)) {
          child.insert(item);
        }
      }
      return;
    }

    // Add to this node.
    _items.add(item);

    // If we exceed the limit and haven't reached max depth, subdivide.
    if (_items.length > maxItemsPerNode && _depth < maxDepth) {
      _subdivide();
    }
  }

  /// ➖ Remove an item from the quadtree.
  bool remove(T item) {
    final itemBounds = _boundsOf(item);

    if (!bounds.overlaps(itemBounds)) return false;

    // If we have children, search in children.
    if (_children != null) {
      for (final child in _children!) {
        if (child.remove(item)) return true;
      }
      return false;
    }

    // Search in this node.
    return _items.remove(item);
  }

  /// 🔍 Query: returns items visible in the viewport.
  ///
  /// PERFORMANCE: O(log n) instead of O(n).
  List<T> queryVisible(Rect viewport, {double margin = 1000.0}) {
    final expandedViewport = viewport.inflate(margin);

    // If this node does not intersect the viewport, no items are visible.
    if (!bounds.overlaps(expandedViewport)) {
      return const [];
    }

    // If we are a leaf, filter items.
    if (_children == null) {
      return _items.where((item) {
        return expandedViewport.overlaps(_boundsOf(item));
      }).toList();
    }

    // Otherwise, collect from children.
    final result = <T>[];
    for (final child in _children!) {
      result.addAll(child.queryVisible(viewport, margin: margin));
    }
    return result;
  }

  /// 📊 Statistics for debugging.
  Map<String, int> get stats {
    int totalItems = _items.length;
    int totalNodes = 1;
    int leafNodes = _children == null ? 1 : 0;
    int maxItemsInNode = _items.length;

    if (_children != null) {
      for (final child in _children!) {
        final childStats = child.stats;
        totalItems += childStats['totalItems']!;
        totalNodes += childStats['totalNodes']!;
        leafNodes += childStats['leafNodes']!;
        if (childStats['maxItemsInNode']! > maxItemsInNode) {
          maxItemsInNode = childStats['maxItemsInNode']!;
        }
      }
    }

    return {
      'totalItems': totalItems,
      'totalNodes': totalNodes,
      'leafNodes': leafNodes,
      'maxItemsInNode': maxItemsInNode,
      'depth': _depth,
    };
  }

  /// 🔄 Subdivide this node into 4 quadrants.
  void _subdivide() {
    final midX = bounds.left + bounds.width / 2;
    final midY = bounds.top + bounds.height / 2;

    _children = [
      // NW (top-left)
      QuadTree<T>(
        Rect.fromLTRB(bounds.left, bounds.top, midX, midY),
        _boundsOf,
        _depth + 1,
      ),
      // NE (top-right)
      QuadTree<T>(
        Rect.fromLTRB(midX, bounds.top, bounds.right, midY),
        _boundsOf,
        _depth + 1,
      ),
      // SW (bottom-left)
      QuadTree<T>(
        Rect.fromLTRB(bounds.left, midY, midX, bounds.bottom),
        _boundsOf,
        _depth + 1,
      ),
      // SE (bottom-right)
      QuadTree<T>(
        Rect.fromLTRB(midX, midY, bounds.right, bounds.bottom),
        _boundsOf,
        _depth + 1,
      ),
    ];

    // Redistribute existing items into children.
    for (final item in _items) {
      for (final child in _children!) {
        if (child.bounds.overlaps(_boundsOf(item))) {
          child._items.add(item);
        }
      }
    }

    // Clear items from this node (children own them now).
    _items.clear();
  }

  /// 🧹 Clear and reset the tree.
  void clear() {
    _items.clear();
    _children = null;
  }
}

// ============================================================================
// Type aliases for backward compatibility
// ============================================================================

/// QuadTree specialized for strokes.
typedef StrokeQuadTree = QuadTree<ProStroke>;

/// QuadTree specialized for geometric shapes.
typedef ShapeQuadTree = QuadTree<GeometricShape>;

// ============================================================================
// Spatial Index Manager
// ============================================================================

/// 🎯 Manages QuadTrees for per-layer viewport culling.
///
/// Maintains one QuadTree per element type (strokes, shapes),
/// updated incrementally as elements are added/removed.
class SpatialIndexManager {
  /// QuadTree for strokes.
  QuadTree<ProStroke>? _strokeTree;

  /// QuadTree for shapes.
  QuadTree<GeometricShape>? _shapeTree;

  /// Canvas bounds (default 100k × 100k).
  static const Rect defaultCanvasBounds = Rect.fromLTWH(0, 0, 100000, 100000);

  /// 🏗️ Build the index from lists of strokes and shapes.
  void build({
    required List<ProStroke> strokes,
    required List<GeometricShape> shapes,
    Rect canvasBounds = defaultCanvasBounds,
  }) {
    _strokeTree = QuadTree<ProStroke>.fromItems(
      strokes,
      canvasBounds,
      (s) => s.bounds,
    );
    _shapeTree = QuadTree<GeometricShape>.fromItems(
      shapes,
      canvasBounds,
      _getShapeBounds,
    );
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
