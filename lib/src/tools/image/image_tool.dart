import 'dart:ui';
import '../../core/models/image_element.dart';

/// 🖼️ IMAGE TOOL
/// Handles selezione, drag e resize of images
class ImageTool {
  ImageElement? _selectedImage;
  String? _resizeHandle; // 'tl', 'tr', 'bl', 'br' (top-left, top-right, etc.)
  Offset? _dragStartPosition;
  Offset? _resizeStartPosition;
  double? _initialScale;

  // Size of handles di resize (more piccoli per aspetto professionale)
  static const double handleSize = 10.0; // Visuale (raggio 5px)
  static const double handleHitArea =
      28.0; // Area touch (more grande per facilità)

  /// Elemento selezionato
  ImageElement? get selectedImage => _selectedImage;

  /// È in mode drag?
  bool get isDragging => _dragStartPosition != null && _resizeHandle == null;

  /// È in mode resize?
  bool get isResizing => _resizeHandle != null;

  /// Seleziona un'immagine
  void selectImage(ImageElement image) {
    _selectedImage = image;
    _clearDragResize();
  }

  /// Deseleziona l'immagine corrente
  void clearSelection() {
    _selectedImage = null;
    _clearDragResize();
  }

  /// Clears drag/resize state
  void _clearDragResize() {
    _dragStartPosition = null;
    _resizeStartPosition = null;
    _resizeHandle = null;
    _initialScale = null;
  }

  /// Hit test su un'immagine (controlla if the punto tocca l'immagine)
  bool hitTest(ImageElement image, Offset point, Size imageSize) {
    // L'immagine viene disegnata con:
    // 1. translate(position)
    // 2. scale(scale)
    // 3. drawImage da topLeft di un rect centrato su zero
    // Quindi dobbiamo calcolare il rect finale dopo tutte le trasformazioni

    final scaledWidth = imageSize.width * image.scale;
    final scaledHeight = imageSize.height * image.scale;

    // The rect originale is centrato su zero, quindi topLeft = (-width/2, -height/2)
    // Dopo la scala: scaledTopLeft = (-scaledWidth/2, -scaledHeight/2)
    // Dopo la traslazione: finalTopLeft = position + scaledTopLeft
    final scaledTopLeft = Offset(-scaledWidth / 2, -scaledHeight / 2);
    final finalTopLeft = image.position + scaledTopLeft;

    final rect = Rect.fromLTWH(
      finalTopLeft.dx,
      finalTopLeft.dy,
      scaledWidth,
      scaledHeight,
    );

    return rect.contains(point);
  }

  /// Hit test sugli handle di resize
  /// Returns il nome dell'handle ('tl', 'tr', 'bl', 'br') o null
  String? hitTestResizeHandle(Offset point, Size imageSize) {
    if (_selectedImage == null) return null;

    final scaledWidth = imageSize.width * _selectedImage!.scale;
    final scaledHeight = imageSize.height * _selectedImage!.scale;

    final rect = Rect.fromCenter(
      center: _selectedImage!.position,
      width: scaledWidth,
      height: scaledHeight,
    );

    // Posizioni of handles
    final handles = {
      'tl': rect.topLeft,
      'tr': rect.topRight,
      'bl': rect.bottomLeft,
      'br': rect.bottomRight,
    };

    // Check quale handle was toccato
    for (final entry in handles.entries) {
      final handleRect = Rect.fromCenter(
        center: entry.value,
        width: handleHitArea,
        height: handleHitArea,
      );
      if (handleRect.contains(point)) {
        return entry.key;
      }
    }

    return null;
  }

  /// Start drag
  void startDrag(Offset position) {
    if (_selectedImage == null) return;
    _dragStartPosition = position;
  }

