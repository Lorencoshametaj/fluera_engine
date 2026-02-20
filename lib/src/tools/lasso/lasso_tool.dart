import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/scene_graph/canvas_node.dart';
import '../../core/nodes/group_node.dart';
import '../../core/scene_graph/node_id.dart';
import '../../core/nodes/layer_node.dart';
import '../../core/nodes/stroke_node.dart';
import '../../core/nodes/shape_node.dart';
import '../../core/nodes/text_node.dart';
import '../../core/nodes/image_node.dart';
import '../../core/models/canvas_layer.dart';
import '../../layers/nebula_layer_controller.dart';
import '../../reflow/content_cluster.dart';
import '../../reflow/reflow_physics_engine.dart';
import '../../systems/selection_manager.dart';

part '_lasso_transforms.dart';
part '_lasso_clipboard.dart';
part '_lasso_advanced.dart';
part '_lasso_alignment.dart';
part '_lasso_properties.dart';
part '_lasso_visual.dart';

// =============================================================================
// Constants
// =============================================================================

/// Default estimated size for image elements when no actual size is known.
const double _kDefaultImageSize = 200.0;

/// Default estimated size for text elements when no context is available.
const double _kDefaultTextWidth = 150.0;
const double _kDefaultTextHeight = 40.0;

/// Padding added to selection bounds for comfortable drag hit-testing.
const double _kSelectionBoundsPadding = 20.0;

/// 🎨 LASSO TOOL — Professional selection tool (scene graph backed)
///
/// All selection state is managed through [SelectionManager].
/// Transforms, alignment, clipboard, and z-ordering all delegate
/// to [CanvasNode] APIs — no flat-layer duplication.
class LassoTool {
  final NebulaLayerController layerController;

  /// The single source of truth for selection state.
  final SelectionManager selectionManager;

  // Lasso path being drawn
  List<Offset> lassoPath = [];

  /// 🚀 PERF: Notifier that fires when lassoPath changes.
  final ValueNotifier<int> lassoPathNotifier = ValueNotifier<int>(0);

  /// 🚀 PERF: Notifier that fires during drag for smooth overlay updates.
  final ValueNotifier<int> dragNotifier = ValueNotifier<int>(0);

  /// All currently selected element IDs (unified set).
  Set<String> get selectedIds => selectionManager.selectedIds;

  /// Restore selection from a set of IDs (used for undo-on-cancel).
  ///
  /// Resolves each ID back to a CanvasNode in the active layer
  /// and re-selects them through the SelectionManager.
  void restoreSelectionFromIds(Set<String> ids) {
    if (ids.isEmpty) return;
    final layerNode = _getActiveLayerNode();
    final nodes = <CanvasNode>[];
    for (final id in ids) {
      final node = layerNode.findChild(id);
      if (node != null) nodes.add(node);
    }
    if (nodes.isNotEmpty) {
      selectionManager.selectAll(nodes);
      _calculateSelectionBounds();
    }
  }

  // Drag state
  bool _isDragging = false;
  Offset? _dragStartPosition;
  Rect? _selectionBounds;

  /// 🚀 PERF: Accumulated drag offset not yet applied to stroke data.
  Offset _pendingDragDelta = Offset.zero;
  int _lastMoveSelectedTime = 0;
  static const int _moveSelectedThrottleMs = 32; // ~30fps for heavy work

  // 🌊 FLING: Velocity tracking during drag (exponential smoothing)
  Offset _dragVelocity = Offset.zero;
  int _lastDragTimestamp = 0;
  static const double _velocitySmoothing = 0.3; // α for EMA

  // Snap-to-grid configuration
  bool snapEnabled = false;
  double gridSpacing = _kDefaultGridSpacing;

  // Undo snapshot (last layer state before a transform batch)
  CanvasLayer? _undoSnapshot;

  // Multi-layer selection mode
  bool multiLayerMode = false;

  // Marquee (rubber band) selection state
  Offset? _marqueeStart;
  Offset? _marqueeEnd;

