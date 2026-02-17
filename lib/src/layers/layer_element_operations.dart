part of 'layer_controller.dart';

// ============================================================================
// LayerController — Element operations
// Strokes, shapes, texts, images CRUD on layers
// ============================================================================

// ignore_for_file: unused_element

/// Private implementation methods for element CRUD, called by the
/// one-liner public overrides in the main [LayerController] class.
///
/// This file is a `part of` layer_controller.dart, so all private
/// members (_layers, _spatialIndex, etc.) are accessible directly.
extension _LayerElementOps on LayerController {
  // --------------------------------------------------------------------------
  // Strokes
  // --------------------------------------------------------------------------

  void _addStrokeImpl(ProStroke stroke) {
    final layer = activeLayer;
    if (layer == null || layer.isLocked) return;

    final index = activeLayerIndex;
    if (index == -1) return;

    final updatedStrokes = List<ProStroke>.from(layer.strokes)..add(stroke);
    _layers[index] = layer.copyWith(strokes: updatedStrokes);

    if (_spatialIndex.isBuilt) {
      _spatialIndex.addStroke(stroke);
    } else {
      _spatialIndexDirty = true;
      _invalidateSceneGraph();
    }

    if (enableDeltaTracking) {
      _deltaTracker.recordStrokeAdded(layer.id, stroke, pageIndex: pageIndex);
      _dirtyRegionTracker.markDirty(stroke.bounds);
    }
    _emitTT(
      CanvasDeltaType.strokeAdded,
      layer.id,
      elementId: stroke.id,
      elementData: stroke.toJson(),
    );
  }

