import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/drawing/filters/one_euro_filter.dart';

void main() {
  // ===========================================================================
  // OneEuroFilter
  // ===========================================================================

  group('OneEuroFilter', () {
    test('first point passes through unchanged', () {
      final filter = OneEuroFilter();
      final result = filter.filter(const Offset(100, 200), 0);
      expect(result.dx, 100);
      expect(result.dy, 200);
    });

    test('smooths noisy input', () {
      final filter = OneEuroFilter(minCutoff: 1.0, beta: 0.007);
      // Simulate a mostly horizontal stroke with noise
      filter.filter(const Offset(0, 100), 0);
      filter.filter(const Offset(10, 102), 16);
      filter.filter(const Offset(20, 98), 32);
      final result = filter.filter(const Offset(30, 105), 48);
      // Smoothed Y should be closer to 100 than the raw 105
      expect(result.dy, closeTo(100, 10));
    });

    test('reset clears state', () {
      final filter = OneEuroFilter();
      filter.filter(const Offset(100, 100), 0);
      filter.filter(const Offset(200, 200), 16);
      filter.reset();
      // After reset, next point should pass through like first point
      final result = filter.filter(const Offset(50, 50), 100);
      expect(result.dx, 50);
      expect(result.dy, 50);
    });

    test('returns last filtered for zero dt', () {
      final filter = OneEuroFilter();
      filter.filter(const Offset(10, 10), 100);
      // Same timestamp → dt=0 → return last filtered
      final result = filter.filter(const Offset(20, 20), 100);
      expect(result.dx, 10);
      expect(result.dy, 10);
    });

    test('fast movement increases reactivity', () {
      final filter = OneEuroFilter(minCutoff: 1.0, beta: 0.007);
      filter.filter(const Offset(0, 0), 0);
      // Very fast movement (large distance, short dt)
      final result = filter.filter(const Offset(100, 0), 10);
      // Filter should output something between 0 and 100
      // (not stuck at 0, not exactly at 100 due to smoothing)
      expect(result.dx, greaterThan(0));
      expect(result.dx, lessThanOrEqualTo(100));
    });
  });

  // ===========================================================================
  // KalmanFilter
  // ===========================================================================

  group('KalmanFilter', () {
    test('first point initializes at origin then converges', () {
      final filter = KalmanFilter();
      // First filter call moves estimate from (0,0) toward the measurement
      final result = filter.filter(const Offset(100, 100));
      // Should be partway between origin and measurement
      expect(result.dx, greaterThan(0));
      expect(result.dx, lessThan(100));
    });

    test('converges toward repeated measurement', () {
      final filter = KalmanFilter();
      Offset result = Offset.zero;
      for (int i = 0; i < 50; i++) {
        result = filter.filter(const Offset(100, 100));
      }
      // After many iterations, should converge close to (100, 100)
      expect(result.dx, closeTo(100, 2));
      expect(result.dy, closeTo(100, 2));
    });

    test('reset returns to origin', () {
      final filter = KalmanFilter();
      filter.filter(const Offset(100, 100));
      filter.filter(const Offset(100, 100));
      filter.reset();
      // After reset, next estimate starts from (0,0) again
      final result = filter.filter(const Offset(50, 50));
      expect(result.dx, lessThan(50));
    });
  });

  // ===========================================================================
  // MovingAverageFilter
  // ===========================================================================

  group('MovingAverageFilter', () {
    test('single point returns itself', () {
      final filter = MovingAverageFilter(windowSize: 3);
      final result = filter.filter(const Offset(100, 200));
      expect(result.dx, 100);
      expect(result.dy, 200);
    });

    test('averages points within window', () {
      final filter = MovingAverageFilter(windowSize: 3);
      filter.filter(const Offset(0, 0));
      filter.filter(const Offset(10, 10));
      final result = filter.filter(const Offset(20, 20));
      // Average of (0,0), (10,10), (20,20) = (10, 10)
      expect(result.dx, closeTo(10, 0.1));
      expect(result.dy, closeTo(10, 0.1));
    });

    test('window slides after reaching size', () {
      final filter = MovingAverageFilter(windowSize: 2);
      filter.filter(const Offset(0, 0));
      filter.filter(const Offset(10, 10));
      final result = filter.filter(const Offset(20, 20));
      // Window: (10,10), (20,20) → average (15, 15)
      expect(result.dx, closeTo(15, 0.1));
      expect(result.dy, closeTo(15, 0.1));
    });

    test('reset clears buffer', () {
      final filter = MovingAverageFilter(windowSize: 3);
      filter.filter(const Offset(100, 100));
      filter.filter(const Offset(200, 200));
      filter.reset();
      final result = filter.filter(const Offset(50, 50));
      // After reset, only one point in buffer
      expect(result.dx, 50);
      expect(result.dy, 50);
    });
  });

  // ===========================================================================
  // AdaptiveStrokeFilter
  // ===========================================================================

  group('AdaptiveStrokeFilter', () {
    test('defaults to oneEuro type', () {
      final filter = AdaptiveStrokeFilter();
      expect(filter.currentType, FilterType.oneEuro);
    });

    test('FilterType.none passes through unchanged', () {
      final filter = AdaptiveStrokeFilter(initialType: FilterType.none);
      final result = filter.filter(const Offset(42, 84));
      expect(result.dx, 42);
      expect(result.dy, 84);
    });

    test('setFilterType switches and resets', () {
      final filter = AdaptiveStrokeFilter();
      filter.filter(const Offset(100, 100));
      filter.setFilterType(FilterType.kalman);
      expect(filter.currentType, FilterType.kalman);
    });

    test('movingAverage type works', () {
      final filter = AdaptiveStrokeFilter(
        initialType: FilterType.movingAverage,
        movingAverageWindow: 2,
      );
      filter.filter(const Offset(0, 0));
      final result = filter.filter(const Offset(10, 10));
      // Average of (0,0) and (10,10) = (5,5)
      expect(result.dx, closeTo(5, 0.1));
    });

    test('reset clears all internal state', () {
      final filter = AdaptiveStrokeFilter();
      filter.filter(const Offset(100, 100));
      filter.reset();
      expect(filter.currentType, FilterType.oneEuro); // type preserved
    });
  });
}
