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

  /// Local actor identifier (CRDT peerId) for filtering own-vs-other
  /// deltas during undo/redo. When set, [undo] / [redo] only act on
  /// deltas whose `actorId == localActorId`. Null in solo-canvas mode
  /// (no filtering — legacy behavior).
  String? localActorId;

  /// Can undo? True only if at least one entry in the stack belongs to
  /// the local actor (so `Ctrl+Z` is a no-op when only teammate edits
  /// are on top of the stack — UI can dim the button accordingly).
  bool get canUndo => _topLocalIndex(_undoStack) >= 0;

  /// Can redo? Symmetric with [canUndo].
  bool get canRedo => _topLocalIndex(_redoStack) >= 0;

  /// Current undo stack size (counts ALL entries including remote — used
  /// for diagnostics, not for UI state).
  int get undoCount => _undoStack.length;

  /// Current redo stack size.
  int get redoCount => _redoStack.length;

  /// Label of the next undoable LOCAL delta (skips teammate entries).
  String? get undoLabel {
    final i = _topLocalIndex(_undoStack);
    return i >= 0 ? _undoStack.elementAt(i).type.name : null;
  }

  /// Label of the next redoable LOCAL delta.
  String? get redoLabel {
    final i = _topLocalIndex(_redoStack);
    return i >= 0 ? _redoStack.elementAt(i).type.name : null;
  }

  /// Find the topmost stack index whose delta belongs to the local
  /// actor. Returns -1 when no such delta exists. When [localActorId]
  /// is null we treat every entry as local (legacy single-user mode).
  int _topLocalIndex(Queue<CanvasDelta> stack) {
    if (stack.isEmpty) return -1;
    final actor = localActorId;
    if (actor == null) return stack.length - 1;
    final list = stack.toList(growable: false);
    for (var i = list.length - 1; i >= 0; i--) {
      final a = list[i].actorId;
      if (a == null || a == actor) return i; // legacy null = treat as local
    }
    return -1;
  }

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

  /// End the current batch and push it as a single COMPOSITE delta — the
  /// whole batch undoes/redoes as one entry. Use this for cluster actions
  /// (move/align/color across many strokes) where the user mentally
  /// thinks of the operation as atomic ("Sposta cluster") and would be
  /// frustrated by N Ctrl+Z presses to revert a single command.
  ///
  /// If the batch is empty, nothing is pushed. If the batch has exactly
  /// one delta the composite wrapper is elided (no nesting needed).
  ///
  /// [label] surfaces in undo-button tooltips (e.g. "Sposta cluster").
  /// [actorId] propagates to the composite for CRDT/collab filtering;
  /// when null, falls back to the first child's actorId.
  void endBatchAsComposite(String label, {String? actorId}) {
    final batch = _activeBatch;
    _activeBatch = null;
    if (batch == null || batch.isEmpty) return;

    final composite = batch.length == 1
        ? batch.single
        : CanvasDelta(
            id: 'composite_${DateTime.now().microsecondsSinceEpoch}',
            type: CanvasDeltaType.composite,
            layerId: batch.first.layerId,
            timestamp: DateTime.now(),
            actorId: actorId ?? batch.first.actorId,
            childDeltas: List.unmodifiable(batch),
            compositeLabel: label,
          );

    _undoStack.add(composite);

    if (_redoStack.isNotEmpty) {
      _redoStack.clear();
    }
    while (_undoStack.length > maxStackSize) {
      _undoStack.removeFirst();
    }
    notifyListeners();
  }

  /// ⬅️ Undo: remove the most-recent local delta (skipping any teammate
  /// edits that happened to land on top after concurrent collaboration).
  CanvasDelta? undo() {
    final i = _topLocalIndex(_undoStack);
    if (i < 0) return null;

    final list = _undoStack.toList();
    final delta = list.removeAt(i);
    _undoStack
      ..clear()
      ..addAll(list);
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

  /// ➡️ Redo: reapply the most-recent locally-undone delta (skips any
  /// teammate-authored entries that landed on the redo stack via the
  /// per-actor filter in [undo]).
  CanvasDelta? redo() {
    final i = _topLocalIndex(_redoStack);
    if (i < 0) return null;

    final list = _redoStack.toList();
    final delta = list.removeAt(i);
    _redoStack
      ..clear()
      ..addAll(list);
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
        // Undo stroke removal = re-add stroke. Defensive: dedupe by id.
        // Composite-undo of the pixel-eraser path produces
        // `strokeRemoved(original) + addStroke(frag)*` children — if the
        // inverse pass races against any other code path that already
        // ressurrected the stroke (or the layer was never fully cleared
        // because the same id is referenced elsewhere), the bare `..add`
        // triggers `GroupNode.add`'s "Duplicate child ID" assert. Skip
        // silently when the stroke is already present.
        if (delta.elementData != null) {
          final stroke = ProStroke.fromJson(delta.elementData!);
          final alreadyPresent =
              layer.strokes.any((s) => s.id == stroke.id);
          if (!alreadyPresent) {
            final updatedStrokes = List<ProStroke>.from(layer.strokes)
              ..add(stroke);
            layerMap[delta.layerId] = layer.copyWith(strokes: updatedStrokes);
          }
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

      case CanvasDeltaType.adjustmentAdded:
      case CanvasDeltaType.adjustmentRemoved:
      case CanvasDeltaType.adjustmentUpdated:
        // Adjustments live in the scene graph (AdjustmentLayerNode),
        // not in the CanvasLayer model. No CanvasLayer mutation needed.
        break;

      case CanvasDeltaType.composite:
        // Composite undo: unfold children in REVERSE order and apply the
        // inverse of each. The recursion is bounded because composite
        // deltas cannot nest (`endBatchAsComposite` flattens nested batches).
        final children = delta.childDeltas;
        if (children != null) {
          var working = layerMap.values.toList();
          for (final child in children.reversed) {
            working = applyInverseDelta(working, child);
          }
          return working;
        }
        break;
    }

    return layerMap.values.toList();
  }

  /// 🔄 Reapply delta (for redo operation).
  ///
  /// Composite deltas are unfolded HERE — never sent to
  /// `CanvasDeltaTracker.applyDeltas`, which is WAL-replay code and treats
  /// composites as a "shouldn't happen" no-op. Children are reapplied in
  /// FORWARD order (mirror image of `applyInverseDelta`'s reversed loop)
  /// so the end state matches what the user originally produced.
  static List<CanvasLayer> reapplyDelta(
    List<CanvasLayer> layers,
    CanvasDelta delta,
  ) {
    if (delta.type == CanvasDeltaType.composite) {
      final children = delta.childDeltas;
      if (children == null || children.isEmpty) return layers;
      var working = layers;
      for (final child in children) {
        working = reapplyDelta(working, child);
      }
      return working;
    }
    // Non-composite: same as normal delta application.
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
  }
}
