import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/image_element.dart';

/// 🖼️ IMAGE INTERACTION TOOL
/// Handles l'interazione con image elements:
/// - Selection on tap
/// - Trascinamento
/// - Resizing via handles
/// - Rotazione
class ImageInteractionTool {
  /// Elemento correntemente selezionato
  ImageElement? _selectedElement;

  /// Offset iniziale del drag
  Offset? _dragStartCanvasPosition;

  /// Handle di resize in dragging (null = nessuno, altrimenti indice 0-3)
  int? _resizeHandleIndex;

  /// Previous position during resize
  Offset? _previousResizePosition;

  /// Distanza totale del drag (per distinguere tap da drag)
  double _totalDragDistance = 0.0;

  /// Dimensioni reali of images caricate (path -> Size)
  final Map<String, Size> imageDimensions = {};

  /// Getter per l'selected element
  ImageElement? get selectedElement => _selectedElement;

  /// Checks if there is a selected element
  bool get hasSelection => _selectedElement != null;

  /// Reset completo
  void reset() {
    _selectedElement = null;
    _dragStartCanvasPosition = null;
    _resizeHandleIndex = null;
    _previousResizePosition = null;
    _totalDragDistance = 0.0;
    imageDimensions.clear();
  }

  /// Seleziona un elemento
  void selectElement(ImageElement element) {
    _selectedElement = element;
  }

  /// Deseleziona elemento corrente
  void deselectElement() {
    _selectedElement = null;
    _dragStartCanvasPosition = null;
    _resizeHandleIndex = null;
    _previousResizePosition = null;
    _totalDragDistance = 0.0;
  }

  /// Hit test: trova elemento toccato da un punto
  ImageElement? hitTest(Offset canvasPosition, List<ImageElement> elements) {
    // Check from last to first (those above have priority)
    for (int i = elements.length - 1; i >= 0; i--) {
      final element = elements[i];
      final localPos = _transformToLocal(canvasPosition, element);

      // Get dimensioni
      final displaySize = _getDisplaySize(element);

      // Check if the point is inside the CENTERED local bounds
      const margin = 20.0;
      final halfWidth = displaySize.width / 2;
      final halfHeight = displaySize.height / 2;

      if (localPos.dx >= -halfWidth - margin &&
          localPos.dx <= halfWidth + margin &&
          localPos.dy >= -halfHeight - margin &&
          localPos.dy <= halfHeight + margin) {
        return element;
      }
    }
    return null;
  }

  /// Calculates bounds of the image (AABB per uso esterno)
  Rect getElementBounds(ImageElement element, [BuildContext? context]) {
    final displaySize = _getDisplaySize(element);

    // Return Rect centrato sulla position
    return Rect.fromCenter(
      center: element.position,
      width: displaySize.width,
      height: displaySize.height,
    );
  }

  /// Hit test su handles di resize
  int? hitTestResizeHandles(Offset canvasPosition, ImageElement element) {
    final localPos = _transformToLocal(canvasPosition, element);
    final displaySize = _getDisplaySize(element);

    final halfWidth = displaySize.width / 2;
    final halfHeight = displaySize.height / 2;

    // Defines handles in local unrotated space (centered)
    final handles = [
      Offset(-halfWidth, -halfHeight), // 0: top-left
      Offset(halfWidth, -halfHeight), // 1: top-right
      Offset(-halfWidth, halfHeight), // 2: bottom-left
      Offset(halfWidth, halfHeight), // 3: bottom-right
    ];

    for (int i = 0; i < handles.length; i++) {
      // Check distance in local space
      if ((localPos - handles[i]).distance <= 30.0) {
        // Increased hit area
        return i;
      }
    }
    return null;
  }

  /// Helper: Transform punto globale in spazio locale (unrotated, centered)
  Offset _transformToLocal(Offset globalPos, ImageElement element) {
    var dx = globalPos.dx - element.position.dx;
    var dy = globalPos.dy - element.position.dy;

    if (element.rotation != 0) {
      final cos = math.cos(-element.rotation);
      final sin = math.sin(-element.rotation);
      final newX = dx * cos - dy * sin;
      final newY = dx * sin + dy * cos;
      dx = newX;
      dy = newY;
    }
    return Offset(dx, dy);
  }

