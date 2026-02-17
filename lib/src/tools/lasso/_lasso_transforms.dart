part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Transform Operations (rotate, scale, flip)
// =============================================================================

extension _LassoTransforms on LassoTool {
  // ===========================================================================
  // Rotate
  // ===========================================================================

  /// Rotate selected elements by 90° clockwise.
  void _rotateSelected90() {
    if (!hasSelection) return;

    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final center = _selectionBounds!.center;
    final activeLayer = _getActiveLayer();

    // Rotate strokes
    final rotatedStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            final rotatedPoints =
                stroke.points.map((point) {
                  final translated = point.position - center;
                  final rotated = Offset(-translated.dy, translated.dx);
                  return point.copyWith(position: rotated + center);
                }).toList();
            return stroke.copyWith(points: rotatedPoints);
          }
          return stroke;
        }).toList();

    // Rotate shapes
    final rotatedShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            final startT = shape.startPoint - center;
            final endT = shape.endPoint - center;
            return shape.copyWith(
              startPoint: Offset(-startT.dy, startT.dx) + center,
              endPoint: Offset(-endT.dy, endT.dx) + center,
            );
          }
          return shape;
        }).toList();

    // Rotate text elements
    final rotatedTexts =
        activeLayer.texts.map((text) {
          if (selectedTextIds.contains(text.id)) {
            final translated = text.position - center;
            final rotated = Offset(-translated.dy, translated.dx);
            return text.copyWith(position: rotated + center);
          }
          return text;
        }).toList();

    // Rotate image elements
    final rotatedImages =
        activeLayer.images.map((image) {
          if (selectedImageIds.contains(image.id)) {
            final translated = image.position - center;
            final rotated = Offset(-translated.dy, translated.dx);
            return image.copyWith(
              position: rotated + center,
              rotation: image.rotation + (pi / 2),
            );
          }
          return image;
        }).toList();

    final updatedLayer = activeLayer.copyWith(
      strokes: rotatedStrokes,
      shapes: rotatedShapes,
      texts: rotatedTexts,
      images: rotatedImages,
    );

    _updateLayer(updatedLayer);
    _calculateSelectionBounds();
  }

  /// Rotate selected elements by an arbitrary angle (radians).
  ///
  /// [radians] Rotation angle (positive = clockwise).
  /// [center] Rotation center (default: selection center).
  void _rotateSelectedByAngle(double radians, {Offset? center}) {
    if (!hasSelection) return;

    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final rotCenter = center ?? _selectionBounds!.center;
    final cosA = cos(radians);
    final sinA = sin(radians);

    final activeLayer = _getActiveLayer();

    Offset rotatePoint(Offset point) {
      final translated = point - rotCenter;
      return Offset(
            translated.dx * cosA - translated.dy * sinA,
            translated.dx * sinA + translated.dy * cosA,
          ) +
          rotCenter;
    }

    final rotatedStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            final rotatedPoints =
                stroke.points
                    .map((p) => p.copyWith(position: rotatePoint(p.position)))
                    .toList();
            return stroke.copyWith(points: rotatedPoints);
          }
          return stroke;
        }).toList();

    final rotatedShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            return shape.copyWith(
              startPoint: rotatePoint(shape.startPoint),
              endPoint: rotatePoint(shape.endPoint),
            );
          }
          return shape;
        }).toList();

    final rotatedTexts =
        activeLayer.texts.map((text) {
          if (selectedTextIds.contains(text.id)) {
            return text.copyWith(position: rotatePoint(text.position));
          }
          return text;
        }).toList();

    final rotatedImages =
        activeLayer.images.map((image) {
          if (selectedImageIds.contains(image.id)) {
            return image.copyWith(
              position: rotatePoint(image.position),
              rotation: image.rotation + radians,
            );
          }
          return image;
        }).toList();

    final updatedLayer = activeLayer.copyWith(
      strokes: rotatedStrokes,
      shapes: rotatedShapes,
      texts: rotatedTexts,
      images: rotatedImages,
    );

    _updateLayer(updatedLayer);
    _calculateSelectionBounds();
  }

  // ===========================================================================
  // Scale
  // ===========================================================================

  /// Scale selected elements relative to a center point.
  ///
  /// [factor] Scale factor (>1 = enlarge, <1 = shrink).
  /// [center] Scale center (default: selection center).
  void _scaleSelected(double factor, {Offset? center}) {
    if (!hasSelection || factor <= 0) return;

    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final scaleCenter = center ?? _selectionBounds!.center;
    final activeLayer = _getActiveLayer();

    Offset scalePoint(Offset point) {
      final translated = point - scaleCenter;
      return Offset(translated.dx * factor, translated.dy * factor) +
          scaleCenter;
    }

    final scaledStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            final scaledPoints =
                stroke.points
                    .map((p) => p.copyWith(position: scalePoint(p.position)))
                    .toList();
            return stroke.copyWith(
              points: scaledPoints,
              baseWidth: stroke.baseWidth * factor,
            );
          }
          return stroke;
        }).toList();

    final scaledShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            return shape.copyWith(
              startPoint: scalePoint(shape.startPoint),
              endPoint: scalePoint(shape.endPoint),
              strokeWidth: shape.strokeWidth * factor,
            );
          }
          return shape;
        }).toList();

    final scaledTexts =
        activeLayer.texts.map((text) {
          if (selectedTextIds.contains(text.id)) {
            return text.copyWith(
              position: scalePoint(text.position),
              scale: text.scale * factor,
            );
          }
          return text;
        }).toList();

    final scaledImages =
        activeLayer.images.map((image) {
          if (selectedImageIds.contains(image.id)) {
            return image.copyWith(
              position: scalePoint(image.position),
              scale: image.scale * factor,
            );
          }
          return image;
        }).toList();

    final updatedLayer = activeLayer.copyWith(
      strokes: scaledStrokes,
      shapes: scaledShapes,
      texts: scaledTexts,
      images: scaledImages,
    );

    _updateLayer(updatedLayer);
    _calculateSelectionBounds();
  }

  // ===========================================================================
  // Flip
  // ===========================================================================

  /// Flip selected elements horizontally.
  void _flipHorizontal() {
    if (!hasSelection) return;

    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final centerX = _selectionBounds!.center.dx;
    final activeLayer = _getActiveLayer();

    double mirrorX(double x) => centerX - (x - centerX);

    final flippedStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            final flippedPoints =
                stroke.points
                    .map(
                      (p) => p.copyWith(
                        position: Offset(mirrorX(p.position.dx), p.position.dy),
                      ),
                    )
                    .toList();
            return stroke.copyWith(points: flippedPoints);
          }
          return stroke;
        }).toList();

    final flippedShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            return shape.copyWith(
              startPoint: Offset(
                mirrorX(shape.startPoint.dx),
                shape.startPoint.dy,
              ),
              endPoint: Offset(mirrorX(shape.endPoint.dx), shape.endPoint.dy),
            );
          }
          return shape;
        }).toList();

    final flippedTexts =
        activeLayer.texts.map((text) {
          if (selectedTextIds.contains(text.id)) {
            return text.copyWith(
              position: Offset(mirrorX(text.position.dx), text.position.dy),
            );
          }
          return text;
        }).toList();

    final flippedImages =
        activeLayer.images.map((image) {
          if (selectedImageIds.contains(image.id)) {
            return image.copyWith(
              position: Offset(mirrorX(image.position.dx), image.position.dy),
              flipHorizontal: !image.flipHorizontal,
            );
          }
          return image;
        }).toList();

    final updatedLayer = activeLayer.copyWith(
      strokes: flippedStrokes,
      shapes: flippedShapes,
      texts: flippedTexts,
      images: flippedImages,
    );

    _updateLayer(updatedLayer);
  }

  /// Flip selected elements vertically.
  void _flipVertical() {
    if (!hasSelection) return;

    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final centerY = _selectionBounds!.center.dy;
    final activeLayer = _getActiveLayer();

    double mirrorY(double y) => centerY - (y - centerY);

    final flippedStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            final flippedPoints =
                stroke.points
                    .map(
                      (p) => p.copyWith(
                        position: Offset(p.position.dx, mirrorY(p.position.dy)),
                      ),
                    )
                    .toList();
            return stroke.copyWith(points: flippedPoints);
          }
          return stroke;
        }).toList();

    final flippedShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            return shape.copyWith(
              startPoint: Offset(
                shape.startPoint.dx,
                mirrorY(shape.startPoint.dy),
              ),
              endPoint: Offset(shape.endPoint.dx, mirrorY(shape.endPoint.dy)),
            );
          }
          return shape;
        }).toList();

    final flippedTexts =
        activeLayer.texts.map((text) {
          if (selectedTextIds.contains(text.id)) {
            return text.copyWith(
              position: Offset(text.position.dx, mirrorY(text.position.dy)),
            );
          }
          return text;
        }).toList();

    final flippedImages =
        activeLayer.images.map((image) {
          if (selectedImageIds.contains(image.id)) {
            return image.copyWith(
              position: Offset(image.position.dx, mirrorY(image.position.dy)),
              flipVertical: !image.flipVertical,
            );
          }
          return image;
        }).toList();

    final updatedLayer = activeLayer.copyWith(
      strokes: flippedStrokes,
      shapes: flippedShapes,
      texts: flippedTexts,
      images: flippedImages,
    );

    _updateLayer(updatedLayer);
  }
}
