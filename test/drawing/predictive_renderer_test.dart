import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/drawing/filters/predictive_renderer.dart';

void main() {
  // ===========================================================================
  // PredictiveRenderer
  // ===========================================================================

  group('PredictiveRenderer', () {
    late PredictiveRenderer predictor;

    setUp(() {
      predictor = PredictiveRenderer(
        predictedPointsCount: 3,
        ghostOpacity: 0.1,
        velocityDecay: 0.8,
      );
    });

    // ── Empty state ───────────────────────────────────────────────────

    test('returns empty predictions with no history', () {
      expect(predictor.predictNextPoints(), isEmpty);
      expect(predictor.predictWithPressure(), isEmpty);
      expect(predictor.canPredict, isFalse);
    });

    test('returns empty predictions with fewer than 3 points', () {
      predictor.addPoint(const Offset(0, 0), 0, pressure: 0.5);
      predictor.addPoint(const Offset(10, 0), 16000, pressure: 0.6);
      expect(predictor.predictNextPoints(), isEmpty);
      expect(predictor.canPredict, isFalse);
    });

    // ── Linear motion ────────────────────────────────────────────────

    test('predicts forward on linear horizontal motion', () {
      // 3 points moving right at constant speed
      predictor.addPoint(const Offset(0, 0), 0, pressure: 0.5);
      predictor.addPoint(const Offset(100, 0), 16000, pressure: 0.5);
      predictor.addPoint(const Offset(200, 0), 32000, pressure: 0.5);

      expect(predictor.canPredict, isTrue);

      final predicted = predictor.predictNextPoints();
      expect(predicted, hasLength(3));

      // All predicted points should be to the RIGHT of the last point
      for (final p in predicted) {
        expect(p.dx, greaterThan(200.0));
      }

      // Predicted points should be monotonically increasing X
      // (velocity decay slows them down but still moving right)
      for (int i = 1; i < predicted.length; i++) {
        expect(predicted[i].dx, greaterThan(predicted[i - 1].dx));
      }
    });

    test('predicts forward on linear vertical motion', () {
      predictor.addPoint(const Offset(0, 0), 0, pressure: 0.5);
      predictor.addPoint(const Offset(0, 50), 16000, pressure: 0.5);
      predictor.addPoint(const Offset(0, 100), 32000, pressure: 0.5);

      final predicted = predictor.predictNextPoints();
      expect(predicted, hasLength(3));

      for (final p in predicted) {
        expect(p.dy, greaterThan(100.0));
        // X should stay near 0 (no horizontal motion)
        expect(p.dx.abs(), lessThan(5.0));
      }
    });

    // ── Pressure prediction ─────────────────────────────────────────

    test('predicts increasing pressure from increasing trend', () {
      predictor.addPoint(const Offset(0, 0), 0, pressure: 0.3);
      predictor.addPoint(const Offset(10, 0), 16000, pressure: 0.5);
      predictor.addPoint(const Offset(20, 0), 32000, pressure: 0.7);

      final predicted = predictor.predictWithPressure();
      expect(predicted, hasLength(3));

      // Pressure should extrapolate upward (clamped to 1.0)
      expect(predicted[0].pressure, greaterThan(0.7));
      expect(predicted[0].pressure, lessThanOrEqualTo(1.0));
    });

    test('predicts decreasing pressure from decreasing trend', () {
      predictor.addPoint(const Offset(0, 0), 0, pressure: 0.9);
      predictor.addPoint(const Offset(10, 0), 16000, pressure: 0.7);
      predictor.addPoint(const Offset(20, 0), 32000, pressure: 0.5);

      final predicted = predictor.predictWithPressure();
      expect(predicted, hasLength(3));

      // Pressure should extrapolate downward (clamped to 0.1)
      expect(predicted[0].pressure, lessThan(0.5));
      expect(predicted[0].pressure, greaterThanOrEqualTo(0.1));
    });

    // ── Reset ────────────────────────────────────────────────────────

    test('reset clears all state', () {
      predictor.addPoint(const Offset(0, 0), 0, pressure: 0.5);
      predictor.addPoint(const Offset(10, 0), 16000, pressure: 0.5);
      predictor.addPoint(const Offset(20, 0), 32000, pressure: 0.5);

      predictor.reset();

      expect(predictor.canPredict, isFalse);
      expect(predictor.predictNextPoints(), isEmpty);
      expect(predictor.getCurrentSpeed(), equals(0.0));
    });

    // ── Stationary points ────────────────────────────────────────────

    test('returns empty predictions when stationary', () {
      predictor.addPoint(const Offset(100, 100), 0, pressure: 0.5);
      predictor.addPoint(const Offset(100, 100), 16000, pressure: 0.5);
      predictor.addPoint(const Offset(100, 100), 32000, pressure: 0.5);

      final predicted = predictor.predictNextPoints();
      expect(predicted, isEmpty); // velocity < threshold
    });

    // ── Velocity decay ───────────────────────────────────────────────

    test('predicted points decelerate due to velocity decay', () {
      predictor.addPoint(const Offset(0, 0), 0, pressure: 0.5);
      predictor.addPoint(const Offset(100, 0), 16000, pressure: 0.5);
      predictor.addPoint(const Offset(200, 0), 32000, pressure: 0.5);

      final predicted = predictor.predictNextPoints();
      expect(predicted.length, equals(3));

      // Gap between consecutive predicted points should decrease (deceleration)
      final gap1 = predicted[0].dx - 200;
      final gap2 = predicted[1].dx - predicted[0].dx;
      final gap3 = predicted[2].dx - predicted[1].dx;

      expect(gap2, lessThan(gap1));
      expect(gap3, lessThan(gap2));
    });

    // ── Speed / Direction ────────────────────────────────────────────

    test('getCurrentSpeed returns positive for moving points', () {
      predictor.addPoint(const Offset(0, 0), 0, pressure: 0.5);
      predictor.addPoint(const Offset(100, 0), 16000, pressure: 0.5);
      predictor.addPoint(const Offset(200, 0), 32000, pressure: 0.5);

      expect(predictor.getCurrentSpeed(), greaterThan(0));
    });

    test('getDirection returns unit vector for moving points', () {
      predictor.addPoint(const Offset(0, 0), 0, pressure: 0.5);
      predictor.addPoint(const Offset(100, 0), 16000, pressure: 0.5);

      final dir = predictor.getDirection();
      expect(dir.dx, closeTo(1.0, 0.01));
      expect(dir.dy, closeTo(0.0, 0.01));
    });
  });
}
