import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/models/shape_type.dart';

// ============================================================================
// 🔷 SHAPE RECOGNITION ENGINE — v2
// ============================================================================

/// Sensitivity levels for shape recognition.
/// Higher sensitivity means more lenient matching (easier to trigger).
enum ShapeRecognitionSensitivity {
  /// Strict matching — only very clean shapes are recognized.
  low(0.82),

  /// Balanced matching (default) — good for most users.
  medium(0.70),

  /// Lenient matching — recognizes rough/sketchy shapes.
  high(0.55);

  final double threshold;
  const ShapeRecognitionSensitivity(this.threshold);
}

/// Result of a shape recognition attempt.
///
/// Contains the recognized [type] (null if no match), a [confidence]
/// score in \[0, 1\], the [boundingBox] of the recognized shape, and
/// whether the shape is an [isEllipse] (non-square bounding box).
class ShapeRecognitionResult {
  /// Recognized shape type, or null if no shape was detected.
  final ShapeType? type;

  /// Confidence score from 0.0 (no match) to 1.0 (perfect match).
  final double confidence;

  /// Axis-aligned bounding box that encloses the recognized shape.
  final Rect boundingBox;

  /// Whether the recognized circle is actually an ellipse (aspect ratio != 1).
  final bool isEllipse;

  /// Rotation angle in radians for rotated shapes (e.g. tilted rectangles).
  /// 0.0 means axis-aligned.
  final double rotationAngle;

  const ShapeRecognitionResult({
    this.type,
    required this.confidence,
    required this.boundingBox,
    this.isEllipse = false,
    this.rotationAngle = 0.0,
  });

  /// Whether the recognition result should be accepted at a given [threshold].
  bool recognizedAt(double threshold) =>
      type != null && confidence >= threshold;

  /// Default recognition check (medium sensitivity).
  bool get recognized => recognizedAt(0.7);

  @override
  String toString() =>
      'ShapeRecognitionResult(type: $type, confidence: ${confidence.toStringAsFixed(2)}'
      '${isEllipse ? ', ellipse' : ''})';
}

/// 🔷 Shape Recognizer — pure geometric analysis of freehand strokes.
///
/// SUPPORTED SHAPES:
/// - Line, Arrow
/// - Circle / Ellipse
/// - Triangle, Rectangle, Diamond
/// - Pentagon, Hexagon
/// - Star (5-pointed)
///
/// DESIGN PRINCIPLES:
/// - Stateless: all methods are static, no allocations persist between calls
/// - Zero Flutter widget dependencies (only dart:math + Offset/Rect)
/// - Fast: O(N) algorithms, runs in < 1ms for typical strokes (< 200 points)
class ShapeRecognizer {
  ShapeRecognizer._(); // Prevent instantiation

  // ============================================================================
  // 🎯 PUBLIC API
  // ============================================================================

  /// Analyze a list of freehand [points] and return a recognition result.
  ///
  /// [sensitivity] controls how strict the matching is.
  /// Returns a result with [type] == null if no shape is recognized.
  static ShapeRecognitionResult recognize(
    List<Offset> points, {
    ShapeRecognitionSensitivity sensitivity =
        ShapeRecognitionSensitivity.medium,
  }) {
    final threshold = sensitivity.threshold;
    return _recognize(points, threshold: threshold);
  }

