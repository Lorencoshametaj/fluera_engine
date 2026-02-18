import 'dart:ui' as ui;
import '../core/models/canvas_layer.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/layer_node.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../core/models/shape_type.dart';
import '../core/models/digital_text_element.dart';
import '../core/models/image_element.dart';
import '../core/scene_graph/scene_graph.dart';
import '../rendering/optimization/spatial_index.dart';
import '../history/canvas_delta_tracker.dart';
import '../history/undo_redo_manager.dart';
import '../rendering/optimization/dirty_region_tracker.dart';
import './nebula_layer_controller.dart';

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
      int? pageIndex,
    });

/// Controller for managing canvas layers.
///
/// Supports QuadTree spatial index for O(log n) performance with 10k+ strokes,
/// delta tracking for incremental sync, undo/redo, and scene graph management.
///
/// Heavy element CRUD is in [layer_element_operations.dart],
/// spatial index in [layer_spatial_index.dart], and scene graph
/// in [layer_scene_graph.dart].
class LayerController extends NebulaLayerController {
  final List<CanvasLayer> _layers = [];
  String? _activeLayerId;

  /// Spatial Index for optimized viewport queries.
  final SpatialIndexManager _spatialIndex = SpatialIndexManager();

  /// Flag to rebuild spatial index.
  bool _spatialIndexDirty = true;

  /// Delta Tracker for incremental sync (singleton).
  final CanvasDeltaTracker _deltaTracker = CanvasDeltaTracker.instance;

  /// Page index (for PDF hybrid storage).
  final int? pageIndex;

  /// Undo/Redo Manager (singleton).
  final UndoRedoManager _undoRedoManager = UndoRedoManager.instance;

  /// Dirty Region Tracker.
  final DirtyRegionTracker _dirtyRegionTracker = DirtyRegionTracker();

  /// Scene graph (lazy-rebuilt from layers).
  SceneGraph _sceneGraph = SceneGraph();
  bool _sceneGraphDirty = true;

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
      pageIndex: pageIndex,
    );
  }

  LayerController({this.pageIndex}) {
    _createDefaultLayer();
    _undoRedoManager.addListener(_onUndoRedoChanged);
  }

  void _onUndoRedoChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _undoRedoManager.removeListener(_onUndoRedoChanged);
    super.dispose();
  }

  // ==========================================================================
  // State getters
  // ==========================================================================

  @override
  List<CanvasLayer> get layers => List.unmodifiable(_layers);

  @override
  CanvasLayer? get activeLayer {
    if (_activeLayerId == null) return null;
    try {
      return _layers.firstWhere((l) => l.id == _activeLayerId);
    } catch (_) {
      return null;
    }
  }

  @override
  String? get activeLayerId => _activeLayerId;

  @override
  int get activeLayerIndex => _layers.indexWhere((l) => l.id == _activeLayerId);

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
  // Layer CRUD
  // ==========================================================================

  void _createDefaultLayer() {
    final layer = CanvasLayer(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Layer 1',
    );
    _layers.add(layer);
    _activeLayerId = layer.id;
  }

  @override
  void addLayer({String? name}) {
    final newLayerNumber = _layers.length + 1;
    final layer = CanvasLayer(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name ?? 'Layer $newLayerNumber',
    );
    _layers.add(layer);
    _activeLayerId = layer.id;

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
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final copy = source.copyWith(id: newId, name: '${source.name} (Copy)');

    _layers.insert(index + 1, copy);
    _activeLayerId = newId;

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
        pageIndex: pageIndex,
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
        pageIndex: pageIndex,
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
        pageIndex: pageIndex,
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
        pageIndex: pageIndex,
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
        pageIndex: pageIndex,
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
      }, pageIndex: pageIndex);
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
      }, pageIndex: pageIndex);
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
  void clearActiveLayer() {
    _clearActiveLayerImpl();
    notifyListeners();
  }

  @override
  List<ProStroke> getAllVisibleStrokes() => _getAllVisibleStrokesImpl();

  @override
  List<GeometricShape> getAllVisibleShapes() => _getAllVisibleShapesImpl();

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

    final updatedLayers = UndoRedoManager.applyInverseDelta(_layers, delta);
    _layers.clear();
    _layers.addAll(updatedLayers);

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

    final updatedLayers = UndoRedoManager.reapplyDelta(_layers, delta);
    _layers.clear();
    _layers.addAll(updatedLayers);

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

    final updatedLayers = UndoRedoManager.applyInverseDelta(_layers, delta);
    _layers.clear();
    _layers.addAll(updatedLayers);

    _spatialIndexDirty = true;
    _invalidateSceneGraph();
    enableDeltaTracking = wasTrackingEnabled;
    notifyListeners();
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
