import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/path_motion.dart';
import 'dart:ui';
import 'dart:math' as math;

void main() {
  group('PathMotion Tests', () {
    test('MotionSegment.linear evaluates correctly', () {
      final segment = MotionSegment.linear(
        const Offset(0, 0),
        const Offset(100, 100),
      );

      expect(segment.p0, const Offset(0, 0));
      expect(segment.p3, const Offset(100, 100));

      expect(segment.evaluate(0.0), const Offset(0, 0));
      expect(segment.evaluate(0.5).dx, closeTo(50.0, 0.01));
      expect(segment.evaluate(0.5).dy, closeTo(50.0, 0.01));
      expect(segment.evaluate(1.0), const Offset(100, 100));

      expect(segment.arcLength(), closeTo(141.42, 0.1)); // sqrt(100^2 + 100^2)
    });

    test('MotionPath.evaluate maintains constant speed (arc length)', () {
      // Create a path with two segments of vastly different conceptual lengths,
      // but parameterized as uniform segments (0..1 locally).
      // If we ask for t=0.5, we should be at exactly 50% of the total DISTANCE,
      // not just the boundary between segment 0 and segment 1.
      final path = MotionPath(
        segments: [
          MotionSegment.linear(
            const Offset(0, 0),
            const Offset(100, 0),
          ), // length 100
          MotionSegment.linear(
            const Offset(100, 0),
            const Offset(400, 0),
          ), // length 300
        ],
      );

      expect(path.totalLength, closeTo(400, 0.1));

      // t=0.25 -> length 100 -> exactly end of segment 1
      final p25 = path.evaluate(0.25);
      expect(p25.dx, closeTo(100.0, 0.1));

      // t=0.5 -> length 200 -> 1/3 into segment 2 -> dx=200
      final p50 = path.evaluate(0.5);
      expect(p50.dx, closeTo(200.0, 0.1));

      // t=0.75 -> length 300 -> 2/3 into segment 2 -> dx=300
      final p75 = path.evaluate(0.75);
      expect(p75.dx, closeTo(300.0, 0.1));
    });

    test('MotionPath.evaluateAngle returns correct tangent angle', () {
      final path = MotionPath(
        segments: [
          MotionSegment.linear(
            const Offset(0, 0),
            const Offset(100, 0),
          ), // Right (0 deg)
          MotionSegment.linear(
            const Offset(100, 0),
            const Offset(100, 100),
          ), // Down (90 deg)
          MotionSegment.linear(
            const Offset(100, 100),
            const Offset(0, 100),
          ), // Left (180 deg)
        ],
      );

      // Segment 1 (Right): t=0.1
      expect(path.evaluateAngleDegrees(0.1), closeTo(0.0, 0.1));

      // Segment 2 (Down): t=0.5
      expect(path.evaluateAngleDegrees(0.5), closeTo(90.0, 0.1));

      // Segment 3 (Left): t=0.9
      final angle3 = path.evaluateAngleDegrees(0.9);
      // Depending on atan2 it's 180 or -180
      expect(angle3.abs(), closeTo(180.0, 0.1));
    });

    test('Serialization roundtrip', () {
      final segment = MotionSegment.cubic(
        const Offset(0, 0),
        const Offset(10, 20),
        const Offset(30, -5),
        const Offset(100, 100),
      );

      final json = segment.toJson();
      expect(json['p1'][0], 10);
      expect(json['p2'][1], -5);

      final restored = MotionSegment.fromJson(json);
      expect(restored.p0, const Offset(0, 0));
      expect(restored.p1, const Offset(10, 20));
      expect(restored.p2, const Offset(30, -5));
      expect(restored.p3, const Offset(100, 100));
    });
  });
}