  /// Low-level recognition with explicit threshold (for testing).
  static ShapeRecognitionResult _recognize(
    List<Offset> points, {
    double threshold = 0.7,
  }) {
    if (points.length < 5) {
      return ShapeRecognitionResult(
        confidence: 0.0,
        boundingBox: _computeBounds(points),
      );
    }

    // Pre-smoothing: 3-point moving average to reduce hand tremor
    final smoothed = _smooth(points);

    // Subsample to keep processing fast
    final sampled = _subsample(smoothed, 64);
    final bounds = _computeBounds(sampled);

    // Minimum size check — ignore tiny gestures (< 40px longest side)
    // Keeps handwriting strokes from entering shape pipeline at all
    if (bounds.longestSide < 40) {
      return ShapeRecognitionResult(confidence: 0.0, boundingBox: bounds);
    }

    // ── 1. ARROW test (before line — arrows are also straight-ish) ──
    final arrowConfidence = _testArrow(sampled, bounds);
    if (arrowConfidence >= threshold) {
      return ShapeRecognitionResult(
        type: ShapeType.arrow,
        confidence: arrowConfidence,
        boundingBox: bounds,
      );
    }

    // ── 2. LINE test (open paths) ──
    final lineConfidence = _testLine(sampled, bounds);
    if (lineConfidence >= threshold) {
      return ShapeRecognitionResult(
        type: ShapeType.line,
        confidence: lineConfidence,
        boundingBox: bounds,
      );
    }

    // For closed shapes, require minimum shortestSide
    if (bounds.shortestSide < 10) {
      return ShapeRecognitionResult(confidence: 0.0, boundingBox: bounds);
    }

    // ── 3. CLOSURE test — all remaining shapes require a closed path ──
    final closureRatio = _closureRatio(sampled, bounds);
    if (closureRatio > 0.30) {
      return ShapeRecognitionResult(confidence: 0.0, boundingBox: bounds);
    }

    // ── 4. STAR test (before circle — stars also have a centroid) ──
    final starConfidence = _testStar(sampled, bounds);
    if (starConfidence >= threshold) {
      return ShapeRecognitionResult(
        type: ShapeType.star,
        confidence: starConfidence,
        boundingBox: bounds,
      );
    }

    // ── 5. POLYGON test (RDP) — run BEFORE circle to prevent hexagons
    //       from being misclassified as circles ──
    final simplified = _rdpSimplify(sampled, bounds.longestSide * 0.08);
    final vertexCount = simplified.length;

    // Triangle (3 vertices)
    if (vertexCount == 3) {
      final triConfidence = _testTriangle(sampled, simplified, bounds);
      if (triConfidence >= threshold) {
        return ShapeRecognitionResult(
          type: ShapeType.triangle,
          confidence: triConfidence,
          boundingBox: bounds,
        );
      }
    }

    // Rectangle or Diamond (4 vertices)
    if (vertexCount == 4) {
      final rectConfidence = _testRectangle(simplified);
      if (rectConfidence >= threshold) {
        return ShapeRecognitionResult(
          type: ShapeType.rectangle,
          confidence: rectConfidence,
          boundingBox: bounds,
        );
      }

      final diamondConfidence = _testDiamond(simplified, bounds);
      if (diamondConfidence >= threshold) {
        return ShapeRecognitionResult(
          type: ShapeType.diamond,
          confidence: diamondConfidence,
          boundingBox: bounds,
        );
      }
    }

    // Rotated rectangle (4 vertices that don't match axis-aligned)
    if (vertexCount == 4) {
      final rotResult = _testRotatedRectangle(simplified, sampled, bounds);
      if (rotResult != null && rotResult.confidence >= threshold) {
        return rotResult;
      }
    }

    // Pentagon (5 vertices)
    if (vertexCount == 5) {
      final pentConfidence = _testRegularPolygon(
        sampled,
        simplified,
        bounds,
        5,
      );
      if (pentConfidence >= threshold) {
        return ShapeRecognitionResult(
          type: ShapeType.pentagon,
          confidence: pentConfidence,
          boundingBox: bounds,
        );
      }
    }

    // Hexagon (6 vertices)
    if (vertexCount == 6) {
      final hexConfidence = _testRegularPolygon(sampled, simplified, bounds, 6);
      if (hexConfidence >= threshold) {
        return ShapeRecognitionResult(
          type: ShapeType.hexagon,
          confidence: hexConfidence,
          boundingBox: bounds,
        );
      }
    }

    // ── 6. CIRCLE / ELLIPSE (fallback — only if no polygon matched) ──
    final circleResult = _testCircleOrEllipse(sampled, bounds);
    if (circleResult.confidence >= threshold) {
      return circleResult;
    }

    // No shape recognized
    return ShapeRecognitionResult(confidence: 0.0, boundingBox: bounds);
  }

  // ============================================================================
  // 🔍 SHAPE TESTS
  // ============================================================================

