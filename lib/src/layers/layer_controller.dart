import 'dart:ui' as ui;
import '../core/models/canvas_layer.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/group_node.dart';
import '../core/nodes/layer_node.dart';
import '../core/nodes/stroke_node.dart';
import '../core/nodes/shape_node.dart';
import '../core/nodes/text_node.dart';
import '../core/nodes/image_node.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../core/models/shape_type.dart';
import '../core/models/digital_text_element.dart';
import '../core/models/image_element.dart';
import '../core/editing/adjustment_layer.dart';
import '../core/nodes/adjustment_layer_node.dart';
import '../core/scene_graph/scene_graph.dart';
import '../rendering/optimization/spatial_index.dart';
import '../history/canvas_delta_tracker.dart';
import '../history/undo_redo_manager.dart';
import '../rendering/optimization/dirty_region_tracker.dart';
import './fluera_layer_controller.dart';

part 'layer_element_operations.dart';
part 'layer_spatial_index.dart';
part 'layer_scene_graph.dart';

/// Typedef for the Time Travel callback.
///
/// Legacy single-callback hook predating [LayerMutationListener]. Setting it
/// remains supported and routes through the multi-listener dispatch.
typedef TimeTravelEventCallback =
    void Function(
      CanvasDeltaType type,
      String layerId, {
      String? elementId,
      Map<String, dynamic>? elementData,
    });

/// Multi-listener observer for every mutation that happens on a
/// [LayerController].
///
/// Receives a fully-populated [CanvasDelta] (the same record used by the
/// undo/redo and incremental sync pipelines), so a listener can choose to:
///   • forward the delta to a CRDT layer for replication;
///   • persist it to a local op-log;
///   • derive analytics events;
///
/// Listeners are invoked synchronously on the calling thread, in registration
/// order, only when [LayerController.enableDeltaTracking] is `true`. This
/// matches the legacy [TimeTravelEventCallback] semantics.
typedef LayerMutationListener = void Function(CanvasDelta delta);

/// Controller for managing canvas layers.
///
/// Supports QuadTree spatial index for O(log n) performance with 10k+ strokes,
/// delta tracking for incremental sync, undo/redo, and scene graph management.
///
/// Heavy element CRUD is in [layer_element_operations.dart],
/// spatial index in [layer_spatial_index.dart], and scene graph
/// in [layer_scene_graph.dart].
class LayerController extends FlueraLayerController {
  final List<CanvasLayer> _layers = [];
  String? _activeLayerId;

  /// 🚀 FIX 3: Atomic counter to prevent ID collisions in batch operations.
  static int _idCounter = 0;
  static String _generateUniqueId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  /// 🚀 FIX 4: Cached active layer index. Invalidated on layer mutations.
  int? _cachedActiveLayerIndex;

  /// Spatial Index for optimized viewport queries.
  final SpatialIndexManager _spatialIndex = SpatialIndexManager();

  /// Flag to rebuild spatial index.
  bool _spatialIndexDirty = true;

  /// Delta Tracker for incremental sync (singleton).
  final CanvasDeltaTracker _deltaTracker = CanvasDeltaTracker.instance;

  /// Undo/Redo Manager (singleton).
  final UndoRedoManager _undoRedoManager = UndoRedoManager.instance;

  /// Dirty Region Tracker.
  final DirtyRegionTracker _dirtyRegionTracker = DirtyRegionTracker();

  /// 🚀 DELTA SAVE: Track which layers have been modified since last save.
  /// Only dirty layers are re-encoded and re-inserted during save.
  final Set<String> _dirtyLayerIds = {};

  /// Scene graph (lazy-rebuilt from layers).
  SceneGraph _sceneGraph = SceneGraph();
  bool _sceneGraphDirty = true;

  /// 🚀 Batch mode: defer version bumps during bulk operations (erasing).
  int _batchDepth = 0;
  bool _batchNeedsBump = false;
  bool _batchNeedsNotify = false;

  /// Flag to enable/disable delta tracking.
  /// Disable during batch operations (e.g., load from storage).
  bool enableDeltaTracking = true;

