part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Alignment & Distribution Tools
// =============================================================================

extension _LassoAlignment on LassoTool {
  // ===========================================================================
  // Alignment
  // ===========================================================================

  /// Align selected elements to the left edge of the selection bounds.
  void _alignLeft() {
    if (!hasSelection) return;
    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final targetX = _selectionBounds!.left + _kSelectionBoundsPadding;
    final activeLayer = _getActiveLayer();

    final alignedStrokes =
        activeLayer.strokes.map((s) {
          if (!selectedStrokeIds.contains(s.id)) return s;
          final bounds = s.bounds;
          final dx = targetX - bounds.left;
          return s.copyWith(
            points:
                s.points
                    .map(
                      (p) => p.copyWith(
                        position: Offset(p.position.dx + dx, p.position.dy),
                      ),
                    )
                    .toList(),
          );
        }).toList();

    final alignedShapes =
        activeLayer.shapes.map((s) {
          if (!selectedShapeIds.contains(s.id)) return s;
          final bounds = Rect.fromPoints(s.startPoint, s.endPoint);
          final dx = targetX - bounds.left;
          return s.copyWith(
            startPoint: s.startPoint + Offset(dx, 0),
            endPoint: s.endPoint + Offset(dx, 0),
          );
        }).toList();

    final alignedTexts =
        activeLayer.texts.map((t) {
          if (!selectedTextIds.contains(t.id)) return t;
          return t.copyWith(position: Offset(targetX, t.position.dy));
        }).toList();

    final alignedImages =
        activeLayer.images.map((i) {
          if (!selectedImageIds.contains(i.id)) return i;
          return i.copyWith(position: Offset(targetX, i.position.dy));
        }).toList();

    _updateLayer(
      activeLayer.copyWith(
        strokes: alignedStrokes,
        shapes: alignedShapes,
        texts: alignedTexts,
        images: alignedImages,
      ),
    );
    _calculateSelectionBounds();
  }

  /// Align selected elements to the right edge of the selection bounds.
  void _alignRight() {
    if (!hasSelection) return;
    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final targetRight = _selectionBounds!.right - _kSelectionBoundsPadding;
    final activeLayer = _getActiveLayer();

    final alignedStrokes =
        activeLayer.strokes.map((s) {
          if (!selectedStrokeIds.contains(s.id)) return s;
          final bounds = s.bounds;
          final dx = targetRight - bounds.right;
          return s.copyWith(
            points:
                s.points
                    .map(
                      (p) => p.copyWith(
                        position: Offset(p.position.dx + dx, p.position.dy),
                      ),
                    )
                    .toList(),
          );
        }).toList();

    final alignedShapes =
        activeLayer.shapes.map((s) {
          if (!selectedShapeIds.contains(s.id)) return s;
          final bounds = Rect.fromPoints(s.startPoint, s.endPoint);
          final dx = targetRight - bounds.right;
          return s.copyWith(
            startPoint: s.startPoint + Offset(dx, 0),
            endPoint: s.endPoint + Offset(dx, 0),
          );
        }).toList();

    final alignedTexts =
        activeLayer.texts.map((t) {
          if (!selectedTextIds.contains(t.id)) return t;
          final bounds = _estimateTextBounds(t);
          final dx = targetRight - bounds.right;
          return t.copyWith(
            position: Offset(t.position.dx + dx, t.position.dy),
          );
        }).toList();

    final alignedImages =
        activeLayer.images.map((i) {
          if (!selectedImageIds.contains(i.id)) return i;
          final bounds = _estimateImageBounds(i);
          final dx = targetRight - bounds.right;
          return i.copyWith(
            position: Offset(i.position.dx + dx, i.position.dy),
          );
        }).toList();

    _updateLayer(
      activeLayer.copyWith(
        strokes: alignedStrokes,
        shapes: alignedShapes,
        texts: alignedTexts,
        images: alignedImages,
      ),
    );
    _calculateSelectionBounds();
  }