  Future<void> _addStrokesBatchImpl(List<ProStroke> strokes) async {
    final layer = activeLayer;
    if (layer == null || layer.isLocked) return;

    final index = activeLayerIndex;
    if (index == -1) return;
    if (strokes.isEmpty) return;

    final wasTrackingEnabled = enableDeltaTracking;
    enableDeltaTracking = false;

    _dirtyRegionTracker.enterBatchMode();

    const chunkSize = 1000;
    final chunks = <List<ProStroke>>[];
    for (int i = 0; i < strokes.length; i += chunkSize) {
      final end =
          (i + chunkSize < strokes.length) ? i + chunkSize : strokes.length;
      chunks.add(strokes.sublist(i, end));
    }

    var currentStrokes = List<ProStroke>.from(layer.strokes);
    final allBounds = <ui.Rect>[];

    for (int chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      final chunk = chunks[chunkIndex];
      currentStrokes.addAll(chunk);

      for (final stroke in chunk) {
        allBounds.add(stroke.bounds);
      }

      if (chunkIndex < chunks.length - 1) {
        await Future.delayed(Duration.zero);
      }
    }

    _layers[index] = layer.copyWith(strokes: currentStrokes);
    _dirtyRegionTracker.markDirtyBatch(allBounds);
    _dirtyRegionTracker.exitBatchMode();

    _spatialIndexDirty = true;
    _invalidateSceneGraph();

    enableDeltaTracking = wasTrackingEnabled;

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerModified(layer.id, {
        'batchStrokesAdded': strokes.length,
      }, pageIndex: pageIndex);
    }
  }

  void _removeStrokeAtImpl(int index) {
    final layer = activeLayer;
    if (layer == null || layer.isLocked) return;
    final layerIndex = activeLayerIndex;
    if (layerIndex == -1 || index < 0 || index >= layer.strokes.length) return;

    _removeStrokeImpl(layer.strokes[index].id);
  }

  void _removeStrokeImpl(String strokeId) {
    bool removed = false;
    for (int i = 0; i < _layers.length; i++) {
      final layer = _layers[i];
      if (layer.isLocked) continue;

      final strokeIndex = layer.strokes.indexWhere((s) => s.id == strokeId);
      if (strokeIndex != -1) {
        if (enableDeltaTracking) {
          _deltaTracker.recordStrokeRemoved(
            layer.id,
            strokeId,
            pageIndex: pageIndex,
          );
        }
        _emitTT(CanvasDeltaType.strokeRemoved, layer.id, elementId: strokeId);

        final updatedStrokes = List<ProStroke>.from(layer.strokes)
          ..removeAt(strokeIndex);
        _layers[i] = layer.copyWith(strokes: updatedStrokes);
        removed = true;
        break;
      }
    }

    if (removed) {
      _spatialIndexDirty = true;
      _invalidateSceneGraph();
    }
  }

  // --------------------------------------------------------------------------
  // Shapes
  // --------------------------------------------------------------------------

  void _addShapeImpl(GeometricShape shape) {
    final layer = activeLayer;
    if (layer == null || layer.isLocked) return;

    final index = activeLayerIndex;
    if (index == -1) return;

    final updatedShapes = List<GeometricShape>.from(layer.shapes)..add(shape);
    _layers[index] = layer.copyWith(shapes: updatedShapes);

    if (_spatialIndex.isBuilt) {
      _spatialIndex.addShape(shape);
    } else {
      _spatialIndexDirty = true;
      _invalidateSceneGraph();
    }

    if (enableDeltaTracking) {
      _deltaTracker.recordShapeAdded(layer.id, shape, pageIndex: pageIndex);
    }
    _emitTT(
      CanvasDeltaType.shapeAdded,
      layer.id,
      elementId: shape.id,
      elementData: shape.toJson(),
    );
  }

  void _removeShapeAtImpl(int index) {
    final layer = activeLayer;
    if (layer == null || layer.isLocked) return;
    final layerIndex = activeLayerIndex;
    if (layerIndex == -1 || index < 0 || index >= layer.shapes.length) return;

    _removeShapeImpl(layer.shapes[index].id);
  }

  void _removeShapeImpl(String shapeId) {
    bool removed = false;
    for (int i = 0; i < _layers.length; i++) {
      final layer = _layers[i];
      if (layer.isLocked) continue;

      final shapeIndex = layer.shapes.indexWhere((s) => s.id == shapeId);
      if (shapeIndex != -1) {
        if (enableDeltaTracking) {
          _deltaTracker.recordShapeRemoved(
            layer.id,
            shapeId,
            pageIndex: pageIndex,
          );
        }
        _emitTT(CanvasDeltaType.shapeRemoved, layer.id, elementId: shapeId);

        final updatedShapes = List<GeometricShape>.from(layer.shapes)
          ..removeAt(shapeIndex);
        _layers[i] = layer.copyWith(shapes: updatedShapes);
        removed = true;
        break;
      }
    }

    if (removed) {
      _spatialIndexDirty = true;
      _invalidateSceneGraph();
    }
  }

  // --------------------------------------------------------------------------
  // Texts
  // --------------------------------------------------------------------------

  void _addTextImpl(DigitalTextElement text) {
    final layer = activeLayer;
    if (layer == null || layer.isLocked) return;

    final index = activeLayerIndex;
    if (index == -1) return;

    final updatedTexts = List<DigitalTextElement>.from(layer.texts)..add(text);
    _layers[index] = layer.copyWith(texts: updatedTexts);

    // TODO: Spatial index for text elements
    _spatialIndexDirty = true;
    _invalidateSceneGraph();

    if (enableDeltaTracking) {
      _deltaTracker.recordTextAdded(layer.id, text, pageIndex: pageIndex);
    }
    _emitTT(
      CanvasDeltaType.textAdded,
      layer.id,
      elementId: text.id,
      elementData: text.toJson(),
    );
  }

  void _removeTextImpl(String textId) {
    final layer = activeLayer;
    if (layer == null || layer.isLocked) return;

    final index = activeLayerIndex;
    if (index == -1) return;

    final updatedTexts = List<DigitalTextElement>.from(layer.texts)
      ..removeWhere((t) => t.id == textId);

    if (updatedTexts.length != layer.texts.length) {
      if (enableDeltaTracking) {
        _deltaTracker.recordTextRemoved(layer.id, textId, pageIndex: pageIndex);
      }
      _emitTT(CanvasDeltaType.textRemoved, layer.id, elementId: textId);

      _layers[index] = layer.copyWith(texts: updatedTexts);
      _spatialIndexDirty = true;
      _invalidateSceneGraph();
    }
  }

  void _updateTextImpl(DigitalTextElement updatedText) {
    for (int i = 0; i < _layers.length; i++) {
      final layer = _layers[i];
      final index = layer.texts.indexWhere((t) => t.id == updatedText.id);
      if (index != -1) {
        final updatedTexts = List<DigitalTextElement>.from(layer.texts);
        updatedTexts[index] = updatedText;
        _layers[i] = layer.copyWith(texts: updatedTexts);

        if (enableDeltaTracking) {
          _deltaTracker.recordTextUpdate(
            layer.id,
            updatedText,
            previousText: layer.texts[index],
            pageIndex: pageIndex,
          );
        }
        _emitTT(
          CanvasDeltaType.textUpdated,
          layer.id,
          elementId: updatedText.id,
          elementData: updatedText.toJson(),
        );

        _spatialIndexDirty = true;
        _invalidateSceneGraph();
        return;
      }
    }
  }

  // --------------------------------------------------------------------------
  // Images
  // --------------------------------------------------------------------------

  void _addImageImpl(ImageElement image) {
    final layer = activeLayer;
    if (layer == null || layer.isLocked) return;

    final index = activeLayerIndex;
    if (index == -1) return;

    final updatedImages = List<ImageElement>.from(layer.images)..add(image);
    _layers[index] = layer.copyWith(images: updatedImages);

    _spatialIndexDirty = true;
    _invalidateSceneGraph();

    if (enableDeltaTracking) {
      _deltaTracker.recordImageAdded(layer.id, image, pageIndex: pageIndex);
    }
    _emitTT(
      CanvasDeltaType.imageAdded,
      layer.id,
      elementId: image.id,
      elementData: image.toJson(),
    );
  }

  void _removeImageImpl(String imageId) {
    bool removed = false;
    for (int i = 0; i < _layers.length; i++) {
      final layer = _layers[i];
      if (layer.isLocked) continue;

      final index = layer.images.indexWhere((img) => img.id == imageId);
      if (index != -1) {
        if (enableDeltaTracking) {
          _deltaTracker.recordImageRemoved(
            layer.id,
            imageId,
            pageIndex: pageIndex,
          );
        }
        _emitTT(CanvasDeltaType.imageRemoved, layer.id, elementId: imageId);

        final updatedImages = List<ImageElement>.from(layer.images)
          ..removeAt(index);
        _layers[i] = layer.copyWith(images: updatedImages);
        removed = true;
        break;
      }
    }

    if (removed) {
      _spatialIndexDirty = true;
      _invalidateSceneGraph();
    }
  }

  void _updateImageImpl(ImageElement updatedImage) {
    bool found = false;
    for (int i = 0; i < _layers.length; i++) {
      final layer = _layers[i];
      final index = layer.images.indexWhere((img) => img.id == updatedImage.id);
      if (index != -1) {
        final updatedImages = List<ImageElement>.from(layer.images);
        updatedImages[index] = updatedImage;
        _layers[i] = layer.copyWith(images: updatedImages);
        found = true;

        if (enableDeltaTracking) {
          _deltaTracker.recordImageUpdate(
            layer.id,
            updatedImage,
            previousImage: layer.images[index],
            pageIndex: pageIndex,
          );
        }
        _emitTT(
          CanvasDeltaType.imageUpdated,
          layer.id,
          elementId: updatedImage.id,
          elementData: updatedImage.toJson(),
        );

        _spatialIndexDirty = true;
        _invalidateSceneGraph();
        break;
      }
    }

    // Image loaded from Firestore directly — add to active layer
    if (!found) {
      final activeIdx = activeLayerIndex;
      if (activeIdx != -1) {
        final layer = _layers[activeIdx];
        final updatedImages = List<ImageElement>.from(layer.images)
          ..add(updatedImage);
        _layers[activeIdx] = layer.copyWith(images: updatedImages);

        if (enableDeltaTracking) {
          _deltaTracker.recordImageAdded(
            layer.id,
            updatedImage,
            pageIndex: pageIndex,
          );
        }
        _emitTT(
          CanvasDeltaType.imageAdded,
          layer.id,
          elementId: updatedImage.id,
          elementData: updatedImage.toJson(),
        );

        _spatialIndexDirty = true;
        _invalidateSceneGraph();
      }
    }
  }

  // --------------------------------------------------------------------------
  // Undo last element / Clear
  // --------------------------------------------------------------------------

  void _undoLastElementImpl() {
    final layer = activeLayer;
    if (layer == null || layer.isLocked) return;

    final index = activeLayerIndex;
    if (index == -1) return;

    if (layer.shapes.isNotEmpty) {
      final shapeToRemove = layer.shapes.last;
      if (enableDeltaTracking) {
        _deltaTracker.recordShapeRemoved(
          layer.id,
          shapeToRemove.id,
          pageIndex: pageIndex,
        );
      }
      final updatedShapes = List<GeometricShape>.from(layer.shapes)
        ..removeLast();
      _layers[index] = layer.copyWith(shapes: updatedShapes);
      _spatialIndexDirty = true;
      _invalidateSceneGraph();
    } else if (layer.strokes.isNotEmpty) {
      final strokeToRemove = layer.strokes.last;
      if (enableDeltaTracking) {
        _deltaTracker.recordStrokeRemoved(
          layer.id,
          strokeToRemove.id,
          pageIndex: pageIndex,
        );
      }
      final updatedStrokes = List<ProStroke>.from(layer.strokes)..removeLast();
      _layers[index] = layer.copyWith(strokes: updatedStrokes);
      _spatialIndexDirty = true;
      _invalidateSceneGraph();
    }
  }

  void _clearActiveLayerImpl() {
    final layer = activeLayer;
    if (layer == null || layer.isLocked) return;

    final index = activeLayerIndex;
    if (index == -1) return;

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerCleared(
        layer.id,
        layerSnapshot: layer.toJson(),
        pageIndex: pageIndex,
      );
    }
    _emitTT(CanvasDeltaType.layerCleared, layer.id);

    _layers[index] = layer.copyWith(strokes: [], shapes: [], texts: []);
    _spatialIndexDirty = true;
    _invalidateSceneGraph();
  }

  // --------------------------------------------------------------------------
  // Queries
  // --------------------------------------------------------------------------

  List<ProStroke> _getAllVisibleStrokesImpl() {
    final allStrokes = <ProStroke>[];
    for (final layer in _layers) {
      if (layer.isVisible) {
        allStrokes.addAll(layer.strokes);
      }
    }
    return allStrokes;
  }

  List<GeometricShape> _getAllVisibleShapesImpl() {
    final allShapes = <GeometricShape>[];
    for (final layer in _layers) {
      if (layer.isVisible) {
        allShapes.addAll(layer.shapes);
      }
    }
    return allShapes;
  }

  List<DigitalTextElement> _getAllVisibleTextsImpl() {
    final allTexts = <DigitalTextElement>[];
    for (final layer in _layers) {
      if (layer.isVisible) {
        allTexts.addAll(layer.texts);
      }
    }
    return allTexts;
  }
}
