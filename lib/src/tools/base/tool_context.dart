import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../core/models/shape_type.dart';
import '../../core/models/digital_text_element.dart';
import '../../core/models/image_element.dart';
import '../../layers/fluera_layer_controller.dart';
import '../../layers/adapters/canvas_adapter.dart';
import '../unified_tool_controller.dart';

/// 🎯 Context provided to all tools
///
/// Abstracts the differences between Infinite Canvas and Multiview.
/// The tool doesn't know which context it's operating in - it only uses this context.
///
/// DESIGN PRINCIPLES:
/// - Immutable (const constructor)
/// - Provides ALL necessary information to the tool
/// - Delegates operations to the adapter for context-specific logic
class ToolContext {
  /// Context-specific adapter (Canvas, etc.)
  final CanvasAdapter adapter;

  /// Layer controller for managing strokes, shapes, etc.
  final FlueraLayerController layerController;

  /// Current viewport scale (1.0 = 100%)
  final double scale;

  /// Viewport offset (top-left position of the visible canvas)
  final Offset viewOffset;

  /// Visible area dimensions (screen coordinates)
  final Size viewportSize;

  /// Current brush settings
  final ToolSettings settings;

  const ToolContext({
    required this.adapter,
    required this.layerController,
    required this.scale,
    required this.viewOffset,
    required this.viewportSize,
    required this.settings,
  });

  // ============================================================================
  // COORDINATE CONVERSION
  // ============================================================================

  /// Converts screen position → canvas
  Offset screenToCanvas(Offset screenPosition) {
    return adapter.screenToCanvas(screenPosition, scale, viewOffset);
  }

  /// Converts canvas position → screen
  Offset canvasToScreen(Offset canvasPosition) {
    return adapter.canvasToScreen(canvasPosition, scale, viewOffset);
  }

  /// Checks if a point is within the canvas/page bounds
  bool isPointInBounds(Offset canvasPosition) {
    return adapter.isPointInBounds(canvasPosition);
  }