  /// Align selected elements to the horizontal center of the selection bounds.
  void _alignCenterH() {
    if (!hasSelection) return;
    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final centerX = _selectionBounds!.center.dx;
    final activeLayer = _getActiveLayer();

    final alignedStrokes =
        activeLayer.strokes.map((s) {
          if (!selectedStrokeIds.contains(s.id)) return s;
          final bounds = s.bounds;
          final dx = centerX - bounds.center.dx;
          return s.copyWith(
            points:
                s.points
                    .map(
                      (p) => p.copyWith(
                        position: Offset(p.position.dx + dx, p.position.dy),
                      ),
                    )
                    .toList(),
          );
        }).toList();

    final alignedShapes =
        activeLayer.shapes.map((s) {
          if (!selectedShapeIds.contains(s.id)) return s;
          final bounds = Rect.fromPoints(s.startPoint, s.endPoint);
          final dx = centerX - bounds.center.dx;
          return s.copyWith(
            startPoint: s.startPoint + Offset(dx, 0),
            endPoint: s.endPoint + Offset(dx, 0),
          );
        }).toList();

    final alignedTexts =
        activeLayer.texts.map((t) {
          if (!selectedTextIds.contains(t.id)) return t;
          final bounds = _estimateTextBounds(t);
          final dx = centerX - bounds.center.dx;
          return t.copyWith(
            position: Offset(t.position.dx + dx, t.position.dy),
          );
        }).toList();

    final alignedImages =
        activeLayer.images.map((i) {
          if (!selectedImageIds.contains(i.id)) return i;
          final bounds = _estimateImageBounds(i);
          final dx = centerX - bounds.center.dx;
          return i.copyWith(
            position: Offset(i.position.dx + dx, i.position.dy),
          );
        }).toList();

    _updateLayer(
      activeLayer.copyWith(
        strokes: alignedStrokes,
        shapes: alignedShapes,
        texts: alignedTexts,
        images: alignedImages,
      ),
    );
    _calculateSelectionBounds();
  }

  /// Align selected elements to the top edge of the selection bounds.
  void _alignTop() {
    if (!hasSelection) return;
    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final targetY = _selectionBounds!.top + _kSelectionBoundsPadding;
    final activeLayer = _getActiveLayer();

    final alignedStrokes =
        activeLayer.strokes.map((s) {
          if (!selectedStrokeIds.contains(s.id)) return s;
          final dy = targetY - s.bounds.top;
          return s.copyWith(
            points:
                s.points
                    .map(
                      (p) => p.copyWith(
                        position: Offset(p.position.dx, p.position.dy + dy),
                      ),
                    )
                    .toList(),
          );
        }).toList();

    final alignedShapes =
        activeLayer.shapes.map((s) {
          if (!selectedShapeIds.contains(s.id)) return s;
          final bounds = Rect.fromPoints(s.startPoint, s.endPoint);
          final dy = targetY - bounds.top;
          return s.copyWith(
            startPoint: s.startPoint + Offset(0, dy),
            endPoint: s.endPoint + Offset(0, dy),
          );
        }).toList();

    final alignedTexts =
        activeLayer.texts.map((t) {
          if (!selectedTextIds.contains(t.id)) return t;
          return t.copyWith(position: Offset(t.position.dx, targetY));
        }).toList();

    final alignedImages =
        activeLayer.images.map((i) {
          if (!selectedImageIds.contains(i.id)) return i;
          return i.copyWith(position: Offset(i.position.dx, targetY));
        }).toList();

    _updateLayer(
      activeLayer.copyWith(
        strokes: alignedStrokes,
        shapes: alignedShapes,
        texts: alignedTexts,
        images: alignedImages,
      ),
    );
    _calculateSelectionBounds();
  }

