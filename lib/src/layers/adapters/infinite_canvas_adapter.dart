import 'package:flutter/material.dart';
import './canvas_adapter.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../core/models/digital_text_element.dart';
import '../../core/models/image_element.dart';
import '../fluera_layer_controller.dart';

/// 🖼️ Adapter for Infinite Canvas
///
/// Implements CanvasAdapter for the standard infinite canvas.
/// Supports:
/// - Coordinate conversion with scale and offset
/// - Infinite bounds (null)
/// - Spatial indexing for viewport queries
class InfiniteCanvasAdapter extends CanvasAdapter {
  /// Callback called when an operation is completed (trigger auto-save)
  final VoidCallback onOperationComplete;

  /// Callback called when state needs to be saved for undo
  final VoidCallback? onSaveUndo;

  /// Callback for adding text elements (managed separately)
  final void Function(DigitalTextElement)? onAddTextElement;

  /// Callback for getting all text elements
  final List<DigitalTextElement> Function()? onGetTextElements;

  /// Callback for updating a text element
  final void Function(DigitalTextElement)? onUpdateTextElement;

  /// Callback for removing a text element by ID
  final void Function(String)? onRemoveTextElement;

  /// Callback for adding image elements (managed separately)
  final void Function(ImageElement)? onAddImageElement;

  /// Callback for getting all image elements
  final List<ImageElement> Function()? onGetImageElements;

  /// Callback for updating an image element
  final void Function(ImageElement)? onUpdateImageElement;

  /// Callback for removing an image element by ID
  final void Function(String)? onRemoveImageElement;

  /// ID of the canvas
  final String canvasId;

  InfiniteCanvasAdapter({
    required this.canvasId,
    required this.onOperationComplete,
    this.onSaveUndo,
    this.onAddTextElement,
    this.onGetTextElements,
    this.onUpdateTextElement,
    this.onRemoveTextElement,
    this.onAddImageElement,
    this.onGetImageElements,
    this.onUpdateImageElement,
    this.onRemoveImageElement,
  });

  // ============================================================================
  // IDENTITY
  // ============================================================================

  @override
  String get contextType => 'infinite_canvas';

  @override
  String get contextId => canvasId;

  @override
  Rect? get bounds => null; // Infinite canvas

  // ============================================================================
  // COORDINATE CONVERSION
  // ============================================================================

  @override
  Offset screenToCanvas(Offset screen, double scale, Offset viewOffset) {
    // Formula: canvasPos = (screenPos - viewOffset) / scale
    return (screen - viewOffset) / scale;
  }

  @override
  Offset canvasToScreen(Offset canvas, double scale, Offset viewOffset) {
    // Formula: screenPos = canvasPos * scale + viewOffset
    return canvas * scale + viewOffset;
  }

  @override
  bool isPointInBounds(Offset canvasPosition) {
    // Infinite canvas: everything is in bounds
    return true;
  }

  // ============================================================================
  // STROKE OPERATIONS
  // ============================================================================

  @override
  void addStroke(FlueraLayerController controller, ProStroke stroke) {
    controller.addStroke(stroke);
  }

  @override
  void removeStroke(FlueraLayerController controller, String strokeId) {
    final layer = controller.activeLayer;
    if (layer == null) return;

    final index = layer.strokes.indexWhere((s) => s.id == strokeId);
    if (index != -1) {
      controller.removeStrokeAt(index);
    }
  }

  @override
  List<ProStroke> getStrokesInViewport(
    FlueraLayerController controller,
    Rect viewport,
  ) {
    // Use spatial index when available for O(log n) performance
    if (controller.spatialIndex.isBuilt) {
      return controller.spatialIndex.queryVisibleStrokes(viewport);
    }

    // Fallback: filter all visible strokes
    final visibleStrokes = <ProStroke>[];
    for (final stroke in controller.getAllVisibleStrokes()) {
      if (stroke.bounds.overlaps(viewport)) {
        visibleStrokes.add(stroke);
      }
    }
    return visibleStrokes;
  }

  // ============================================================================
  // SHAPE OPERATIONS
  // ============================================================================

  @override
  void addShape(FlueraLayerController controller, GeometricShape shape) {
    controller.addShape(shape);
  }

  @override
  void removeShape(FlueraLayerController controller, String shapeId) {
    final layer = controller.activeLayer;
    if (layer == null) return;

    final index = layer.shapes.indexWhere((s) => s.id == shapeId);
    if (index != -1) {
      controller.removeShapeAt(index);
    }
  }

  @override
  List<GeometricShape> getShapesInViewport(
    FlueraLayerController controller,
    Rect viewport,
  ) {
    // Use spatial index when available
    if (controller.spatialIndex.isBuilt) {
      return controller.spatialIndex.queryVisibleShapes(viewport);
    }

    // Fallback: filter all visible shapes
    final visibleShapes = <GeometricShape>[];
    for (final shape in controller.getAllVisibleShapes()) {
      final shapeBounds = Rect.fromPoints(shape.startPoint, shape.endPoint);
      if (shapeBounds.overlaps(viewport)) {
        visibleShapes.add(shape);
      }
    }
    return visibleShapes;
  }

  // ============================================================================
  // TEXT & IMAGE OPERATIONS
  // ============================================================================

  @override
  void addTextElement(DigitalTextElement element) {
    onAddTextElement?.call(element);
  }

  @override
  List<DigitalTextElement> getTextElements() {
    return onGetTextElements?.call() ?? [];
  }

  @override
  void updateTextElement(DigitalTextElement element) {
    onUpdateTextElement?.call(element);
  }

  @override
  void removeTextElement(String elementId) {
    onRemoveTextElement?.call(elementId);
  }

  @override
  void addImageElement(ImageElement element) {
    onAddImageElement?.call(element);
  }

  @override
  List<ImageElement> getImageElements() {
    return onGetImageElements?.call() ?? [];
  }

  @override
  void updateImageElement(ImageElement element) {
    onUpdateImageElement?.call(element);
  }

  @override
  void removeImageElement(String elementId) {
    onRemoveImageElement?.call(elementId);
  }

  // ============================================================================
  // UNDO/REDO & PERSISTENCE
  // ============================================================================

  @override
  void saveUndoState() {
    onSaveUndo?.call();
  }

  @override
  void notifyOperationComplete() {
    onOperationComplete();
  }

  // ============================================================================
  // DEBUG
  // ============================================================================

  AdapterDebugInfo getDebugInfo(FlueraLayerController controller) {
    return AdapterDebugInfo(
      contextType: contextType,
      contextId: contextId,
      bounds: bounds,
      strokeCount: controller.getAllVisibleStrokes().length,
      shapeCount: controller.getAllVisibleShapes().length,
    );
  }
}
