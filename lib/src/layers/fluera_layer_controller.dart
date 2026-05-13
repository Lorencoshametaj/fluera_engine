import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../core/models/canvas_layer.dart';
import '../core/scene_graph/canvas_node.dart';
import '../drawing/models/pro_drawing_point.dart';
import '../core/models/shape_type.dart';
import '../core/models/digital_text_element.dart';
import '../core/models/image_element.dart';
import '../core/editing/adjustment_layer.dart';
import '../rendering/optimization/spatial_index.dart';
import '../core/scene_graph/scene_graph.dart';

/// 🏗️ Abstract interface for layer management in the Fluera Engine SDK.
///
/// The SDK never depends on concrete layer implementations.
/// The app provides a concrete implementation (e.g., with Firebase sync,
/// undo/redo, delta tracking) that implements this interface.
///
/// ```dart
/// class MyLayerController extends FlueraLayerController {
///   // ... concrete implementation with Firebase, undo/redo, etc.
/// }
/// ```
abstract class FlueraLayerController extends ChangeNotifier {
  // ============================================================================
  // LAYER STATE
  // ============================================================================

  /// All layers in the canvas
  List<CanvasLayer> get layers;

  /// Currently active layer (where strokes/shapes are added)
  CanvasLayer? get activeLayer;

  /// ID of the currently active layer
  String? get activeLayerId;

  /// Spatial index for fast hit-testing
  SpatialIndexManager get spatialIndex;

  /// Scene graph for hierarchical rendering
  SceneGraph get sceneGraph;

  // ============================================================================
  // LAYER MANAGEMENT
  // ============================================================================

  /// Append a new layer.
  ///
  /// [name] sets the display label (auto-generated when null). [id] forces a
  /// specific identifier — used by the CRDT applier to mirror a remote
  /// peer's layer using the same id; left null in normal local usage.
  void addLayer({String? name, String? id});

  /// Remove a layer by ID
  void removeLayer(String layerId);

  /// Select a layer as active
  void selectLayer(String layerId);

  /// Rename a layer
  void renameLayer(String layerId, String newName);

  /// Toggle layer visibility
  void toggleLayerVisibility(String layerId);

  /// Toggle layer lock
  void toggleLayerLock(String layerId);

  /// Set layer opacity
  void setLayerOpacity(String layerId, double opacity);

  /// Set layer blend mode
  void setLayerBlendMode(String layerId, ui.BlendMode blendMode);

  /// Move layer up in the stack
  void moveLayerUp(String layerId);

  /// Move layer down in the stack
  void moveLayerDown(String layerId);

  /// Update a layer's data
  void updateLayer(CanvasLayer updatedLayer);

  /// Clear all layers and load new ones
  void clearAllAndLoadLayers(List<CanvasLayer> newLayers);

  /// Duplicate a layer by ID, inserting the copy directly above the original
  void duplicateLayer(String layerId);

  // ============================================================================
  // STROKE OPERATIONS
  // ============================================================================

  /// Add a stroke to the active layer
  void addStroke(ProStroke stroke);

  /// Add multiple strokes in batch
  void addStrokesBatch(List<ProStroke> strokes);

  /// Remove a stroke by index from the active layer
  void removeStrokeAt(int index);

  /// Remove a stroke by ID (searches all layers)
  void removeStroke(String strokeId);

  /// Get all visible strokes across all visible layers
  List<ProStroke> getAllVisibleStrokes();

  /// Delete N scene-graph nodes as a single atomic undoable operation.
  ///
  /// Returns the number of nodes actually removed. Implementations should
  /// route each node to the appropriate typed removal (`removeStroke`,
  /// `removeShape`, `removeText`, `removeImage`) and aggregate the
  /// resulting deltas into one composite undo entry so the user gets a
  /// single Ctrl+Z to revert a bulk selection delete.
  ///
  /// Default implementation forwards to per-element removal without
  /// batching — concrete controllers (e.g. `LayerController`) override
  /// this to provide the composite-undo guarantee.
  Future<int> deleteNodes(List<CanvasNode> nodes) async => 0;

  // ============================================================================
  // SHAPE OPERATIONS
  // ============================================================================

  /// Add a shape to the active layer
  void addShape(GeometricShape shape);

  /// Remove a shape by index from the active layer
  void removeShapeAt(int index);

  /// Remove a shape by ID (searches all layers)
  void removeShape(String shapeId);

  /// Get all visible shapes across all visible layers
  List<GeometricShape> getAllVisibleShapes();

  // ============================================================================
  // TEXT OPERATIONS
  // ============================================================================

  /// Add text element to the active layer
  void addText(DigitalTextElement text);

  /// Remove text by ID
  void removeText(String textId);

  /// Update text element
  void updateText(DigitalTextElement updatedText);

  // ============================================================================
  // IMAGE OPERATIONS
  // ============================================================================

  /// Add image to the active layer
  void addImage(ImageElement image);

  /// Remove image by ID
  void removeImage(String imageId);

  // ============================================================================
  // ADJUSTMENT LAYER OPERATIONS
  // ============================================================================

  /// Add an adjustment layer to the active layer.
  void addAdjustmentLayer(String id, AdjustmentStack stack);

  /// Remove an adjustment layer by ID.
  void removeAdjustmentLayer(String adjustmentId);

  /// Update an existing adjustment layer's stack.
  void updateAdjustmentLayer(String adjustmentId, AdjustmentStack newStack);

  // ============================================================================
  // UNDO/REDO
  // ============================================================================

  /// Undo the last element on the active layer
  void undoLastElement();

  /// Clear all elements from the active layer
  void clearActiveLayer() {
    // Default no-op — concrete implementations override
  }

  // ============================================================================
  // BATCH MODE
  // ============================================================================

  /// Begin a batch of mutations (defers version bumps until [endBatch]).
  void beginBatch() {}

  /// End a batch and flush deferred operations.
  void endBatch() {}

  /// Index of the currently active layer (-1 if none)
  int get activeLayerIndex => -1;

  /// Dispose resources
  @override
  void dispose();
}
