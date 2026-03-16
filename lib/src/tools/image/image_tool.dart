import 'dart:ui';
import 'dart:math' as math;
import '../../core/models/image_element.dart';

/// 🖼️ IMAGE TOOL
/// Handles selezione, drag e resize of images
class ImageTool {
  ImageElement? _selectedImage;
  String? _resizeHandle; // 'tl', 'tr', 'bl', 'br' (top-left, top-right, etc.)
  Offset? _dragStartPosition;
  Offset? _resizeStartPosition;
  double? _initialScale;
  bool _isRotating = false;
  double _initialImageRotation = 0.0;
  double _initialImageScale = 1.0;

  // Size of handles di resize (more piccoli per aspetto professionale)
  static const double handleSize = 10.0; // Visuale (raggio 5px)
  static const double handleHitArea = 28.0; // Area touch

  // 🌀 Rotation handle: positioned above the image
  static const double rotationHandleDistance = 40.0; // Distance above image
  static const double rotationHandleHitArea = 36.0; // Touch area

  // 🌀 Single-finger rotation state
  bool _isHandleRotating = false;
  double _handleRotationInitial = 0.0;
  Offset _handleRotationCenter = Offset.zero;
  double _handleRotationStartAngle = 0.0;

  /// Elemento selezionato
  ImageElement? get selectedImage => _selectedImage;

  /// È in mode drag?
  bool get isDragging => _dragStartPosition != null && _resizeHandle == null;

  /// È in mode resize?
  bool get isResizing => _resizeHandle != null;

  /// È in mode rotazione (two-finger)?
  bool get isRotating => _isRotating;

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

  /// Hit test su un'immagine (rotation-aware)
  bool hitTest(ImageElement image, Offset point, Size imageSize) {
    // Transform point into image-local space (undo rotation around center)
    final localPoint = _unrotatePoint(point, image.position, image.rotation);

    final scaledWidth = imageSize.width * image.scale;
    final scaledHeight = imageSize.height * image.scale;

    final rect = Rect.fromCenter(
      center: image.position,
      width: scaledWidth,
      height: scaledHeight,
    );

    return rect.contains(localPoint);
  }

  /// Hit test sugli handle di resize (rotation-aware)
  /// Returns il nome dell'handle ('tl', 'tr', 'bl', 'br') o null
  String? hitTestResizeHandle(Offset point, Size imageSize) {
    if (_selectedImage == null) return null;

    // Transform point into image-local space
    final localPoint = _unrotatePoint(
      point,
      _selectedImage!.position,
      _selectedImage!.rotation,
    );

    final scaledWidth = imageSize.width * _selectedImage!.scale;
    final scaledHeight = imageSize.height * _selectedImage!.scale;

    final rect = Rect.fromCenter(
      center: _selectedImage!.position,
      width: scaledWidth,
      height: scaledHeight,
    );

    final handles = {
      'tl': rect.topLeft,
      'tr': rect.topRight,
      'bl': rect.bottomLeft,
      'br': rect.bottomRight,
    };

    for (final entry in handles.entries) {
      final handleRect = Rect.fromCenter(
        center: entry.value,
        width: handleHitArea,
        height: handleHitArea,
      );
      if (handleRect.contains(localPoint)) {
        return entry.key;
      }
    }

    return null;
  }

  /// Hit test on the rotation handle (circle above the image)
  bool hitTestRotationHandle(Offset point, Size imageSize) {
    if (_selectedImage == null) return false;

    final scaledHeight = imageSize.height * _selectedImage!.scale;
    // Handle is above the image center, in rotated space
    final handleCenter = _rotatePoint(
      _selectedImage!.position +
          Offset(0, -scaledHeight / 2 - rotationHandleDistance),
      _selectedImage!.position,
      _selectedImage!.rotation,
    );

    return (point - handleCenter).distance < rotationHandleHitArea / 2;
  }

  /// Start single-finger rotation via the handle
  void startHandleRotation(Offset position) {
    if (_selectedImage == null) return;
    _isHandleRotating = true;
    _isRotating = true;
    _handleRotationCenter = _selectedImage!.position;
    _handleRotationInitial = _selectedImage!.rotation;
    _initialImageScale = _selectedImage!.scale;
    // Angle from center to initial touch point
    final delta = position - _handleRotationCenter;
    _handleRotationStartAngle = math.atan2(delta.dy, delta.dx);
  }