  /// Test if the stroke is a straight line.
  static double _testLine(List<Offset> points, Rect bounds) {
    final directDistance = (points.last - points.first).distance;
    final pathLength = _pathLength(points);
    if (pathLength < 1e-6) return 0.0;

    final straightness = directDistance / pathLength;

    // Must be reasonably long (relative to bounding box)
    if (directDistance < bounds.longestSide * 0.5) return 0.0;

    // 🛡️ MINIMUM ABSOLUTE LENGTH — prevent short handwriting strokes
    // (e.g. letter 'i', 'l', accents, diacritics) from triggering line
    // recognition. Typical handwriting strokes are 20-60px; a deliberate
    // geometric line is significantly longer.
    if (directDistance < 80.0) return 0.0;

    // Map straightness [0.93, 1.0] → confidence [0.0, 1.0]
    // Raised from 0.90 to reduce false positives from natural writing
    if (straightness < 0.93) return 0.0;
    return ((straightness - 0.93) / 0.07).clamp(0.0, 1.0);
  }

  /// Test if the stroke is an arrow (straight stem + V-shaped head).
  ///
  /// Detects patterns where the last ~20% of the stroke deviates from the
  /// main direction, forming a V-tip characteristic of hand-drawn arrows.
  static double _testArrow(List<Offset> points, Rect bounds) {
    if (points.length < 10) return 0.0;

    final directDistance = (points.last - points.first).distance;
    final pathLength = _pathLength(points);
    if (pathLength < 1e-6 || directDistance < bounds.longestSide * 0.3) {
      return 0.0;
    }

    // The stem should be mostly straight (first ~75% of points)
    final stemEnd = (points.length * 0.75).round();
    final stemPoints = points.sublist(0, stemEnd);
    final stemDirect = (stemPoints.last - stemPoints.first).distance;
    final stemPath = _pathLength(stemPoints);
    if (stemPath < 1e-6) return 0.0;
    final stemStraightness = stemDirect / stemPath;
    if (stemStraightness < 0.85) return 0.0;

    // The head (last ~25%) should deviate significantly from stem direction
    final stemDir = Offset(
      stemPoints.last.dx - stemPoints.first.dx,
      stemPoints.last.dy - stemPoints.first.dy,
    );
    final stemDirNorm = stemDir / stemDir.distance;

    // Check that the endpoint returns near the stem line (V-shape)
    final headPoints = points.sublist(stemEnd);
    if (headPoints.length < 3) return 0.0;

    // The head path should be significantly longer than its direct distance
    // (indicating a V-turn)
    final headDirect = (headPoints.last - headPoints.first).distance;
    final headPath = _pathLength(headPoints);
    if (headPath < 1e-6) return 0.0;
    final headCurvature = headPath / (headDirect + 1e-6);

    // A V-shape has curvature > 1.3 (path is longer due to the turn)
    if (headCurvature < 1.3) return 0.0;

    // The overall path should not be too curved
    final overallStraightness = directDistance / pathLength;
    if (overallStraightness > 0.95) return 0.0; // Too straight → it's a line

    // Calculate angle between stem direction and head direction
    final headDir = Offset(
      headPoints.last.dx - headPoints.first.dx,
      headPoints.last.dy - headPoints.first.dy,
    );
    if (headDir.distance < 1e-6) return 0.0;

    final dotProduct =
        stemDirNorm.dx * headDir.dx / headDir.distance +
        stemDirNorm.dy * headDir.dy / headDir.distance;
    // The head should go roughly backwards (dot product < 0.3)
    if (dotProduct > 0.3) return 0.0;

    // Compose confidence from stem straightness and head curvature
    final conf =
        (stemStraightness - 0.85) / 0.15 * 0.5 +
        ((headCurvature - 1.3) / 1.0).clamp(0.0, 0.5);
    return conf.clamp(0.0, 1.0);
  }

