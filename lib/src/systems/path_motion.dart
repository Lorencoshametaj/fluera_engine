/// 🛤️ PATH MOTION — Animate nodes along Bézier paths.
///
/// Evaluates position and angle along a motion path defined by
/// cubic Bézier segments, with arc-length parameterization for
/// constant-speed motion.
///
/// ```dart
/// final path = MotionPath(segments: [
///   MotionSegment.cubic(p0, p1, p2, p3),
/// ]);
/// final pos = path.evaluate(0.5); // position at 50%
/// final angle = path.evaluateAngle(0.5); // tangent angle
/// ```
library;

import 'dart:math' as math;
import 'dart:ui';

/// A single cubic Bézier segment in a motion path.
class MotionSegment {
  final Offset p0;
  final Offset p1;
  final Offset p2;
  final Offset p3;

  const MotionSegment({
    required this.p0,
    required this.p1,
    required this.p2,
    required this.p3,
  });

  /// Create a cubic Bézier segment.
  const MotionSegment.cubic(this.p0, this.p1, this.p2, this.p3);

  /// Create a linear segment (control points on the line).
  factory MotionSegment.linear(Offset start, Offset end) {
    final third = (end - start) / 3;
    return MotionSegment(
      p0: start,
      p1: start + third,
      p2: start + third * 2,
      p3: end,
    );
  }

  /// Evaluate position at parameter t (0..1).
  Offset evaluate(double t) {
    final u = 1.0 - t;
    return p0 * (u * u * u) +
        p1 * (3 * u * u * t) +
        p2 * (3 * u * t * t) +
        p3 * (t * t * t);
  }

  /// Evaluate tangent (first derivative) at parameter t.
  Offset tangent(double t) {
    final u = 1.0 - t;
    return (p1 - p0) * (3 * u * u) +
        (p2 - p1) * (6 * u * t) +
        (p3 - p2) * (3 * t * t);
  }

  /// Approximate arc length using subdivision.
  double arcLength({int subdivisions = 64}) {
    double length = 0;
    Offset prev = p0;
    for (int i = 1; i <= subdivisions; i++) {
      final t = i / subdivisions;
      final current = evaluate(t);
      length += (current - prev).distance;
      prev = current;
    }
    return length;
  }

  Map<String, dynamic> toJson() => {
    'p0': [p0.dx, p0.dy],
    'p1': [p1.dx, p1.dy],
    'p2': [p2.dx, p2.dy],
    'p3': [p3.dx, p3.dy],
  };

  factory MotionSegment.fromJson(Map<String, dynamic> json) {
    Offset parseOffset(List<dynamic> arr) =>
        Offset((arr[0] as num).toDouble(), (arr[1] as num).toDouble());
    return MotionSegment(
      p0: parseOffset(json['p0'] as List<dynamic>),
      p1: parseOffset(json['p1'] as List<dynamic>),
      p2: parseOffset(json['p2'] as List<dynamic>),
      p3: parseOffset(json['p3'] as List<dynamic>),
    );
  }
}

/// A complete motion path made of connected Bézier segments.
class MotionPath {
  final List<MotionSegment> segments;

  /// Cached arc lengths per segment (lazy computed).
  List<double>? _segmentLengths;
  double? _totalLength;

  MotionPath({required this.segments});

  /// Total arc length of the path.
  double get totalLength {
    _ensureLengths();
    return _totalLength!;
  }

  /// Evaluate position at normalized time t (0..1) with arc-length
  /// parameterization for constant-speed motion.
  Offset evaluate(double t) {
    if (segments.isEmpty) return Offset.zero;
    if (t <= 0) return segments.first.p0;
    if (t >= 1) return segments.last.p3;

    _ensureLengths();
    final targetLength = t * _totalLength!;
    return _evaluateAtLength(targetLength);
  }

  /// Evaluate the tangent angle (in radians) at normalized time t.
  double evaluateAngle(double t) {
    if (segments.isEmpty) return 0;
    final clamped = t.clamp(0.0, 1.0);

    _ensureLengths();
    final targetLength = clamped * _totalLength!;
    final result = _segmentAndLocalT(targetLength);
    final tangent = segments[result.segmentIndex].tangent(result.localT);
    return math.atan2(tangent.dy, tangent.dx);
  }

  /// Evaluate angle in degrees.
  double evaluateAngleDegrees(double t) => evaluateAngle(t) * 180 / math.pi;

  void _ensureLengths() {
    if (_segmentLengths != null) return;
    final lengths = segments.map((s) => s.arcLength()).toList();
    _segmentLengths = lengths;
    _totalLength = lengths.fold<double>(0.0, (a, b) => a + b);
  }

  Offset _evaluateAtLength(double targetLength) {
    final result = _segmentAndLocalT(targetLength);
    return segments[result.segmentIndex].evaluate(result.localT);
  }

  _SegmentResult _segmentAndLocalT(double targetLength) {
    double accumulated = 0;
    for (int i = 0; i < segments.length; i++) {
      final segLen = _segmentLengths![i];
      if (accumulated + segLen >= targetLength || i == segments.length - 1) {
        final localLength = targetLength - accumulated;
        final localT =
            segLen > 0 ? (localLength / segLen).clamp(0.0, 1.0) : 0.0;
        return _SegmentResult(i, localT);
      }
      accumulated += segLen;
    }
    return _SegmentResult(segments.length - 1, 1.0);
  }

  Map<String, dynamic> toJson() => {
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  factory MotionPath.fromJson(Map<String, dynamic> json) => MotionPath(
    segments:
        (json['segments'] as List<dynamic>)
            .map((s) => MotionSegment.fromJson(s as Map<String, dynamic>))
            .toList(),
  );
}

class _SegmentResult {
  final int segmentIndex;
  final double localT;
  const _SegmentResult(this.segmentIndex, this.localT);
}
