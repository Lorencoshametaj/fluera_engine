import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/tools/scratch_out/scratch_out_detector.dart';
import 'package:fluera_engine/src/drawing/models/pro_drawing_point.dart';

void main() {
  group('ScratchOutDetector', () {
    /// Helper: Generate a horizontal zigzag pattern.
    /// Creates points that zigzag up and down along the x axis.
    /// Uses fast timestamps (3ms intervals) to exceed speed threshold (1.5 px/ms).
    List<ProDrawingPoint> _makeHorizontalZigzag({
      int zigzags = 6,
      double width = 200.0,
      double height = 40.0,
      int pointsPerSeg = 8,
      int msPerPoint = 3,
    }) {
      final points = <ProDrawingPoint>[];
      final totalSegs = zigzags * 2;
      final segWidth = width / totalSegs;
      int ts = 1000;

      for (int seg = 0; seg <= totalSegs; seg++) {
        final x = seg * segWidth;
        final y = (seg % 2 == 0) ? 0.0 : height;

        if (seg == 0) {
          points.add(ProDrawingPoint(
            position: Offset(x, y),
            pressure: 1.0,
            timestamp: ts,
          ));
        } else {
          // Interpolate from previous point
          final prev = points.last.position;
          for (int i = 1; i <= pointsPerSeg; i++) {
            final t = i / pointsPerSeg;
            ts += msPerPoint;
            points.add(ProDrawingPoint(
              position: Offset(
                prev.dx + (x - prev.dx) * t,
                prev.dy + (y - prev.dy) * t,
              ),
              pressure: 1.0,
              timestamp: ts,
            ));
          }
        }
      }
      return points;
    }

    /// Helper: Generate a vertical zigzag pattern.
    List<ProDrawingPoint> _makeVerticalZigzag({
      int zigzags = 6,
      double width = 40.0,
      double height = 200.0,
      int pointsPerSeg = 8,
      int msPerPoint = 3,
    }) {
      final points = <ProDrawingPoint>[];
      final totalSegs = zigzags * 2;
      final segHeight = height / totalSegs;
      int ts = 1000;

      for (int seg = 0; seg <= totalSegs; seg++) {
        final y = seg * segHeight;
        final x = (seg % 2 == 0) ? 0.0 : width;

        if (seg == 0) {
          points.add(ProDrawingPoint(
            position: Offset(x, y),
            pressure: 1.0,
            timestamp: ts,
          ));
        } else {
          final prev = points.last.position;
          for (int i = 1; i <= pointsPerSeg; i++) {
            final t = i / pointsPerSeg;
            ts += msPerPoint;
            points.add(ProDrawingPoint(
              position: Offset(
                prev.dx + (x - prev.dx) * t,
                prev.dy + (y - prev.dy) * t,
              ),
              pressure: 1.0,
              timestamp: ts,
            ));
          }
        }
      }
      return points;
    }

    /// Helper: Generate a straight line.
    List<ProDrawingPoint> _makeStraightLine({
      Offset from = const Offset(0, 0),
      Offset to = const Offset(200, 0),
      int pointCount = 30,
    }) {
      final points = <ProDrawingPoint>[];
      int ts = 1000;
      for (int i = 0; i < pointCount; i++) {
        final t = i / (pointCount - 1);
        ts += 10;
        points.add(ProDrawingPoint(
          position: Offset.lerp(from, to, t)!,
          pressure: 1.0,
          timestamp: ts,
        ));
      }
      return points;
    }

    /// Helper: Generate a circle.
    List<ProDrawingPoint> _makeCircle({
      double radius = 60.0,
      Offset center = const Offset(100, 100),
      int pointCount = 40,
    }) {
      final points = <ProDrawingPoint>[];
      int ts = 1000;
      for (int i = 0; i < pointCount; i++) {
        final angle = (i / pointCount) * math.pi * 2;
        ts += 15;
        points.add(ProDrawingPoint(
          position: Offset(
            center.dx + radius * math.cos(angle),
            center.dy + radius * math.sin(angle),
          ),
          pressure: 1.0,
          timestamp: ts,
        ));
      }
      return points;
    }

    test('recognizes horizontal zigzag', () {
      final points = _makeHorizontalZigzag(zigzags: 6);
      final result = ScratchOutDetector.analyze(points);

      expect(result.recognized, isTrue);
      expect(result.reversalCount, greaterThanOrEqualTo(6));
      expect(result.confidence, greaterThan(0.0));
      expect(result.scratchBounds, isNot(Rect.zero));
    });

    test('recognizes vertical zigzag', () {
      final points = _makeVerticalZigzag(zigzags: 6);
      final result = ScratchOutDetector.analyze(points);

      expect(result.recognized, isTrue);
      expect(result.reversalCount, greaterThanOrEqualTo(6));
    });

    test('rejects straight line (no reversals)', () {
      final points = _makeStraightLine();
      final result = ScratchOutDetector.analyze(points);

      expect(result.recognized, isFalse);
      expect(result.reversalCount, equals(0));
    });

    test('rejects circle (aspect ratio ~1:1)', () {
      final points = _makeCircle();
      final result = ScratchOutDetector.analyze(points);

      expect(result.recognized, isFalse);
    });

    test('rejects too few reversals (2 zigzags only)', () {
      // 2 zigzags = 3 reversals < minimum 6
      final points = _makeHorizontalZigzag(zigzags: 2, pointsPerSeg: 10);
      final result = ScratchOutDetector.analyze(points);

      expect(result.recognized, isFalse);
    });

    test('rejects too few points', () {
      // Only 5 points — way below minimum 15
      final points = List.generate(
        5,
        (i) => ProDrawingPoint(
          position: Offset(i * 10.0, 0),
          pressure: 1.0,
          timestamp: 1000 + i * 10,
        ),
      );
      final result = ScratchOutDetector.analyze(points);

      expect(result.recognized, isFalse);
    });

    test('rejects slow gesture (> 2s)', () {
      // Make a zigzag but with 3000ms duration (> maxDurationMs)
      final points = _makeHorizontalZigzag(zigzags: 6);
      // Override timestamps to be very spread out
      final slowPoints = <ProDrawingPoint>[];
      for (int i = 0; i < points.length; i++) {
        slowPoints.add(ProDrawingPoint(
          position: points[i].position,
          pressure: points[i].pressure,
          // Spread over 3 seconds (> maxDurationMs = 2000)
          timestamp: 1000 + (i * 3000 ~/ points.length),
        ));
      }
      final result = ScratchOutDetector.analyze(slowPoints);

      expect(result.recognized, isFalse);
    });

    test('scratchBounds covers the zigzag area', () {
      final points = _makeHorizontalZigzag(
        zigzags: 6,
        width: 200,
        height: 40,
      );
      final result = ScratchOutDetector.analyze(points);

      if (result.recognized) {
        // Bounds should be at least as wide as the zigzag
        expect(result.scratchBounds.width, greaterThanOrEqualTo(190.0));
        // Bounds should be inflated by 5px
        expect(result.scratchBounds.left, lessThanOrEqualTo(0.0));
      }
    });

    test('ScratchOutResult.notRecognized has all defaults', () {
      const result = ScratchOutResult.notRecognized;
      expect(result.recognized, isFalse);
      expect(result.scratchBounds, Rect.zero);
      expect(result.reversalCount, 0);
      expect(result.confidence, 0.0);
    });

    test('recognizes diagonal zigzag (45° angle via PCA)', () {
      // Generate a zigzag along a 45° diagonal
      final points = <ProDrawingPoint>[];
      int ts = 1000;
      const zigzags = 6;
      const totalSegs = zigzags * 2;
      const segLen = 25.0;

      for (int seg = 0; seg <= totalSegs; seg++) {
        // Diagonal advance: move along (1,1) direction
        final along = seg * segLen;
        // Perpendicular oscillation: alternate ±20px on (-1,1) axis
        final perpOffset = (seg % 2 == 0) ? -20.0 : 20.0;
        final x = along / math.sqrt(2) + perpOffset / math.sqrt(2);
        final y = along / math.sqrt(2) - perpOffset / math.sqrt(2);

        if (seg == 0) {
          points.add(ProDrawingPoint(
            position: Offset(x, y),
            pressure: 1.0,
            timestamp: ts,
          ));
        } else {
          final prev = points.last.position;
          for (int i = 1; i <= 8; i++) {
            final t = i / 8.0;
            ts += 3; // Fast timestamps to exceed speed threshold
            points.add(ProDrawingPoint(
              position: Offset(
                prev.dx + (x - prev.dx) * t,
                prev.dy + (y - prev.dy) * t,
              ),
              pressure: 1.0,
              timestamp: ts,
            ));
          }
        }
      }

      final result = ScratchOutDetector.analyze(points);
      expect(result.recognized, isTrue);
      expect(result.reversalCount, greaterThanOrEqualTo(6));
    });

    test('analyzePartial accepts with lower thresholds', () {
      // 3 zigzags = ~5 reversals, which is below full threshold's
      // confidence but above partial's minReversalsPartial = 3
      final points = _makeHorizontalZigzag(zigzags: 3, pointsPerSeg: 8);
      
      // Full analyze might reject (low confidence)
      final fullResult = ScratchOutDetector.analyze(points);
      // Partial should be more lenient
      final partialResult = ScratchOutDetector.analyzePartial(points);
      
      // Partial should recognize (>=4 reversals partial, no confidence gate)
      expect(partialResult.recognized, isTrue);
      expect(partialResult.reversalCount, greaterThanOrEqualTo(4));
    });

    test('rejects zoom-like gesture (small jittery movement)', () {
      // Simulate a finger doing a tiny zigzag during pinch-to-zoom:
      // small area (~30x10), few points, low amplitude
      final points = <ProDrawingPoint>[];
      int ts = 1000;
      for (int i = 0; i < 30; i++) {
        ts += 10;
        final x = i * 1.0; // 30px wide
        final y = (i % 2 == 0) ? 0.0 : 5.0; // 5px jitter
        points.add(ProDrawingPoint(
          position: Offset(x + 100, y + 100),
          pressure: 1.0,
          timestamp: ts,
        ));
      }
      final result = ScratchOutDetector.analyze(points);
      expect(result.recognized, isFalse,
        reason: 'Zoom jitter should NOT be recognized as scratch-out');
    });

    test('rejects small fast scribble (area < 2000px²)', () {
      // Small zigzag: 40x10 = 400px² < minBboxArea(2000)
      final points = _makeHorizontalZigzag(
        zigzags: 6,
        width: 40,
        height: 10,
        pointsPerSeg: 5,
      );
      final result = ScratchOutDetector.analyze(points);
      expect(result.recognized, isFalse,
        reason: 'Small bbox area should be rejected');
    });
  });
}
