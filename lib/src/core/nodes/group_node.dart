import 'package:flutter/material.dart';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_visitor.dart';

/// A node that contains an ordered list of child [CanvasNode]s.
///
/// Children are rendered in list order (index 0 = bottom, last = top).
/// The group's [localBounds] is the union of all children's world bounds
/// transformed back into local space.
class GroupNode extends CanvasNode {
  final List<CanvasNode> _children = [];

  /// Cached bounds — invalidated when children change.
  Rect? _cachedLocalBounds;
  bool _boundsDirty = true;

  GroupNode({
    required super.id,
    super.name,
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  // ---------------------------------------------------------------------------
  // Children access
  // ---------------------------------------------------------------------------

  /// Read-only view of children.
  List<CanvasNode> get children => List.unmodifiable(_children);

  /// Number of children.
  int get childCount => _children.length;

  /// Whether this group has no children.
  bool get isEmpty => _children.isEmpty;

  // ---------------------------------------------------------------------------
  // Modification
  // ---------------------------------------------------------------------------

  /// Add a child at the end (top of z-order).
  ///
  /// Throws [StateError] if adding [child] would create a cycle.
  void add(CanvasNode child) {
    _assertNoCycle(child);
    assert(
      !_children.any((c) => c.id == child.id),
      'Duplicate child ID "${child.id}" in ${this.id}',
    );
    child.parent = this;
    _children.add(child);
    _expandBoundsIncremental(child);
  }

  /// Expand the cached bounds to include [child]'s world bounds
  /// without recomputing the entire subtree.
  void _expandBoundsIncremental(CanvasNode child) {
    if (_boundsDirty) return; // already dirty, nothing to expand
    final childBounds = child.worldBounds;
    if (childBounds.isEmpty) return;

    final inverse = Matrix4.tryInvert(worldTransform);
    final localChildBounds =
        inverse != null
            ? MatrixUtils.transformRect(inverse, childBounds)
            : childBounds;

    final current = _cachedLocalBounds ?? Rect.zero;
    _cachedLocalBounds =
        current.isEmpty
            ? localChildBounds
            : current.expandToInclude(localChildBounds);
    // Propagate upward — parent group's bounds depend on ours.
    if (parent is GroupNode) {
      (parent as GroupNode).invalidateBoundsCache();
    }
  }

  /// Insert a child at a specific z-index.
  ///
  /// Throws [StateError] if adding [child] would create a cycle.
  void insertAt(int index, CanvasNode child) {
    _assertNoCycle(child);
    assert(
      !_children.any((c) => c.id == child.id),
      'Duplicate child ID "${child.id}" in ${this.id}',
    );
    child.parent = this;
    _children.insert(index, child);
    invalidateBoundsCache();
  }

  /// Remove a child by reference.
  bool remove(CanvasNode child) {
    final removed = _children.remove(child);
    if (removed) {
      child.parent = null;
      invalidateBoundsCache();
    }
    return removed;
  }

  /// Remove a child by ID.
  CanvasNode? removeById(String nodeId) {
    final index = _children.indexWhere((c) => c.id == nodeId);
    if (index == -1) return null;
    final child = _children.removeAt(index);
    child.parent = null;
    invalidateBoundsCache();
    return child;
  }

  /// Remove a child at a specific index.
  CanvasNode removeAt(int index) {
    final child = _children.removeAt(index);
    child.parent = null;
    invalidateBoundsCache();
    return child;
  }

  /// Move a child from [oldIndex] to [newIndex].
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final child = _children.removeAt(oldIndex);
    // Adjust index after removal
    final adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _children.insert(adjustedIndex, child);
    invalidateBoundsCache();
  }

  /// Remove all children.
  void clear() {
    for (final child in _children) {
      child.parent = null;
    }
    _children.clear();
    invalidateBoundsCache();
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Find a child by ID (non-recursive, direct children only).
  CanvasNode? findChild(String nodeId) {
    for (final child in _children) {
      if (child.id == nodeId) return child;
    }
    return null;
  }

  /// Recursively find a node by ID in this subtree.
  CanvasNode? findDescendant(String nodeId) {
    for (final child in _children) {
      if (child.id == nodeId) return child;
      if (child is GroupNode) {
        final found = child.findDescendant(nodeId);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Index of a child, or -1 if not found.
  int indexOf(CanvasNode child) => _children.indexOf(child);

  /// Index of a child by ID, or -1 if not found.
  int indexOfById(String nodeId) => _children.indexWhere((c) => c.id == nodeId);

  // ---------------------------------------------------------------------------
  // Typed convenience getters
  // ---------------------------------------------------------------------------

  /// All children of type [T].
  List<T> childrenOfType<T extends CanvasNode>() =>
      _children.whereType<T>().toList();

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    if (!_boundsDirty && _cachedLocalBounds != null) {
      return _cachedLocalBounds!;
    }

    if (_children.isEmpty) {
      _cachedLocalBounds = Rect.zero;
      _boundsDirty = false;
      return Rect.zero;
    }

    // Compute the inverse ONCE — it doesn't change across children.
    final inverse = Matrix4.tryInvert(worldTransform);

    Rect? result;
    for (final child in _children) {
      if (!child.isVisible) continue;
      final childBounds = child.worldBounds;
      if (childBounds.isEmpty) continue;

      // Transform child world bounds back to our local space
      final localChildBounds =
          inverse != null
              ? MatrixUtils.transformRect(inverse, childBounds)
              : childBounds;

      result =
          result == null
              ? localChildBounds
              : result.expandToInclude(localChildBounds);
    }

    _cachedLocalBounds = result ?? Rect.zero;
    _boundsDirty = false;
    return _cachedLocalBounds!;
  }

  /// Invalidate the cached bounds for this group and propagate upward.
  ///
  /// Called when children are added, removed, reordered, or when
  /// a child's transform changes.
  void invalidateBoundsCache() {
    _boundsDirty = true;
    _cachedLocalBounds = null;
    // Propagate upward — parent group's bounds depend on ours.
    if (parent is GroupNode) {
      (parent as GroupNode).invalidateBoundsCache();
    }
  }

  // ---------------------------------------------------------------------------
  // Hit testing
  // ---------------------------------------------------------------------------

  /// Hit test children in reverse z-order (top to bottom).
  /// Returns the topmost hit child, or null.
  CanvasNode? hitTestChildren(Offset worldPoint) {
    for (int i = _children.length - 1; i >= 0; i--) {
      final child = _children[i];
      if (!child.isVisible) continue;

      if (child is GroupNode) {
        final hit = child.hitTestChildren(worldPoint);
        if (hit != null) return hit;
      }

      if (child.hitTest(worldPoint)) return child;
    }
    return null;
  }

  @override
  bool hitTest(Offset worldPoint) {
    if (!isVisible) return false;
    return hitTestChildren(worldPoint) != null;
  }

  // ---------------------------------------------------------------------------
  // Iteration
  // ---------------------------------------------------------------------------

  /// Iterate over all descendant nodes (depth-first).
  Iterable<CanvasNode> get allDescendants sync* {
    for (final child in _children) {
      yield child;
      if (child is GroupNode) {
        yield* child.allDescendants;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'group';
    json['children'] = _children.map((c) => c.toJson()).toList();
    return json;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitGroup(this);

  /// Restore children from JSON. Call after constructing the GroupNode.
  void loadChildrenFromJson(
    List<dynamic> childrenJson,
    CanvasNode Function(Map<String, dynamic>) nodeFactory,
  ) {
    _children.clear();
    for (final childJson in childrenJson) {
      final child = nodeFactory(childJson as Map<String, dynamic>);
      child.parent = this;
      _children.add(child);
    }
    invalidateBoundsCache();
  }

  // ---------------------------------------------------------------------------
  // Transform cache
  // ---------------------------------------------------------------------------

  /// Invalidate cached world transform for this node and all descendants.
  ///
  /// When a parent moves, every child's world transform is stale.
  @override
  void invalidateTransformCache() {
    super.invalidateTransformCache();
    invalidateBoundsCache();
    for (final child in _children) {
      // Mark children as "propagating" so they don't individually
      // fire onNodeTransformInvalidated → avoids O(n²) cascade.
      child.propagatingTransform_ = true;
      child.invalidateTransformCache();
      child.propagatingTransform_ = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Verify that [child] is not an ancestor of this node (cycle prevention).
  void _assertNoCycle(CanvasNode child) {
    CanvasNode? current = this;
    while (current != null) {
      if (identical(current, child)) {
        throw StateError(
          'Cannot add node "${child.id}" as its own descendant — '
          'this would create a cycle in the scene graph.',
        );
      }
      current = current.parent;
    }
  }
}