  // Selection mode: lasso or marquee
  SelectionMode _selectionMode = SelectionMode.lasso;

  // Additive selection mode (Shift + lasso adds to existing selection)
  bool _additiveMode = false;

  // 🌊 REFLOW: Physics engine and cluster cache for content reflow
  ReflowPhysicsEngine? _reflowEngine;
  List<ContentCluster> _clusterCache = [];

  /// Current reflow cluster cache (for ghost rendering in overlay).
  List<ContentCluster> get clusterCache => _clusterCache;

  /// Current reflow ghost displacements (during drag, for preview rendering).
  Map<String, Offset> reflowGhostDisplacements = {};

  /// Whether content reflow is active (engine and clusters available).
  bool get isReflowEnabled =>
      _reflowEngine != null && _reflowEngine!.config.enabled;

  LassoTool({required this.layerController, SelectionManager? selectionManager})
    : selectionManager = selectionManager ?? SelectionManager();

  /// 🌊 REFLOW: Attach the reflow physics engine and initial cluster cache.
  void attachReflow(ReflowPhysicsEngine engine, List<ContentCluster> clusters) {
    _reflowEngine = engine;
    _clusterCache = clusters;
  }

  /// 🌊 REFLOW: Update the cluster cache (called when layer content changes).
  void updateClusterCache(List<ContentCluster> clusters) {
    _clusterCache = clusters;
  }

  /// 🌊 REFLOW: Detach the reflow engine.
  void detachReflow() {
    _reflowEngine = null;
    _clusterCache = [];
    reflowGhostDisplacements = {};
  }

  // ===========================================================================
  // Selection Query
  // ===========================================================================

  bool get hasSelection => selectionManager.isNotEmpty;

  int get selectionCount => selectionManager.count;

  bool get isDragging => _isDragging;

  /// 🌊 FLING: Last computed drag velocity (canvas-space pixels/second).
  Offset get lastDragVelocity => _dragVelocity;

  // ===========================================================================
  // Drag Operations
  // ===========================================================================

  bool isPointInSelection(Offset point) {
    if (!hasSelection) return false;
    if (_selectionBounds == null) _calculateSelectionBounds();
    return _selectionBounds?.contains(point) ?? false;
  }

  void startDrag(Offset position) {
    _isDragging = true;
    _dragStartPosition = position;
    _dragVelocity = Offset.zero;
    _lastDragTimestamp = DateTime.now().millisecondsSinceEpoch;
    saveUndoSnapshot();
  }

  /// Returns true if data was actually updated (moveSelected ran),
  /// false if the frame was throttled (only bounds shifted).
  bool updateDrag(Offset currentPosition) {
    if (!_isDragging || _dragStartPosition == null) return false;
    var delta = currentPosition - _dragStartPosition!;
    if (snapEnabled) delta = snapDelta(delta);

    // 🌊 FLING: Track velocity via exponential moving average
    final now = DateTime.now().millisecondsSinceEpoch;
    final dtMs = now - _lastDragTimestamp;
    if (dtMs > 0) {
      final dtSeconds = dtMs / 1000.0;
      final instantVelocity = delta / dtSeconds;
      _dragVelocity = Offset(
        _dragVelocity.dx * (1 - _velocitySmoothing) +
            instantVelocity.dx * _velocitySmoothing,
        _dragVelocity.dy * (1 - _velocitySmoothing) +
            instantVelocity.dy * _velocitySmoothing,
      );
      _lastDragTimestamp = now;
    }

    // 🚀 PERF: Always update selection bounds (cheap) for smooth overlay
    if (_selectionBounds != null) {
      _selectionBounds = _selectionBounds!.shift(delta);
    }
    _dragStartPosition = currentPosition;
    dragNotifier.value++;

    // 🚀 PERF: Throttle the expensive translateAll.
    _pendingDragDelta += delta;
    if (now - _lastMoveSelectedTime >= _moveSelectedThrottleMs) {
      _lastMoveSelectedTime = now;
      selectionManager.translateAll(_pendingDragDelta.dx, _pendingDragDelta.dy);
      _pendingDragDelta = Offset.zero;
      return true;
    }
    return false;
  }

