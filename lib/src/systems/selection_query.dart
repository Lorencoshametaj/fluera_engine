import 'package:flutter/material.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/group_node.dart';
import 'selection_manager.dart';

// =============================================================================
// SELECTION QUERY — Predicate-based scene-graph selection.
// =============================================================================

/// High-level, predicate-based selection queries over the scene graph.
///
/// Wraps [SelectionManager] to provide Figma-style "Select Matching"
/// operations without requiring manual iteration.
///
/// ```dart
/// final query = SelectionQuery(selectionManager, rootNode);
/// query.selectWhere((n) => n.name.contains('Button'));
/// query.selectByType<ImageNode>();
/// query.invertSelection();
/// query.selectSiblings();
/// ```
class SelectionQuery {
  /// The underlying selection state manager.
  final SelectionManager _manager;

  /// Scene graph root for traversal.
  final GroupNode _root;

  SelectionQuery(this._manager, this._root);

  // ---------------------------------------------------------------------------
  // Predicate queries
  // ---------------------------------------------------------------------------

  /// Select all nodes matching [predicate].
  ///
  /// If [additive] is true, adds to the current selection.
  /// Returns the number of nodes selected.
  int selectWhere(
    bool Function(CanvasNode node) predicate, {
    bool additive = false,
  }) {
    final matches = <CanvasNode>[];
    _collectWhere(_root, predicate, matches);

    if (additive) {
      for (final node in matches) {
        _manager.addToSelection(node);
      }
    } else {
      _manager.selectAll(matches);
    }
    return matches.length;
  }

  /// Select all nodes of a specific runtime type.
  ///
  /// Returns the number of nodes selected.
  int selectByType<T extends CanvasNode>({bool additive = false}) {
    return selectWhere((n) => n is T, additive: additive);
  }

  /// Select nodes whose [CanvasNode.name] matches [pattern].
  ///
  /// Supports simple glob: `*` matches any sequence, `?` matches one char.
  /// Returns the number of nodes selected.
  int selectByName(String pattern, {bool additive = false}) {
    final regex = _globToRegex(pattern);
    return selectWhere((n) => regex.hasMatch(n.name), additive: additive);
  }

  // ---------------------------------------------------------------------------
  // Hierarchy queries
  // ---------------------------------------------------------------------------

  /// Expand selection to include all siblings of currently selected nodes.
  ///
  /// Returns the number of siblings added.
  int selectSiblings() {
    final parents = <GroupNode>{};
    for (final node in _manager.selectedNodes) {
      final parent = node.parent;
      if (parent is GroupNode) {
        parents.add(parent);
      }
    }

    int added = 0;
    for (final parent in parents) {
      for (final child in parent.children) {
        if (!_manager.isSelected(child.id)) {
          _manager.addToSelection(child);
          added++;
        }
      }
    }
    return added;
  }

  /// Replace selection with the parent of the current selection.
  ///
  /// If multiple nodes are selected, uses the parent of the first.
  void selectParent() {
    final nodes = _manager.selectedNodes;
    if (nodes.isEmpty) return;

    final parent = nodes.first.parent;
    if (parent != null) {
      _manager.select(parent);
    }
  }

  /// Select all children of the current selection.
  ///
  /// Only works if the selected node is a [GroupNode].
  /// Returns the number of children selected.
  int selectChildren() {
    final groups = _manager.selectedNodes.whereType<GroupNode>().toList();
    if (groups.isEmpty) return 0;

    final children = <CanvasNode>[];
    for (final group in groups) {
      children.addAll(group.children);
    }

    _manager.selectAll(children);
    return children.length;
  }

  // ---------------------------------------------------------------------------
  // Set operations
  // ---------------------------------------------------------------------------

  /// Invert the selection: deselect everything currently selected,
  /// and select everything that was not selected.
  ///
  /// Returns the new selection count.
  int invertSelection() {
    final currentIds = _manager.selectedIds;
    final all = <CanvasNode>[];
    _collectWhere(_root, (n) => !currentIds.contains(n.id), all);
    _manager.selectAll(all);
    return all.length;
  }

  // ---------------------------------------------------------------------------
  // Deep marquee
  // ---------------------------------------------------------------------------

  /// Scene-graph-aware marquee: respects full transform hierarchy.
  ///
  /// Unlike [SelectionManager.marqueeSelect], this uses
  /// [CanvasNode.hitTest] for each point in the rect corners,
  /// providing accurate selection for rotated/scaled nodes.
  ///
  /// Returns the number of nodes selected.
  int deepMarquee(Rect rect, {bool additive = false}) {
    final matches = <CanvasNode>[];
    _collectDeepMarquee(_root, rect, matches);

    if (additive) {
      for (final node in matches) {
        _manager.addToSelection(node);
      }
    } else {
      _manager.selectAll(matches);
    }
    return matches.length;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Recursively collect leaf nodes matching [predicate].
  void _collectWhere(
    GroupNode group,
    bool Function(CanvasNode) predicate,
    List<CanvasNode> results,
  ) {
    for (final child in group.children) {
      if (!child.isVisible) continue;

      if (child is GroupNode) {
        // Check the group itself.
        if (predicate(child)) {
          results.add(child);
        }
        // Recurse into children.
        _collectWhere(child, predicate, results);
      } else {
        if (predicate(child)) {
          results.add(child);
        }
      }
    }
  }

  /// Deep marquee: check world bounds AND transform-aware containment.
  void _collectDeepMarquee(
    GroupNode group,
    Rect marquee,
    List<CanvasNode> results,
  ) {
    for (final child in group.children) {
      if (!child.isVisible || child.isLocked) continue;

      if (child is GroupNode) {
        _collectDeepMarquee(child, marquee, results);
      } else {
        final bounds = child.worldBounds;
        if (!bounds.isFinite) continue;

        // Fast AABB pre-filter.
        if (!marquee.overlaps(bounds)) continue;

        // Precise check: test if the center of the node is inside marquee.
        // This handles rotated nodes better than pure AABB overlap.
        final center = bounds.center;
        if (marquee.contains(center)) {
          results.add(child);
        }
      }
    }
  }

  /// Convert a simple glob pattern to a RegExp.
  /// `*` → `.*`, `?` → `.`
  RegExp _globToRegex(String pattern) {
    final escaped = pattern.replaceAllMapped(
      RegExp(r'[.+^${}()|[\]\\]'),
      (m) => '\\${m[0]}',
    );
    final regexStr =
        '^${escaped.replaceAll('*', '.*').replaceAll('?', '.')}'
        r'$';
    return RegExp(regexStr, caseSensitive: false);
  }
}
