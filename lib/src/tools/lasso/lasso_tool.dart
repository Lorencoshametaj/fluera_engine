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
import '../../layers/fluera_layer_controller.dart';
import '../../reflow/reflow_controller.dart';
import '../../reflow/content_cluster.dart';
import '../../systems/selection_manager.dart';
import '../../rendering/canvas/drawing_painter.dart';

part '_lasso_transforms.dart';
part '_lasso_clipboard.dart';
part '_lasso_advanced.dart';
part '_lasso_alignment.dart';
part '_lasso_properties.dart';
part '_lasso_visual.dart';
part '_lasso_color_select.dart';
part '_lasso_warp.dart';

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
  final FlueraLayerController layerController;

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
  static const int _moveSelectedThrottleMs = 16; // ~60fps real-time drag

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

  // Selection mode: lasso, marquee, or ellipse
  SelectionMode _selectionMode = SelectionMode.lasso;

  // Additive selection mode (Shift + lasso adds to existing selection)
  bool _additiveMode = false;

  // Subtractive selection mode (Alt + lasso removes from existing selection)
  bool _subtractiveMode = false;

  /// Feather radius for soft-edge selection (0.0 = sharp, higher = softer).
  double featherRadius = 0.0;

  /// Color tolerance for color-based automatic selection (0.0–1.0).
  double colorTolerance = 0.15;

  /// Reference layer ID — when set, hit-testing uses this layer's nodes
  /// but selects the corresponding nodes on the active layer.
  String? referenceLayerId;

  /// Transform mode for handle-based transforms.
  TransformMode transformMode = TransformMode.uniform;

  /// Active warp mesh for mesh deformation (null when inactive).
  WarpMeshGrid? _warpMesh;

  // 🌊 REFLOW: Delegated to ReflowController (tool-agnostic)
  ReflowController? reflowController;

  /// Current reflow cluster cache (for ghost rendering in overlay).
  List<ContentCluster> get clusterCache => reflowController?.clusterCache ?? [];

  /// Current reflow ghost displacements (during drag, for preview rendering).
  Map<String, Offset> get reflowGhostDisplacements =>
      reflowController?.ghostDisplacements ?? {};

  /// Whether content reflow is active (controller attached and enabled).
  bool get isReflowEnabled => reflowController?.isEnabled ?? false;

  LassoTool({required this.layerController, SelectionManager? selectionManager})
    : selectionManager = selectionManager ?? SelectionManager();

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

      // 🌊 REFLOW: Compute ghost displacements in real-time during drag
      if (isReflowEnabled) {
        _calculateSelectionBounds();
        if (_selectionBounds != null) {
          final excludeIds = reflowController!.getClusterIdsForElements(
            selectionManager.selectedIds,
          );
          reflowController!.computeGhostDisplacements(
            disturbance: _selectionBounds!,
            excludeIds: excludeIds,
          );
        }
      }

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

  void endDrag({bool skipReflow = false}) {
    // 🚀 PERF: Flush any remaining pending drag delta
    if (_pendingDragDelta != Offset.zero) {
      selectionManager.translateAll(_pendingDragDelta.dx, _pendingDragDelta.dy);
      _pendingDragDelta = Offset.zero;
    }

    _isDragging = false;
    _dragStartPosition = null;
    _lastMoveSelectedTime = 0;

    // 🌊 REFLOW: On drag end, do the full solve and bake displacements
    // Skip when fling is starting — reflow will be baked at fling end instead
    if (!skipReflow && isReflowEnabled && reflowGhostDisplacements.isNotEmpty) {
      _calculateSelectionBounds();
      if (_selectionBounds != null) {
        final excludeIds = reflowController!.getClusterIdsForElements(
          selectionManager.selectedIds,
        );
        reflowController!.solveAndBake(
          disturbance: _selectionBounds!,
          excludeIds: excludeIds,
          layerNode: _getActiveLayerNode(),
        );
      }
    }
    if (!skipReflow) {
      reflowController?.clearGhosts();
    }

    // 🚀 Bake localTransform into raw stroke points so re-selection
    // and hit-testing find strokes at their new position.
    // Skip when fling is starting — bake happens at fling end instead.
    if (!skipReflow) {
      selectionManager.bakeStrokeTransforms();
      _getActiveLayerNode().invalidateStrokeCache();
      // 🚀 FIX: Force R-tree rebuild with new bounds (doesn't invalidate tiles)
      DrawingPainter.invalidateRenderIndex();
    }
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
    // Determine which layer to hit-test against
    final hitTestLayer = referenceLayerId != null
        ? _getLayerNodeById(referenceLayerId!)
        : _getActiveLayerNode();
    // Determine which layer to select from
    final selectionLayer = _getActiveLayerNode();
    final lassoBounds = lassoPath.getBounds();
    final hits = <CanvasNode>[];

    for (final child in hitTestLayer.children) {
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
        if (referenceLayerId != null) {
          // Reference layer mode: find corresponding node on active layer
          final activeNode = selectionLayer.findChild(child.id);
          if (activeNode != null) hits.add(activeNode);
        } else {
          hits.add(child);
        }
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
        final excludeIds = reflowController!.getClusterIdsForElements(
          selectionManager.selectedIds,
        );
        reflowController!.computeGhostDisplacements(
          disturbance: _selectionBounds!,
          excludeIds: excludeIds,
        );
      }
    }
  }

  /// 🌊 REFLOW: Public API to bake ghost displacements into actual positions.
  void bakeReflowDisplacements() {
    if (reflowController == null || reflowGhostDisplacements.isEmpty) return;
    _calculateSelectionBounds();
    if (_selectionBounds == null) return;
    final excludeIds = reflowController!.getClusterIdsForElements(
      selectionManager.selectedIds,
    );
    reflowController!.solveAndBake(
      disturbance: _selectionBounds!,
      excludeIds: excludeIds,
      layerNode: _getActiveLayerNode(),
    );
  }

  // ===========================================================================
  // Public API — Delegates
  // ===========================================================================

  // Transforms — StrokeNodes modify actual points (renderer ignores localTransform
  // scale/rotation). Non-stroke nodes use localTransform via SceneGraphRenderer.

  void rotateSelected() {
    _rotateSelectedByAngle(pi / 2);
  }

  void rotateSelectedByAngle(double radians, {Offset? center}) {
    _rotateSelectedByAngle(radians, center: center);
  }

  void _rotateSelectedByAngle(double radians, {Offset? center}) {
    final pivot = center ?? selectionManager.aggregateCenter;
    final cosA = cos(radians);
    final sinA = sin(radians);
    for (final node in selectionManager.selectedNodes) {
      if (node.isLocked) continue;
      if (node is StrokeNode) {
        final rotatedPoints =
            node.stroke.points.map((p) {
              final dx = p.position.dx - pivot.dx;
              final dy = p.position.dy - pivot.dy;
              return p.copyWith(
                position: Offset(
                  pivot.dx + dx * cosA - dy * sinA,
                  pivot.dy + dx * sinA + dy * cosA,
                ),
              );
            }).toList();
        node.stroke = node.stroke.copyWith(points: rotatedPoints);
        node.localTransform = Matrix4.identity();
        node.invalidateTransformCache();
      } else {
        node.rotateAround(radians, pivot);
      }
    }
    _selectionBounds = null;
  }

  void scaleSelected(double factor, {Offset? center}) {
    final anchor = center ?? selectionManager.aggregateCenter;
    for (final node in selectionManager.selectedNodes) {
      if (node.isLocked) continue;
      if (node is StrokeNode) {
        final scaledPoints =
            node.stroke.points.map((p) {
              final dx = anchor.dx + (p.position.dx - anchor.dx) * factor;
              final dy = anchor.dy + (p.position.dy - anchor.dy) * factor;
              return p.copyWith(position: Offset(dx, dy));
            }).toList();
        final scaledWidth = node.stroke.baseWidth * factor;
        node.stroke = node.stroke.copyWith(
          points: scaledPoints,
          baseWidth: scaledWidth.clamp(0.5, 200.0),
        );
        node.localTransform = Matrix4.identity();
        node.invalidateTransformCache();
      } else {
        node.scaleFrom(factor, factor, anchor);
      }
    }
    _selectionBounds = null;
    // 🚀 FIX: Invalidate LayerNode's cached stroke list so it picks up
    // the new ProStroke objects (copyWith creates new instances).
    _getActiveLayerNode().invalidateStrokeCache();
  }

  /// 🚀 Combined rotate + scale in a single pass — avoids double iteration
  /// and double point allocation during pinch-to-transform.
  void rotateAndScaleSelected(double radians, double scaleFactor, {Offset? center}) {
    if (radians.abs() < 0.0001 && (scaleFactor - 1.0).abs() < 0.0001) return;
    final pivot = center ?? selectionManager.aggregateCenter;
    final cosA = cos(radians);
    final sinA = sin(radians);
    for (final node in selectionManager.selectedNodes) {
      if (node.isLocked) continue;
      if (node is StrokeNode) {
        final transformed = node.stroke.points.map((p) {
          // Translate to pivot
          final dx = p.position.dx - pivot.dx;
          final dy = p.position.dy - pivot.dy;
          // Rotate
          final rx = dx * cosA - dy * sinA;
          final ry = dx * sinA + dy * cosA;
          // Scale from pivot
          return p.copyWith(
            position: Offset(pivot.dx + rx * scaleFactor, pivot.dy + ry * scaleFactor),
          );
        }).toList();
        node.stroke = node.stroke.copyWith(
          points: transformed,
          baseWidth: (node.stroke.baseWidth * scaleFactor).clamp(0.5, 200.0),
        );
        node.localTransform = Matrix4.identity();
        node.invalidateTransformCache();
      } else {
        if (radians.abs() > 0.0001) node.rotateAround(radians, pivot);
        if ((scaleFactor - 1.0).abs() > 0.0001) node.scaleFrom(scaleFactor, scaleFactor, pivot);
      }
    }
    _selectionBounds = null;
  }

  void flipHorizontal() {
    final anchor = selectionManager.aggregateCenter;
    for (final node in selectionManager.selectedNodes) {
      if (node.isLocked) continue;
      if (node is StrokeNode) {
        final flippedPoints =
            node.stroke.points.map((p) {
              return p.copyWith(
                position: Offset(
                  anchor.dx - (p.position.dx - anchor.dx),
                  p.position.dy,
                ),
              );
            }).toList();
        node.stroke = node.stroke.copyWith(points: flippedPoints);
        node.localTransform = Matrix4.identity();
        node.invalidateTransformCache();
      } else {
        node.scaleFrom(-1, 1, anchor);
      }
    }
    _selectionBounds = null;
  }

  void flipVertical() {
    final anchor = selectionManager.aggregateCenter;
    for (final node in selectionManager.selectedNodes) {
      if (node.isLocked) continue;
      if (node is StrokeNode) {
        final flippedPoints =
            node.stroke.points.map((p) {
              return p.copyWith(
                position: Offset(
                  p.position.dx,
                  anchor.dy - (p.position.dy - anchor.dy),
                ),
              );
            }).toList();
        node.stroke = node.stroke.copyWith(points: flippedPoints);
        node.localTransform = Matrix4.identity();
        node.invalidateTransformCache();
      } else {
        node.scaleFrom(1, -1, anchor);
      }
    }
    _selectionBounds = null;
  }

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

  // Freeform (non-uniform) Scale
  void freeformScale(double sx, double sy, {Offset? anchor}) =>
      _freeformScale(sx, sy, anchor: anchor);

  // Distort (4-corner perspective deformation)
  void distort(List<Offset> corners) => _distort(corners);


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

  // Ellipse Selection
  void startEllipse(Offset position) => _startEllipse(position);
  void updateEllipse(Offset position) => _updateEllipse(position);
  void completeEllipse() => _completeEllipse();
  Rect? get ellipseRect => _getEllipseRect();

  // Additive Selection (Shift + Lasso)
  bool get additiveMode => _additiveMode;
  set additiveMode(bool value) => _additiveMode = value;
  void completeLassoAdditive() => _completeLassoAdditive();

  // Subtractive Selection (Alt + Lasso)
  bool get subtractiveMode => _subtractiveMode;
  set subtractiveMode(bool value) => _subtractiveMode = value;

  // Inverse Selection
  void invertSelection() => _invertSelection();

  // Color-Based Automatic Selection
  int selectByColor(Offset tapPoint, {double? tolerance, bool additive = false}) =>
      _selectByColor(tapPoint, tolerance: tolerance ?? colorTolerance, additive: additive);

  // Contiguous Flood-Fill Selection (Procreate-style)
  int floodFillSelect(Offset tapPoint, {
    double? tolerance,
    double gapThreshold = 20.0,
    bool additive = false,
  }) => _floodFillSelect(
    tapPoint,
    tolerance: tolerance ?? colorTolerance,
    gapThreshold: gapThreshold,
    additive: additive,
  );

  // Rotation with Snap (15°/45°/90° detents)
  void rotateWithSnap(double radians, {bool snap = true}) =>
      _rotateWithSnap(radians, snap: snap);

  // Edge-Magnetic Movement (snap to canvas edges/center)
  Offset snapMoveToEdges(Offset delta, Rect selectionBounds, Size canvasSize) =>
      _snapToEdges(delta, selectionBounds, canvasSize);

  // Paste in Place (zero offset)
  int pasteInPlace() => _pasteFromClipboard(offset: Offset.zero);

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
    _calculateSelectionBounds();
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

  /// Look up a layer node by its layer ID (used for reference layer hit-testing).
  LayerNode _getLayerNodeById(String layerId) {
    final layer = layerController.layers.firstWhere(
      (l) => l.id == layerId,
      orElse: () => _getActiveLayer(),
    );
    return layer.node;
  }


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
