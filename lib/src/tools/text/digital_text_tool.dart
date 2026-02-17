import 'package:flutter/material.dart';
import '../../core/models/digital_text_element.dart';

/// 🔧 DIGITAL TEXT TOOL
/// Handles l'interazione con text elements digitale:
/// - Selection on tap
/// - Dragging (with auto-scroll at edges)
/// - Resizing via handles
/// - Deselection su tap area vuota
class DigitalTextTool {
  /// Elemento correntemente selezionato
  DigitalTextElement? _selectedElement;

  /// Offset iniziale del drag (to calculate delta)
  Offset? _dragStartCanvasPosition;

  /// Handle di resize in dragging (null = nessuno, altrimenti indice 0-3)
  int? _resizeHandleIndex;

  /// Previous position during resize (for incremental delta calculation)
  Offset? _previousResizePosition;

  /// Getter per l'selected element
  DigitalTextElement? get selectedElement => _selectedElement;

  /// Checks if there is a selected element
  bool get hasSelection => _selectedElement != null;

  /// Reset completo
  void reset() {
    _selectedElement = null;
    _dragStartCanvasPosition = null;
    _resizeHandleIndex = null;
    _previousResizePosition = null;
  }

  /// Seleziona un elemento
  void selectElement(DigitalTextElement element) {
    _selectedElement = element;
  }

  /// Deseleziona elemento corrente
  void deselectElement() {
    _selectedElement = null;
    _dragStartCanvasPosition = null;
    _resizeHandleIndex = null;
    _previousResizePosition = null;
  }

  /// Hit test: trova elemento toccato da un punto
  DigitalTextElement? hitTest(
    Offset canvasPosition,
    List<DigitalTextElement> elements,
    BuildContext context,
  ) {
    // Check from last to first (those above have priority)
    for (int i = elements.length - 1; i >= 0; i--) {
      if (elements[i].containsPoint(canvasPosition, context)) {
        return elements[i];
      }
    }
    return null;
  }

  /// Hit test su handles di resize (ritorna indice handle o null)
  int? hitTestResizeHandles(
    Offset canvasPosition,
    DigitalTextElement element,
    BuildContext context,
  ) {
    final bounds = element.getBounds(context);
    final handles = _getResizeHandles(bounds);

    for (int i = 0; i < handles.length; i++) {
      final handleRect = Rect.fromCenter(
        center: handles[i],
        width: 40,
        height: 40,
      );
      if (handleRect.contains(canvasPosition)) {
        return i;
      }
    }
    return null;
  }

  /// Gets posizioni dei 4 handles di resize
  List<Offset> _getResizeHandles(Rect bounds) {
    return [
      bounds.topLeft, // 0: top-left
      bounds.topRight, // 1: top-right
      bounds.bottomLeft, // 2: bottom-left
      bounds.bottomRight, // 3: bottom-right
    ];
  }

  /// Gets handles di resize per elemento (metodo pubblico)
  List<Offset> getResizeHandles(
    DigitalTextElement element,
    BuildContext context,
  ) {
    final bounds = element.getBounds(context);
    return _getResizeHandles(bounds);
  }

  /// Start drag of the element
  void startDrag(Offset canvasPosition) {
    if (_selectedElement == null) return;
    _dragStartCanvasPosition = canvasPosition;
  }

  /// Updates drag of the element
  DigitalTextElement? updateDrag(Offset canvasPosition) {
    if (_selectedElement == null || _dragStartCanvasPosition == null) {
      return null;
    }

    // Calculate delta dat the point precedente (non dat the point iniziale!)
    final delta = canvasPosition - _dragStartCanvasPosition!;

    // Sposta l'elemento del delta
    _selectedElement = _selectedElement!.copyWith(
      position: _selectedElement!.position + delta,
      modifiedAt: DateTime.now(),
    );

    // IMPORTANTE: Update dragStartPosition for the next frame
    _dragStartCanvasPosition = canvasPosition;

    return _selectedElement;
  }

  /// Termina drag
  void endDrag() {
    _dragStartCanvasPosition = null;
  }