  /// Test if the stroke forms a circle or ellipse.
  ///
  /// Returns a result with [isEllipse] = true if the shape is more oval than
  /// circular (aspect ratio deviates > 15% from 1.0).
  static ShapeRecognitionResult _testCircleOrEllipse(
    List<Offset> points,
    Rect bounds,
  ) {
    final center = _centroid(points);
    final meanR = _meanRadius(points, center);
    if (meanR < 1e-6) {
      return ShapeRecognitionResult(confidence: 0.0, boundingBox: bounds);
    }

    // Compute coefficient of variation
    double sumSqDiff = 0.0;
    for (final p in points) {
      final r = (p - center).distance;
      sumSqDiff += (r - meanR) * (r - meanR);
    }
    final cv = sqrt(sumSqDiff / points.length) / meanR;

    // Aspect ratio analysis
    final aspectRatio = bounds.width / bounds.height;
    final isEllipse = aspectRatio < 0.85 || aspectRatio > 1.18;

    // For ellipses, we use an ellipse-aware deviation check instead of CV
    double confidence;
    if (isEllipse) {
      // Fit an ellipse: semi-axes = bounds.width/2, bounds.height/2
      final cx = bounds.center.dx;
      final cy = bounds.center.dy;
      final rx = bounds.width / 2;
      final ry = bounds.height / 2;
      if (rx < 1e-6 || ry < 1e-6) {
        return ShapeRecognitionResult(confidence: 0.0, boundingBox: bounds);
      }

      // Average normalized distance from ellipse boundary
      double totalDev = 0.0;
      for (final p in points) {
        final nx = (p.dx - cx) / rx;
        final ny = (p.dy - cy) / ry;
        final ellipseDist = (sqrt(nx * nx + ny * ny) - 1.0).abs();
        totalDev += ellipseDist;
      }
      final avgDev = totalDev / points.length;

      // Map avgDev [0.0, 0.20] → confidence [1.0, 0.0]
      if (avgDev > 0.20) {
        return ShapeRecognitionResult(confidence: 0.0, boundingBox: bounds);
      }
      confidence = (1.0 - avgDev / 0.20).clamp(0.0, 1.0);

      // Reject extreme aspect ratios (> 3:1)
      if (aspectRatio < 0.33 || aspectRatio > 3.0) {
        return ShapeRecognitionResult(confidence: 0.0, boundingBox: bounds);
      }
    } else {
      // Standard circle test
      if (cv > 0.20) {
        return ShapeRecognitionResult(confidence: 0.0, boundingBox: bounds);
      }
      confidence = (1.0 - cv / 0.20).clamp(0.0, 1.0);
    }

    // Build bounding box
    final shapeBounds =
        isEllipse
            ? bounds
            : Rect.fromCenter(
              center: center,
              width: meanR * 2,
              height: meanR * 2,
            );

    return ShapeRecognitionResult(
      type: ShapeType.circle,
      confidence: confidence,
      boundingBox: shapeBounds,
      isEllipse: isEllipse,
    );
  }

  /// Test for star shape.
  ///
  /// Stars have alternating inner/outer radii when measured from
  /// the centroid. We detect this by looking for a bimodal radius
  /// distribution with roughly 5 peaks and 5 valleys.
  static double _testStar(List<Offset> points, Rect bounds) {
    final center = _centroid(points);
    final meanR = _meanRadius(points, center);
    if (meanR < 1e-6) return 0.0;

    // Compute radii and find local maxima/minima
    final radii = points.map((p) => (p - center).distance).toList();

    int peaks = 0;
    int valleys = 0;
    // Use smoothed peaks detection (skip first/last)
    for (int i = 2; i < radii.length - 2; i++) {
      final avg =
          (radii[i - 2] +
              radii[i - 1] +
              radii[i] +
              radii[i + 1] +
              radii[i + 2]) /
          5;
      if (radii[i] > avg * 1.08) {
        // Check if it's a local maximum
        if (radii[i] > radii[i - 1] && radii[i] > radii[i + 1]) {
          peaks++;
        }
      } else if (radii[i] < avg * 0.92) {
        if (radii[i] < radii[i - 1] && radii[i] < radii[i + 1]) {
          valleys++;
        }
      }
    }

    // A 5-pointed star should have 5 peaks and 5 valleys (±1)
    if (peaks < 4 || peaks > 6 || valleys < 4 || valleys > 6) return 0.0;

    // Check that the radius variation is significant (> 20% of mean)
    final maxR = radii.reduce(max);
    final minR = radii.reduce(min);
    final variation = (maxR - minR) / meanR;
    if (variation < 0.25) return 0.0;

    // Compute confidence based on peak count accuracy and variation magnitude
    final peakAccuracy = 1.0 - (peaks - 5).abs() / 2.0;
    final valleyAccuracy = 1.0 - (valleys - 5).abs() / 2.0;
    final variationScore = (variation - 0.25).clamp(0.0, 0.5) / 0.5;

    return ((peakAccuracy + valleyAccuracy) / 2 * 0.6 + variationScore * 0.4)
        .clamp(0.0, 1.0);
  }

