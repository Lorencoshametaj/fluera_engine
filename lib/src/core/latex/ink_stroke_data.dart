import 'dart:ui';

/// 🖊️ Ink stroke data model for handwriting recognition.
///
/// Captures raw stylus/touch input as a series of timestamped points
/// with optional pressure data. This data is rasterized into a bitmap
/// before being sent to the ML model for recognition.

/// A single point in an ink stroke.
class InkPoint {
  /// X coordinate in logical pixels.
  final double x;

  /// Y coordinate in logical pixels.
  final double y;

  /// Stylus pressure (0.0 to 1.0). Defaults to 0.5 for touch input.
  final double pressure;

  /// Timestamp in milliseconds since epoch.
  final int timestamp;

  const InkPoint({
    required this.x,
    required this.y,
    this.pressure = 0.5,
    this.timestamp = 0,
  });

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'pressure': pressure,
    'timestamp': timestamp,
  };

  factory InkPoint.fromJson(Map<String, dynamic> json) {
    return InkPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      pressure: (json['pressure'] as num?)?.toDouble() ?? 0.5,
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }
}

/// A single continuous stroke (pen-down → pen-up).
class InkStroke {
  /// Ordered list of points in this stroke.
  final List<InkPoint> points;

  const InkStroke(this.points);

  /// Whether this stroke has enough points to be meaningful.
  bool get isValid => points.length >= 2;

  /// Bounding rect of this stroke.
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.x, maxX = points.first.x;
    double minY = points.first.y, maxY = points.first.y;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => p.toJson()).toList(),
  };

  factory InkStroke.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>;
    return InkStroke(
      rawPoints
          .map((p) => InkPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Collection of ink strokes representing a complete handwriting input.
class InkData {
  /// All captured strokes in chronological order.
  final List<InkStroke> strokes;

  const InkData(this.strokes);

  /// Whether there is any valid ink data.
  bool get isEmpty => strokes.isEmpty;
  bool get isNotEmpty => strokes.isNotEmpty;

  /// Total number of points across all strokes.
  int get totalPoints => strokes.fold(0, (sum, s) => sum + s.points.length);

  /// Bounding rect encompassing all strokes.
  Rect get boundingBox {
    if (strokes.isEmpty) return Rect.zero;
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final stroke in strokes) {
      final b = stroke.bounds;
      if (b.left < minX) minX = b.left;
      if (b.right > maxX) maxX = b.right;
      if (b.top < minY) minY = b.top;
      if (b.bottom > maxY) maxY = b.bottom;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Map<String, dynamic> toJson() => {
    'strokes': strokes.map((s) => s.toJson()).toList(),
  };

  factory InkData.fromJson(Map<String, dynamic> json) {
    final rawStrokes = json['strokes'] as List<dynamic>;
    return InkData(
      rawStrokes
          .map((s) => InkStroke.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
