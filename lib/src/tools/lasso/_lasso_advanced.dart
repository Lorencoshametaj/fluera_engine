part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Advanced Features (select all, z-ordering, group, snap, undo)
// =============================================================================

/// Default grid spacing for snap-to-grid (in canvas units).
const double _kDefaultGridSpacing = 20.0;

extension _LassoAdvanced on LassoTool {
  // ===========================================================================
  // Select All
  // ===========================================================================

  /// Select all elements in the active layer.
  void _selectAll() {
    final activeLayer = _getActiveLayer();

    for (final stroke in activeLayer.strokes) {
      selectedStrokeIds.add(stroke.id);
    }
    for (final shape in activeLayer.shapes) {
      selectedShapeIds.add(shape.id);
    }
    for (final text in activeLayer.texts) {
      selectedTextIds.add(text.id);
    }
    for (final image in activeLayer.images) {
      selectedImageIds.add(image.id);
    }

    _calculateSelectionBounds();
  }

  // ===========================================================================
  // Z-Ordering — Bring to Front / Send to Back
  // ===========================================================================

  /// Bring selected elements to the front of their respective lists.
  ///
  /// Moves selected strokes/shapes/texts/images to the end of their
  /// lists so they render on top.
  void _bringToFront() {
    if (!hasSelection) return;
    final activeLayer = _getActiveLayer();

    final (selectedStrokes, otherStrokes) = _partition(
      activeLayer.strokes,
      (s) => selectedStrokeIds.contains(s.id),
    );
    final (selectedShapes, otherShapes) = _partition(
      activeLayer.shapes,
      (s) => selectedShapeIds.contains(s.id),
    );
    final (selectedTexts, otherTexts) = _partition(
      activeLayer.texts,
      (t) => selectedTextIds.contains(t.id),
    );
    final (selectedImages, otherImages) = _partition(
      activeLayer.images,
      (i) => selectedImageIds.contains(i.id),
    );

    _updateLayer(
      activeLayer.copyWith(
        strokes: [...otherStrokes, ...selectedStrokes],
        shapes: [...otherShapes, ...selectedShapes],
        texts: [...otherTexts, ...selectedTexts],
        images: [...otherImages, ...selectedImages],
      ),
    );
  }

  /// Send selected elements to the back of their respective lists.
  ///
  /// Moves selected strokes/shapes/texts/images to the start of their
  /// lists so they render behind everything.
  void _sendToBack() {
    if (!hasSelection) return;
    final activeLayer = _getActiveLayer();

    final (selectedStrokes, otherStrokes) = _partition(
      activeLayer.strokes,
      (s) => selectedStrokeIds.contains(s.id),
    );
    final (selectedShapes, otherShapes) = _partition(
      activeLayer.shapes,
      (s) => selectedShapeIds.contains(s.id),
    );
    final (selectedTexts, otherTexts) = _partition(
      activeLayer.texts,
      (t) => selectedTextIds.contains(t.id),
    );
    final (selectedImages, otherImages) = _partition(
      activeLayer.images,
      (i) => selectedImageIds.contains(i.id),
    );

    _updateLayer(
      activeLayer.copyWith(
        strokes: [...selectedStrokes, ...otherStrokes],
        shapes: [...selectedShapes, ...otherShapes],
        texts: [...selectedTexts, ...otherTexts],
        images: [...selectedImages, ...otherImages],
      ),
    );
  }

  /// Partition a list into two: elements matching [test] and those that don't.
  (List<T>, List<T>) _partition<T>(List<T> items, bool Function(T) test) {
    final matched = <T>[];
    final rest = <T>[];
    for (final item in items) {
      if (test(item)) {
        matched.add(item);
      } else {
        rest.add(item);
      }
    }
    return (matched, rest);
  }

  // ===========================================================================
  // Grouping — Lightweight In-Session Groups
  // ===========================================================================

  /// Group currently selected elements under a shared group ID.
  ///
  /// Returns the generated group ID, or null if nothing is selected.
  String? _groupSelected() {
    if (!hasSelection) return null;

    final groupId = 'grp_${DateTime.now().microsecondsSinceEpoch}';
    final allIds = {
      ...selectedStrokeIds,
      ...selectedShapeIds,
      ...selectedTextIds,
      ...selectedImageIds,
    };
    _groups[groupId] = allIds;
    return groupId;
  }

  /// Ungroup: if any selected element belongs to a group, dissolve that group.
  ///
  /// Returns the number of groups dissolved.
  int _ungroupSelected() {
    if (!hasSelection) return 0;

    final allSelectedIds = {
      ...selectedStrokeIds,
      ...selectedShapeIds,
      ...selectedTextIds,
      ...selectedImageIds,
    };

    int dissolved = 0;
    final groupsToRemove = <String>[];
    for (final entry in _groups.entries) {
      if (entry.value.intersection(allSelectedIds).isNotEmpty) {
        groupsToRemove.add(entry.key);
        dissolved++;
      }
    }
    for (final key in groupsToRemove) {
      _groups.remove(key);
    }
    return dissolved;
  }

  /// Expand the current selection to include all elements that share a
  /// group with any currently selected element.
  void _expandSelectionToGroups() {
    if (_groups.isEmpty) return;

    final allSelectedIds = {
      ...selectedStrokeIds,
      ...selectedShapeIds,
      ...selectedTextIds,
      ...selectedImageIds,
    };

    // Find all group IDs that overlap with the current selection
    final expandedIds = <String>{};
    for (final entry in _groups.entries) {
      if (entry.value.intersection(allSelectedIds).isNotEmpty) {
        expandedIds.addAll(entry.value);
      }
    }

    if (expandedIds.isEmpty) return;

    // Map expanded IDs back to their element types
    final activeLayer = _getActiveLayer();
    for (final stroke in activeLayer.strokes) {
      if (expandedIds.contains(stroke.id)) selectedStrokeIds.add(stroke.id);
    }
    for (final shape in activeLayer.shapes) {
      if (expandedIds.contains(shape.id)) selectedShapeIds.add(shape.id);
    }
    for (final text in activeLayer.texts) {
      if (expandedIds.contains(text.id)) selectedTextIds.add(text.id);
    }
    for (final image in activeLayer.images) {
      if (expandedIds.contains(image.id)) selectedImageIds.add(image.id);
    }

    _calculateSelectionBounds();
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
  ///
  /// Returns the adjusted delta.
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
  ///
  /// Call this before performing destructive operations. The returned
  /// snapshot can be passed to [restoreSnapshot] to revert.
  CanvasLayer _takeSnapshot() {
    return _getActiveLayer();
  }

  /// Restore a previously taken snapshot, replacing the active layer.
  void _restoreSnapshot(CanvasLayer snapshot) {
    _updateLayer(snapshot);
  }
}
