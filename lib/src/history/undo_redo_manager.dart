import 'dart:collection';
import 'package:flutter/foundation.dart';
import './canvas_delta_tracker.dart';
import '../core/models/canvas_layer.dart';
import '../drawing/models/pro_drawing_point.dart'; // For ProStroke
import '../core/models/shape_type.dart'; // For GeometricShape
import '../core/models/digital_text_element.dart';
import '../core/models/image_element.dart';
import '../core/engine_scope.dart';

/// 🔄 Undo/Redo Manager for Professional Canvas
///
/// Leverages existing DeltaTracker system for zero-overhead undo/redo.
/// Maintains separate undo/redo stacks with configurable limits.
class UndoRedoManager extends ChangeNotifier {
  /// Legacy singleton accessor — delegates to [EngineScope.current].
  static UndoRedoManager get instance => EngineScope.current.undoRedoManager;

  /// Creates a new instance (used by [EngineScope]).
  UndoRedoManager.create();

  /// Undo stack: list of deltas to undo
  final Queue<CanvasDelta> _undoStack = Queue();

  /// Redo stack: list of deltas to redo
  final Queue<CanvasDelta> _redoStack = Queue();

  /// Maximum stack size (prevent memory issues)
  static const int maxStackSize = 100;

  /// Active batch accumulator, or null if no batch is open.
  List<CanvasDelta>? _activeBatch;

  /// Can undo?
  bool get canUndo => _undoStack.isNotEmpty;

  /// Can redo?
  bool get canRedo => _redoStack.isNotEmpty;

  /// Current undo stack size
  int get undoCount => _undoStack.length;

  /// Current redo stack size
  int get redoCount => _redoStack.length;

  /// Label of the next undo delta, or null.
  String? get undoLabel => canUndo ? _undoStack.last.type.name : null;

  /// Label of the next redo delta, or null.
  String? get redoLabel => canRedo ? _redoStack.last.type.name : null;