  /// Gets the current viewport in canvas coordinates
  Rect get canvasViewport {
    final topLeft = screenToCanvas(Offset.zero);
    final bottomRight = screenToCanvas(
      Offset(viewportSize.width, viewportSize.height),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  // ============================================================================
  // CONTENT OPERATIONS (delegated to adapter)
  // ============================================================================

  /// Adds a stroke
  void addStroke(ProStroke stroke) {
    adapter.addStroke(layerController, stroke);
  }

  /// Removes a stroke by ID
  void removeStroke(String strokeId) {
    adapter.removeStroke(layerController, strokeId);
  }

  /// Adds a shape
  void addShape(GeometricShape shape) {
    adapter.addShape(layerController, shape);
  }

  /// Removes a shape by ID
  void removeShape(String shapeId) {
    adapter.removeShape(layerController, shapeId);
  }

  /// Adds a text element
  void addTextElement(DigitalTextElement element) {
    adapter.addTextElement(element);
  }

  /// Gets all text elements in the current context
  List<DigitalTextElement> getTextElements() {
    return adapter.getTextElements();
  }

  /// Updates a text element (matched by ID)
  void updateTextElement(DigitalTextElement element) {
    adapter.updateTextElement(element);
  }

  /// Removes a text element by ID
  void removeTextElement(String elementId) {
    adapter.removeTextElement(elementId);
  }

  /// Adds an image element
  void addImageElement(ImageElement element) {
    adapter.addImageElement(element);
  }

  /// Gets all image elements in the current context
  List<ImageElement> getImageElements() {
    return adapter.getImageElements();
  }

  /// Updates an image element (matched by ID)
  void updateImageElement(ImageElement element) {
    adapter.updateImageElement(element);
  }

  /// Removes an image element by ID
  void removeImageElement(String elementId) {
    adapter.removeImageElement(elementId);
  }

  /// Gets all strokes within the specified viewport
  List<ProStroke> getStrokesInViewport(Rect viewport) {
    return adapter.getStrokesInViewport(layerController, viewport);
  }

  /// Gets all shapes within the specified viewport
  List<GeometricShape> getShapesInViewport(Rect viewport) {
    return adapter.getShapesInViewport(layerController, viewport);
  }

  /// Saves state for undo (before destructive operations)
  void saveUndoState() {
    adapter.saveUndoState();
  }

  /// Notifies that an operation has been completed (triggers auto-save)
  void notifyOperationComplete() {
    adapter.notifyOperationComplete();
  }

  // ============================================================================
  // FACTORY
  // ============================================================================

  /// Creates a copy with new settings
  ToolContext copyWith({
    CanvasAdapter? adapter,
    FlueraLayerController? layerController,
    double? scale,
    Offset? viewOffset,
    Size? viewportSize,
    ToolSettings? settings,
  }) {
    return ToolContext(
      adapter: adapter ?? this.adapter,
      layerController: layerController ?? this.layerController,
      scale: scale ?? this.scale,
      viewOffset: viewOffset ?? this.viewOffset,
      viewportSize: viewportSize ?? this.viewportSize,
      settings: settings ?? this.settings,
    );
  }
}

/// ⚙️ Current tool settings
///
/// Contains all drawing settings shared across tools.
class ToolSettings {
  /// Selected brush type
  final ProPenType penType;

  /// Selected color
  final Color color;

  /// Stroke width (in pixels at 1.0 scale)
  final double width;

  /// Opacity (0.0 - 1.0)
  final double opacity;

  /// Shape type for the shape tool
  final ShapeType shapeType;

  const ToolSettings({
    this.penType = ProPenType.fountain,
    this.color = Colors.black,
    this.width = 3.78, // 1mm = 3.78px @ 96 DPI
    this.opacity = 1.0,
    this.shapeType = ShapeType.freehand,
  });

  /// Color with opacity applied
  Color get effectiveColor => color.withValues(alpha: opacity);

  /// Width scaled for the current viewport scale
  double widthAtScale(double scale) => width / scale;

  ToolSettings copyWith({
    ProPenType? penType,
    Color? color,
    double? width,
    double? opacity,
    ShapeType? shapeType,
  }) {
    return ToolSettings(
      penType: penType ?? this.penType,
      color: color ?? this.color,
      width: width ?? this.width,
      opacity: opacity ?? this.opacity,
      shapeType: shapeType ?? this.shapeType,
    );
  }

  Map<String, dynamic> toJson() => {
    'penType': penType.index,
    'color': color.toARGB32(),
    'width': width,
    'opacity': opacity,
    'shapeType': shapeType.index,
  };

  factory ToolSettings.fromJson(Map<String, dynamic> json) {
    return ToolSettings(
      penType: ProPenType.values[json['penType'] ?? 0],
      color: Color(json['color'] ?? Colors.black.toARGB32()),
      width: (json['width'] ?? 3.78).toDouble(),
      opacity: (json['opacity'] ?? 1.0).toDouble(),
      shapeType: ShapeType.values[json['shapeType'] ?? 0],
    );
  }

  /// B3: Create ToolSettings snapshot from a [UnifiedToolController].
  ///
  /// This eliminates manual field-by-field mapping when building
  /// a [ToolContext] from the controller's current state.
  factory ToolSettings.fromController(UnifiedToolController ctrl) {
    return ToolSettings(
      penType: ctrl.penType,
      color: ctrl.color,
      width: ctrl.width,
      opacity: ctrl.opacity,
      shapeType: ctrl.shapeType,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ToolSettings &&
        other.penType == penType &&
        other.color == color &&
        other.width == width &&
        other.opacity == opacity &&
        other.shapeType == shapeType;
  }

  @override
  int get hashCode => Object.hash(penType, color, width, opacity, shapeType);
}