  void compensateScroll(Offset scrollDelta) {
    if (!_isDragging || _dragStartPosition == null) return;
    selectionManager.translateAll(scrollDelta.dx, scrollDelta.dy);
    _dragStartPosition = _dragStartPosition! + scrollDelta;
    if (_selectionBounds != null) {
      _selectionBounds = _selectionBounds!.shift(scrollDelta);
    }
  }

  void endDrag() {
    // 🚀 PERF: Flush any remaining pending drag delta
    if (_pendingDragDelta != Offset.zero) {
      selectionManager.translateAll(_pendingDragDelta.dx, _pendingDragDelta.dy);
      _pendingDragDelta = Offset.zero;
    }

    _isDragging = false;
    _dragStartPosition = null;
    _lastMoveSelectedTime = 0;

    // 🌊 REFLOW: On drag end, do the full solve and bake displacements
    if (isReflowEnabled && reflowGhostDisplacements.isNotEmpty) {
      _bakeReflowDisplacements();
    }
    reflowGhostDisplacements = {};
  }

  // ===========================================================================
  // Lasso Path Lifecycle
  // ===========================================================================

  void startLasso(Offset position) {
    lassoPath.clear();
    lassoPath.add(position);
    lassoPathNotifier.value++;
    clearSelection();
  }

  void updateLasso(Offset position) {
    lassoPath.add(position);
    lassoPathNotifier.value++;
  }

  void completeLasso() {
    if (_additiveMode) {
      _completeLassoAdditive();
      return;
    }

    if (lassoPath.length < 3) {
      lassoPath.clear();
      return;
    }

    if (lassoPath.first != lassoPath.last) {
      lassoPath.add(lassoPath.first);
    }

    final path = Path();
    path.moveTo(lassoPath.first.dx, lassoPath.first.dy);
    for (var i = 1; i < lassoPath.length; i++) {
      path.lineTo(lassoPath[i].dx, lassoPath[i].dy);
    }
    path.close();

    if (multiLayerMode) {
      selectFromAllLayers(path);
    } else {
      _selectElementsInPath(path);
    }

    if (!hasSelection) {
      lassoPath.clear();
      return;
    }

    _calculateSelectionBounds();
    lassoPath.clear();
  }

  // ===========================================================================
  // Hit-Testing — Scene Graph
  // ===========================================================================

  void _selectElementsInPath(Path lassoPath) {
    final layerNode = _getActiveLayerNode();
    final lassoBounds = lassoPath.getBounds();
    final hits = <CanvasNode>[];

    for (final child in layerNode.children) {
      if (!child.isVisible || child.isLocked) continue;

      final bounds = child.worldBounds;
      if (!bounds.isFinite || bounds.isEmpty) continue;
      if (!bounds.overlaps(lassoBounds)) continue;

      // Multi-point test: center + corners
      if (lassoPath.contains(bounds.center) ||
          lassoPath.contains(bounds.topLeft) ||
          lassoPath.contains(bounds.topRight) ||
          lassoPath.contains(bounds.bottomLeft) ||
          lassoPath.contains(bounds.bottomRight)) {
        hits.add(child);
      }
    }

    if (hits.isNotEmpty) {
      selectionManager.selectAll(hits);
    }
  }

  // ===========================================================================
  // Element Operations — Delete & Move
  // ===========================================================================

  void deleteSelected() {
    selectionManager.deleteAll();
  }

  void moveSelected(Offset delta) {
    if (!hasSelection) return;
    if (isSelectionLocked) return;
    selectionManager.translateAll(delta.dx, delta.dy);

    // 🌊 REFLOW: Estimate ghost displacements
    if (isReflowEnabled) {
      _calculateSelectionBounds();
      if (_selectionBounds != null) {
        final excludeIds = _getSelectedClusterIds();
        reflowGhostDisplacements = _reflowEngine!.estimateDisplacements(
          clusters: _clusterCache,
          disturbance: _selectionBounds!,
          excludeIds: excludeIds,
        );
      }
    }
  }

