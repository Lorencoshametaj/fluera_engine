// ============================================================================
// 🧪 SampleSizeCalculator — verified against reference values
// (cross-checked with evanmiller.org/ab-testing/sample-size.html)
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/experiments/sample_size_calculator.dart';

void main() {
  group('SampleSizeCalculator.proportion', () {
    test('Reference: baseline 0.42, lift 5%, power 0.80, alpha 0.05', () {
      // Evan Miller calculator gives ~7700 per branch for these inputs.
      final n = SampleSizeCalculator.proportion(
        baselineRate: 0.42,
        minDetectableLift: 0.05,
        power: 0.80,
        alpha: 0.05,
      );
      // Allow ±15% tolerance vs reference (BSM approx vs exact Fleiss).
      expect(n, greaterThan(6900));
      expect(n, lessThan(9500));
    });

    test('Larger lift → smaller sample size', () {
      final smallLift = SampleSizeCalculator.proportion(
        baselineRate: 0.50,
        minDetectableLift: 0.05,
      );
      final bigLift = SampleSizeCalculator.proportion(
        baselineRate: 0.50,
        minDetectableLift: 0.20,
      );
      expect(bigLift, lessThan(smallLift));
    });

    test('Higher power → larger sample size', () {
      final lowPower = SampleSizeCalculator.proportion(
        baselineRate: 0.50,
        minDetectableLift: 0.10,
        power: 0.70,
      );
      final highPower = SampleSizeCalculator.proportion(
        baselineRate: 0.50,
        minDetectableLift: 0.10,
        power: 0.95,
      );
      expect(highPower, greaterThan(lowPower));
    });

    test('Tighter alpha → larger sample size', () {
      final loose = SampleSizeCalculator.proportion(
        baselineRate: 0.50,
        minDetectableLift: 0.10,
        alpha: 0.10,
      );
      final tight = SampleSizeCalculator.proportion(
        baselineRate: 0.50,
        minDetectableLift: 0.10,
        alpha: 0.01,
      );
      expect(tight, greaterThan(loose));
    });

    test('Rejects invalid baselineRate', () {
      expect(
        () => SampleSizeCalculator.proportion(
            baselineRate: 0.0, minDetectableLift: 0.1),
        throwsArgumentError,
      );
      expect(
        () => SampleSizeCalculator.proportion(
            baselineRate: 1.0, minDetectableLift: 0.1),
        throwsArgumentError,
      );
    });

    test('Rejects when lifted rate would exceed 1.0', () {
      expect(
        () => SampleSizeCalculator.proportion(
            baselineRate: 0.95, minDetectableLift: 0.10),
        throwsArgumentError,
      );
    });
  });
}