  /// Identifier of the local actor (CRDT peerId). When set, every
  /// [_emitTT] stamps the resulting [CanvasDelta] with this id so the
  /// undo manager can later filter "deltas I authored" from "deltas a
  /// teammate authored". Wired by the CRDT collab init; stays null for
  /// solo-canvas sessions (the undo manager just doesn't filter).
  ///
  /// Setting this also propagates to [UndoRedoManager.localActorId] so
  /// the per-actor filter in `undo()` / `redo()` is in sync.
  String? get localActorId => _localActorId;
  set localActorId(String? value) {
    _localActorId = value;
    _undoRedoManager.localActorId = value;
  }

  String? _localActorId;

  /// While true, [_emitTT] still notifies mutation observers (the CRDT
  /// pipeline keeps replicating) but skips the legacy `onTimeTravelEvent`
  /// hook that feeds the undo manager. Set by
  /// [CRDTToLayerControllerApplier.applyRemote] for the duration of a
  /// remote op replay so a peer's edit doesn't land on the local user's
  /// undo stack — `Ctrl+Z` should never revert another user's stroke.
  bool suppressUndoTracking = false;

  /// Time Travel: optional callback to record events.
  TimeTravelEventCallback? onTimeTravelEvent;

  /// Registered mutation observers, dispatched in registration order.
  final List<LayerMutationListener> _mutationObservers = [];

  /// Cached snapshot of mutation observers, rebuilt on register/unregister.
  /// Avoids allocating a copy on every dispatch (mutations are hot-path).
  List<LayerMutationListener> _mutationObserverSnapshot = const [];

  /// Register a [LayerMutationListener] to receive every canvas mutation.
  ///
  /// Listeners fire only while [enableDeltaTracking] is `true`, matching the
  /// existing `onTimeTravelEvent` hook. Returns an unsubscribe closure for
  /// scoped registration (`final off = lc.addMutationObserver(...);
  /// off();`).
  void Function() addMutationObserver(LayerMutationListener observer) {
    _mutationObservers.add(observer);
    _mutationObserverSnapshot = List.of(_mutationObservers);
    return () => removeMutationObserver(observer);
  }

  /// Unregister a previously-added [LayerMutationListener].
  void removeMutationObserver(LayerMutationListener observer) {
    if (_mutationObservers.remove(observer)) {
      _mutationObserverSnapshot = List.of(_mutationObservers);
    }
  }

  /// Emit a mutation event to TimeTravel (legacy) and every registered
  /// [LayerMutationListener]. No-op while [enableDeltaTracking] is `false`.
  ///
  /// [previousData] is the pre-mutation snapshot used by reversible
  /// operations (textUpdated, imageUpdated, layerModified, layerCleared,
  /// adjustmentUpdated). Pass `null` for non-reversible operations.
  void _emitTT(
    CanvasDeltaType type,
    String layerId, {
    String? elementId,
    Map<String, dynamic>? elementData,
    Map<String, dynamic>? previousData,
  }) {
    if (!enableDeltaTracking) return;

    // Undo tracking is gated separately so a remote-applied mutation
    // can still flow through the CRDT mutation observers (which dedup
    // their own re-emission via runSilently) without polluting the
    // local user's undo stack.
    if (!suppressUndoTracking) {
      onTimeTravelEvent?.call(
        type,
        layerId,
        elementId: elementId,
        elementData: elementData,
      );
    }

    final observers = _mutationObserverSnapshot;
    if (observers.isEmpty) return;

    final delta = CanvasDelta(
      id: _generateUniqueId(),
      type: type,
      layerId: layerId,
      timestamp: DateTime.now(),
      elementId: elementId,
      elementData: elementData,
      previousData: previousData,
      actorId: localActorId,
    );
    for (final obs in observers) {
      obs(delta);
    }
  }

  LayerController() {
    _createDefaultLayer();
    _undoRedoManager.addListener(_onUndoRedoChanged);
  }

  void _onUndoRedoChanged() {
    notifyListeners();
  }

  @override
  void notifyListeners() {
    // 🚀 During batch mode, suppress per-mutation notifications.
    // The eraser calls removeStroke() up to 30× per frame (interpolation).
    // Without this guard, each call triggers cache invalidation + widget
    // rebuild — 30 rebuilds per frame instead of 1.
    if (_isBatching) {
      _batchNeedsNotify = true;
      return;
    }
    _invalidateLayersCache();
    _cachedActiveLayerIndex = null;
    _cachedVisibleShapes = null;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _undoRedoManager.removeListener(_onUndoRedoChanged);
    super.dispose();
  }

