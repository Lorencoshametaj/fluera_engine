import 'package:flutter/material.dart';
import '../base/tool_context.dart';
import '../base/base_tool.dart';
import '../../core/models/image_element.dart';

/// 🖼️ UNIFIED IMAGE TOOL
///
/// Strumento per immagini che funziona su:
/// - Canvas infinito
/// - PDF Pages
/// - Multiview
class UnifiedImageTool extends BaseTool {
  // ============================================================================
  // IDENTITY
  // ============================================================================

  @override
  String get toolId => 'image';

  @override
  IconData get icon => Icons.image;

  @override
  String get label => 'Immagine';

  @override
  String get description => 'Aggiungi e modifica immagini';

  @override
  bool get hasOverlay => true;

  // ============================================================================
  // STATE
  // ============================================================================

  ImageElement? _selectedElement;
  ImageElement? get selectedElement => _selectedElement;
  bool get hasSelection => _selectedElement != null;

  Offset? _dragStartOffset;
  Offset? _originalPosition;
  bool _isDragging = false;
  bool _isResizing = false;
  double? _originalScale;

  bool get isDragging => _isDragging;
  bool get isResizing => _isResizing;

  /// Size di default delle immagini (to calculate bounds)
  static const double _defaultImageSize = 200.0;

  // ============================================================================
  // POINTER EVENTS (required by DrawingTool interface)
  // ============================================================================

  @override
  void onPointerDown(ToolContext context, PointerDownEvent event) {
    beginOperation(context, event.localPosition);
  }

  @override
  void onPointerMove(ToolContext context, PointerMoveEvent event) {
    if (_isDragging && currentCanvasPosition != null) {
      continueOperation(context, event.localPosition);
    }
  }

  @override
  void onPointerUp(ToolContext context, PointerUpEvent event) {
    if (_isDragging) {
      endDrag();
    }
    if (_isResizing) {
      endResize();
    }
    completeOperation(context);
  }

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  @override
  void onDeactivate(ToolContext context) {
    super.onDeactivate(context);
    deselectElement();
  }

  // ============================================================================
  // SELECTION
  // ============================================================================

  void selectElement(ImageElement element) {
    _selectedElement = element;
  }

  void deselectElement() {
    _selectedElement = null;
    _isDragging = false;
    _isResizing = false;
    _dragStartOffset = null;
    _originalPosition = null;
    _originalScale = null;
  }

  ImageElement? hitTest(Offset canvasPosition, List<ImageElement> elements) {
    for (final element in elements.reversed) {
      final size = _defaultImageSize * element.scale;
      final bounds = Rect.fromLTWH(
        element.position.dx,
        element.position.dy,
        size,
        size,
      );
      if (bounds.contains(canvasPosition)) {
        return element;
      }
    }
    return null;
  }

  // ============================================================================
  // DRAG
  // ============================================================================

  void startDrag(Offset canvasPosition) {
    if (_selectedElement == null) return;
    _isDragging = true;
    _dragStartOffset = canvasPosition;
    _originalPosition = _selectedElement!.position;
  }

  ImageElement? updateDrag(Offset canvasPosition) {
    if (!_isDragging || _selectedElement == null || _originalPosition == null) {
      return null;
    }
    final delta = canvasPosition - _dragStartOffset!;
    final newPosition = _originalPosition! + delta;
    _selectedElement = _selectedElement!.copyWith(position: newPosition);
    return _selectedElement;
  }

  void endDrag() {
    _isDragging = false;
    _dragStartOffset = null;
    _originalPosition = null;
  }

  // ============================================================================
  // RESIZE
  // ============================================================================

  void startResize(Offset canvasPosition) {
    if (_selectedElement == null) return;
    _isResizing = true;
    _dragStartOffset = canvasPosition;
    _originalScale = _selectedElement!.scale;
  }

  ImageElement? updateResize(Offset canvasPosition) {
    if (!_isResizing || _selectedElement == null || _originalScale == null) {
      return null;
    }
    final delta = canvasPosition - _dragStartOffset!;
    final scaleFactor = 1.0 + (delta.dx + delta.dy) / 200.0;
    final newScale = (_originalScale! * scaleFactor).clamp(0.1, 5.0);
    _selectedElement = _selectedElement!.copyWith(scale: newScale);
    return _selectedElement;
  }

  void endResize() {
    _isResizing = false;
    _dragStartOffset = null;
    _originalScale = null;
  }

  // ============================================================================
  // OVERLAY
  // ============================================================================

  @override
  Widget? buildOverlay(ToolContext context) {
    if (_selectedElement == null) return null;

    final size = _defaultImageSize * _selectedElement!.scale;
    final bounds = Rect.fromLTWH(
      _selectedElement!.position.dx,
      _selectedElement!.position.dy,
      size,
      size,
    );

    final topLeft = context.canvasToScreen(bounds.topLeft);
    final bottomRight = context.canvasToScreen(bounds.bottomRight);
    final screenBounds = Rect.fromPoints(topLeft, bottomRight);

    return Positioned(
      left: screenBounds.left - 4,
      top: screenBounds.top - 4,
      child: IgnorePointer(
        child: Container(
          width: screenBounds.width + 8,
          height: screenBounds.height + 8,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.green, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // SERIALIZATION
  // ============================================================================

  @override
  Map<String, dynamic> saveConfig() => {};

  @override
  void loadConfig(Map<String, dynamic> config) {}
}