  /// Align selected elements to the bottom edge of the selection bounds.
  void _alignBottom() {
    if (!hasSelection) return;
    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final targetBottom = _selectionBounds!.bottom - _kSelectionBoundsPadding;
    final activeLayer = _getActiveLayer();

    final alignedStrokes =
        activeLayer.strokes.map((s) {
          if (!selectedStrokeIds.contains(s.id)) return s;
          final dy = targetBottom - s.bounds.bottom;
          return s.copyWith(
            points:
                s.points
                    .map(
                      (p) => p.copyWith(
                        position: Offset(p.position.dx, p.position.dy + dy),
                      ),
                    )
                    .toList(),
          );
        }).toList();

    final alignedShapes =
        activeLayer.shapes.map((s) {
          if (!selectedShapeIds.contains(s.id)) return s;
          final bounds = Rect.fromPoints(s.startPoint, s.endPoint);
          final dy = targetBottom - bounds.bottom;
          return s.copyWith(
            startPoint: s.startPoint + Offset(0, dy),
            endPoint: s.endPoint + Offset(0, dy),
          );
        }).toList();

    final alignedTexts =
        activeLayer.texts.map((t) {
          if (!selectedTextIds.contains(t.id)) return t;
          final bounds = _estimateTextBounds(t);
          final dy = targetBottom - bounds.bottom;
          return t.copyWith(
            position: Offset(t.position.dx, t.position.dy + dy),
          );
        }).toList();

    final alignedImages =
        activeLayer.images.map((i) {
          if (!selectedImageIds.contains(i.id)) return i;
          final bounds = _estimateImageBounds(i);
          final dy = targetBottom - bounds.bottom;
          return i.copyWith(
            position: Offset(i.position.dx, i.position.dy + dy),
          );
        }).toList();

    _updateLayer(
      activeLayer.copyWith(
        strokes: alignedStrokes,
        shapes: alignedShapes,
        texts: alignedTexts,
        images: alignedImages,
      ),
    );
    _calculateSelectionBounds();
  }

  /// Align selected elements to the vertical center of the selection bounds.
  void _alignCenterV() {
    if (!hasSelection) return;
    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final centerY = _selectionBounds!.center.dy;
    final activeLayer = _getActiveLayer();

    final alignedStrokes =
        activeLayer.strokes.map((s) {
          if (!selectedStrokeIds.contains(s.id)) return s;
          final dy = centerY - s.bounds.center.dy;
          return s.copyWith(
            points:
                s.points
                    .map(
                      (p) => p.copyWith(
                        position: Offset(p.position.dx, p.position.dy + dy),
                      ),
                    )
                    .toList(),
          );
        }).toList();

    final alignedShapes =
        activeLayer.shapes.map((s) {
          if (!selectedShapeIds.contains(s.id)) return s;
          final bounds = Rect.fromPoints(s.startPoint, s.endPoint);
          final dy = centerY - bounds.center.dy;
          return s.copyWith(
            startPoint: s.startPoint + Offset(0, dy),
            endPoint: s.endPoint + Offset(0, dy),
          );
        }).toList();

    final alignedTexts =
        activeLayer.texts.map((t) {
          if (!selectedTextIds.contains(t.id)) return t;
          final bounds = _estimateTextBounds(t);
          final dy = centerY - bounds.center.dy;
          return t.copyWith(
            position: Offset(t.position.dx, t.position.dy + dy),
          );
        }).toList();

    final alignedImages =
        activeLayer.images.map((i) {
          if (!selectedImageIds.contains(i.id)) return i;
          final bounds = _estimateImageBounds(i);
          final dy = centerY - bounds.center.dy;
          return i.copyWith(
            position: Offset(i.position.dx, i.position.dy + dy),
          );
        }).toList();

    _updateLayer(
      activeLayer.copyWith(
        strokes: alignedStrokes,
        shapes: alignedShapes,
        texts: alignedTexts,
        images: alignedImages,
      ),
    );
    _calculateSelectionBounds();
  }

  // ===========================================================================
  // Distribution
  // ===========================================================================

