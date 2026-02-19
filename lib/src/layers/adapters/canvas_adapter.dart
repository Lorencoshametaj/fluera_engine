import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../core/models/digital_text_element.dart';
import '../../core/models/image_element.dart';
import '../nebula_layer_controller.dart';

/// 🔌 Adapter interface for different canvas contexts
///
/// Abstracts common operations between:
/// - Infinite canvas (InfiniteCanvasAdapter)
/// - Synchronized multiview (future)
///
/// DESIGN PRINCIPLES:
/// - Each adapter knows how to handle coordinates of its context
/// - Each adapter knows how to persist data in its context
/// - Tools use ONLY the interface, never concrete implementations
abstract class CanvasAdapter {
  // ============================================================================
  // IDENTITY
  // ============================================================================

  /// Type of context (for debug/logging)
  String get contextType;

  /// Bounds of the canvas/page (null = infinite canvas)
  Rect? get bounds;

  /// Unique ID of the context (e.g.: canvasId for canvas)
  String get contextId;

  // ============================================================================
  // COORDINATE CONVERSION
  // ============================================================================

  /// Converts coordinate screen → canvas
  ///
  /// [screen] - Position in screen coordinates (e.g.: from PointerEvent.localPosition)
  /// [scale] - Current viewport scale
  /// [viewOffset] - Current viewport offset
  Offset screenToCanvas(Offset screen, double scale, Offset viewOffset);

  /// Converts canvas coordinates → screen
  ///
  /// [canvas] - Position in canvas coordinates
  /// [scale] - Current viewport scale
  /// [viewOffset] - Current viewport offset
  Offset canvasToScreen(Offset canvas, double scale, Offset viewOffset);

  /// Checks if a canvas position is within bounds
  ///
  /// For infinite canvas, always returns true.
  /// For bounded contexts, verifies that it is within the bounds.
  bool isPointInBounds(Offset canvasPosition);

  // ============================================================================
  // STROKE OPERATIONS
  // ============================================================================

  /// Adds a stroke to context
  void addStroke(NebulaLayerController controller, ProStroke stroke);

  /// Removes a stroke by ID
  void removeStroke(NebulaLayerController controller, String strokeId);

  /// Gets strokes visible in a viewport
  ///
  /// Uses spatial indexing when available for O(log n) performance.
  List<ProStroke> getStrokesInViewport(
    NebulaLayerController controller,
    Rect viewport,
  );

  // ============================================================================
  // SHAPE OPERATIONS
  // ============================================================================

  /// Adds a geometric shape to context
  void addShape(NebulaLayerController controller, GeometricShape shape);

  /// Removes a shape by ID
  void removeShape(NebulaLayerController controller, String shapeId);

  /// Gets shapes visible in a viewport
  List<GeometricShape> getShapesInViewport(
    NebulaLayerController controller,
    Rect viewport,
  );

  // ============================================================================
  // TEXT & IMAGE OPERATIONS
  // ============================================================================

  /// Adds a text element
  void addTextElement(DigitalTextElement element);

  /// Gets all text elements in the current context
  List<DigitalTextElement> getTextElements();

  /// Updates a text element (matched by ID)
  void updateTextElement(DigitalTextElement element);

  /// Removes a text element by ID
  void removeTextElement(String elementId);

  /// Adds an image element
  void addImageElement(ImageElement element);

  /// Gets all image elements in the current context
  List<ImageElement> getImageElements();

  /// Updates an image element (matched by ID)
  void updateImageElement(ImageElement element);

  /// Removes an image element by ID
  void removeImageElement(String elementId);

  // ============================================================================
  // UNDO/REDO & PERSISTENCE
  // ============================================================================

  /// Saves the current state for undo
  ///
  /// Called BEFORE destructive operations (erase, delete, etc.)
  void saveUndoState();

  /// Notifies that an operation has been completed
  ///
  /// Trigger for auto-save, sync, etc.
  void notifyOperationComplete();

  // ============================================================================
  // OPTIONAL: ADVANCED OPERATIONS
  // ============================================================================

  /// Checks if a stroke intersects a point within a radius
  ///
  /// Useful for eraser tool. Default implementation uses distance check.
  bool strokeIntersectsPoint(ProStroke stroke, Offset point, double radius) {
    for (final p in stroke.points) {
      if ((p.position - point).distance <= radius) {
        return true;
      }
    }
    return false;
  }

  /// Checks if a shape intersects a point within a radius
  bool shapeIntersectsPoint(GeometricShape shape, Offset point, double radius) {
    final startDist = (shape.startPoint - point).distance;
    final endDist = (shape.endPoint - point).distance;
    if (startDist <= radius || endDist <= radius) return true;

    final rect = Rect.fromPoints(shape.startPoint, shape.endPoint);
    return rect.inflate(radius).contains(point);
  }
}

/// 📊 Debug info for adapter
class AdapterDebugInfo {
  final String contextType;
  final String contextId;
  final Rect? bounds;
  final int strokeCount;
  final int shapeCount;

  const AdapterDebugInfo({
    required this.contextType,
    required this.contextId,
    this.bounds,
    this.strokeCount = 0,
    this.shapeCount = 0,
  });

  @override
  String toString() {
    return 'Adapter[$contextType:$contextId] '
        'bounds=$bounds strokes=$strokeCount shapes=$shapeCount';
  }
}
