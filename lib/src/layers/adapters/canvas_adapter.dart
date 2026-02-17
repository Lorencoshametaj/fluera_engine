import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../core/models/digital_text_element.dart';
import '../../core/models/image_element.dart';
import '../nebula_layer_controller.dart';

/// 🔌 Interfaccia adattatore per diversi contesti canvas
///
/// Astrae le operazioni comuni tra:
/// - Canvas infinito (InfiniteCanvasAdapter)
/// - Pagina PDF (PDFPageAdapter)
/// - Multiview sincronizzato (futuro)
///
/// DESIGN PRINCIPLES:
/// - Ogni adapter sa come gestire le coordinate del suo contesto
/// - Ogni adapter sa come persistere i dati nel suo contesto
/// - I tools usano SOLO l'interfaccia, mai le implementazioni concrete
abstract class CanvasAdapter {
  // ============================================================================
  // IDENTITY
  // ============================================================================

  /// Type of contesto (per debug/logging)
  String get contextType;

  /// Bounds of the canvas/pagina (null = canvas infinito)
  Rect? get bounds;

  /// ID univoco del contesto (es: pageIndex per PDF, canvasId per canvas)
  String get contextId;

  // ============================================================================
  // COORDINATE CONVERSION
  // ============================================================================

  /// Converts coordinate screen → canvas
  ///
  /// [screen] - Position in screen coordinates (es: da PointerEvent.localPosition)
  /// [scale] - Scala corrente of the viewport
  /// [viewOffset] - Current viewport offset
  Offset screenToCanvas(Offset screen, double scale, Offset viewOffset);

  /// Converts canvas coordinates → screen
  ///
  /// [canvas] - Position in canvas coordinates
  /// [scale] - Scala corrente of the viewport
  /// [viewOffset] - Current viewport offset
  Offset canvasToScreen(Offset canvas, double scale, Offset viewOffset);

  /// Checks if a position canvas is dentro i bounds
  ///
  /// For canvas infinito, ritorna sempre true.
  /// For PDF, verifica che sia dentro la pagina.
  bool isPointInBounds(Offset canvasPosition);

  // ============================================================================
  // STROKE OPERATIONS
  // ============================================================================

  /// Adds uno stroke al contesto
  void addStroke(NebulaLayerController controller, ProStroke stroke);

  /// Removes uno stroke per ID
  void removeStroke(NebulaLayerController controller, String strokeId);

  /// Gets strokes visibili in un viewport
  ///
  /// Use spatial indexing se disponibile for performance O(log n).
  List<ProStroke> getStrokesInViewport(
    NebulaLayerController controller,
    Rect viewport,
  );

  // ============================================================================
  // SHAPE OPERATIONS
  // ============================================================================

  /// Adds a geometric shape al contesto
  void addShape(NebulaLayerController controller, GeometricShape shape);

  /// Removes una shape per ID
  void removeShape(NebulaLayerController controller, String shapeId);

  /// Gets shapes visibili in un viewport
  List<GeometricShape> getShapesInViewport(
    NebulaLayerController controller,
    Rect viewport,
  );

  // ============================================================================
  // TEXT & IMAGE OPERATIONS
  // ============================================================================

  /// Adds a text element
  void addTextElement(DigitalTextElement element);

  /// Adds an image element
  void addImageElement(ImageElement element);

  // ============================================================================
  // UNDO/REDO & PERSISTENCE
  // ============================================================================

  /// Saves lo current state for ado
  ///
  /// Called BEFORE destructive operations (erase, delete, etc.)
  void saveUndoState();

  /// Notifies che un'operazione is stata completata
  ///
  /// Trigger per auto-save, sync, etc.
  void notifyOperationComplete();

  // ============================================================================
  // OPTIONAL: ADVANCED OPERATIONS
  // ============================================================================

  /// Checks se uno stroke interseca un punto with a raggio
  ///
  /// Utile per eraser tool. Default implementation usa distance check.
  bool strokeIntersectsPoint(ProStroke stroke, Offset point, double radius) {
    for (final p in stroke.points) {
      if ((p.position - point).distance <= radius) {
        return true;
      }
    }
    return false;
  }

  /// Checks if a shape interseca un punto with a raggio
  bool shapeIntersectsPoint(GeometricShape shape, Offset point, double radius) {
    final startDist = (shape.startPoint - point).distance;
    final endDist = (shape.endPoint - point).distance;
    if (startDist <= radius || endDist <= radius) return true;

    final rect = Rect.fromPoints(shape.startPoint, shape.endPoint);
    return rect.inflate(radius).contains(point);
  }
}

/// 📊 Info di debug per adapter
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
