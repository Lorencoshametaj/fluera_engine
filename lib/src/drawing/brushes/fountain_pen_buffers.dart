import 'dart:ui';

// ============================================================================
// 🎨 ZERO-ALLOCATION STROKE BUFFERS
// ============================================================================

/// Pre-allocated double buffer for width calculations.
/// Avoids creating a new List<double> on every stroke render call.
///
/// DESIGN PRINCIPLES:
/// - Zero allocation in hot path — reuses internal array
/// - Auto-grows when capacity exceeded (doubling strategy)
/// - Used by FountainPenBrush for per-point width pipeline
class StrokeWidthBuffer {
  static const int _initialCapacity = 2048;
  List<double> _data = List<double>.filled(_initialCapacity, 0.0);
  int _length = 0;

  int get length => _length;

  void reset(int expectedSize) {
    if (expectedSize > _data.length) {
      _data = List<double>.filled(expectedSize * 2, 0.0);
    }
    _length = 0;
  }

  void add(double value) {
    if (_length >= _data.length) {
      final newData = List<double>.filled(_data.length * 2, 0.0);
      newData.setRange(0, _data.length, _data);
      _data = newData;
    }
    _data[_length++] = value;
  }

  double operator [](int index) => _data[index];
  void operator []=(int index, double value) => _data[index] = value;
}

/// Pre-allocated Offset buffer for tangents, left/right contour points.
/// Avoids creating a new List<Offset> on every stroke render call.
///
/// DESIGN PRINCIPLES:
/// - Same zero-allocation strategy as [StrokeWidthBuffer]
/// - Provides [view] for read-only sublist access without copy
/// - Used for tangent computation, outline generation, Chaikin subdivision
class StrokeOffsetBuffer {
  static const int _initialCapacity = 2048;
  List<Offset> _data = List<Offset>.filled(_initialCapacity, Offset.zero);
  int _length = 0;

  int get length => _length;

  /// A view of the buffer contents (sublist without copy for read access).
  List<Offset> get view => _data.sublist(0, _length);

  void reset(int expectedSize) {
    if (expectedSize > _data.length) {
      _data = List<Offset>.filled(expectedSize * 2, Offset.zero);
    }
    _length = 0;
  }

  void add(Offset value) {
    if (_length >= _data.length) {
      final newData = List<Offset>.filled(_data.length * 2, Offset.zero);
      newData.setRange(0, _data.length, _data);
      _data = newData;
    }
    _data[_length++] = value;
  }

  Offset operator [](int index) => _data[index];
  void operator []=(int index, Offset value) => _data[index] = value;
}
