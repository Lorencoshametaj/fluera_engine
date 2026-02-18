import 'dart:math';
import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../core/models/canvas_layer.dart';
import '../../core/models/digital_text_element.dart';
import '../../core/models/image_element.dart';
import '../../layers/nebula_layer_controller.dart';
import '../../reflow/content_cluster.dart';
import '../../reflow/reflow_physics_engine.dart';

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

/// 🎨 LASSO TOOL — Professional selection tool
///
/// Features:
/// - Freehand lasso selection
/// - All element types: strokes, shapes, text, images
/// - Bounding-box pre-filter for fast hit-testing
/// - Move, delete, copy, duplicate, rotate, scale, flip
/// - Alignment, distribution, z-ordering, grouping
/// - Lock, opacity, color, snap-to-grid, undo
/// - Multi-layer + export selection
class LassoTool {
  final NebulaLayerController layerController;

  // Lasso path being drawn
  List<Offset> lassoPath = [];

  /// 🚀 PERF: Notifier that fires when lassoPath changes.
  /// Listeners repaint only the lasso overlay — no full setState rebuild.
  final ValueNotifier<int> lassoPathNotifier = ValueNotifier<int>(0);

  // Selected element IDs by type
  final Set<String> selectedStrokeIds = {};
  final Set<String> selectedShapeIds = {};
  final Set<String> selectedTextIds = {};
  final Set<String> selectedImageIds = {};

  // Drag state
  bool _isDragging = false;
  Offset? _dragStartPosition;
  Rect? _selectionBounds;

  // Clipboard for copy/paste
  List<ProStroke> _clipboardStrokes = [];
  List<GeometricShape> _clipboardShapes = [];
  List<DigitalTextElement> _clipboardTexts = [];
  List<ImageElement> _clipboardImages = [];

  // Group tracking (in-session, lightweight)
  final Map<String, Set<String>> _groups = {};

  // Snap-to-grid configuration
  bool snapEnabled = false;
  double gridSpacing = _kDefaultGridSpacing;

  // Undo snapshot (last layer state before a transform batch)
  CanvasLayer? _undoSnapshot;

  // Locked element IDs (cannot be moved/transformed while locked)
  final Set<String> _lockedIds = {};

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

  LassoTool({required this.layerController});

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

  bool get hasSelection =>
      selectedStrokeIds.isNotEmpty ||
      selectedShapeIds.isNotEmpty ||
      selectedTextIds.isNotEmpty ||
      selectedImageIds.isNotEmpty;

  int get selectionCount =>
      selectedStrokeIds.length +
      selectedShapeIds.length +
      selectedTextIds.length +
      selectedImageIds.length;

  bool get hasClipboard =>
      _clipboardStrokes.isNotEmpty ||
      _clipboardShapes.isNotEmpty ||
      _clipboardTexts.isNotEmpty ||
      _clipboardImages.isNotEmpty;