  /// Distribute selected elements evenly along the horizontal axis.
  ///
  /// Requires at least 3 selected elements to distribute.
  void _distributeHorizontal() {
    if (selectionCount < 3) return;
    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    // Collect all element bounds with their IDs
    final entries = _collectElementBounds();
    if (entries.length < 3) return;

    // Sort by horizontal center
    entries.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));

    final firstCenter = entries.first.bounds.center.dx;
    final lastCenter = entries.last.bounds.center.dx;
    final step = (lastCenter - firstCenter) / (entries.length - 1);

    for (int i = 1; i < entries.length - 1; i++) {
      final targetX = firstCenter + step * i;
      final dx = targetX - entries[i].bounds.center.dx;
      _moveElementById(entries[i].id, Offset(dx, 0));
    }
    _calculateSelectionBounds();
  }

  /// Distribute selected elements evenly along the vertical axis.
  ///
  /// Requires at least 3 selected elements to distribute.
  void _distributeVertical() {
    if (selectionCount < 3) return;
    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final entries = _collectElementBounds();
    if (entries.length < 3) return;

    // Sort by vertical center
    entries.sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));

    final firstCenter = entries.first.bounds.center.dy;
    final lastCenter = entries.last.bounds.center.dy;
    final step = (lastCenter - firstCenter) / (entries.length - 1);

    for (int i = 1; i < entries.length - 1; i++) {
      final targetY = firstCenter + step * i;
      final dy = targetY - entries[i].bounds.center.dy;
      _moveElementById(entries[i].id, Offset(0, dy));
    }
    _calculateSelectionBounds();
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// Collects bounds for all selected elements as (id, bounds) pairs.
  List<_ElementEntry> _collectElementBounds() {
    final activeLayer = _getActiveLayer();
    final entries = <_ElementEntry>[];

    for (final s in activeLayer.strokes) {
      if (selectedStrokeIds.contains(s.id)) {
        entries.add(_ElementEntry(s.id, s.bounds));
      }
    }
    for (final s in activeLayer.shapes) {
      if (selectedShapeIds.contains(s.id)) {
        entries.add(
          _ElementEntry(s.id, Rect.fromPoints(s.startPoint, s.endPoint)),
        );
      }
    }
    for (final t in activeLayer.texts) {
      if (selectedTextIds.contains(t.id)) {
        entries.add(_ElementEntry(t.id, _estimateTextBounds(t)));
      }
    }
    for (final i in activeLayer.images) {
      if (selectedImageIds.contains(i.id)) {
        entries.add(_ElementEntry(i.id, _estimateImageBounds(i)));
      }
    }
    return entries;
  }

  /// Move a single element by ID and delta.
  void _moveElementById(String id, Offset delta) {
    final activeLayer = _getActiveLayer();

    // Check strokes
    final strokeIdx = activeLayer.strokes.indexWhere((s) => s.id == id);
    if (strokeIdx >= 0) {
      final s = activeLayer.strokes[strokeIdx];
      final moved = s.copyWith(
        points:
            s.points
                .map((p) => p.copyWith(position: p.position + delta))
                .toList(),
      );
      final strokes = List.of(activeLayer.strokes);
      strokes[strokeIdx] = moved;
      _updateLayer(activeLayer.copyWith(strokes: strokes));
      return;
    }

    // Check shapes
    final shapeIdx = activeLayer.shapes.indexWhere((s) => s.id == id);
    if (shapeIdx >= 0) {
      final s = activeLayer.shapes[shapeIdx];
      final moved = s.copyWith(
        startPoint: s.startPoint + delta,
        endPoint: s.endPoint + delta,
      );
      final shapes = List.of(activeLayer.shapes);
      shapes[shapeIdx] = moved;
      _updateLayer(activeLayer.copyWith(shapes: shapes));
      return;
    }

    // Check texts
    final textIdx = activeLayer.texts.indexWhere((t) => t.id == id);
    if (textIdx >= 0) {
      final t = activeLayer.texts[textIdx];
      final moved = t.copyWith(position: t.position + delta);
      final texts = List.of(activeLayer.texts);
      texts[textIdx] = moved;
      _updateLayer(activeLayer.copyWith(texts: texts));
      return;
    }

    // Check images
    final imageIdx = activeLayer.images.indexWhere((i) => i.id == id);
    if (imageIdx >= 0) {
      final i = activeLayer.images[imageIdx];
      final moved = i.copyWith(position: i.position + delta);
      final images = List.of(activeLayer.images);
      images[imageIdx] = moved;
      _updateLayer(activeLayer.copyWith(images: images));
    }
  }
}

/// Lightweight entry for distribution sorting.
class _ElementEntry {
  final String id;
  final Rect bounds;
  const _ElementEntry(this.id, this.bounds);
}
