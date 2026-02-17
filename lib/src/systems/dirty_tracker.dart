import 'dart:ui';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/group_node.dart';

/// Tracks which nodes have been modified and computes the minimal
/// region that needs repainting.
///
/// **How it works:**
/// 1. When a node changes, call [markDirty] with that node.
/// 2. The dirty flag propagates up to ancestors (so parent groups
///    know they need re-traversal).
/// 3. Before rendering, call [collectDirtyRegion] to get the union
///    of all dirty world-bounds.
/// 4. After rendering, call [clearAll] to reset flags.
///
/// **Layer caching:**
/// The tracker supports per-layer dirty tracking. Each layer can
/// cache its rendered output; only layers containing dirty nodes
/// need re-rendering. Use [isDirtyLayer] to check.
///
/// ```dart
/// final tracker = DirtyTracker();
/// tracker.markDirty(movedNode);
///
/// if (tracker.hasDirty) {
///   final region = tracker.collectDirtyRegion();
///   // Only repaint `region` instead of entire canvas
///   renderer.renderRegion(canvas, sceneGraph, region);
///   tracker.clearAll();
/// }
/// ```
class DirtyTracker {
  /// Set of node IDs that have been marked dirty this frame.
  final Set<String> _dirtyIds = {};

  /// Cached dirty region (computed lazily).
  Rect? _cachedRegion;

  /// Node lookup for resolving IDs to bounds.
  final Map<String, CanvasNode> _nodeRegistry = {};

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Register a node so the tracker can resolve its bounds.
  ///
  /// Call this when nodes are added to the scene graph.
  void registerNode(CanvasNode node) {
    _nodeRegistry[node.id] = node;
  }

  /// Unregister a node (when removed from scene graph).
  void unregisterNode(String nodeId) {
    _nodeRegistry.remove(nodeId);
    _dirtyIds.remove(nodeId);
  }

  /// Register all nodes in a subtree.
  void registerSubtree(CanvasNode root) {
    registerNode(root);
    if (root is GroupNode) {
      for (final child in root.children) {
        registerSubtree(child);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Marking dirty
  // ---------------------------------------------------------------------------

  /// Mark a node as dirty. Propagates up to ancestors.
  ///
  /// Both the node's old bounds (before the change) and new bounds
  /// (after the change) should be invalidated. The caller should
  /// call this *before* modifying the node, passing [oldBounds],
  /// then modify the node (the new bounds will be read automatically).
  void markDirty(CanvasNode node, {Rect? oldBounds}) {
    _dirtyIds.add(node.id);
    _cachedRegion = null; // Invalidatete cached region.

    // If old bounds provided, track them as a special dirty rect.
    if (oldBounds != null && !oldBounds.isEmpty) {
      _extraDirtyRects.add(oldBounds);
    }

    // Propagate up to ancestors.
    CanvasNode? current = node.parent;
    while (current != null) {
      _dirtyIds.add(current.id);
      current = current.parent;
    }
  }

  /// Mark a node dirty by ID (if registered).
  void markDirtyById(String nodeId) {
    final node = _nodeRegistry[nodeId];
    if (node != null) markDirty(node);
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Whether any node is dirty.
  bool get hasDirty => _dirtyIds.isNotEmpty || _extraDirtyRects.isNotEmpty;

  /// Whether a specific node is dirty.
  bool isDirty(String nodeId) => _dirtyIds.contains(nodeId);

  /// Number of dirty nodes.
  int get dirtyCount => _dirtyIds.length;

  /// Whether a layer (identified by its node ID) contains any dirty nodes.
  ///
  /// Checks if the layer itself or any of its descendants are dirty.
  bool isDirtyLayer(String layerId) {
    if (_dirtyIds.contains(layerId)) return true;

    final layer = _nodeRegistry[layerId];
    if (layer is GroupNode) {
      return _hasAnyDirtyDescendant(layer);
    }
    return false;
  }

  bool _hasAnyDirtyDescendant(GroupNode group) {
    for (final child in group.children) {
      if (_dirtyIds.contains(child.id)) return true;
      if (child is GroupNode && _hasAnyDirtyDescendant(child)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Dirty region computation
  // ---------------------------------------------------------------------------

  /// Extra dirty rects for old-bounds tracking.
  final List<Rect> _extraDirtyRects = [];

  /// Compute the minimal bounding rect that encloses all dirty nodes.
  ///
  /// Returns [Rect.zero] if nothing is dirty.
  Rect collectDirtyRegion() {
    if (!hasDirty) return Rect.zero;
    if (_cachedRegion != null) return _cachedRegion!;

    Rect? region;

    // Union of dirty node bounds.
    for (final id in _dirtyIds) {
      final node = _nodeRegistry[id];
      if (node == null) continue;
      if (node is GroupNode) continue; // Groups derive bounds from children.

      final bounds = node.worldBounds;
      if (bounds.isFinite && !bounds.isEmpty) {
        region = region == null ? bounds : region.expandToInclude(bounds);
      }
    }

    // Union with extra dirty rects (old positions).
    for (final rect in _extraDirtyRects) {
      if (rect.isFinite && !rect.isEmpty) {
        region = region == null ? rect : region.expandToInclude(rect);
      }
    }

    _cachedRegion = region ?? Rect.zero;
    return _cachedRegion!;
  }

  /// Get all dirty leaf node IDs (excluding groups).
  Set<String> get dirtyLeafIds {
    return _dirtyIds.where((id) {
      final node = _nodeRegistry[id];
      return node != null && node is! GroupNode;
    }).toSet();
  }

  // ---------------------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------------------

  /// Clear all dirty flags after rendering.
  void clearAll() {
    _dirtyIds.clear();
    _extraDirtyRects.clear();
    _cachedRegion = null;
  }

  /// Clear dirty flag for a single node.
  void clearNode(String nodeId) {
    _dirtyIds.remove(nodeId);
    _cachedRegion = null;
  }

  /// Clear entire registry (when scene graph is disposed).
  void dispose() {
    _dirtyIds.clear();
    _extraDirtyRects.clear();
    _nodeRegistry.clear();
    _cachedRegion = null;
  }
}
