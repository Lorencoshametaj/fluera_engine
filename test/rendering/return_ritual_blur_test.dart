// Pure unit test for [ReturnRitualBlurController.intensityFromDays].
// No widget tree, no animation — verifies the piecewise lerp matches
// the pedagogical curve documented in §1047-1062 of the theory doc:
// 1d → 0.07 / 3d → 0.20 / 7d → 0.35 / 14+d → 0.50.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/rendering/canvas/return_ritual_blur_painter.dart';

void main() {
  group('ReturnRitualBlurController.intensityFromDays', () {
    test('returns 0.0 for same-day / negative gap (no ritual)', () {
      expect(ReturnRitualBlurController.intensityFromDays(0), 0.0);
      expect(ReturnRitualBlurController.intensityFromDays(-5), 0.0);
    });

    test('exact anchor points match the documented curve', () {
      expect(ReturnRitualBlurController.intensityFromDays(1), closeTo(0.07, 1e-6));
      expect(ReturnRitualBlurController.intensityFromDays(3), closeTo(0.20, 1e-6));
      expect(ReturnRitualBlurController.intensityFromDays(7), closeTo(0.35, 1e-6));
      expect(ReturnRitualBlurController.intensityFromDays(14), closeTo(0.50, 1e-6));
    });

    test('caps at 0.50 for very long gaps', () {
      expect(ReturnRitualBlurController.intensityFromDays(30), 0.50);
      expect(ReturnRitualBlurController.intensityFromDays(365), 0.50);
    });

    test('monotone non-decreasing across the range', () {
      double last = -1;
      for (var d = 0; d <= 20; d++) {
        final v = ReturnRitualBlurController.intensityFromDays(d);
        expect(v, greaterThanOrEqualTo(last));
        last = v;
      }
    });

    test('intermediate values are interpolated, not jumpy', () {
      // Day 2 sits between 0.07 and 0.20.
      final d2 = ReturnRitualBlurController.intensityFromDays(2);
      expect(d2, greaterThan(0.07));
      expect(d2, lessThan(0.20));
      // Day 5 sits between 0.20 and 0.35.
      final d5 = ReturnRitualBlurController.intensityFromDays(5);
      expect(d5, greaterThan(0.20));
      expect(d5, lessThan(0.35));
      // Day 10 sits between 0.35 and 0.50.
      final d10 = ReturnRitualBlurController.intensityFromDays(10);
      expect(d10, greaterThan(0.35));
      expect(d10, lessThan(0.50));
    });
  });
}