  bool get isDragging => _isDragging;

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
    // Save undo snapshot before any drag transformation
    saveUndoSnapshot();
  }

  void updateDrag(Offset currentPosition) {
    if (!_isDragging || _dragStartPosition == null) return;
    var delta = currentPosition - _dragStartPosition!;
    // Apply snap-to-grid if enabled
    if (snapEnabled) delta = snapDelta(delta);
    moveSelected(delta);
    _dragStartPosition = currentPosition;
    if (_selectionBounds != null) {
      _selectionBounds = _selectionBounds!.shift(delta);
    }
  }

  void compensateScroll(Offset scrollDelta) {
    if (!_isDragging || _dragStartPosition == null) return;
    moveSelected(scrollDelta);
    _dragStartPosition = _dragStartPosition! + scrollDelta;
    if (_selectionBounds != null) {
      _selectionBounds = _selectionBounds!.shift(scrollDelta);
    }
  }

  void endDrag() {
    // Set dragging false FIRST so _onLayerChanged can rebuild cluster cache
    _isDragging = false;
    _dragStartPosition = null;

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
    // In additive mode, delegate to the additive completion
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

    // Select from active layer or all layers based on mode
    if (multiLayerMode) {
      selectFromAllLayers(path);
    } else {
      _selectElementsInPath(path);
    }

    if (!hasSelection) {
      lassoPath.clear();
      return;
    }

    // If any selected element belongs to a group, select the whole group
    expandSelectionToGroups();
    _calculateSelectionBounds();
    lassoPath.clear();
  }

  // ===========================================================================
  // Hit-Testing — With Bounding-Box Pre-Filter
  // ===========================================================================

  void _selectElementsInPath(Path lassoPath) {
    final activeLayer = _getActiveLayer();
    final lassoBounds = lassoPath.getBounds();

    // Strokes — bounding-box pre-filter + point-in-path test
    for (final stroke in activeLayer.strokes) {
      if (!stroke.bounds.overlaps(lassoBounds)) continue;
      if (_strokeIntersectsPath(stroke, lassoPath)) {
        selectedStrokeIds.add(stroke.id);
      }
    }

    // Shapes — bounding-box pre-filter + multi-point test
    for (final shape in activeLayer.shapes) {
      final shapeBounds = Rect.fromPoints(shape.startPoint, shape.endPoint);
      if (!shapeBounds.overlaps(lassoBounds)) continue;
      if (_shapeIntersectsPath(shape, lassoPath)) {
        selectedShapeIds.add(shape.id);
      }
    }

    // Text elements
    for (final text in activeLayer.texts) {
      final textBounds = _estimateTextBounds(text);
      if (!textBounds.overlaps(lassoBounds)) continue;
      if (_textIntersectsPath(text, lassoPath)) {
        selectedTextIds.add(text.id);
      }
    }

    // Image elements
    for (final image in activeLayer.images) {
      final imageBounds = _estimateImageBounds(image);
      if (!imageBounds.overlaps(lassoBounds)) continue;
      if (_imageIntersectsPath(image, lassoPath)) {
        selectedImageIds.add(image.id);
      }
    }
  }

  bool _strokeIntersectsPath(ProStroke stroke, Path lassoPath) {
    for (final point in stroke.points) {
      if (lassoPath.contains(point.position)) return true;
    }
    return false;
  }

  /// Tests all 4 corners, edge midpoints, and center (9-point check).
  bool _shapeIntersectsPath(GeometricShape shape, Path lassoPath) {
    final rect = Rect.fromPoints(shape.startPoint, shape.endPoint);
    if (lassoPath.contains(rect.topLeft)) return true;
    if (lassoPath.contains(rect.topRight)) return true;
    if (lassoPath.contains(rect.bottomLeft)) return true;
    if (lassoPath.contains(rect.bottomRight)) return true;
    if (lassoPath.contains(rect.topCenter)) return true;
    if (lassoPath.contains(rect.bottomCenter)) return true;
    if (lassoPath.contains(rect.centerLeft)) return true;
    if (lassoPath.contains(rect.centerRight)) return true;
    if (lassoPath.contains(rect.center)) return true;
    return false;
  }

  bool _textIntersectsPath(DigitalTextElement text, Path lassoPath) {
    final bounds = _estimateTextBounds(text);
    if (lassoPath.contains(bounds.topLeft)) return true;
    if (lassoPath.contains(bounds.topRight)) return true;
    if (lassoPath.contains(bounds.bottomLeft)) return true;
    if (lassoPath.contains(bounds.bottomRight)) return true;
    if (lassoPath.contains(bounds.center)) return true;
    return false;
  }

  bool _imageIntersectsPath(ImageElement image, Path lassoPath) {
    final bounds = _estimateImageBounds(image);
    if (lassoPath.contains(bounds.topLeft)) return true;
    if (lassoPath.contains(bounds.topRight)) return true;
    if (lassoPath.contains(bounds.bottomLeft)) return true;
    if (lassoPath.contains(bounds.bottomRight)) return true;
    if (lassoPath.contains(bounds.center)) return true;
    return false;
  }

  // ===========================================================================
  // Element Operations — Delete & Move
  // ===========================================================================

  void deleteSelected() {
    if (!hasSelection) return;
    final activeLayer = _getActiveLayer();
    final updatedLayer = activeLayer.copyWith(
      strokes:
          activeLayer.strokes
              .where((s) => !selectedStrokeIds.contains(s.id))
              .toList(),
      shapes:
          activeLayer.shapes
              .where((s) => !selectedShapeIds.contains(s.id))
              .toList(),
      texts:
          activeLayer.texts
              .where((t) => !selectedTextIds.contains(t.id))
              .toList(),
      images:
          activeLayer.images
              .where((i) => !selectedImageIds.contains(i.id))
              .toList(),
    );
    _updateLayer(updatedLayer);
    clearSelection();
  }

  void moveSelected(Offset delta) {
    if (!hasSelection) return;
    if (isSelectionLocked) return; // Lock guard
    final activeLayer = _getActiveLayer();

    final movedStrokes =
        activeLayer.strokes.map((stroke) {
          if (selectedStrokeIds.contains(stroke.id)) {
            return stroke.copyWith(
              points:
                  stroke.points
                      .map((p) => p.copyWith(position: p.position + delta))
                      .toList(),
            );
          }
          return stroke;
        }).toList();

    final movedShapes =
        activeLayer.shapes.map((shape) {
          if (selectedShapeIds.contains(shape.id)) {
            return shape.copyWith(
              startPoint: shape.startPoint + delta,
              endPoint: shape.endPoint + delta,
            );
          }
          return shape;
        }).toList();

    final movedTexts =
        activeLayer.texts.map((text) {
          if (selectedTextIds.contains(text.id)) {
            return text.copyWith(position: text.position + delta);
          }
          return text;
        }).toList();

    final movedImages =
        activeLayer.images.map((image) {
          if (selectedImageIds.contains(image.id)) {
            return image.copyWith(position: image.position + delta);
          }
          return image;
        }).toList();

    _updateLayer(
      activeLayer.copyWith(
        strokes: movedStrokes,
        shapes: movedShapes,
        texts: movedTexts,
        images: movedImages,
      ),
    );

    // 🌊 REFLOW: Estimate ghost displacements for surrounding content
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
    final ids = <String>{};
    final allSelectedIds = {
      ...selectedStrokeIds,
      ...selectedShapeIds,
      ...selectedTextIds,
      ...selectedImageIds,
    };
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

  /// 🌊 REFLOW: Bake ghost displacements into actual element positions.
  /// Called once on drag end for atomic undo.
  void _bakeReflowDisplacements() {
    if (reflowGhostDisplacements.isEmpty) return;

    // Full solve (iterative collision resolution)
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

    // Apply displacements to actual element positions
    final activeLayer = _getActiveLayer();

    final updatedStrokes =
        activeLayer.strokes.map((stroke) {
          final disp = affectedElementIds[stroke.id];
          if (disp == null) return stroke;
          return stroke.copyWith(
            points:
                stroke.points
                    .map((p) => p.copyWith(position: p.position + disp))
                    .toList(),
          );
        }).toList();

    final updatedShapes =
        activeLayer.shapes.map((shape) {
          final disp = affectedElementIds[shape.id];
          if (disp == null) return shape;
          return shape.copyWith(
            startPoint: shape.startPoint + disp,
            endPoint: shape.endPoint + disp,
          );
        }).toList();

    final updatedTexts =
        activeLayer.texts.map((text) {
          final disp = affectedElementIds[text.id];
          if (disp == null) return text;
          return text.copyWith(position: text.position + disp);
        }).toList();

    final updatedImages =
        activeLayer.images.map((image) {
          final disp = affectedElementIds[image.id];
          if (disp == null) return image;
          return image.copyWith(position: image.position + disp);
        }).toList();

    _updateLayer(
      activeLayer.copyWith(
        strokes: updatedStrokes,
        shapes: updatedShapes,
        texts: updatedTexts,
        images: updatedImages,
      ),
    );
  }

  // ===========================================================================
  // Public API — Delegates to Part Files
  // ===========================================================================

  // Transforms
  void rotateSelected() => _rotateSelected90();
  void rotateSelectedByAngle(double radians, {Offset? center}) =>
      _rotateSelectedByAngle(radians, center: center);
  void scaleSelected(double factor, {Offset? center}) =>
      _scaleSelected(factor, center: center);
  void flipHorizontal() => _flipHorizontal();
  void flipVertical() => _flipVertical();

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
  void expandSelectionToGroups() => _expandSelectionToGroups();
  bool get hasGroups => _groups.isNotEmpty;
  int get groupCount => _groups.length;

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
  void alignLeft() => _alignLeft();
  void alignRight() => _alignRight();
  void alignCenterH() => _alignCenterH();
  void alignTop() => _alignTop();
  void alignBottom() => _alignBottom();
  void alignCenterV() => _alignCenterV();
  void distributeHorizontal() => _distributeHorizontal();
  void distributeVertical() => _distributeVertical();

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
      _scaleProportional(factor, center: center);

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
    selectedStrokeIds.clear();
    selectedShapeIds.clear();
    selectedTextIds.clear();
    selectedImageIds.clear();
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

  List<ProStroke> getSelectedStrokes() {
    if (selectedStrokeIds.isEmpty) return [];
    return _getActiveLayer().strokes
        .where((s) => selectedStrokeIds.contains(s.id))
        .toList();
  }

  List<GeometricShape> getSelectedShapes() {
    if (selectedShapeIds.isEmpty) return [];
    return _getActiveLayer().shapes
        .where((s) => selectedShapeIds.contains(s.id))
        .toList();
  }

  List<DigitalTextElement> getSelectedTexts() {
    if (selectedTextIds.isEmpty) return [];
    return _getActiveLayer().texts
        .where((t) => selectedTextIds.contains(t.id))
        .toList();
  }

  List<ImageElement> getSelectedImages() {
    if (selectedImageIds.isEmpty) return [];
    return _getActiveLayer().images
        .where((i) => selectedImageIds.contains(i.id))
        .toList();
  }

  // ===========================================================================
  // Private Helpers
  // ===========================================================================

  CanvasLayer _getActiveLayer() {
    return layerController.layers.firstWhere(
      (layer) => layer.id == layerController.activeLayerId,
      orElse: () => layerController.layers.first,
    );
  }

  void _updateLayer(CanvasLayer updatedLayer) {
    layerController.updateLayer(updatedLayer);
  }

  void _calculateSelectionBounds() {
    if (!hasSelection) {
      _selectionBounds = null;
      return;
    }

    final activeLayer = _getActiveLayer();
    Rect? bounds;

    for (final stroke in activeLayer.strokes) {
      if (selectedStrokeIds.contains(stroke.id)) {
        bounds = bounds?.expandToInclude(stroke.bounds) ?? stroke.bounds;
      }
    }
    for (final shape in activeLayer.shapes) {
      if (selectedShapeIds.contains(shape.id)) {
        final r = Rect.fromPoints(shape.startPoint, shape.endPoint);
        bounds = bounds?.expandToInclude(r) ?? r;
      }
    }
    for (final text in activeLayer.texts) {
      if (selectedTextIds.contains(text.id)) {
        final r = _estimateTextBounds(text);
        bounds = bounds?.expandToInclude(r) ?? r;
      }
    }
    for (final image in activeLayer.images) {
      if (selectedImageIds.contains(image.id)) {
        final r = _estimateImageBounds(image);
        bounds = bounds?.expandToInclude(r) ?? r;
      }
    }

    if (bounds != null) {
      _selectionBounds = bounds.inflate(_kSelectionBoundsPadding);
    }
  }

  Rect _estimateTextBounds(DigitalTextElement text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text.text,
        style: TextStyle(
          fontSize: text.fontSize * text.scale,
          fontWeight: text.fontWeight,
          fontFamily: text.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    return Rect.fromLTWH(
      text.position.dx,
      text.position.dy,
      max(tp.width, _kDefaultTextWidth),
      max(tp.height, _kDefaultTextHeight),
    );
  }

  Rect _estimateImageBounds(ImageElement image) {
    final size = _kDefaultImageSize * image.scale;
    return Rect.fromLTWH(image.position.dx, image.position.dy, size, size);
  }
}
