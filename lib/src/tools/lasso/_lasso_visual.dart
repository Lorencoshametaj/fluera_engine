part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Visual/UX Features (rubber band, additive, guides, persistence)
// =============================================================================

/// Rubber band (marquee) selection mode.
enum SelectionMode {
  /// Freehand lasso path.
  lasso,

  /// Rectangular marquee.
  marquee,
}

extension _LassoVisual on LassoTool {
  // ===========================================================================
  // Rubber Band / Marquee Selection
  // ===========================================================================

  /// Start a marquee (rectangular) selection.
  void _startMarquee(Offset position) {
    _marqueeStart = position;
    _marqueeEnd = position;
  }

  /// Update the marquee rectangle as the user drags.
  void _updateMarquee(Offset position) {
    _marqueeEnd = position;
  }

  /// Complete the marquee selection — creates a rectangular path
  /// and selects elements within it using existing hit-testing.
  void _completeMarquee() {
    if (_marqueeStart == null || _marqueeEnd == null) return;

    final rect = Rect.fromPoints(_marqueeStart!, _marqueeEnd!);
    if (rect.width < 4 && rect.height < 4) {
      _marqueeStart = null;
      _marqueeEnd = null;
      return;
    }

    final path = Path()..addRect(rect);

    if (_additiveMode) {
      // Keep existing selection, add new elements
      _selectElementsInPath(path);
    } else {
      clearSelection();
      _selectElementsInPath(path);
    }

    expandSelectionToGroups();
    _calculateSelectionBounds();
    _marqueeStart = null;
    _marqueeEnd = null;
  }

  /// Get the current marquee rectangle (for rendering).
  Rect? _getMarqueeRect() {
    if (_marqueeStart == null || _marqueeEnd == null) return null;
    return Rect.fromPoints(_marqueeStart!, _marqueeEnd!);
  }

  // ===========================================================================
  // Additive Selection (Shift + Lasso)
  // ===========================================================================

  /// Complete a lasso in additive mode — adds to existing selection
  /// without clearing first.
  void _completeLassoAdditive() {
    if (lassoPath.length < 3) {
      lassoPath.clear();
      return;
    }

    if (lassoPath.first != lassoPath.last) {
      lassoPath.add(lassoPath.first);
    }

    final path = Path();
    path.moveTo(lassoPath.first.dx, lassoPath.first.dy);
    for (var i = 1; i < lassoPath.length; i++) {
      path.lineTo(lassoPath[i].dx, lassoPath[i].dy);
    }
    path.close();

    // Don't clear — just add to existing selection
    _selectElementsInPath(path);
    expandSelectionToGroups();
    _calculateSelectionBounds();
    lassoPath.clear();
  }

  // ===========================================================================
  // Smart Guide Integration
  // ===========================================================================

  /// Collect bounds of all non-selected elements for guide detection.
  List<Rect> _getNonSelectedElementBounds() {
    final activeLayer = _getActiveLayer();
    final bounds = <Rect>[];

    for (final stroke in activeLayer.strokes) {
      if (!selectedStrokeIds.contains(stroke.id)) {
        bounds.add(stroke.bounds);
      }
    }
    for (final shape in activeLayer.shapes) {
      if (!selectedShapeIds.contains(shape.id)) {
        bounds.add(Rect.fromPoints(shape.startPoint, shape.endPoint));
      }
    }
    for (final text in activeLayer.texts) {
      if (!selectedTextIds.contains(text.id)) {
        bounds.add(_estimateTextBounds(text));
      }
    }
    for (final image in activeLayer.images) {
      if (!selectedImageIds.contains(image.id)) {
        bounds.add(_estimateImageBounds(image));
      }
    }
    return bounds;
  }

  // ===========================================================================
  // Selection Persistence (JSON serialization)
  // ===========================================================================

  /// Serialize the current selection state to a JSON-compatible map.
  Map<String, dynamic> _serializeSelection() {
    return {
      'strokeIds': selectedStrokeIds.toList(),
      'shapeIds': selectedShapeIds.toList(),
      'textIds': selectedTextIds.toList(),
      'imageIds': selectedImageIds.toList(),
      'lockedIds': _lockedIds.toList(),
      'groups': _groups.map((k, v) => MapEntry(k, v.toList())),
      'snapEnabled': snapEnabled,
      'gridSpacing': gridSpacing,
      'multiLayerMode': multiLayerMode,
      'selectionMode': _selectionMode.index,
    };
  }

  /// Restore selection state from a previously serialized map.
  void _deserializeSelection(Map<String, dynamic> data) {
    clearSelection();

    final strokeIds = data['strokeIds'] as List<dynamic>?;
    if (strokeIds != null) {
      selectedStrokeIds.addAll(strokeIds.cast<String>());
    }
    final shapeIds = data['shapeIds'] as List<dynamic>?;
    if (shapeIds != null) {
      selectedShapeIds.addAll(shapeIds.cast<String>());
    }
    final textIds = data['textIds'] as List<dynamic>?;
    if (textIds != null) {
      selectedTextIds.addAll(textIds.cast<String>());
    }
    final imageIds = data['imageIds'] as List<dynamic>?;
    if (imageIds != null) {
      selectedImageIds.addAll(imageIds.cast<String>());
    }

    final lockedIds = data['lockedIds'] as List<dynamic>?;
    if (lockedIds != null) {
      _lockedIds.addAll(lockedIds.cast<String>());
    }

    final groups = data['groups'] as Map<String, dynamic>?;
    if (groups != null) {
      _groups.clear();
      for (final entry in groups.entries) {
        _groups[entry.key] =
            (entry.value as List<dynamic>).cast<String>().toSet();
      }
    }

    snapEnabled = data['snapEnabled'] as bool? ?? false;
    gridSpacing =
        (data['gridSpacing'] as num?)?.toDouble() ?? _kDefaultGridSpacing;
    multiLayerMode = data['multiLayerMode'] as bool? ?? false;

    final modeIndex = data['selectionMode'] as int?;
    if (modeIndex != null && modeIndex < SelectionMode.values.length) {
      _selectionMode = SelectionMode.values[modeIndex];
    }

    if (hasSelection) {
      _calculateSelectionBounds();
    }
  }
}
