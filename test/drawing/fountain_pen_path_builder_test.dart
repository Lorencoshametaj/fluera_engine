import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/drawing/brushes/fountain_pen_path_builder.dart';
import 'package:nebula_engine/src/drawing/brushes/fountain_pen_buffers.dart';

void main() {
  // =========================================================================
  // inkNoise
  // =========================================================================

  group('inkNoise', () {
    test('returns value in expected range [-0.03, +0.03]', () {
      for (int i = 0; i < 100; i++) {
        final noise = FountainPenPathBuilder.inkNoise(i, 1.0);
        expect(noise, greaterThanOrEqualTo(-0.04));
        expect(noise, lessThanOrEqualTo(0.04));
      }
    });

    test('is deterministic — same inputs give same output', () {
      final a = FountainPenPathBuilder.inkNoise(42, 3.14);
      final b = FountainPenPathBuilder.inkNoise(42, 3.14);
      expect(a, b);
    });

    test('varies with index', () {
      final a = FountainPenPathBuilder.inkNoise(0, 1.0);
      final b = FountainPenPathBuilder.inkNoise(1, 1.0);
      expect(a, isNot(b));
    });

    test('varies with seed', () {
      final a = FountainPenPathBuilder.inkNoise(10, 1.0);
      final b = FountainPenPathBuilder.inkNoise(10, 2.0);
      expect(a, isNot(b));
    });
  });

  // =========================================================================
  // Chaikin Subdivision
  // =========================================================================

  group('applyChaikinSubdivision', () {
    test('no-op for fewer than 3 points', () {
      final buf = StrokeOffsetBuffer();
      buf.reset(2);
      buf.add(const Offset(0, 0));
      buf.add(const Offset(10, 10));
      FountainPenPathBuilder.applyChaikinSubdivision(buf);
      expect(buf.length, 2); // unchanged
    });

    test('increases point count', () {
      final buf = StrokeOffsetBuffer();
      buf.reset(10);
      buf.add(const Offset(0, 0));
      buf.add(const Offset(10, 0));
      buf.add(const Offset(20, 10));
      buf.add(const Offset(30, 10));
      final originalLength = buf.length; // 4
      FountainPenPathBuilder.applyChaikinSubdivision(buf);
      expect(buf.length, greaterThan(originalLength));
    });

    test('preserves first and last points', () {
      final buf = StrokeOffsetBuffer();
      buf.reset(10);
      buf.add(const Offset(0, 0));
      buf.add(const Offset(10, 0));
      buf.add(const Offset(20, 10));
      FountainPenPathBuilder.applyChaikinSubdivision(buf);
      expect(buf[0], const Offset(0, 0));
      expect(buf[buf.length - 1], const Offset(20, 10));
    });

    test('subdivided points lie between originals', () {
      final buf = StrokeOffsetBuffer();
      buf.reset(10);
      buf.add(const Offset(0, 0));
      buf.add(const Offset(100, 0));
      buf.add(const Offset(200, 0));
      FountainPenPathBuilder.applyChaikinSubdivision(buf);
      // All x values should be between 0 and 200
      for (int i = 0; i < buf.length; i++) {
        expect(buf[i].dx, greaterThanOrEqualTo(0));
        expect(buf[i].dx, lessThanOrEqualTo(200));
      }
    });

    test('formula correctness: Q = 0.75*P0 + 0.25*P1', () {
      final buf = StrokeOffsetBuffer();
      buf.reset(10);
      buf.add(const Offset(0, 0));
      buf.add(const Offset(100, 0));
      buf.add(const Offset(200, 100));

      FountainPenPathBuilder.applyChaikinSubdivision(buf);
      // After first point (preserved: 0,0), next is Q = 0.75*(0,0) + 0.25*(100,0) = (25, 0)
      expect(buf[1].dx, closeTo(25, 0.01));
      expect(buf[1].dy, closeTo(0, 0.01));
      // R = 0.25*(0,0) + 0.75*(100,0) = (75, 0)
      expect(buf[2].dx, closeTo(75, 0.01));
      expect(buf[2].dy, closeTo(0, 0.01));
    });
  });

  // =========================================================================
  // Tangent Computation
  // =========================================================================

  group('computeSmoothedTangentsFromOffsets', () {
    test('produces one tangent per input point', () {
      final pts = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(20, 0),
        const Offset(30, 0),
        const Offset(40, 0),
      ];
      final buf = StrokeOffsetBuffer();
      FountainPenPathBuilder.computeSmoothedTangentsFromOffsets(pts, buf);
      expect(buf.length, pts.length);
    });

    test('tangents are unit vectors', () {
      final pts = [
        const Offset(0, 0),
        const Offset(10, 5),
        const Offset(20, 10),
        const Offset(30, 20),
        const Offset(40, 25),
      ];
      final buf = StrokeOffsetBuffer();
      FountainPenPathBuilder.computeSmoothedTangentsFromOffsets(pts, buf);
      for (int i = 0; i < buf.length; i++) {
        final len = buf[i].distance;
        expect(len, closeTo(1.0, 0.01));
      }
    });

    test('horizontal line produces horizontal tangents', () {
      final pts = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(20, 0),
        const Offset(30, 0),
        const Offset(40, 0),
      ];
      final buf = StrokeOffsetBuffer();
      FountainPenPathBuilder.computeSmoothedTangentsFromOffsets(pts, buf);
      for (int i = 0; i < buf.length; i++) {
        expect(buf[i].dx, closeTo(1.0, 0.01));
        expect(buf[i].dy, closeTo(0.0, 0.01));
      }
    });

    test('first tangent uses forward difference', () {
      final pts = [
        const Offset(0, 0),
        const Offset(0, 10), // straight up
        const Offset(0, 20),
      ];
      final buf = StrokeOffsetBuffer();
      FountainPenPathBuilder.computeSmoothedTangentsFromOffsets(pts, buf);
      // First tangent = pts[1] - pts[0] = (0,10), normalized = (0,1)
      expect(buf[0].dx, closeTo(0, 0.01));
      expect(buf[0].dy, closeTo(1.0, 0.01));
    });

    test('last tangent uses backward difference', () {
      final pts = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(20, 0),
      ];
      final buf = StrokeOffsetBuffer();
      FountainPenPathBuilder.computeSmoothedTangentsFromOffsets(pts, buf);
      // Last tangent = pts[2] - pts[1] = (10,0), normalized = (1,0)
      expect(buf[buf.length - 1].dx, closeTo(1.0, 0.01));
      expect(buf[buf.length - 1].dy, closeTo(0, 0.01));
    });
  });
}
