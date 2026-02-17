part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Clipboard Operations (copy, paste, duplicate)
// =============================================================================

extension _LassoClipboard on LassoTool {
  /// Copy selected elements to the internal clipboard.
  void _copySelected() {
    if (!hasSelection) return;

    final activeLayer = _getActiveLayer();

    _clipboardStrokes =
        activeLayer.strokes
            .where((s) => selectedStrokeIds.contains(s.id))
            .toList();

    _clipboardShapes =
        activeLayer.shapes
            .where((s) => selectedShapeIds.contains(s.id))
            .toList();

    _clipboardTexts =
        activeLayer.texts.where((t) => selectedTextIds.contains(t.id)).toList();

    _clipboardImages =
        activeLayer.images
            .where((i) => selectedImageIds.contains(i.id))
            .toList();
  }

  /// Paste clipboard contents into the active layer with a slight offset.
  ///
  /// Each pasted element gets a new unique ID to avoid collisions.
  /// Returns the number of elements pasted.
  int _pasteFromClipboard({Offset offset = const Offset(20, 20)}) {
    if (!hasClipboard) return 0;

    final activeLayer = _getActiveLayer();
    final now = DateTime.now();
    int count = 0;

    final pastedStrokes =
        _clipboardStrokes.map((stroke) {
          count++;
          final movedPoints =
              stroke.points
                  .map((p) => p.copyWith(position: p.position + offset))
                  .toList();
          return stroke.copyWith(
            id: 's_${now.microsecondsSinceEpoch}_$count',
            points: movedPoints,
            createdAt: now,
          );
        }).toList();

    final pastedShapes =
        _clipboardShapes.map((shape) {
          count++;
          return shape.copyWith(
            id: 'sh_${now.microsecondsSinceEpoch}_$count',
            startPoint: shape.startPoint + offset,
            endPoint: shape.endPoint + offset,
          );
        }).toList();

    final pastedTexts =
        _clipboardTexts.map((text) {
          count++;
          return text.copyWith(
            id: 'txt_${now.microsecondsSinceEpoch}_$count',
            position: text.position + offset,
            createdAt: now,
          );
        }).toList();

    final pastedImages =
        _clipboardImages.map((image) {
          count++;
          return image.copyWith(
            id: 'img_${now.microsecondsSinceEpoch}_$count',
            position: image.position + offset,
            createdAt: now,
          );
        }).toList();

    final updatedLayer = activeLayer.copyWith(
      strokes: [...activeLayer.strokes, ...pastedStrokes],
      shapes: [...activeLayer.shapes, ...pastedShapes],
      texts: [...activeLayer.texts, ...pastedTexts],
      images: [...activeLayer.images, ...pastedImages],
    );

    _updateLayer(updatedLayer);

    // Auto-select the pasted elements
    clearSelection();
    for (final s in pastedStrokes) {
      selectedStrokeIds.add(s.id);
    }
    for (final s in pastedShapes) {
      selectedShapeIds.add(s.id);
    }
    for (final t in pastedTexts) {
      selectedTextIds.add(t.id);
    }
    for (final i in pastedImages) {
      selectedImageIds.add(i.id);
    }
    _calculateSelectionBounds();

    return count;
  }

  /// Duplicate selected elements in-place with a slight offset.
  ///
  /// Combines copy + paste — the duplicated elements become the new selection.
  int _duplicateSelected({Offset offset = const Offset(20, 20)}) {
    _copySelected();
    return _pasteFromClipboard(offset: offset);
  }
}
