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

extension LassoVisual on LassoTool {
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

  /// Complete the marquee selection — uses SelectionManager.marqueeSelect.
  void _completeMarquee() {
    if (_marqueeStart == null || _marqueeEnd == null) return;

    final rect = Rect.fromPoints(_marqueeStart!, _marqueeEnd!);
    if (rect.width < 4 && rect.height < 4) {
      _marqueeStart = null;
      _marqueeEnd = null;
      return;
    }

    final layerNode = _getActiveLayerNode();
    selectionManager.marqueeSelect(layerNode, rect, additive: _additiveMode);

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

    // Hit test: add new nodes to existing selection
    final layerNode = _getActiveLayerNode();
    final lassoBounds = path.getBounds();

    for (final child in layerNode.children) {
      if (!child.isVisible || child.isLocked) continue;
      if (selectionManager.isSelected(child.id)) continue;

      final bounds = child.worldBounds;
      if (!bounds.isFinite || bounds.isEmpty) continue;
      if (!bounds.overlaps(lassoBounds)) continue;

      if (path.contains(bounds.center)) {
        selectionManager.addToSelection(child);
      }
    }

    expandSelectionToGroups();
    _calculateSelectionBounds();
    lassoPath.clear();
  }

  // ===========================================================================
  // Smart Guide Integration
  // ===========================================================================

  /// Collect bounds of all non-selected elements for guide detection.
  List<Rect> _getNonSelectedElementBounds() {
    final layerNode = _getActiveLayerNode();
    final bounds = <Rect>[];

    for (final child in layerNode.children) {
      if (selectionManager.isSelected(child.id)) continue;
      final b = child.worldBounds;
      if (b.isFinite && !b.isEmpty) {
        bounds.add(b);
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
      'selectedIds': selectionManager.selectedIds.toList(),
      'snapEnabled': snapEnabled,
      'gridSpacing': gridSpacing,
      'multiLayerMode': multiLayerMode,
      'selectionMode': _selectionMode.index,
    };
  }

  /// Restore selection state from a previously serialized map.
  void _deserializeSelection(Map<String, dynamic> data) {
    clearSelection();

    final ids = data['selectedIds'] as List<dynamic>?;
    if (ids != null) {
      final layerNode = _getActiveLayerNode();
      final nodes = <CanvasNode>[];
      for (final id in ids) {
        final node = layerNode.findChild(id as String);
        if (node != null) nodes.add(node);
      }
      if (nodes.isNotEmpty) {
        selectionManager.selectAll(nodes);
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
