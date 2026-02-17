import 'package:flutter/material.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/group_node.dart';

/// Manages the set of currently selected nodes and provides
/// aggregate operations (bounding box, group transforms, marquee).
///
/// This is the core selection state manager. UI controllers should
/// listen to [onSelectionChanged] to update visual handles.
///
/// ```dart
/// final selection = SelectionManager();
/// selection.select(node1);
/// selection.toggleSelect(node2);
/// print(selection.aggregateBounds); // union of both bounds
/// selection.transformAll(Matrix4.translationValues(10, 0, 0));
/// ```
class SelectionManager {
  final Set<String> _selectedIds = {};
  final Map<String, CanvasNode> _nodeCache = {};

  /// Callback fired whenever the selection changes.
  void Function()? onSelectionChanged;

  // ---------------------------------------------------------------------------
  // State queries
  // ---------------------------------------------------------------------------

  /// Currently selected node IDs.
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);

  /// Number of selected nodes.
  int get count => _selectedIds.length;

  /// Whether anything is selected.
  bool get isEmpty => _selectedIds.isEmpty;
  bool get isNotEmpty => _selectedIds.isNotEmpty;

  /// Whether exactly one node is selected.
  bool get isSingle => _selectedIds.length == 1;

  /// Whether multiple nodes are selected.
  bool get isMultiple => _selectedIds.length > 1;

  /// Whether [nodeId] is in the selection.
  bool isSelected(String nodeId) => _selectedIds.contains(nodeId);

  /// All selected nodes (resolved from cache).
  List<CanvasNode> get selectedNodes =>
      _selectedIds.map((id) => _nodeCache[id]).whereType<CanvasNode>().toList();

  /// The single selected node, or null if 0 or 2+ selected.
  CanvasNode? get singleSelected =>
      isSingle ? _nodeCache[_selectedIds.first] : null;

  // ---------------------------------------------------------------------------
  // Selection operations
  // ---------------------------------------------------------------------------

  /// Select a single node, clearing previous selection.
  void select(CanvasNode node) {
    _selectedIds.clear();
    _nodeCache.clear();
    _selectedIds.add(node.id);
    _nodeCache[node.id] = node;
    _notify();
  }

  /// Add a node to the selection (Shift+click behavior).
  void addToSelection(CanvasNode node) {
    _selectedIds.add(node.id);
    _nodeCache[node.id] = node;
    _notify();
  }

  /// Toggle a node in/out of the selection.
  void toggleSelect(CanvasNode node) {
    if (_selectedIds.contains(node.id)) {
      _selectedIds.remove(node.id);
      _nodeCache.remove(node.id);
    } else {
      _selectedIds.add(node.id);
      _nodeCache[node.id] = node;
    }
    _notify();
  }

  /// Remove a specific node from the selection.
  void deselect(String nodeId) {
    _selectedIds.remove(nodeId);
    _nodeCache.remove(nodeId);
    _notify();
  }

  /// Clear the entire selection.
  void clearSelection() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    _nodeCache.clear();
    _notify();
  }

  /// Select multiple nodes at once.
  void selectAll(List<CanvasNode> nodes) {
    _selectedIds.clear();
    _nodeCache.clear();
    for (final node in nodes) {
      _selectedIds.add(node.id);
      _nodeCache[node.id] = node;
    }
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Marquee (rubber band) selection
  // ---------------------------------------------------------------------------

  /// Select all nodes in [root] whose world bounds intersect [marqueeRect].
  ///
  /// If [additive] is true, adds to existing selection (Shift+drag).
  /// Skips locked and invisible nodes.
  void marqueeSelect(
    GroupNode root,
    Rect marqueeRect, {
    bool additive = false,
  }) {
    if (!additive) {
      _selectedIds.clear();
      _nodeCache.clear();
    }

    _marqueeCollect(root, marqueeRect);
    _notify();
  }

  void _marqueeCollect(GroupNode group, Rect marquee) {
    for (final child in group.children) {
      if (!child.isVisible || child.isLocked) continue;

      if (child is GroupNode) {
        // Recurse into groups
        _marqueeCollect(child, marquee);
      } else {
        // Leaf node: check bounds intersection
        final bounds = child.worldBounds;
        if (bounds.isFinite && marquee.overlaps(bounds)) {
          _selectedIds.add(child.id);
          _nodeCache[child.id] = child;
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Selection filters
  // ---------------------------------------------------------------------------

  /// Filter selection to only nodes of type [T].
  List<T> selectedOfType<T extends CanvasNode>() =>
      selectedNodes.whereType<T>().toList();

  /// Remove locked nodes from the selection.
  void removeLockedFromSelection() {
    final lockedIds =
        selectedNodes.where((n) => n.isLocked).map((n) => n.id).toList();
    for (final id in lockedIds) {
      _selectedIds.remove(id);
      _nodeCache.remove(id);
    }
    if (lockedIds.isNotEmpty) _notify();
  }

  // ---------------------------------------------------------------------------
  // Aggregate bounds
  // ---------------------------------------------------------------------------

  /// Bounding box enclosing all selected nodes (world space).
  Rect get aggregateBounds {
    if (_selectedIds.isEmpty) return Rect.zero;

    Rect? result;
    for (final node in selectedNodes) {
      final bounds = node.worldBounds;
      if (!bounds.isFinite || bounds.isEmpty) continue;
      result = result == null ? bounds : result.expandToInclude(bounds);
    }
    return result ?? Rect.zero;
  }

  /// Center point of the aggregate bounding box.
  Offset get aggregateCenter => aggregateBounds.center;

  // ---------------------------------------------------------------------------
  // Group transforms
  // ---------------------------------------------------------------------------

  /// Translate all selected nodes by [dx], [dy].
  void translateAll(double dx, double dy) {
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      node.translate(dx, dy);
    }
  }

  /// Rotate all selected nodes around the selection center by [radians].
  void rotateAll(double radians) {
    final pivot = aggregateCenter;
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      node.rotateAround(radians, pivot);
    }
  }

  /// Scale all selected nodes from the selection center by [sx], [sy].
  void scaleAll(double sx, double sy) {
    final anchor = aggregateCenter;
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      node.scaleFrom(sx, sy, anchor);
    }
  }

  /// Apply a full transform matrix to all selected nodes.
  ///
  /// The transform is applied relative to the aggregate center,
  /// so nodes scale/rotate around the selection midpoint.
  void transformAll(Matrix4 transform) {
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      node.localTransform = transform.multiplied(node.localTransform);
    }
  }

  // ---------------------------------------------------------------------------
  // Alignment helpers
  // ---------------------------------------------------------------------------

  /// Align all selected nodes' left edges to the leftmost node.
  void alignLeft() {
    if (!isMultiple) return;
    final targetX = aggregateBounds.left;
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      final dx = targetX - node.worldBounds.left;
      node.translate(dx, 0);
    }
  }

  /// Align all selected nodes' right edges to the rightmost node.
  void alignRight() {
    if (!isMultiple) return;
    final targetX = aggregateBounds.right;
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      final dx = targetX - node.worldBounds.right;
      node.translate(dx, 0);
    }
  }

  /// Align all selected nodes' top edges to the topmost node.
  void alignTop() {
    if (!isMultiple) return;
    final targetY = aggregateBounds.top;
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      final dy = targetY - node.worldBounds.top;
      node.translate(0, dy);
    }
  }

  /// Align all selected nodes' bottom edges to the bottommost node.
  void alignBottom() {
    if (!isMultiple) return;
    final targetY = aggregateBounds.bottom;
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      final dy = targetY - node.worldBounds.bottom;
      node.translate(0, dy);
    }
  }

  /// Center all selected nodes horizontally relative to aggregate bounds.
  void alignCenterH() {
    if (!isMultiple) return;
    final targetX = aggregateBounds.center.dx;
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      final dx = targetX - node.worldBounds.center.dx;
      node.translate(dx, 0);
    }
  }

  /// Center all selected nodes vertically relative to aggregate bounds.
  void alignCenterV() {
    if (!isMultiple) return;
    final targetY = aggregateBounds.center.dy;
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      final dy = targetY - node.worldBounds.center.dy;
      node.translate(0, dy);
    }
  }

  /// Distribute selected nodes evenly (equal spacing) along the X axis.
  void distributeHorizontally() {
    if (count < 3) return;
    final nodes =
        selectedNodes.where((n) => !n.isLocked).toList()
          ..sort((a, b) => a.worldBounds.left.compareTo(b.worldBounds.left));

    if (nodes.length < 3) return;

    final totalWidth =
        nodes.last.worldBounds.right - nodes.first.worldBounds.left;
    final contentWidth = nodes.fold<double>(
      0,
      (sum, n) => sum + n.worldBounds.width,
    );
    final spacing = (totalWidth - contentWidth) / (nodes.length - 1);

    double currentX = nodes.first.worldBounds.right + spacing;
    for (int i = 1; i < nodes.length - 1; i++) {
      final dx = currentX - nodes[i].worldBounds.left;
      nodes[i].translate(dx, 0);
      currentX = nodes[i].worldBounds.right + spacing;
    }
  }

  /// Distribute selected nodes evenly along the Y axis.
  void distributeVertically() {
    if (count < 3) return;
    final nodes =
        selectedNodes.where((n) => !n.isLocked).toList()
          ..sort((a, b) => a.worldBounds.top.compareTo(b.worldBounds.top));

    if (nodes.length < 3) return;

    final totalHeight =
        nodes.last.worldBounds.bottom - nodes.first.worldBounds.top;
    final contentHeight = nodes.fold<double>(
      0,
      (sum, n) => sum + n.worldBounds.height,
    );
    final spacing = (totalHeight - contentHeight) / (nodes.length - 1);

    double currentY = nodes.first.worldBounds.bottom + spacing;
    for (int i = 1; i < nodes.length - 1; i++) {
      final dy = currentY - nodes[i].worldBounds.top;
      nodes[i].translate(0, dy);
      currentY = nodes[i].worldBounds.bottom + spacing;
    }
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Serialize current selection state.
  Map<String, dynamic> toJson() => {'selectedIds': _selectedIds.toList()};

  /// Restore selection from JSON. Nodes must be re-resolved from the
  /// scene graph after deserialization.
  void loadFromJson(
    Map<String, dynamic> json,
    CanvasNode? Function(String id) nodeResolver,
  ) {
    _selectedIds.clear();
    _nodeCache.clear();

    final ids = (json['selectedIds'] as List<dynamic>?) ?? [];
    for (final id in ids) {
      final node = nodeResolver(id as String);
      if (node != null) {
        _selectedIds.add(node.id);
        _nodeCache[node.id] = node;
      }
    }
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _notify() {
    onSelectionChanged?.call();
  }
}
