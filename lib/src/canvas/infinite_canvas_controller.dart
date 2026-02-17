import 'package:flutter/material.dart';

/// Controller per canvas infinito con zoom e pan
class InfiniteCanvasController extends ChangeNotifier {
  // Canvas transformations
  Offset _offset = Offset.zero;
  double _scale = 1.0;

  // Limiti zoom
  static const double _minScale = 0.1; // Dezoom massimo per vedere more canvas
  static const double _maxScale = 5.0;

  // Getters
  Offset get offset => _offset;
  double get scale => _scale;

  /// Applica offset (pan)
  void setOffset(Offset newOffset) {
    _offset = newOffset;
    notifyListeners();
  }

  /// Applica zoom
  void setScale(double newScale) {
    _scale = newScale.clamp(_minScale, _maxScale);
    notifyListeners();
  }

  /// Applica trasformazione combinata (zoom + pan)
  void updateTransform({required Offset offset, required double scale}) {
    _offset = offset;
    _scale = scale.clamp(_minScale, _maxScale);
    notifyListeners();
  }

  /// Reset alla vista iniziale
  void reset() {
    _offset = Offset.zero;
    _scale = 1.0;
    notifyListeners();
  }

  /// 🎯 Cenbetween the viewport sull'origine (0,0) of the canvas
  void centerCanvas(
    Size viewportSize, {
    Size canvasSize = const Size(5000, 5000),
  }) {
    // The origin (0,0) of the canvas maps to the center of the screen
    _offset = Offset(viewportSize.width / 2, viewportSize.height / 2);
    notifyListeners();
  }

  /// Convert screen coordinates in canvas coordinates
  Offset screenToCanvas(Offset screenPoint) {
    return (screenPoint - _offset) / _scale;
  }

  /// Convert canvas coordinates in screen coordinates
  Offset canvasToScreen(Offset canvasPoint) {
    return canvasPoint * _scale + _offset;
  }
}
