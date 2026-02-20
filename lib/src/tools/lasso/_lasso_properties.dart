part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Property Operations & Enterprise Features
// =============================================================================

/// Selection statistics breakdown by element type.
class SelectionStats {
  final int strokes;
  final int shapes;
  final int texts;
  final int images;
  final int total;

  const SelectionStats({
    required this.strokes,
    required this.shapes,
    required this.texts,
    required this.images,
  }) : total = strokes + shapes + texts + images;

  /// Human-readable summary, e.g. "3 strokes, 2 images"
  String get summary {
    final parts = <String>[];
    if (strokes > 0) parts.add('$strokes stroke${strokes > 1 ? 's' : ''}');
    if (shapes > 0) parts.add('$shapes shape${shapes > 1 ? 's' : ''}');
    if (texts > 0) parts.add('$texts text${texts > 1 ? 's' : ''}');
    if (images > 0) parts.add('$images image${images > 1 ? 's' : ''}');
    return parts.isEmpty ? 'Nothing selected' : parts.join(', ');
  }

  @override
  String toString() => 'SelectionStats($summary)';
}

extension LassoProperties on LassoTool {
  // ===========================================================================
  // Selection Statistics
  // ===========================================================================

  /// Get a breakdown of selected element counts by type.
  SelectionStats _getSelectionStats() {
    final layerNode = _getActiveLayerNode();
    final ids = selectionManager.selectedIds;

    int strokes = 0, shapes = 0, texts = 0, images = 0;
    for (final child in layerNode.children) {
      if (!ids.contains(child.id)) continue;
      if (child is StrokeNode) {
        strokes++;
      } else if (child is ShapeNode) {
        shapes++;
      } else if (child is TextNode) {
        texts++;
      } else if (child is ImageNode) {
        images++;
      }
    }

    return SelectionStats(
      strokes: strokes,
      shapes: shapes,
      texts: texts,
      images: images,
    );
  }

  // ===========================================================================
  // Lock / Unlock Elements
  // ===========================================================================

  /// Lock all currently selected elements.
  void _lockSelected() {
    for (final node in selectionManager.selectedNodes) {
      node.isLocked = true;
    }
  }

  /// Unlock all currently selected elements.
  void _unlockSelected() {
    for (final node in selectionManager.selectedNodes) {
      node.isLocked = false;
    }
  }

  /// Check if an element ID is locked.
  bool _isLocked(String id) {
    final node = _resolveNode(id);
    return node?.isLocked ?? false;
  }

  /// Check if the entire current selection is locked.
  bool _isSelectionLocked() {
    final nodes = selectionManager.selectedNodes;
    return nodes.isNotEmpty && nodes.every((n) => n.isLocked);
  }

  // ===========================================================================
  // Opacity Control
  // ===========================================================================

  /// Set the opacity for all selected elements.
  void _setSelectedOpacity(double opacity) {
    if (!hasSelection) return;
    final clamped = opacity.clamp(0.0, 1.0);
    for (final node in selectionManager.selectedNodes) {
      node.opacity = clamped;
    }
  }

  // ===========================================================================
  // Color Override
  // ===========================================================================

  /// Change the color of all selected strokes and shapes.
  ///
  /// Preserves the existing alpha (opacity) of each element.
  void _setSelectedColor(Color newColor) {
    if (!hasSelection) return;
    final layerNode = _getActiveLayerNode();

    for (final node in selectionManager.selectedNodes) {
      if (node is StrokeNode) {
        final color = newColor.withValues(alpha: node.stroke.color.a);
        node.stroke = node.stroke.copyWith(color: color);
      } else if (node is ShapeNode) {
        final color = newColor.withValues(alpha: node.shape.color.a);
        node.shape = node.shape.copyWith(color: color);
      }
    }
  }

  // ===========================================================================
  // Multi-Layer Selection
  // ===========================================================================

  /// Select elements from ALL visible layers.
  void _selectFromAllLayers(Path lassoPath) {
    final lassoBounds = lassoPath.getBounds();
    final hits = <CanvasNode>[];

    for (final layer in layerController.layers) {
      if (!layer.isVisible) continue;

      for (final child in layer.node.children) {
        if (!child.isVisible || child.isLocked) continue;

        final bounds = child.worldBounds;
        if (!bounds.isFinite || bounds.isEmpty) continue;
        if (!bounds.overlaps(lassoBounds)) continue;

        if (lassoPath.contains(bounds.center)) {
          hits.add(child);
        }
      }
    }

    if (hits.isNotEmpty) {
      selectionManager.selectAll(hits);
    }
  }

  // ===========================================================================
  // Export Selection
  // ===========================================================================

  /// Get the selection bounds (useful for external export).
  Rect? _getExportBounds() {
    if (!hasSelection) return null;
    final bounds = selectionManager.aggregateBounds;
    return bounds == Rect.zero ? null : bounds;
  }
}