  /// 📝 Push delta to undo stack (called automatically by DeltaTracker).
  ///
  /// If a batch is open ([beginBatch] was called), the delta is accumulated
  /// in the batch instead of being pushed directly.
  void pushDelta(CanvasDelta delta) {
    if (_activeBatch != null) {
      _activeBatch!.add(delta);
      return;
    }

    _undoStack.add(delta);

    // Clear redo stack on new action (standard behavior)
    if (_redoStack.isNotEmpty) {
      _redoStack.clear();
    }

    // Enforce stack size limit (FIFO)
    while (_undoStack.length > maxStackSize) {
      _undoStack.removeFirst();
    }

    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // Batch support
  // --------------------------------------------------------------------------

  /// Begin a batch — all subsequent [pushDelta] calls are accumulated
  /// into a single undo step until [endBatch] is called.
  void beginBatch() {
    _activeBatch = [];
  }

  /// End the current batch and push all accumulated deltas as individual
  /// entries that undo/redo together.
  ///
  /// If the batch is empty, nothing is pushed.
  void endBatch() {
    final batch = _activeBatch;
    _activeBatch = null;
    if (batch == null || batch.isEmpty) return;

    // Push each delta individually so applyInverseDelta can process them.
    // They all sit contiguously on the stack for grouped undo.
    for (final delta in batch) {
      _undoStack.add(delta);
    }

    // Clear redo stack — new branch.
    if (_redoStack.isNotEmpty) {
      _redoStack.clear();
    }

    // Enforce stack size limit.
    while (_undoStack.length > maxStackSize) {
      _undoStack.removeFirst();
    }

    notifyListeners();
  }

  /// ⬅️ Undo: remove last delta
  CanvasDelta? undo() {
    if (!canUndo) return null;

    final delta = _undoStack.removeLast();
    _redoStack.add(delta);

    // Enforce redo stack limit
    while (_redoStack.length > maxStackSize) {
      _redoStack.removeFirst();
    }

    notifyListeners();
    return delta;
  }

  /// 🗑️ Discard last undo entry WITHOUT pushing to redo stack.
  ///
  /// Used when the action should be silently removed (e.g., double-tap zoom
  /// removing the accidental dot from the first tap).
  CanvasDelta? discardLastUndo() {
    if (!canUndo) return null;

    final delta = _undoStack.removeLast();
    // Intentionally NOT adding to _redoStack
    notifyListeners();
    return delta;
  }

  /// ➡️ Redo: reapply undone delta
  CanvasDelta? redo() {
    if (!canRedo) return null;

    final delta = _redoStack.removeLast();
    _undoStack.add(delta);

    // Enforce undo stack limit
    while (_undoStack.length > maxStackSize) {
      _undoStack.removeFirst();
    }

    notifyListeners();
    return delta;
  }

  /// 🔄 Apply inverse of delta (for undo operation)
  static List<CanvasLayer> applyInverseDelta(
    List<CanvasLayer> layers,
    CanvasDelta delta,
  ) {
    final layerMap = {for (final l in layers) l.id: l};
    final layer = layerMap[delta.layerId];

    if (layer == null) return layers;

    switch (delta.type) {
      case CanvasDeltaType.strokeAdded:
        // Undo stroke addition = remove stroke
        if (delta.elementId != null) {
          final updatedStrokes =
              layer.strokes.where((s) => s.id != delta.elementId).toList();
          layerMap[delta.layerId] = layer.copyWith(strokes: updatedStrokes);
        }
        break;

      case CanvasDeltaType.strokeRemoved:
        // Undo stroke removal = re-add stroke
        if (delta.elementData != null) {
          final stroke = ProStroke.fromJson(delta.elementData!);
          final updatedStrokes = List<ProStroke>.from(layer.strokes)
            ..add(stroke);
          layerMap[delta.layerId] = layer.copyWith(strokes: updatedStrokes);
        }
        break;

      case CanvasDeltaType.shapeAdded:
        // Undo shape addition = remove shape
        if (delta.elementId != null) {
          final updatedShapes =
              layer.shapes.where((s) => s.id != delta.elementId).toList();
          layerMap[delta.layerId] = layer.copyWith(shapes: updatedShapes);
        }
        break;

      case CanvasDeltaType.shapeRemoved:
        // Undo shape removal = re-add shape
        if (delta.elementData != null) {
          final shape = GeometricShape.fromJson(delta.elementData!);
          final updatedShapes = List<GeometricShape>.from(layer.shapes)
            ..add(shape);
          layerMap[delta.layerId] = layer.copyWith(shapes: updatedShapes);
        }
        break;

      case CanvasDeltaType.layerAdded:
        // Undo layer addition = remove layer
        layerMap.remove(delta.layerId);
        break;

      case CanvasDeltaType.layerRemoved:
        // Undo layer removal = re-add layer
        if (delta.elementData != null) {
          final restoredLayer = CanvasLayer.fromJson(delta.elementData!);
          layerMap[delta.layerId] = restoredLayer;
        }
        break;

      case CanvasDeltaType.layerModified:
        // Undo layer modification: restore previous property values
        if (delta.previousData != null) {
          final prev = delta.previousData!;
          layerMap[delta.layerId] = layer.copyWith(
            name: prev['name'] as String?,
            isVisible: prev['isVisible'] as bool?,
            isLocked: prev['isLocked'] as bool?,
            opacity: (prev['opacity'] as num?)?.toDouble(),
          );
        }
        break;

      case CanvasDeltaType.layerCleared:
        // Undo layer clear: restore full layer from snapshot
        if (delta.previousData != null) {
          final restoredLayer = CanvasLayer.fromJson(delta.previousData!);
          layerMap[delta.layerId] = restoredLayer;
        }
        break;

      case CanvasDeltaType.textAdded:
        // Undo text addition = remove text
        if (delta.elementId != null) {
          final updatedTexts =
              layer.texts.where((t) => t.id != delta.elementId).toList();
          layerMap[delta.layerId] = layer.copyWith(texts: updatedTexts);
        }
        break;

      case CanvasDeltaType.textRemoved:
        // Undo text removal = re-add text
        if (delta.elementData != null) {
          final text = DigitalTextElement.fromJson(delta.elementData!);
          final updatedTexts = List<DigitalTextElement>.from(layer.texts)
            ..add(text);
          layerMap[delta.layerId] = layer.copyWith(texts: updatedTexts);
        }
        break;

      case CanvasDeltaType.textUpdated:
        // Undo text update: restore previous text version
        if (delta.previousData != null) {
          final oldText = DigitalTextElement.fromJson(delta.previousData!);
          final updatedTexts =
              layer.texts.map((t) => t.id == oldText.id ? oldText : t).toList();
          layerMap[delta.layerId] = layer.copyWith(texts: updatedTexts);
        }
        break;

      case CanvasDeltaType.imageAdded:
        // Undo image addition = remove image
        if (delta.elementId != null) {
          final updatedImages =
              layer.images.where((i) => i.id != delta.elementId).toList();
          layerMap[delta.layerId] = layer.copyWith(images: updatedImages);
        }
        break;

      case CanvasDeltaType.imageRemoved:
        // Undo image removal = re-add image
        if (delta.elementData != null) {
          final image = ImageElement.fromJson(delta.elementData!);
          final updatedImages = List<ImageElement>.from(layer.images)
            ..add(image);
          layerMap[delta.layerId] = layer.copyWith(images: updatedImages);
        }
        break;

      case CanvasDeltaType.imageUpdated:
        // Undo image update: restore previous image version
        if (delta.previousData != null) {
          final oldImage = ImageElement.fromJson(delta.previousData!);
          final updatedImages =
              layer.images
                  .map((i) => i.id == oldImage.id ? oldImage : i)
                  .toList();
          layerMap[delta.layerId] = layer.copyWith(images: updatedImages);
        }
        break;
    }

    return layerMap.values.toList();
  }

  /// 🔄 Reapply delta (for redo operation)
  static List<CanvasLayer> reapplyDelta(
    List<CanvasLayer> layers,
    CanvasDelta delta,
  ) {
    // Reapply is same as normal delta application
    return CanvasDeltaTracker.applyDeltas(layers, [delta]);
  }

  /// 🧹 Clear all stacks (e.g., when loading new canvas)
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _activeBatch = null;
    notifyListeners();
  }

  /// Reset singleton state for testing. Clears all stacks without notifying.
  @visibleForTesting
  void resetForTesting() {
    _undoStack.clear();
    _redoStack.clear();
    _activeBatch = null;
  }

  /// 📊 Debug info
  void printStatus() {
    debugPrint(
      '[UndoRedoManager] undo: ${_undoStack.length}, redo: ${_redoStack.length}',
    );
  }
}