  /// Update single-finger rotation via the handle
  ImageElement? updateHandleRotation(Offset currentPosition) {
    if (_selectedImage == null || !_isHandleRotating) return null;

    final delta = currentPosition - _handleRotationCenter;
    final currentAngle = math.atan2(delta.dy, delta.dx);
    final angleDelta = currentAngle - _handleRotationStartAngle;

    final newRotation = _handleRotationInitial + angleDelta;
    final updatedImage = _selectedImage!.copyWith(rotation: newRotation);
    _selectedImage = updatedImage;
    return updatedImage;
  }

  /// End single-finger handle rotation
  void endHandleRotation() {
    _isHandleRotating = false;
    _isRotating = false;
  }

  /// Whether the handle rotation is active
  bool get isHandleRotating => _isHandleRotating;

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

  /// Compensate the canvas scroll during drag/resize
  /// (used by auto-scroll to keep the image under the finger)
  void compensateScroll(Offset compensation) {
    if (_selectedImage == null) return;

    // Update position of the selected image
    _selectedImage = _selectedImage!.copyWith(
      position: _selectedImage!.position + compensation,
    );

    // ⚡ IMPORTANTE: aggiorna anche dragStartPosition per mantenere
    // the correct reference when the user continues to move the finger
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

  /// Start two-finger rotation
  void startRotation() {
    if (_selectedImage == null) return;
    _isRotating = true;
    _initialImageRotation = _selectedImage!.rotation;
    _initialImageScale = _selectedImage!.scale;
  }

  /// Update rotation + scale simultaneously (absolute deltas from gesture start)
  /// Returns (updatedImage, didSnap) — didSnap is true when the angle
  /// magnetically locks to a common angle (0°/45°/90°/135°/180°/...).
  (ImageElement?, bool) updateRotation(
    double absoluteRotationDelta,
    double scaleRatio,
  ) {
    if (_selectedImage == null || !_isRotating) return (null, false);

    double newRotation = _initialImageRotation + absoluteRotationDelta;
    final newScale = (_initialImageScale * scaleRatio).clamp(0.05, 3.0);

    // 🧲 MAGNETIC SNAP: Snap TOTAL rotation to 0°/45°/90°/135°/180°/...
    // Applied to the absolute angle so the image actually lands on famous angles.
    const snapInterval = 0.7853981633974483; // π/4 = 45°
    const snapThreshold = 0.12; // ~7° magnetic zone
    final nearestSnap = (newRotation / snapInterval).round() * snapInterval;
    final distFromSnap = (newRotation - nearestSnap).abs();
    bool didSnap = false;
    if (distFromSnap < snapThreshold) {
      // Cubic dampening for magnetic feel
      final t = (distFromSnap / snapThreshold).clamp(0.0, 1.0);
      final dampening = t * t * t;
      newRotation = nearestSnap + (newRotation - nearestSnap) * dampening;
      didSnap = true;
    }

    final updatedImage = _selectedImage!.copyWith(
      rotation: newRotation,
      scale: newScale,
    );
    _selectedImage = updatedImage;
    return (updatedImage, didSnap);
  }

  /// End rotation
  void endRotation() {
    _isRotating = false;
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

  // ===========================================================================
  // 🧮 Geometry helpers
  // ===========================================================================

  /// Transform point into unrotated space around a center (inverse rotation)
  Offset _unrotatePoint(Offset point, Offset center, double rotation) {
    if (rotation == 0.0) return point;
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final cos = math.cos(-rotation);
    final sin = math.sin(-rotation);
    return Offset(
      center.dx + dx * cos - dy * sin,
      center.dy + dx * sin + dy * cos,
    );
  }

  /// Rotate a point around a center (forward rotation)
  Offset _rotatePoint(Offset point, Offset center, double rotation) {
    if (rotation == 0.0) return point;
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    return Offset(
      center.dx + dx * cos - dy * sin,
      center.dy + dx * sin + dy * cos,
    );
  }
}
