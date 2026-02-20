part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Advanced Features (select all, z-ordering, group, snap, undo)
// =============================================================================

/// Default grid spacing for snap-to-grid (in canvas units).
const double _kDefaultGridSpacing = 20.0;

extension LassoAdvanced on LassoTool {
  // ===========================================================================
  // Select All
  // ===========================================================================

  /// Select all elements in the active layer.
  void _selectAll() {
    final layerNode = _getActiveLayerNode();
    final allChildren =
        layerNode.children.where((c) => c.isVisible && !c.isLocked).toList();
    selectionManager.selectAll(allChildren);
    _calculateSelectionBounds();
  }

  // ===========================================================================
  // Z-Ordering — Bring to Front / Send to Back
  // ===========================================================================

  /// Bring selected elements to the front (end of children list).
  void _bringToFront() {
    if (!hasSelection) return;
    final layerNode = _getActiveLayerNode();

    // Collect selected children, remove them, then re-add at end
    final selected = <CanvasNode>[];
    for (final node in selectionManager.selectedNodes) {
      if (layerNode.children.contains(node)) {
        selected.add(node);
      }
    }

    for (final node in selected) {
      layerNode.remove(node);
    }
    for (final node in selected) {
      layerNode.add(node);
    }
  }

  /// Send selected elements to the back (start of children list).
  void _sendToBack() {
    if (!hasSelection) return;
    final layerNode = _getActiveLayerNode();

    // Collect non-selected and selected children in the right order
    final selected = <CanvasNode>[];
    final others = <CanvasNode>[];
    for (final child in layerNode.children) {
      if (selectionManager.isSelected(child.id)) {
        selected.add(child);
      } else {
        others.add(child);
      }
    }

    // Remove all, then re-add selected first, then others
    layerNode.clear();
    for (final node in selected) {
      layerNode.add(node);
    }
    for (final node in others) {
      layerNode.add(node);
    }
  }

  // ===========================================================================
  // Grouping — Lightweight In-Session Groups
  // ===========================================================================

  /// Group currently selected elements under a new GroupNode.
  ///
  /// Returns the group node ID, or null if nothing is selected.
  String? _groupSelected() {
    if (!hasSelection) return null;

    final layerNode = _getActiveLayerNode();
    final groupId = 'grp_${DateTime.now().microsecondsSinceEpoch}';
    final group = GroupNode(id: NodeId(groupId), name: 'Group');

    // Move selected nodes into the group
    final selected =
        selectionManager.selectedNodes
            .where((n) => layerNode.children.contains(n))
            .toList();

    for (final node in selected) {
      layerNode.remove(node);
      group.add(node);
    }

    layerNode.add(group);

    // Select the group itself
    selectionManager.select(group);
    _calculateSelectionBounds();

    return groupId;
  }

  /// Ungroup: if any selected element is a GroupNode, dissolve it.
  ///
  /// Returns the number of groups dissolved.
  int _ungroupSelected() {
    if (!hasSelection) return 0;

    final layerNode = _getActiveLayerNode();
    int dissolved = 0;
    final ungroupedChildren = <CanvasNode>[];

    for (final node in selectionManager.selectedNodes.toList()) {
      if (node is GroupNode && node.parent == layerNode) {
        // Move children out of the group
        final children = node.children.toList();
        for (final child in children) {
          node.remove(child);
          layerNode.add(child);
          ungroupedChildren.add(child);
        }
        layerNode.remove(node);
        dissolved++;
      }
    }

    if (ungroupedChildren.isNotEmpty) {
      selectionManager.selectAll(ungroupedChildren);
      _calculateSelectionBounds();
    }

    return dissolved;
  }

  /// Expand the current selection to include all elements that share a
  /// GroupNode parent with any currently selected element.
  void expandSelectionToGroups() {
    // For each selected node, if its parent is a GroupNode (not the layer),
    // select all siblings in that group.
    final layerNode = _getActiveLayerNode();
    final toAdd = <CanvasNode>[];

    for (final node in selectionManager.selectedNodes) {
      final parent = node.parent;
      if (parent is GroupNode && parent != layerNode) {
        for (final sibling in parent.children) {
          if (!selectionManager.isSelected(sibling.id)) {
            toAdd.add(sibling);
          }
        }
      }
    }

    for (final node in toAdd) {
      selectionManager.addToSelection(node);
    }

    if (toAdd.isNotEmpty) {
      _calculateSelectionBounds();
    }
  }

  // ===========================================================================
  // Snap-to-Grid
  // ===========================================================================

  /// Snap an offset to the nearest grid point.
  Offset _snapToGrid(
    Offset point, {
    double gridSpacing = _kDefaultGridSpacing,
  }) {
    return Offset(
      (point.dx / gridSpacing).round() * gridSpacing,
      (point.dy / gridSpacing).round() * gridSpacing,
    );
  }

  /// Snap a delta so the selection bounds' top-left aligns to the grid.
  Offset _snapDeltaToGrid(
    Offset delta, {
    double gridSpacing = _kDefaultGridSpacing,
  }) {
    if (_selectionBounds == null) return delta;

    final newTopLeft = _selectionBounds!.topLeft + delta;
    final snapped = _snapToGrid(newTopLeft, gridSpacing: gridSpacing);
    return delta + (snapped - newTopLeft);
  }

  // ===========================================================================
  // Undo Snapshot
  // ===========================================================================

  /// Take a snapshot of the current active layer state.
  CanvasLayer _takeSnapshot() {
    return _getActiveLayer();
  }

  /// Restore a previously taken snapshot, replacing the active layer.
  void _restoreSnapshot(CanvasLayer snapshot) {
    _updateLayer(snapshot);
  }
}