  /// Compensate the canvas scroll during drag (for smooth auto-scroll)
  void compensateScroll(Offset scrollDelta) {
    if (_selectedElement == null) return;

    // Compensate the position like the lasso
    _selectedElement = _selectedElement!.copyWith(
      position: _selectedElement!.position + scrollDelta,
      modifiedAt: DateTime.now(),
    );

    // Compensate the reference points to maintain the correct delta
    if (isDragging && _dragStartCanvasPosition != null) {
      _dragStartCanvasPosition = _dragStartCanvasPosition! + scrollDelta;
    }

    if (isResizing && _previousResizePosition != null) {
      _previousResizePosition = _previousResizePosition! + scrollDelta;
    }
  }

  /// Start resize
  void startResize(
    int handleIndex,
    Offset canvasPosition,
    BuildContext context,
  ) {
    if (_selectedElement == null) return;
    _resizeHandleIndex = handleIndex;
    _dragStartCanvasPosition = canvasPosition;
    _previousResizePosition = canvasPosition; // Save position iniziale
  }

  /// Updates resize
  DigitalTextElement? updateResize(
    Offset canvasPosition,
    BuildContext context,
  ) {
    if (_selectedElement == null ||
        _resizeHandleIndex == null ||
        _previousResizePosition == null) {
      return null;
    }

    // Calculate delta from the position PRECEDENTE (non from the beginning!)
    final delta = canvasPosition - _previousResizePosition!;

    // Use the distance to calculate scale variation
    final scaleDelta = (delta.dx.abs() + delta.dy.abs()) / 200.0;

    // Determina if it is zoom in o out basato sulla direzione dell'handle
    final isZoomIn =
        (_resizeHandleIndex == 3 &&
            delta.dx > 0 &&
            delta.dy > 0) || // bottom-right
        (_resizeHandleIndex == 1 &&
            delta.dx > 0 &&
            delta.dy < 0) || // top-right
        (_resizeHandleIndex == 2 &&
            delta.dx < 0 &&
            delta.dy > 0) || // bottom-left
        (_resizeHandleIndex == 0 && delta.dx < 0 && delta.dy < 0); // top-left

    // Applica delta incrementale alla scala CORRENTE
    double newScale =
        _selectedElement!.scale + (isZoomIn ? scaleDelta : -scaleDelta);

    // Limita scala tra 0.3 e 3.0
    newScale = newScale.clamp(0.3, 3.0);

    _selectedElement = _selectedElement!.copyWith(
      scale: newScale,
      modifiedAt: DateTime.now(),
    );

    // IMPORTANTE: Update position precedente for the next frame
    _previousResizePosition = canvasPosition;

    return _selectedElement;
  }

  /// Termina resize
  void endResize() {
    _resizeHandleIndex = null;
    _dragStartCanvasPosition = null;
    _previousResizePosition = null;
  }

  /// Checks se sta facendo resize
  bool get isResizing => _resizeHandleIndex != null;

  /// Checks se sta facendo drag
  bool get isDragging => _dragStartCanvasPosition != null && !isResizing;

  /// Draws selection box e handles
  void paintSelection(
    Canvas canvas,
    DigitalTextElement element,
    BuildContext context,
  ) {
    // RETTANGOLO DISATTIVATO - solo per debug
    // NON disegnare nulla
    return;
  }

  /// Calculates if the drag is vicino ai bordi (per auto-scroll)
  Offset? calculateAutoScrollDelta(
    Offset screenPosition,
    Size screenSize, {
    double edgeThreshold = 50.0,
    double scrollSpeed = 5.0,
  }) {
    double dx = 0.0;
    double dy = 0.0;

    // Left edge
    if (screenPosition.dx < edgeThreshold) {
      dx = -scrollSpeed * (1 - screenPosition.dx / edgeThreshold);
    }
    // Right edge
    else if (screenPosition.dx > screenSize.width - edgeThreshold) {
      dx =
          scrollSpeed *
          (1 - (screenSize.width - screenPosition.dx) / edgeThreshold);
    }

    // Top edge
    if (screenPosition.dy < edgeThreshold) {
      dy = -scrollSpeed * (1 - screenPosition.dy / edgeThreshold);
    }
    // Bottom edge
    else if (screenPosition.dy > screenSize.height - edgeThreshold) {
      dy =
          scrollSpeed *
          (1 - (screenSize.height - screenPosition.dy) / edgeThreshold);
    }

    if (dx != 0.0 || dy != 0.0) {
      return Offset(dx, dy);
    }
    return null;
  }
}
