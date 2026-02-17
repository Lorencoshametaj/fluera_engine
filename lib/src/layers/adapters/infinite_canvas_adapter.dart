import 'package:flutter/material.dart';
import './canvas_adapter.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../core/models/digital_text_element.dart';
import '../../core/models/image_element.dart';
import '../nebula_layer_controller.dart';

/// 🖼️ Adapter per Canvas Infinito
///
/// Implementa CanvasAdapter for the canvas infinito standard.
/// Supporta:
/// - Coordinate conversion with scale and offset
/// - Bounds infiniti (null)
/// - Spatial indexing for viewport query
class InfiniteCanvasAdapter extends CanvasAdapter {
  /// Callback called when a'operazione is completata (trigger auto-save)
  final VoidCallback onOperationComplete;

  /// Callback called when state needs to be saved for ado
  final VoidCallback? onSaveUndo;

  /// Callback for adding text elements (managed separately)
  final void Function(DigitalTextElement)? onAddTextElement;

  /// Callback for adding image elements (managed separately)
  final void Function(ImageElement)? onAddImageElement;

  /// ID of the canvas
  final String canvasId;

  InfiniteCanvasAdapter({
    required this.canvasId,
    required this.onOperationComplete,
    this.onSaveUndo,
    this.onAddTextElement,
    this.onAddImageElement,
  });

  // ============================================================================
  // IDENTITY
  // ============================================================================

  @override
  String get contextType => 'infinite_canvas';

  @override
  String get contextId => canvasId;

  @override
  Rect? get bounds => null; // Canvas infinito

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
  void addStroke(NebulaLayerController controller, ProStroke stroke) {
    controller.addStroke(stroke);
  }

  @override
  void removeStroke(NebulaLayerController controller, String strokeId) {
    final layer = controller.activeLayer;
    if (layer == null) return;

    final index = layer.strokes.indexWhere((s) => s.id == strokeId);
    if (index != -1) {
      controller.removeStrokeAt(index);
    }
  }

  @override
  List<ProStroke> getStrokesInViewport(
    NebulaLayerController controller,
    Rect viewport,
  ) {
    // Use spatial index se disponibile for performance O(log n)
    if (controller.spatialIndex.isBuilt) {
      return controller.spatialIndex.queryVisibleStrokes(viewport);
    }

    // Fallback: filtra tutti gli strokes visibili
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
  void addShape(NebulaLayerController controller, GeometricShape shape) {
    controller.addShape(shape);
  }

  @override
  void removeShape(NebulaLayerController controller, String shapeId) {
    final layer = controller.activeLayer;
    if (layer == null) return;

    final index = layer.shapes.indexWhere((s) => s.id == shapeId);
    if (index != -1) {
      controller.removeShapeAt(index);
    }
  }

  @override
  List<GeometricShape> getShapesInViewport(
    NebulaLayerController controller,
    Rect viewport,
  ) {
    // Use spatial index se disponibile
    if (controller.spatialIndex.isBuilt) {
      return controller.spatialIndex.queryVisibleShapes(viewport);
    }

    // Fallback: filtra tutte le shapes visibili
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
  void addImageElement(ImageElement element) {
    onAddImageElement?.call(element);
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

  AdapterDebugInfo getDebugInfo(NebulaLayerController controller) {
    return AdapterDebugInfo(
      contextType: contextType,
      contextId: contextId,
      bounds: bounds,
      strokeCount: controller.getAllVisibleStrokes().length,
      shapeCount: controller.getAllVisibleShapes().length,
    );
  }
}