  /// Helper: Calculate dimensioni visuali
  Size _getDisplaySize(ImageElement element) {
    Size imageSize = imageDimensions[element.imagePath] ?? const Size(300, 300);

    const maxWidth = 300.0;
    const maxHeight = 300.0;

    final scaleX =
        imageSize.width > maxWidth ? maxWidth / imageSize.width : 1.0;
    final scaleY =
        imageSize.height > maxHeight ? maxHeight / imageSize.height : 1.0;
    final baseScale = scaleX < scaleY ? scaleX : scaleY;

    return Size(
      imageSize.width * baseScale * element.scale,
      imageSize.height * baseScale * element.scale,
    );
  }

  /// Gets handles di resize per elemento (metodo pubblico)
  /// Gets handles di resize per elemento (metodo pubblico)
  List<Offset> getResizeHandles(ImageElement element) {
    final displaySize = _getDisplaySize(element);
    final halfWidth = displaySize.width / 2;
    final halfHeight = displaySize.height / 2;

    // Handles in local unrotated centered space
    final localHandles = [
      Offset(-halfWidth, -halfHeight), // top-left
      Offset(halfWidth, -halfHeight), // top-right
      Offset(-halfWidth, halfHeight), // bottom-left
      Offset(halfWidth, halfHeight), // bottom-right
    ];

    // Transform back to global space
    return localHandles.map((local) {
      return _transformToGlobal(local, element);
    }).toList();
  }

  /// Helper: Transform punto locale in spazio globale
  Offset _transformToGlobal(Offset localPos, ImageElement element) {
    double dx = localPos.dx;
    double dy = localPos.dy;

    // Rotate
    if (element.rotation != 0) {
      final cos = math.cos(element.rotation);
      final sin = math.sin(element.rotation);
      final newX = dx * cos - dy * sin;
      final newY = dx * sin + dy * cos;
      dx = newX;
      dy = newY;
    }

    // Translate
    return Offset(dx + element.position.dx, dy + element.position.dy);
  }

  /// Start drag of the element
  void startDrag(Offset canvasPosition) {
    if (_selectedElement == null) return;
    _dragStartCanvasPosition = canvasPosition;
    _totalDragDistance = 0.0; // Reset distanza
  }

  /// Updates drag of the element
  ImageElement? updateDrag(Offset canvasPosition) {
    if (_selectedElement == null || _dragStartCanvasPosition == null) {
      return null;
    }

    final delta = canvasPosition - _dragStartCanvasPosition!;

    // Accumula distanza totale del drag
    _totalDragDistance += delta.distance;

    _selectedElement = _selectedElement!.copyWith(
      position: _selectedElement!.position + delta,
    );

    _dragStartCanvasPosition = canvasPosition;

    return _selectedElement;
  }

  /// Termina drag
  void endDrag() {
    _dragStartCanvasPosition = null;
  }

  /// Checks se l'interazione is stata un tap (movimento minimo)
  /// Soglia di 10 pixel per considerare un movimento come drag
  bool wasTap() {
    return _totalDragDistance < 10.0;
  }

  /// Gets la distanza totale del drag
  double get totalDragDistance => _totalDragDistance;

  /// Start resize
  void startResize(int handleIndex, Offset canvasPosition) {
    if (_selectedElement == null) return;
    _resizeHandleIndex = handleIndex;
    _dragStartCanvasPosition = canvasPosition;
    _previousResizePosition = canvasPosition;
  }

  /// Updates resize
  ImageElement? updateResize(Offset canvasPosition) {
    if (_selectedElement == null ||
        _resizeHandleIndex == null ||
        _previousResizePosition == null) {
      return null;
    }

    final delta = canvasPosition - _previousResizePosition!;
    final scaleDelta = (delta.dx.abs() + delta.dy.abs()) / 200.0;

    final isZoomIn =
        (_resizeHandleIndex == 3 && delta.dx > 0 && delta.dy > 0) ||
        (_resizeHandleIndex == 1 && delta.dx > 0 && delta.dy < 0) ||
        (_resizeHandleIndex == 2 && delta.dx < 0 && delta.dy > 0) ||
        (_resizeHandleIndex == 0 && delta.dx < 0 && delta.dy < 0);

    double newScale =
        _selectedElement!.scale + (isZoomIn ? scaleDelta : -scaleDelta);
    newScale = newScale.clamp(0.1, 5.0);

    _selectedElement = _selectedElement!.copyWith(scale: newScale);
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
}