  // ==========================================================================
  // 🚀 Batch mode (used by eraser for deferred version bumps)
  // ==========================================================================

  /// Begin a batch of mutations. Version bumps are deferred until [endBatch].
  ///
  /// Nestable — only the outermost [endBatch] triggers the version bump.
  void beginBatch() {
    _batchDepth++;
  }

  /// End a batch of mutations and flush any deferred version bump.
  void endBatch() {
    assert(_batchDepth > 0, 'endBatch called without matching beginBatch');
    _batchDepth--;
    if (_batchDepth == 0) {
      if (_batchNeedsBump) {
        _batchNeedsBump = false;
        if (!_sceneGraphDirty) {
          _sceneGraph.bumpVersion();
        }
      }
      // 🚀 Flush deferred notification — single rebuild for the entire batch
      if (_batchNeedsNotify) {
        _batchNeedsNotify = false;
        _invalidateLayersCache();
        _cachedActiveLayerIndex = null;
        _cachedVisibleShapes = null;
        super.notifyListeners();
      }
    }
  }

  /// Whether we are inside a batch.
  bool get _isBatching => _batchDepth > 0;

  /// Run [body] inside a composite undo batch.
  ///
  /// Every mutation that lands on the [UndoRedoManager] during [body] is
  /// accumulated and pushed as a SINGLE composite undo entry on completion
  /// (one Ctrl+Z reverts the whole operation). Also wraps the call in the
  /// existing [beginBatch] / [endBatch] pair so version bumps and
  /// listener notifications fire once at the end.
  ///
  /// On exception: any partially-accumulated deltas are reverted in-place
  /// and the error is rethrown — the canvas state ends up where it was
  /// before [body] started, preserving atomicity.
  ///
  /// Use for AI cluster actions, group operations, and any high-level
  /// command the user perceives as a single step.
  Future<T> runAsBatch<T>(
    String label,
    Future<T> Function() body,
  ) async {
    beginBatch();
    _undoRedoManager.beginBatch();
    try {
      final result = await body();
      _undoRedoManager.endBatchAsComposite(label, actorId: localActorId);
      return result;
    } catch (e) {
      // Roll back accumulated deltas: pop them off the in-progress batch
      // by ending it as a no-op composite that we then discard.
      _undoRedoManager.endBatchAsComposite('${label}_rolled_back',
          actorId: localActorId);
      _undoRedoManager.discardLastUndo();
      rethrow;
    } finally {
      endBatch();
    }
  }

  /// Delete N scene-graph nodes in a single composite undo entry.
  ///
  /// Routes each node to the appropriate typed removal API
  /// (`removeStroke` / `removeShape` / `removeText` / `removeImage`) and
  /// falls back to a direct `parent.remove(node)` for node types that
  /// don't have a dedicated `LayerController` method (LatexNode,
  /// TabularNode, PathNode, etc.) — the delta tracker captures these via
  /// the scene-graph mutation observer all the same.
  ///
  /// Returns the number of nodes actually removed (skipped types are
  /// counted as 0 — useful for `"$removed elementi rimossi"` snackbars).
  ///
  /// Replaces the legacy `SelectionManager.deleteAll()` path which
  /// generated N separate undo entries — one Ctrl+Z used to revert just
  /// one element of a multi-selection delete. With this API, one Ctrl+Z
  /// reverts the whole bulk delete.
  Future<int> deleteNodes(List<CanvasNode> nodes) async {
    if (nodes.isEmpty) return 0;
    var removed = 0;
    await runAsBatch('Cancella ${nodes.length} elementi', () async {
      for (final node in nodes) {
        if (node is StrokeNode) {
          removeStroke(node.id.toString());
          removed++;
        } else if (node is ShapeNode) {
          removeShape(node.id.toString());
          removed++;
        } else if (node is TextNode) {
          removeText(node.id.toString());
          removed++;
        } else if (node is ImageNode) {
          removeImage(node.id.toString());
          removed++;
        } else {
          // Scene-graph fallback for node types without a typed LayerController
          // removal API. The mutation observer still captures the change as
          // a delta inside the active batch.
          final parent = node.parent;
          if (parent is GroupNode) {
            parent.remove(node);
            removed++;
          }
          // Silently skip orphan nodes (no parent) — defensive.
        }
      }
    });
    return removed;
  }

