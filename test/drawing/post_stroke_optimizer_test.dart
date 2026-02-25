import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/drawing/filters/post_stroke_optimizer.dart';

void main() {
  // ===========================================================================
  // PostStrokeOptimizer — basic
  // ===========================================================================

  group('PostStrokeOptimizer - basic', () {
    test('returns input for < 3 points', () {
      final optimizer = PostStrokeOptimizer();
      final singlePoint = [const Offset(0, 0)];
      expect(optimizer.optimize(singlePoint), singlePoint);

      final twoPoints = [const Offset(0, 0), const Offset(10, 10)];
      expect(optimizer.optimize(twoPoints), twoPoints);
    });

    test('reduces point count on noisy input', () {
      final optimizer = PostStrokeOptimizer(
        simplificationTolerance: 1.0,
        targetPointDistance: 5.0,
      );
      // Generate noisy horizontal line
      final points = <Offset>[];
      for (int i = 0; i < 100; i++) {
        points.add(Offset(i.toDouble(), (i % 2 == 0) ? 0.2 : -0.2));
      }
      final optimized = optimizer.optimize(points);
      // Should be significantly fewer points after simplification
      expect(optimized.length, lessThan(points.length));
      expect(optimized.length, greaterThan(2)); // But not trivially reduced
    });

    test('preserves start and end points', () {
      final optimizer = PostStrokeOptimizer();
      final points = <Offset>[];
      for (int i = 0; i < 20; i++) {
        points.add(Offset(i * 5.0, 0));
      }
      final optimized = optimizer.optimize(points);
      expect(optimized.first, points.first);
      expect(optimized.last, points.last);
    });
  });

  // ===========================================================================
  // PostStrokeOptimizer — calculatePathLength
  // ===========================================================================

  group('PostStrokeOptimizer - calculatePathLength', () {
    test('returns 0 for single point', () {
      final optimizer = PostStrokeOptimizer();
      expect(optimizer.calculatePathLength([const Offset(0, 0)]), 0);
    });

    test('returns correct length for horizontal line', () {
      final optimizer = PostStrokeOptimizer();
      final points = [const Offset(0, 0), const Offset(100, 0)];
      expect(optimizer.calculatePathLength(points), closeTo(100, 0.1));
    });

    test('returns correct length for multi-segment path', () {
      final optimizer = PostStrokeOptimizer();
      final points = [
        const Offset(0, 0),
        const Offset(3, 4), // distance 5 from origin
        const Offset(3, 14), // distance 10 from previous
      ];
      expect(optimizer.calculatePathLength(points), closeTo(15, 0.1));
    });
  });

  // ===========================================================================
  // PostStrokeOptimizer — calculateSmoothness
  // ===========================================================================

  group('PostStrokeOptimizer - calculateSmoothness', () {
    test('returns 0 for single/double points', () {
      final optimizer = PostStrokeOptimizer();
      expect(optimizer.calculateSmoothness([const Offset(0, 0)]), 0);
      expect(
        optimizer.calculateSmoothness([const Offset(0, 0), const Offset(1, 0)]),
        0,
      );
    });

    test('straight line has near-zero smoothness', () {
      final optimizer = PostStrokeOptimizer();
      final points = <Offset>[];
      for (int i = 0; i < 10; i++) {
        points.add(Offset(i * 10.0, 0));
      }
      final smoothness = optimizer.calculateSmoothness(points);
      expect(smoothness, closeTo(0, 0.01));
    });

    test('zigzag has high smoothness value', () {
      final optimizer = PostStrokeOptimizer();
      final points = <Offset>[];
      for (int i = 0; i < 10; i++) {
        points.add(Offset(i * 10.0, (i % 2 == 0) ? 0 : 20.0));
      }
      final smoothness = optimizer.calculateSmoothness(points);
      expect(smoothness, greaterThan(0.5));
    });
  });

  // ===========================================================================
  // PostStrokeOptimizer — smoothing disabled
  // ===========================================================================

  group('PostStrokeOptimizer - smoothing toggle', () {
    test('disabling smoothing still simplifies', () {
      final optimizer = PostStrokeOptimizer(
        enableFinalSmoothing: false,
        simplificationTolerance: 1.0,
        targetPointDistance: 5.0,
      );
      final points = <Offset>[];
      for (int i = 0; i < 50; i++) {
        points.add(Offset(i * 2.0, (i % 3 == 0) ? 0.3 : 0));
      }
      final optimized = optimizer.optimize(points);
      expect(optimized.length, lessThan(points.length));
    });
  });
}