  /// 🌊 REFLOW: Get cluster IDs that contain any selected element.
  Set<String> _getSelectedClusterIds() {
    final allSelectedIds = selectionManager.selectedIds;
    final ids = <String>{};
    for (final cluster in _clusterCache) {
      for (final elementId in allSelectedIds) {
        if (cluster.containsElement(elementId)) {
          ids.add(cluster.id);
          break;
        }
      }
    }
    return ids;
  }

  /// 🌊 REFLOW: Public API to bake ghost displacements into actual positions.
  void bakeReflowDisplacements() => _bakeReflowDisplacements();

  /// 🌊 REFLOW: Bake ghost displacements into actual element positions.
  void _bakeReflowDisplacements() {
    if (reflowGhostDisplacements.isEmpty) return;

    _calculateSelectionBounds();
    if (_selectionBounds == null) return;

    final excludeIds = _getSelectedClusterIds();
    final finalDisplacements = _reflowEngine!.solve(
      clusters: _clusterCache,
      disturbance: _selectionBounds!,
      excludeIds: excludeIds,
    );

    if (finalDisplacements.isEmpty) return;

    // Collect all element IDs that need to move
    final affectedElementIds = <String, Offset>{};
    for (final entry in finalDisplacements.entries) {
      final cluster = _clusterCache.firstWhere(
        (c) => c.id == entry.key,
        orElse:
            () => ContentCluster(
              id: '',
              strokeIds: const [],
              bounds: Rect.zero,
              centroid: Offset.zero,
            ),
      );
      if (cluster.id.isEmpty) continue;
      for (final id in cluster.strokeIds) {
        affectedElementIds[id] = entry.value;
      }
      for (final id in cluster.shapeIds) {
        affectedElementIds[id] = entry.value;
      }
      for (final id in cluster.textIds) {
        affectedElementIds[id] = entry.value;
      }
      for (final id in cluster.imageIds) {
        affectedElementIds[id] = entry.value;
      }
    }

    if (affectedElementIds.isEmpty) return;

    // Apply displacements via scene graph
    final layerNode = _getActiveLayerNode();
    for (final entry in affectedElementIds.entries) {
      final node = layerNode.findChild(entry.key);
      if (node != null && !node.isLocked) {
        node.translate(entry.value.dx, entry.value.dy);
      }
    }
  }

  // ===========================================================================
  // Public API — Delegates
  // ===========================================================================

  // Transforms
  void rotateSelected() => selectionManager.rotateAll(pi / 2);
  void rotateSelectedByAngle(double radians, {Offset? center}) =>
      selectionManager.rotateAll(radians);
  void scaleSelected(double factor, {Offset? center}) =>
      selectionManager.scaleAll(factor, factor);
  void flipHorizontal() => selectionManager.flipHorizontal();
  void flipVertical() => selectionManager.flipVertical();

  // Clipboard
  void copySelected() => _copySelected();
  int pasteFromClipboard({Offset offset = const Offset(20, 20)}) =>
      _pasteFromClipboard(offset: offset);
  int duplicateSelected({Offset offset = const Offset(20, 20)}) =>
      _duplicateSelected(offset: offset);

  // Select All
  void selectAll() => _selectAll();

  // Z-ordering
  void bringToFront() => _bringToFront();
  void sendToBack() => _sendToBack();

  // Grouping
  String? groupSelected() => _groupSelected();
  int ungroupSelected() => _ungroupSelected();

  // Snap-to-grid
  Offset snapDelta(Offset delta) =>
      snapEnabled ? _snapDeltaToGrid(delta, gridSpacing: gridSpacing) : delta;
  void toggleSnap() => snapEnabled = !snapEnabled;

  // Undo snapshots
  void saveUndoSnapshot() => _undoSnapshot = _takeSnapshot();
  void restoreUndo() {
    if (_undoSnapshot != null) {
      _restoreSnapshot(_undoSnapshot!);
      _undoSnapshot = null;
    }
  }