  /// Bump scene graph version (deferred if batching).
  void _bumpVersionOrDefer() {
    if (_isBatching) {
      _batchNeedsBump = true;
    } else if (!_sceneGraphDirty) {
      _sceneGraph.bumpVersion();
    }
  }

  // ==========================================================================
  // State getters
  // ==========================================================================

  /// 🚀 PERF: Cached unmodifiable view. Recreated only when layers mutate.
  /// Without this, shouldRepaint returned true on EVERY frame because
  /// List.unmodifiable() created a new object on each access.
  List<CanvasLayer>? _cachedUnmodifiableLayers;

  @override
  List<CanvasLayer> get layers {
    _cachedUnmodifiableLayers ??= List.unmodifiable(_layers);
    return _cachedUnmodifiableLayers!;
  }

  /// Invalidate the cached unmodifiable list when layers change.
  void _invalidateLayersCache() {
    _cachedUnmodifiableLayers = null;
  }

  @override
  CanvasLayer? get activeLayer {
    final idx = activeLayerIndex;
    return idx == -1 ? null : _layers[idx];
  }

  @override
  String? get activeLayerId => _activeLayerId;

  @override
  int get activeLayerIndex {
    if (_activeLayerId == null) return -1;
    if (_cachedActiveLayerIndex != null) return _cachedActiveLayerIndex!;
    final idx = _layers.indexWhere((l) => l.id == _activeLayerId);
    _cachedActiveLayerIndex = idx;
    return idx;
  }

  @override
  SpatialIndexManager get spatialIndex {
    if (_spatialIndexDirty) {
      _rebuildSpatialIndexImpl();
    }
    return _spatialIndex;
  }

  /// Get the LayerNode for a given CanvasLayer.
  LayerNode getLayerNode(CanvasLayer layer) => _getLayerNodeImpl(layer);

  /// Find any node by ID anywhere in the scene graph.
  CanvasNode? findNodeById(String nodeId) => _findNodeByIdImpl(nodeId);

  /// The current scene graph (lazy-rebuilt).
  SceneGraph get sceneGraph {
    if (_sceneGraphDirty) {
      _rebuildSceneGraphImpl();
    }
    return _sceneGraph;
  }

  // ==========================================================================
  // 🚀 Delta Save API
  // ==========================================================================

  /// Mark a layer as dirty (content changed since last save).
  void markLayerDirty(String layerId) => _dirtyLayerIds.add(layerId);

  /// Get all layer IDs that have been modified since last save.
  Set<String> get dirtyLayerIds => Set.unmodifiable(_dirtyLayerIds);

  /// Clear dirty tracking after a successful save.
  void clearDirtyLayerIds() => _dirtyLayerIds.clear();

  // ==========================================================================
  // Layer CRUD
  // ==========================================================================

  void _createDefaultLayer() {
    final layer = CanvasLayer(id: _generateUniqueId(), name: 'Layer 1');
    _layers.add(layer);
    _activeLayerId = layer.id;
    // 🛡️ Defensive: the unmodifiable-layers cache uses `??=` and is only
    // invalidated by `notifyListeners()`. If anything reads `layers`
    // before the next notification (e.g. during construction or inside
    // `clearAllAndLoadLayers` between `_layers.clear()` and the trailing
    // notify), the cache freezes against the wrong list. Invalidate
    // explicitly so the next read sees the freshly-added layer.
    _invalidateLayersCache();
    _cachedActiveLayerIndex = null;
  }

