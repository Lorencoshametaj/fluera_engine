import 'dart:ui' as ui;
import '../core/models/canvas_layer.dart';
import '../core/scene_graph/canvas_node.dart';
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
typedef TimeTravelEventCallback =
    void Function(
      CanvasDeltaType type,
      String layerId, {
      String? elementId,
      Map<String, dynamic>? elementData,
    });

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

  /// Flag to enable/disable delta tracking.
  /// Disable during batch operations (e.g., load from storage).
  bool enableDeltaTracking = true;

  /// Time Travel: optional callback to record events.
  TimeTravelEventCallback? onTimeTravelEvent;

  /// Helper: emit Time Travel event if callback is set.
  void _emitTT(
    CanvasDeltaType type,
    String layerId, {
    String? elementId,
    Map<String, dynamic>? elementData,
  }) {
    if (!enableDeltaTracking) return;
    onTimeTravelEvent?.call(
      type,
      layerId,
      elementId: elementId,
      elementData: elementData,
    );
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
    if (_batchDepth == 0 && _batchNeedsBump) {
      _batchNeedsBump = false;
      if (!_sceneGraphDirty) {
        _sceneGraph.bumpVersion();
      }
    }
  }

  /// Whether we are inside a batch.
  bool get _isBatching => _batchDepth > 0;

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
  }

  @override
  void addLayer({String? name}) {
    final newLayerNumber = _layers.length + 1;
    final layer = CanvasLayer(
      id: _generateUniqueId(),
      name: name ?? 'Layer $newLayerNumber',
    );
    _layers.add(layer);
    _activeLayerId = layer.id;
    _dirtyLayerIds.add(layer.id);

    if (enableDeltaTracking) {
      _deltaTracker.recordLayerAdded(layer);
    }
    _emitTT(CanvasDeltaType.layerAdded, layer.id);
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