  /// Updates drag (restituisce immagine aggiornata without modificare la lista)
  ImageElement? updateDrag(Offset currentPosition) {
    if (_selectedImage == null || _dragStartPosition == null) return null;

    // Calculate delta dal frame precedente (non from the beginning)
    final delta = currentPosition - _dragStartPosition!;

    // 🔧 Limit delta to avoid giant jumps (glitch protection)
    // Max 200px per frame (molto permissivo, solo anti-glitch)
    final clampedDelta = Offset(
      delta.dx.clamp(-200.0, 200.0),
      delta.dy.clamp(-200.0, 200.0),
    );

    // Update position
    final updatedImage = _selectedImage!.copyWith(
      position: _selectedImage!.position + clampedDelta,
    );

    // Update internal state
    _selectedImage = updatedImage;
    _dragStartPosition = currentPosition; // ⚡ Update per next frame

    return updatedImage;
  }

  /// Fine drag
  void endDrag() {
    _dragStartPosition = null;
  }

  /// Compensate the scroll of the canvas durante drag/resize
  /// (used by auto-scroll to keep the image under the finger)
  void compensateScroll(Offset compensation) {
    if (_selectedImage == null) return;

    // Update position of the selected image
    _selectedImage = _selectedImage!.copyWith(
      position: _selectedImage!.position + compensation,
    );

    // ⚡ IMPORTANTE: aggiorna anche dragStartPosition per mantenere
    // il riferimento corretto quando l'utente continua a muovere il dito
    if (_dragStartPosition != null) {
      _dragStartPosition = _dragStartPosition! + compensation;
    }

    // For il resize, aggiorna anthat the position di partenza
    if (_resizeStartPosition != null) {
      _resizeStartPosition = _resizeStartPosition! + compensation;
    }
  }

  /// Start resize
  void startResize(String handle, Offset position) {
    if (_selectedImage == null) return;
    _resizeHandle = handle;
    _resizeStartPosition = position;
    _initialScale = _selectedImage!.scale;
  }

  /// Updates resize (restituisce immagine aggiornata without modificare la lista)
  ImageElement? updateResize(Offset currentPosition) {
    if (_selectedImage == null ||
        _resizeHandle == null ||
        _resizeStartPosition == null ||
        _initialScale == null) {
      return null;
    }

    // Calculate delta
    final delta = currentPosition - _resizeStartPosition!;

    // Calculate nuovo scale basato sul delta
    // Sensibilità molto ridotta per controllo preciso (1000.0 = molto lento)
    double scaleDelta = 0;

    switch (_resizeHandle) {
      case 'br': // Bottom-right: both directions increase the scale
        scaleDelta = (delta.dx + delta.dy) / 1000.0;
        break;
      case 'tl': // Top-left: inverse
        scaleDelta = -(delta.dx + delta.dy) / 1000.0;
        break;
      case 'tr': // Top-right
        scaleDelta = (delta.dx - delta.dy) / 1000.0;
        break;
      case 'bl': // Bottom-left
        scaleDelta = (-delta.dx + delta.dy) / 1000.0;
        break;
    }

    // Applica nuovo scale con limiti professionali
    // Min: 0.05 (5% size originale), Max: 3.0 (300% per dettagli)
    final newScale = (_initialScale! + scaleDelta).clamp(0.05, 3.0);

    final updatedImage = _selectedImage!.copyWith(scale: newScale);

    // Update internal state
    _selectedImage = updatedImage;

    return updatedImage;
  }

  /// Termina resize
  void endResize() {
    _resizeHandle = null;
    _resizeStartPosition = null;
    _initialScale = null;
  }

  /// Get bounds of the image selezionata
  Rect? getSelectedBounds(Size imageSize) {
    if (_selectedImage == null) return null;

    final scaledWidth = imageSize.width * _selectedImage!.scale;
    final scaledHeight = imageSize.height * _selectedImage!.scale;

    return Rect.fromCenter(
      center: _selectedImage!.position,
      width: scaledWidth,
      height: scaledHeight,
    );
  }
}