  @override
  void addLayer({String? name, String? id}) {
    // Skip silently if a layer with the requested id already exists. This
    // matters when the CRDT applier replays a remote layerAdded op that has
    // already been observed locally — the operation must be idempotent.
    if (id != null && _layers.any((l) => l.id == id)) {
      _activeLayerId = id;
      notifyListeners();
      return;
    }
    final newLayerNumber = _layers.length + 1;
    final layer = CanvasLayer(
      id: id ?? _generateUniqueId(),
      name: name ?? 'Layer $newLayerNumber',
    );
    _layers.add(layer);
    _activeLayerId = layer.id;
    _dirtyLayerIds.add(layer.id);

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerAdded(layer);
    }
    _emitTT(
      CanvasDeltaType.layerAdded,
      layer.id,
      elementData: layer.toJsonMetadataOnly(),
    );
    _invalidateSceneGraph();
    notifyListeners();
  }

  @override
  void duplicateLayer(String layerId) {
    final index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index == -1) return;

    final source = _layers[index];
    final newId = _generateUniqueId();
    final copy = source.copyWith(id: newId, name: '${source.name} (Copy)');

    _layers.insert(index + 1, copy);
    _activeLayerId = newId;
    _dirtyLayerIds.add(newId);

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerAdded(copy);
    }
    _emitTT(CanvasDeltaType.layerAdded, newId);
    _invalidateSceneGraph();

    _spatialIndexDirty = true;
    notifyListeners();
  }

  @override
  void removeLayer(String layerId) {
    if (_layers.length <= 1) return;

    final index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index == -1) return;

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerRemoved(layerId);
    }
    _emitTT(CanvasDeltaType.layerRemoved, layerId);
    _invalidateSceneGraph();

    _layers.removeAt(index);

    if (_activeLayerId == layerId) {
      if (_layers.isNotEmpty) {
        _activeLayerId = _layers[index > 0 ? index - 1 : 0].id;
      } else {
        _activeLayerId = null;
      }
    }

    notifyListeners();
  }

  @override
  void selectLayer(String layerId) {
    if (_layers.any((l) => l.id == layerId)) {
      _activeLayerId = layerId;
      notifyListeners();
    }
  }

  @override
  void renameLayer(String layerId, String newName) {
    final index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index == -1) return;

    final layer = _layers[index];
    final oldName = layer.name;
    _layers[index] = layer.copyWith(name: newName);

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerModified(
        layerId,
        {'name': newName},
        previousValues: {'name': oldName},
      );
    }
    _emitTT(CanvasDeltaType.layerModified, layerId);
    notifyListeners();
  }

  @override
  void toggleLayerVisibility(String layerId) {
    final index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index == -1) return;

    final layer = _layers[index];
    final newVisibility = !layer.isVisible;
    _layers[index] = layer.copyWith(isVisible: newVisibility);

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerModified(
        layerId,
        {'isVisible': newVisibility},
        previousValues: {'isVisible': layer.isVisible},
      );
    }
    _emitTT(CanvasDeltaType.layerModified, layerId);

    _spatialIndexDirty = true;
    _invalidateSceneGraph();
    notifyListeners();
  }

  @override
  void toggleLayerLock(String layerId) {
    final index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index == -1) return;

    final layer = _layers[index];
    final newLock = !layer.isLocked;
    _layers[index] = layer.copyWith(isLocked: newLock);

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerModified(
        layerId,
        {'isLocked': newLock},
        previousValues: {'isLocked': layer.isLocked},
      );
    }
    _emitTT(CanvasDeltaType.layerModified, layerId);
    notifyListeners();
  }

  @override
  void setLayerOpacity(String layerId, double opacity) {
    final index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index == -1) return;

    final layer = _layers[index];
    final clampedOpacity = opacity.clamp(0.0, 1.0);

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerModified(
        layerId,
        {'opacity': clampedOpacity},
        previousValues: {'opacity': layer.opacity},
      );
    }
    _emitTT(CanvasDeltaType.layerModified, layerId);

    _layers[index] = layer.copyWith(opacity: clampedOpacity);
    _invalidateSceneGraph();
    notifyListeners();
  }

  @override
  void setLayerBlendMode(String layerId, ui.BlendMode blendMode) {
    final index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index == -1) return;

    final layer = _layers[index];

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerModified(
        layerId,
        {'blendMode': blendMode.index},
        previousValues: {'blendMode': layer.blendMode.index},
      );
    }
    _emitTT(CanvasDeltaType.layerModified, layerId);

    _layers[index] = layer.copyWith(blendMode: blendMode);
    _invalidateSceneGraph();
    notifyListeners();
  }

  @override
  void moveLayerUp(String layerId) {
    final index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index == -1 || index >= _layers.length - 1) return;

    final layer = _layers.removeAt(index);
    _layers.insert(index + 1, layer);

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerModified(layerId, {
        'reorder': 'up',
        'from': index,
        'to': index + 1,
      });
    }
    _emitTT(CanvasDeltaType.layerModified, layerId);
    _invalidateSceneGraph();
    notifyListeners();
  }

  @override
  void moveLayerDown(String layerId) {
    final index = _layers.indexWhere((layer) => layer.id == layerId);
    if (index <= 0) return;

    final layer = _layers.removeAt(index);
    _layers.insert(index - 1, layer);

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerModified(layerId, {
        'reorder': 'down',
        'from': index,
        'to': index - 1,
      });
    }
    _emitTT(CanvasDeltaType.layerModified, layerId);
    _invalidateSceneGraph();
    notifyListeners();
  }

  // ==========================================================================
  // Element operations (delegated → layer_element_operations.dart)
  // ==========================================================================

  @override
  void addStroke(ProStroke stroke) {
    _addStrokeImpl(stroke);
    notifyListeners();
  }

  @override
  Future<void> addStrokesBatch(List<ProStroke> strokes) async {
    await _addStrokesBatchImpl(strokes);
    notifyListeners();
  }

  @override
  void addShape(GeometricShape shape) {
    _addShapeImpl(shape);
    notifyListeners();
  }

  @override
  void removeStrokeAt(int index) {
    _removeStrokeAtImpl(index);
    notifyListeners();
  }

  @override
  void removeStroke(String strokeId) {
    _removeStrokeImpl(strokeId);
    notifyListeners();
  }

  @override
  void removeShapeAt(int index) {
    _removeShapeAtImpl(index);
    notifyListeners();
  }

  @override
  void removeShape(String shapeId) {
    _removeShapeImpl(shapeId);
    notifyListeners();
  }

  @override
  void undoLastElement() {
    _undoLastElementImpl();
    notifyListeners();
  }

  @override
  void addText(DigitalTextElement text) {
    _addTextImpl(text);
    notifyListeners();
  }

  @override
  void removeText(String textId) {
    _removeTextImpl(textId);
    notifyListeners();
  }

  @override
  void updateText(DigitalTextElement updatedText) {
    _updateTextImpl(updatedText);
    notifyListeners();
  }

  @override
  void addImage(ImageElement image) {
    _addImageImpl(image);
    notifyListeners();
  }

  @override
  void removeImage(String imageId) {
    _removeImageImpl(imageId);
    notifyListeners();
  }

  void updateImage(ImageElement updatedImage) {
    _updateImageImpl(updatedImage);
    notifyListeners();
  }

  @override
  void addAdjustmentLayer(String id, AdjustmentStack stack) {
    _addAdjustmentLayerImpl(id, stack);
    notifyListeners();
  }

  @override
  void removeAdjustmentLayer(String adjustmentId) {
    _removeAdjustmentLayerImpl(adjustmentId);
    notifyListeners();
  }

  @override
  void updateAdjustmentLayer(String adjustmentId, AdjustmentStack newStack) {
    _updateAdjustmentLayerImpl(adjustmentId, newStack);
    notifyListeners();
  }

  @override
  void clearActiveLayer() {
    _clearActiveLayerImpl();
    notifyListeners();
  }

  @override
  List<ProStroke> getAllVisibleStrokes() => _getAllVisibleStrokesImpl();

  /// 🚀 PERF: Cached visible shapes list.
  List<GeometricShape>? _cachedVisibleShapes;

  @override
  List<GeometricShape> getAllVisibleShapes() {
    _cachedVisibleShapes ??= _getAllVisibleShapesImpl();
    return _cachedVisibleShapes!;
  }

  List<DigitalTextElement> getAllVisibleTexts() => _getAllVisibleTextsImpl();

  // ==========================================================================
  // Spatial index (delegated → layer_spatial_index.dart)
  // ==========================================================================

  void invalidateSpatialIndex() {
    _invalidateSpatialIndexImpl();
  }

  // ==========================================================================
  // Undo/Redo (via UndoRedoManager)
  // ==========================================================================

  void undo() {
    final delta = _undoRedoManager.undo();
    if (delta == null) return;

    final wasTrackingEnabled = enableDeltaTracking;
    enableDeltaTracking = false;

    final oldLayers = List<CanvasLayer>.from(_layers);
    final updatedLayers = UndoRedoManager.applyInverseDelta(_layers, delta);
    _layers.clear();
    _layers.addAll(updatedLayers);
    _transplantExtraChildren(oldLayers, _layers);

    // Mark ALL layers dirty — undo can affect any layer
    for (final l in _layers) {
      _dirtyLayerIds.add(l.id);
    }

    _spatialIndexDirty = true;
    _invalidateSceneGraph();
    enableDeltaTracking = wasTrackingEnabled;
    notifyListeners();
  }

  void redo() {
    final delta = _undoRedoManager.redo();
    if (delta == null) return;

    final wasTrackingEnabled = enableDeltaTracking;
    enableDeltaTracking = false;

    final oldLayers = List<CanvasLayer>.from(_layers);
    final updatedLayers = UndoRedoManager.reapplyDelta(_layers, delta);
    _layers.clear();
    _layers.addAll(updatedLayers);
    _transplantExtraChildren(oldLayers, _layers);

    // Mark ALL layers dirty — redo can affect any layer
    for (final l in _layers) {
      _dirtyLayerIds.add(l.id);
    }

    _spatialIndexDirty = true;
    _invalidateSceneGraph();
    enableDeltaTracking = wasTrackingEnabled;
    notifyListeners();
  }

  bool get canUndo => _undoRedoManager.canUndo;
  bool get canRedo => _undoRedoManager.canRedo;

  /// 🗑️ Silently discard the last action without adding to redo stack.
  /// Used by double-tap zoom to remove the accidental dot from the first tap.
  void discardLastAction() {
    final delta = _undoRedoManager.discardLastUndo();
    if (delta == null) return;

    final wasTrackingEnabled = enableDeltaTracking;
    enableDeltaTracking = false;

    final oldLayers = List<CanvasLayer>.from(_layers);
    final updatedLayers = UndoRedoManager.applyInverseDelta(_layers, delta);
    _layers.clear();
    _layers.addAll(updatedLayers);
    _transplantExtraChildren(oldLayers, _layers);

    for (final l in _layers) {
      _dirtyLayerIds.add(l.id);
    }

    _spatialIndexDirty = true;
    _invalidateSceneGraph();
    enableDeltaTracking = wasTrackingEnabled;
    notifyListeners();
  }

  /// 🔄 Transplant extra children (TabularNode, LatexNode, PdfDocumentNode, etc.)
  /// from old layers to new layers after undo/redo/discard.
  ///
  /// `CanvasLayer.copyWith()` only preserves strokes/shapes/texts/images,
  /// silently dropping non-standard scene graph children. This method
  /// re-attaches them to the matching new layer by ID.
  void _transplantExtraChildren(
    List<CanvasLayer> oldLayers,
    List<CanvasLayer> newLayers,
  ) {
    final newLayerMap = {for (final l in newLayers) l.id: l};
    for (final oldLayer in oldLayers) {
      final newLayer = newLayerMap[oldLayer.id];
      if (newLayer == null) continue;
      // Skip if they're the same instance (no copyWith happened)
      if (identical(oldLayer.node, newLayer.node)) continue;

      // 🚀 Generic: transfer ALL non-standard children by type check.
      // No need to build a set of standard IDs — just check the type.
      for (final child in oldLayer.node.children) {
        if (child is! StrokeNode &&
            child is! ShapeNode &&
            child is! TextNode &&
            child is! ImageNode) {
          newLayer.node.add(child);
        }
      }
    }
  }

  // ==========================================================================
  // Scene graph (private)
  // ==========================================================================

  void _invalidateSceneGraph() {
    _sceneGraphDirty = true;
  }

  // ==========================================================================
  // Bulk operations
  // ==========================================================================

  @override
  void updateLayer(CanvasLayer updatedLayer) {
    final index = _layers.indexWhere((layer) => layer.id == updatedLayer.id);
    if (index == -1) return;

    _layers[index] = updatedLayer;
    _spatialIndexDirty = true;
    _invalidateSceneGraph();
    notifyListeners();
  }

  @override
  void clearAllAndLoadLayers(List<CanvasLayer> newLayers) {
    final wasTrackingEnabled = enableDeltaTracking;
    enableDeltaTracking = false;

    _layers.clear();
    // Clear dirty tracking — fresh load, nothing to diff against
    _dirtyLayerIds.clear();

    if (newLayers.isEmpty) {
      _createDefaultLayer();
    } else {
      _layers.addAll(newLayers);

      final hasActiveLayer =
          _activeLayerId != null &&
          newLayers.any((l) => l.id == _activeLayerId);

      if (!hasActiveLayer) {
        _activeLayerId = newLayers.first.id;
      }
    }

    _spatialIndexDirty = true;
    _invalidateSceneGraph();
    enableDeltaTracking = wasTrackingEnabled;
    notifyListeners();
  }
}
