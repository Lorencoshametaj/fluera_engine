import 'dart:async';
import 'package:flutter/material.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/group_node.dart';
import '../core/engine_scope.dart';
import '../core/engine_event.dart';

// =============================================================================
// SELECTION EVENTS — Reactive change notifications.
// =============================================================================

/// Kind of selection change.
enum SelectionChangeType {
  /// One or more nodes were added to the selection.
  selected,

  /// One or more nodes were removed from the selection.
  deselected,

  /// The entire selection was cleared.
  cleared,

  /// The selection was fully replaced (e.g. selectAll, marquee).
  replaced,
}

/// A single, immutable selection change event.
class SelectionEvent {
  /// What kind of change happened.
  final SelectionChangeType type;

  /// IDs of the nodes affected by this change.
  final List<String> affectedIds;

  /// Total number of selected nodes after this change.
  final int totalSelected;

  /// When the change occurred.
  final DateTime timestamp;

  const SelectionEvent({
    required this.type,
    required this.affectedIds,
    required this.totalSelected,
    required this.timestamp,
  });

  @override
  String toString() =>
      'SelectionEvent(${type.name}, affected=${affectedIds.length}, '
      'total=$totalSelected)';
}

// =============================================================================
// SELECTION MANAGER
// =============================================================================

/// Manages the set of currently selected nodes and provides
/// aggregate operations (bounding box, group transforms, marquee).
///
/// This is the core selection state manager. UI controllers should
/// listen to [selectionEvents] for reactive updates.
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

  /// Legacy callback fired whenever the selection changes.
  void Function()? onSelectionChanged;

  // ---------------------------------------------------------------------------
  // Event stream
  // ---------------------------------------------------------------------------

  final StreamController<SelectionEvent> _eventController =
      StreamController<SelectionEvent>.broadcast();

  /// Reactive stream of selection change events.
  ///
  /// Use this instead of [onSelectionChanged] for fine-grained updates.
  Stream<SelectionEvent> get selectionEvents => _eventController.stream;

  // ---------------------------------------------------------------------------
  // Selection history
  // ---------------------------------------------------------------------------

  /// Max selection states to remember.
  static const int _maxHistory = 10;
  final List<Set<String>> _selectionHistory = [];

  /// Re-select the previous selection.
  ///
  /// Pops the most recent history entry and restores it.
  /// Returns true if history was available and applied.
  bool reselectPrevious() {
    if (_selectionHistory.isEmpty) return false;

    final previous = _selectionHistory.removeLast();
    final oldIds = _selectedIds.toList();

    _selectedIds.clear();
    _nodeCache.removeWhere((id, _) => !previous.contains(id));

    for (final id in previous) {
      _selectedIds.add(id);
      // Node cache may be stale if nodes were removed; keep what we have.
    }

    _emit(SelectionChangeType.replaced, oldIds);
    return true;
  }

  /// Available history depth.
  int get historyDepth => _selectionHistory.length;

  /// Push current selection to history before changing it.
  void _pushHistory() {
    if (_selectedIds.isEmpty && _selectionHistory.isEmpty) return;

    _selectionHistory.add(Set<String>.from(_selectedIds));
    if (_selectionHistory.length > _maxHistory) {
      _selectionHistory.removeAt(0);
    }
  }

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
    _pushHistory();
    final oldIds = _selectedIds.toList();
    _selectedIds.clear();
    _nodeCache.clear();
    _selectedIds.add(node.id);
    _nodeCache[node.id] = node;
    _emit(SelectionChangeType.replaced, [...oldIds, node.id]);
  }

  /// Add a node to the selection (Shift+click behavior).
  void addToSelection(CanvasNode node) {
    _pushHistory();
    _selectedIds.add(node.id);
    _nodeCache[node.id] = node;
    _emit(SelectionChangeType.selected, [node.id]);
  }

  /// Toggle a node in/out of the selection.
  void toggleSelect(CanvasNode node) {
    _pushHistory();
    if (_selectedIds.contains(node.id)) {
      _selectedIds.remove(node.id);
      _nodeCache.remove(node.id);
      _emit(SelectionChangeType.deselected, [node.id]);
    } else {
      _selectedIds.add(node.id);
      _nodeCache[node.id] = node;
      _emit(SelectionChangeType.selected, [node.id]);
    }
  }

  /// Remove a specific node from the selection.
  void deselect(String nodeId) {
    _pushHistory();
    _selectedIds.remove(nodeId);
    _nodeCache.remove(nodeId);
    _emit(SelectionChangeType.deselected, [nodeId]);
  }

  /// Clear the entire selection.
  void clearSelection() {
    if (_selectedIds.isEmpty) return;
    _pushHistory();
    final oldIds = _selectedIds.toList();
    _selectedIds.clear();
    _nodeCache.clear();
    _emit(SelectionChangeType.cleared, oldIds);
  }

  /// Select multiple nodes at once.
  void selectAll(List<CanvasNode> nodes) {
    _pushHistory();
    final oldIds = _selectedIds.toList();
    _selectedIds.clear();
    _nodeCache.clear();
    for (final node in nodes) {
      _selectedIds.add(node.id);
      _nodeCache[node.id] = node;
    }
    _emit(SelectionChangeType.replaced, [...oldIds, ...nodes.map((n) => n.id)]);
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
    _pushHistory();
    if (!additive) {
      _selectedIds.clear();
      _nodeCache.clear();
    }

    final before = _selectedIds.length;
    _marqueeCollect(root, marqueeRect);
    final newIds = _selectedIds.skip(before).toList();
    _emit(
      additive ? SelectionChangeType.selected : SelectionChangeType.replaced,
      newIds,
    );
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
    if (lockedIds.isNotEmpty) {
      _emit(SelectionChangeType.deselected, lockedIds);
    }
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
  // Flip
  // ---------------------------------------------------------------------------

  /// Flip all selected nodes horizontally around the selection center.
  void flipHorizontal() {
    final anchor = aggregateCenter;
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      node.scaleFrom(-1, 1, anchor);
    }
  }

  /// Flip all selected nodes vertically around the selection center.
  void flipVertical() {
    final anchor = aggregateCenter;
    for (final node in selectedNodes) {
      if (node.isLocked) continue;
      node.scaleFrom(1, -1, anchor);
    }
  }

  // ---------------------------------------------------------------------------
  // Destructive operations
  // ---------------------------------------------------------------------------

  /// Delete all selected nodes from the scene graph.
  ///
  /// Each node is removed from its parent [GroupNode]. Returns the number
  /// of nodes removed.
  int deleteAll() {
    if (_selectedIds.isEmpty) return 0;
    _pushHistory();

    int removed = 0;
    for (final node in selectedNodes.toList()) {
      final parent = node.parent;
      if (parent is GroupNode) {
        parent.remove(node);
        removed++;
      }
    }

    final oldIds = _selectedIds.toList();
    _selectedIds.clear();
    _nodeCache.clear();
    _emit(SelectionChangeType.cleared, oldIds);
    return removed;
  }

  /// Duplicate all selected nodes with an offset.
  ///
  /// Each node is cloned (deep copy via JSON round-trip), translated
  /// by [offset], and added to its original parent. The duplicated
  /// nodes become the new selection.
  ///
  /// Returns the list of newly created nodes.
  List<CanvasNode> duplicateAll({Offset offset = const Offset(20, 20)}) {
    if (_selectedIds.isEmpty) return const [];

    final newNodes = <CanvasNode>[];
    for (final node in selectedNodes.toList()) {
      final parent = node.parent;
      if (parent is! GroupNode) continue;

      final clone = node.clone();
      clone.translate(offset.dx, offset.dy);
      parent.add(clone);
      newNodes.add(clone);
    }

    // Auto-select the duplicated nodes.
    if (newNodes.isNotEmpty) {
      selectAll(newNodes);
    }

    return newNodes;
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
    _emit(SelectionChangeType.replaced, _selectedIds.toList());
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  /// Close the event stream. Call when the manager is no longer needed.
  void dispose() {
    _eventController.close();
    _selectionHistory.clear();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  /// Emit a selection event and fire the legacy callback.
  void _emit(SelectionChangeType type, List<String> affectedIds) {
    if (!_eventController.isClosed) {
      _eventController.add(
        SelectionEvent(
          type: type,
          affectedIds: affectedIds,
          totalSelected: _selectedIds.length,
          timestamp: DateTime.now(),
        ),
      );
    }
    // Bridge to centralized event bus
    if (EngineScope.hasScope) {
      EngineScope.current.eventBus.emit(
        SelectionChangedEngineEvent(
          changeType: type.name,
          affectedIds: affectedIds,
          totalSelected: _selectedIds.length,
        ),
      );
    }
    onSelectionChanged?.call();
  }
}