  bool get hasUndoSnapshot => _undoSnapshot != null;

  // Alignment
  void alignLeft() => selectionManager.alignLeft();
  void alignRight() => selectionManager.alignRight();
  void alignCenterH() => selectionManager.alignCenterH();
  void alignTop() => selectionManager.alignTop();
  void alignBottom() => selectionManager.alignBottom();
  void alignCenterV() => selectionManager.alignCenterV();
  void distributeHorizontal() => selectionManager.distributeHorizontally();
  void distributeVertical() => selectionManager.distributeVertically();

  // Lock / Unlock
  void lockSelected() => _lockSelected();
  void unlockSelected() => _unlockSelected();
  bool get isSelectionLocked => _isSelectionLocked();
  bool isElementLocked(String id) => _isLocked(id);

  // Opacity
  void setSelectedOpacity(double opacity) => _setSelectedOpacity(opacity);

  // Color
  void setSelectedColor(Color color) => _setSelectedColor(color);

  // Proportional Scaling
  void scaleProportional(double factor, {Offset? center}) =>
      scaleSelected(factor, center: center);

  // Selection Statistics
  SelectionStats get selectionStats => _getSelectionStats();

  // Multi-Layer Selection
  void selectFromAllLayers(Path path) => _selectFromAllLayers(path);
  void toggleMultiLayerMode() => multiLayerMode = !multiLayerMode;

  // Export Selection
  Rect? get exportBounds => _getExportBounds();

  // Rubber Band / Marquee Selection
  SelectionMode get selectionMode => _selectionMode;
  set selectionMode(SelectionMode mode) => _selectionMode = mode;
  void startMarquee(Offset position) => _startMarquee(position);
  void updateMarquee(Offset position) => _updateMarquee(position);
  void completeMarquee() => _completeMarquee();
  Rect? get marqueeRect => _getMarqueeRect();

  // Additive Selection (Shift + Lasso)
  bool get additiveMode => _additiveMode;
  set additiveMode(bool value) => _additiveMode = value;
  void completeLassoAdditive() => _completeLassoAdditive();

  // Smart Guides
  List<Rect> get nonSelectedElementBounds => _getNonSelectedElementBounds();

  // Selection Persistence
  Map<String, dynamic> serializeSelection() => _serializeSelection();
  void deserializeSelection(Map<String, dynamic> data) =>
      _deserializeSelection(data);

  // ===========================================================================
  // Selection Management
  // ===========================================================================

  void clearSelection() {
    selectionManager.clearSelection();
    _selectionBounds = null;
    lassoPath.clear();
    _isDragging = false;
    _dragStartPosition = null;
  }

  void clearLassoPath() {
    lassoPath.clear();
  }

  Rect? getSelectionBounds() {
    if (_selectionBounds == null) _calculateSelectionBounds();
    return _selectionBounds;
  }

  // ===========================================================================
  // Clipboard compatibility (hasClipboard)
  // ===========================================================================

  bool get hasClipboard => LassoClipboard._clipboardNodes.isNotEmpty;

  // ===========================================================================
  // Private Helpers
  // ===========================================================================

  CanvasLayer _getActiveLayer() {
    return layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );
  }

  LayerNode _getActiveLayerNode() => _getActiveLayer().node;

  void _updateLayer(CanvasLayer updatedLayer) {
    layerController.updateLayer(updatedLayer);
  }

  void _calculateSelectionBounds() {
    if (!hasSelection) {
      _selectionBounds = null;
      return;
    }

    final bounds = selectionManager.aggregateBounds;
    if (bounds == Rect.zero) {
      _selectionBounds = null;
      return;
    }
    _selectionBounds = bounds.inflate(_kSelectionBoundsPadding);
  }

  /// Resolve an element ID to its CanvasNode in the active layer.
  CanvasNode? _resolveNode(String id) {
    return _getActiveLayerNode().findChild(id);
  }
}