  /// Test for triangle (3-vertex polygon).
  static double _testTriangle(
    List<Offset> allPoints,
    List<Offset> vertices,
    Rect bounds,
  ) {
    if (vertices.length != 3) return 0.0;

    final triArea = _triangleArea(vertices[0], vertices[1], vertices[2]);
    final boxArea = bounds.width * bounds.height;
    if (boxArea < 1e-6) return 0.0;
    if (triArea / boxArea < 0.10) return 0.0;

    final avgDeviation = _averageDeviationFromPolygon(allPoints, vertices);
    final diagLength = bounds.longestSide;
    if (diagLength < 1e-6) return 0.0;
    final deviationRatio = avgDeviation / diagLength;

    if (deviationRatio > 0.15) return 0.0;
    return (1.0 - deviationRatio / 0.15).clamp(0.0, 1.0);
  }

  /// Test for rectangle (4-vertex polygon with ~90° angles).
  static double _testRectangle(List<Offset> vertices) {
    if (vertices.length != 4) return 0.0;

    double maxAngleError = 0.0;
    for (int i = 0; i < 4; i++) {
      final prev = vertices[(i + 3) % 4];
      final curr = vertices[i];
      final next = vertices[(i + 1) % 4];
      final angle = _angleBetween(prev, curr, next);
      final error = (angle - pi / 2).abs();
      if (error > maxAngleError) maxAngleError = error;
    }

    if (maxAngleError > 0.44) return 0.0;
    return (1.0 - (maxAngleError / 0.44) * 0.5).clamp(0.0, 1.0);
  }

  /// Test for diamond / rhombus (4-vertex polygon with equal sides).
  static double _testDiamond(List<Offset> vertices, Rect bounds) {
    if (vertices.length != 4) return 0.0;

    final sides = <double>[];
    for (int i = 0; i < 4; i++) {
      sides.add((vertices[(i + 1) % 4] - vertices[i]).distance);
    }

    final meanSide = sides.reduce((a, b) => a + b) / 4.0;
    if (meanSide < 1e-6) return 0.0;

    double maxSideError = 0.0;
    for (final s in sides) {
      final error = (s - meanSide).abs() / meanSide;
      if (error > maxSideError) maxSideError = error;
    }
    if (maxSideError > 0.30) return 0.0;

    // Must NOT be a rectangle
    bool hasNonRightAngle = false;
    for (int i = 0; i < 4; i++) {
      final prev = vertices[(i + 3) % 4];
      final curr = vertices[i];
      final next = vertices[(i + 1) % 4];
      final angle = _angleBetween(prev, curr, next);
      if ((angle - pi / 2).abs() > 0.25) {
        hasNonRightAngle = true;
        break;
      }
    }
    if (!hasNonRightAngle) return 0.0;

    return (1.0 - maxSideError / 0.30).clamp(0.0, 1.0) * 0.9;
  }

  /// Test for regular polygon (pentagon = 5, hexagon = 6).
  ///
  /// Checks that all sides are roughly equal length and all interior
  /// angles are roughly equal.
  static double _testRegularPolygon(
    List<Offset> allPoints,
    List<Offset> vertices,
    Rect bounds,
    int expectedSides,
  ) {
    if (vertices.length != expectedSides) return 0.0;

    // Check side length consistency
    final sides = <double>[];
    for (int i = 0; i < expectedSides; i++) {
      sides.add((vertices[(i + 1) % expectedSides] - vertices[i]).distance);
    }
    final meanSide = sides.reduce((a, b) => a + b) / expectedSides;
    if (meanSide < 1e-6) return 0.0;

    double maxSideError = 0.0;
    for (final s in sides) {
      final error = (s - meanSide).abs() / meanSide;
      if (error > maxSideError) maxSideError = error;
    }
    if (maxSideError > 0.40) return 0.0;

    // Check angle consistency
    final expectedAngle = (expectedSides - 2) * pi / expectedSides;
    double maxAngleError = 0.0;
    for (int i = 0; i < expectedSides; i++) {
      final prev = vertices[(i + expectedSides - 1) % expectedSides];
      final curr = vertices[i];
      final next = vertices[(i + 1) % expectedSides];
      final angle = _angleBetween(prev, curr, next);
      final error = (angle - expectedAngle).abs();
      if (error > maxAngleError) maxAngleError = error;
    }
    if (maxAngleError > 0.50) return 0.0;

    // Check deviation from polygon edges
    final avgDev = _averageDeviationFromPolygon(allPoints, vertices);
    final devRatio = avgDev / bounds.longestSide;
    if (devRatio > 0.15) return 0.0;

    // Compose confidence
    final sideScore = (1.0 - maxSideError / 0.40).clamp(0.0, 1.0);
    final angleScore = (1.0 - maxAngleError / 0.50).clamp(0.0, 1.0);
    final devScore = (1.0 - devRatio / 0.15).clamp(0.0, 1.0);

    return (sideScore * 0.3 + angleScore * 0.4 + devScore * 0.3).clamp(
      0.0,
      1.0,
    );
  }

