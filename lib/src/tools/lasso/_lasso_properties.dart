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

extension _LassoProperties on LassoTool {
  // ===========================================================================
  // Selection Statistics
  // ===========================================================================

  /// Get a breakdown of selected element counts by type.
  SelectionStats _getSelectionStats() {
    return SelectionStats(
      strokes: selectedStrokeIds.length,
      shapes: selectedShapeIds.length,
      texts: selectedTextIds.length,
      images: selectedImageIds.length,
    );
  }

  // ===========================================================================
  // Lock / Unlock Elements
  // ===========================================================================

  /// Lock all currently selected elements.
  ///
  /// Locked elements cannot be moved, transformed, or deleted until unlocked.
  void _lockSelected() {
    _lockedIds.addAll(selectedStrokeIds);
    _lockedIds.addAll(selectedShapeIds);
    _lockedIds.addAll(selectedTextIds);
    _lockedIds.addAll(selectedImageIds);
  }

  /// Unlock all currently selected elements.
  void _unlockSelected() {
    _lockedIds.removeAll(selectedStrokeIds);
    _lockedIds.removeAll(selectedShapeIds);
    _lockedIds.removeAll(selectedTextIds);
    _lockedIds.removeAll(selectedImageIds);
  }

  /// Check if an element ID is locked.
  bool _isLocked(String id) => _lockedIds.contains(id);

  /// Check if the entire current selection is locked.
  bool _isSelectionLocked() {
    final allIds = {
      ...selectedStrokeIds,
      ...selectedShapeIds,
      ...selectedTextIds,
      ...selectedImageIds,
    };
    return allIds.isNotEmpty && allIds.every(_lockedIds.contains);
  }

  // ===========================================================================
  // Opacity Control
  // ===========================================================================

  /// Set the opacity for all selected strokes and shapes.
  ///
  /// [opacity] must be between 0.0 (fully transparent) and 1.0 (fully opaque).
  void _setSelectedOpacity(double opacity) {
    if (!hasSelection) return;
    final clamped = opacity.clamp(0.0, 1.0);
    final activeLayer = _getActiveLayer();

    final updatedStrokes =
        activeLayer.strokes.map((s) {
          if (!selectedStrokeIds.contains(s.id)) return s;
          // Apply opacity via color alpha channel
          final newColor = s.color.withValues(alpha: clamped);
          return s.copyWith(color: newColor);
        }).toList();

    final updatedShapes =
        activeLayer.shapes.map((s) {
          if (!selectedShapeIds.contains(s.id)) return s;
          final newColor = s.color.withValues(alpha: clamped);
          return s.copyWith(color: newColor);
        }).toList();

    _updateLayer(
      activeLayer.copyWith(strokes: updatedStrokes, shapes: updatedShapes),
    );
  }

  // ===========================================================================
  // Color Override
  // ===========================================================================

  /// Change the color of all selected strokes and shapes.
  ///
  /// Preserves the existing alpha (opacity) of each element.
  void _setSelectedColor(Color newColor) {
    if (!hasSelection) return;
    final activeLayer = _getActiveLayer();

    final updatedStrokes =
        activeLayer.strokes.map((s) {
          if (!selectedStrokeIds.contains(s.id)) return s;
          // Preserve original alpha
          final color = newColor.withValues(alpha: s.color.a);
          return s.copyWith(color: color);
        }).toList();

    final updatedShapes =
        activeLayer.shapes.map((s) {
          if (!selectedShapeIds.contains(s.id)) return s;
          final color = newColor.withValues(alpha: s.color.a);
          return s.copyWith(color: color);
        }).toList();

    _updateLayer(
      activeLayer.copyWith(strokes: updatedStrokes, shapes: updatedShapes),
    );
  }

  // ===========================================================================
  // Proportional Scaling
  // ===========================================================================

  /// Scale selected elements while maintaining their aspect ratio.
  ///
  /// [factor] Scale factor (>1 = enlarge, <1 = shrink).
  /// Both X and Y are scaled by the same factor, preserving proportions.
  void _scaleProportional(double factor, {Offset? center}) {
    // Proportional scaling is identical to regular scaling since
    // we apply the same factor to both axes. The constraint is
    // enforced at the interaction level (transform handles).
    _scaleSelected(factor, center: center);
  }

  // ===========================================================================
  // Multi-Layer Selection
  // ===========================================================================

  /// Select elements from ALL visible layers (not just the active layer).
  ///
  /// This extends the lasso to cross layer boundaries, useful for
  /// complex compositions where elements span multiple layers.
  void _selectFromAllLayers(Path lassoPath) {
    final lassoBounds = lassoPath.getBounds();

    for (final layer in layerController.layers) {
      // Skip invisible layers
      if (!layer.isVisible) continue;

      for (final stroke in layer.strokes) {
        if (!stroke.bounds.overlaps(lassoBounds)) continue;
        if (_strokeIntersectsPath(stroke, lassoPath)) {
          selectedStrokeIds.add(stroke.id);
        }
      }

      for (final shape in layer.shapes) {
        final shapeBounds = Rect.fromPoints(shape.startPoint, shape.endPoint);
        if (!shapeBounds.overlaps(lassoBounds)) continue;
        if (_shapeIntersectsPath(shape, lassoPath)) {
          selectedShapeIds.add(shape.id);
        }
      }

      for (final text in layer.texts) {
        final textBounds = _estimateTextBounds(text);
        if (!textBounds.overlaps(lassoBounds)) continue;
        if (_textIntersectsPath(text, lassoPath)) {
          selectedTextIds.add(text.id);
        }
      }

      for (final image in layer.images) {
        final imageBounds = _estimateImageBounds(image);
        if (!imageBounds.overlaps(lassoBounds)) continue;
        if (_imageIntersectsPath(image, lassoPath)) {
          selectedImageIds.add(image.id);
        }
      }
    }
  }

  // ===========================================================================
  // Export Selection
  // ===========================================================================

  /// Get the selection bounds (useful for external export via RepaintBoundary).
  ///
  /// Returns a [Rect] cropped to the exact selection area without padding.
  /// External code can use this with a [RepaintBoundary] and
  /// [RenderRepaintBoundary.toImage] to capture the selection.
  Rect? _getExportBounds() {
    if (!hasSelection) return null;

    final activeLayer = _getActiveLayer();
    Rect? bounds;

    for (final stroke in activeLayer.strokes) {
      if (selectedStrokeIds.contains(stroke.id)) {
        bounds = bounds?.expandToInclude(stroke.bounds) ?? stroke.bounds;
      }
    }
    for (final shape in activeLayer.shapes) {
      if (selectedShapeIds.contains(shape.id)) {
        final r = Rect.fromPoints(shape.startPoint, shape.endPoint);
        bounds = bounds?.expandToInclude(r) ?? r;
      }
    }
    for (final text in activeLayer.texts) {
      if (selectedTextIds.contains(text.id)) {
        final r = _estimateTextBounds(text);
        bounds = bounds?.expandToInclude(r) ?? r;
      }
    }
    for (final image in activeLayer.images) {
      if (selectedImageIds.contains(image.id)) {
        final r = _estimateImageBounds(image);
        bounds = bounds?.expandToInclude(r) ?? r;
      }
    }

    return bounds;
  }
}
