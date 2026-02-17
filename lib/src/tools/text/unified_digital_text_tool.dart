import 'package:flutter/material.dart';
import '../base/tool_context.dart';
import '../base/base_tool.dart';
import '../../core/models/digital_text_element.dart';

/// 📝 UNIFIED DIGITAL TEXT TOOL
///
/// Strumento per testo digitale che funziona su:
/// - Canvas infinito
/// - PDF Pages
/// - Multiview
class UnifiedDigitalTextTool extends BaseTool {
  // ============================================================================
  // IDENTITY
  // ============================================================================

  @override
  String get toolId => 'digital_text';

  @override
  IconData get icon => Icons.text_fields;

  @override
  String get label => 'Testo';

  @override
  String get description => 'Aggiungi e modifica testo';

  @override
  bool get hasOverlay => true;

  // ============================================================================
  // STATE
  // ============================================================================

  DigitalTextElement? _selectedElement;
  DigitalTextElement? get selectedElement => _selectedElement;
  bool get hasSelection => _selectedElement != null;

  Offset? _dragStartOffset;
  Offset? _originalPosition;
  bool _isDragging = false;
  bool _isResizing = false;

  bool get isDragging => _isDragging;
  bool get isResizing => _isResizing;

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

  void selectElement(DigitalTextElement element) {
    _selectedElement = element;
  }

  void deselectElement() {
    _selectedElement = null;
    _isDragging = false;
    _isResizing = false;
    _dragStartOffset = null;
    _originalPosition = null;
  }

  DigitalTextElement? hitTest(
    Offset canvasPosition,
    List<DigitalTextElement> elements,
  ) {
    for (final element in elements.reversed) {
      final bounds = _calculateElementBounds(element);
      if (bounds.contains(canvasPosition)) {
        return element;
      }
    }
    return null;
  }

  Rect _calculateElementBounds(DigitalTextElement element) {
    final textWidth = element.text.length * element.fontSize * 0.6;
    final textHeight = element.fontSize * 1.5;
    return Rect.fromLTWH(
      element.position.dx,
      element.position.dy,
      textWidth.clamp(50.0, double.infinity),
      textHeight,
    );
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

  DigitalTextElement? updateDrag(Offset canvasPosition) {
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
  // OVERLAY
  // ============================================================================

  @override
  Widget? buildOverlay(ToolContext context) {
    if (_selectedElement == null) return null;

    final bounds = _calculateElementBounds(_selectedElement!);
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
            border: Border.all(color: Colors.blue, width: 2),
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