  // ============================================================================
  // 📐 GEOMETRY HELPERS
  // ============================================================================

  /// Ratio of start↔end gap to bounding box diagonal.
  static double _closureRatio(List<Offset> points, Rect bounds) {
    final gap = (points.last - points.first).distance;
    final diag = sqrt(
      bounds.width * bounds.width + bounds.height * bounds.height,
    );
    if (diag < 1e-6) return 1.0;
    return gap / diag;
  }

  /// Total path length of the polyline.
  static double _pathLength(List<Offset> points) {
    double len = 0.0;
    for (int i = 1; i < points.length; i++) {
      len += (points[i] - points[i - 1]).distance;
    }
    return len;
  }

  /// Centroid (average position) of points.
  static Offset _centroid(List<Offset> points) {
    double x = 0, y = 0;
    for (final p in points) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / points.length, y / points.length);
  }

  /// Mean radius from [center] to all [points].
  static double _meanRadius(List<Offset> points, Offset center) {
    double sum = 0;
    for (final p in points) {
      sum += (p - center).distance;
    }
    return sum / points.length;
  }

  /// Area of a triangle defined by three vertices.
  static double _triangleArea(Offset a, Offset b, Offset c) {
    return ((b.dx - a.dx) * (c.dy - a.dy) - (c.dx - a.dx) * (b.dy - a.dy))
            .abs() /
        2;
  }

  /// Angle (in radians) at vertex [curr] formed by vectors curr→prev and curr→next.
  static double _angleBetween(Offset prev, Offset curr, Offset next) {
    final v1 = prev - curr;
    final v2 = next - curr;
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final cross = v1.dx * v2.dy - v1.dy * v2.dx;
    return atan2(cross.abs(), dot);
  }

  /// Average perpendicular deviation of [points] from polygon edges.
  static double _averageDeviationFromPolygon(
    List<Offset> points,
    List<Offset> polygon,
  ) {
    double totalDev = 0;
    for (final p in points) {
      double minDist = double.infinity;
      for (int i = 0; i < polygon.length; i++) {
        final a = polygon[i];
        final b = polygon[(i + 1) % polygon.length];
        final dist = _pointToSegmentDistance(p, a, b);
        if (dist < minDist) minDist = dist;
      }
      totalDev += minDist;
    }
    return totalDev / points.length;
  }

  /// Shortest distance from point [p] to line segment [a]→[b].
  static double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLenSq < 1e-10) return (p - a).distance;

    double t = (ap.dx * ab.dx + ap.dy * ab.dy) / abLenSq;
    t = t.clamp(0.0, 1.0);

    final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - proj).distance;
  }

  /// Compute axis-aligned bounding box.
  static Rect _computeBounds(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // ============================================================================
  // 🔧 PREPROCESSING
  // ============================================================================

  /// 3-point moving average to reduce hand tremor noise.
  /// Preserves first and last points for accurate bounding.
  static List<Offset> _smooth(List<Offset> points) {
    if (points.length < 3) return points;

    final result = <Offset>[points.first];
    for (int i = 1; i < points.length - 1; i++) {
      result.add(
        Offset(
          (points[i - 1].dx + points[i].dx + points[i + 1].dx) / 3,
          (points[i - 1].dy + points[i].dy + points[i + 1].dy) / 3,
        ),
      );
    }
    result.add(points.last);
    return result;
  }

  /// Detect a rotated rectangle that doesn't align with axes.
  ///
  /// Uses the oriented bounding box approach: project points onto the
  /// principal axis (first edge direction) and check if the 4-vertex
  /// shape has ~90° angles and reasonable side ratios.
  static ShapeRecognitionResult? _testRotatedRectangle(
    List<Offset> vertices,
    List<Offset> allPoints,
    Rect bounds,
  ) {
    if (vertices.length != 4) return null;

    // Check angles — all should be ~90°
    double maxAngleError = 0.0;
    for (int i = 0; i < 4; i++) {
      final prev = vertices[(i + 3) % 4];
      final curr = vertices[i];
      final next = vertices[(i + 1) % 4];
      final angle = _angleBetween(prev, curr, next);
      final error = (angle - pi / 2).abs();
      if (error > maxAngleError) maxAngleError = error;
    }

    // More relaxed than axis-aligned rectangle — up to ~35°
    if (maxAngleError > 0.60) return null;

    // Check that sides come in pairs (opposite sides ≈ equal)
    final sides = <double>[];
    for (int i = 0; i < 4; i++) {
      sides.add((vertices[(i + 1) % 4] - vertices[i]).distance);
    }
    final pairError1 = (sides[0] - sides[2]).abs() / (sides[0] + 1e-6);
    final pairError2 = (sides[1] - sides[3]).abs() / (sides[1] + 1e-6);
    if (pairError1 > 0.30 || pairError2 > 0.30) return null;

    // Calculate rotation angle from the first edge
    final edge = vertices[1] - vertices[0];
    double rotation = atan2(edge.dy, edge.dx);

    // Normalize to [-π/4, π/4] — snap to nearest axis direction
    while (rotation > pi / 4) {
      rotation -= pi / 2;
    }
    while (rotation < -pi / 4) {
      rotation += pi / 2;
    }

    // If rotation is tiny, it's an axis-aligned rectangle (already handled)
    if (rotation.abs() < 0.10) return null;

    // Confidence from angle accuracy and side-pair consistency
    final confidence =
        (1.0 - (maxAngleError / 0.60) * 0.5).clamp(0.0, 1.0) *
        (1.0 - (pairError1 + pairError2) / 2).clamp(0.0, 1.0);

    if (confidence < 0.5) return null;

    return ShapeRecognitionResult(
      type: ShapeType.rectangle,
      confidence: confidence,
      boundingBox: bounds,
      rotationAngle: rotation,
    );
  }

  /// Subsample [points] to at most [maxCount] points.
  static List<Offset> _subsample(List<Offset> points, int maxCount) {
    if (points.length <= maxCount) return points;

    final result = <Offset>[points.first];
    final step = (points.length - 1) / (maxCount - 1);
    for (int i = 1; i < maxCount - 1; i++) {
      result.add(points[(i * step).round()]);
    }
    result.add(points.last);
    return result;
  }

  /// Ramer-Douglas-Peucker polyline simplification.
  static List<Offset> _rdpSimplify(List<Offset> points, double epsilon) {
    if (points.length < 3) return List.of(points);

    final closed = List<Offset>.from(points);
    if ((closed.first - closed.last).distance > epsilon) {
      closed.add(closed.first);
    }

    final keep = List.filled(closed.length, false);
    keep[0] = true;
    keep[closed.length - 1] = true;

    _rdpRecurse(closed, 0, closed.length - 1, epsilon, keep);

    final result = <Offset>[];
    for (int i = 0; i < closed.length; i++) {
      if (keep[i]) result.add(closed[i]);
    }

    if (result.length > 1 && (result.first - result.last).distance < epsilon) {
      result.removeLast();
    }

    return result;
  }

  static void _rdpRecurse(
    List<Offset> points,
    int start,
    int end,
    double epsilon,
    List<bool> keep,
  ) {
    if (end - start < 2) return;

    double maxDist = 0;
    int maxIndex = start;

    for (int i = start + 1; i < end; i++) {
      final d = _pointToSegmentDistance(points[i], points[start], points[end]);
      if (d > maxDist) {
        maxDist = d;
        maxIndex = i;
      }
    }

    if (maxDist > epsilon) {
      keep[maxIndex] = true;
      _rdpRecurse(points, start, maxIndex, epsilon, keep);
      _rdpRecurse(points, maxIndex, end, epsilon, keep);
    }
  }
}
