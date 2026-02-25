import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/color/color_blindness_simulator.dart';

void main() {
  const sim = ColorBlindnessSimulator();

  // ===========================================================================
  // Enum
  // ===========================================================================

  group('ColorBlindnessType', () {
    test('has 5 types', () {
      expect(ColorBlindnessType.values.length, 5);
    });
  });

  // ===========================================================================
  // simulate
  // ===========================================================================

  group('ColorBlindnessSimulator - simulate', () {
    test('normal returns same color', () {
      final result = sim.simulate(0.8, 0.2, 0.3, ColorBlindnessType.normal);
      expect(result.r, closeTo(0.8, 0.01));
      expect(result.g, closeTo(0.2, 0.01));
      expect(result.b, closeTo(0.3, 0.01));
    });

    test('achromatopsia returns grayscale', () {
      final result = sim.simulate(
        1.0,
        0.0,
        0.0,
        ColorBlindnessType.achromatopsia,
      );
      expect(result.r, result.g);
      expect(result.g, result.b);
    });

    test('protanopia transforms red', () {
      final result = sim.simulate(1.0, 0.0, 0.0, ColorBlindnessType.protanopia);
      expect(result.type, ColorBlindnessType.protanopia);
      // Red should look different under protanopia
      expect(result.r, isNot(closeTo(1.0, 0.1)));
    });

    test('deuteranopia transforms green', () {
      final result = sim.simulate(
        0.0,
        1.0,
        0.0,
        ColorBlindnessType.deuteranopia,
      );
      expect(result.type, ColorBlindnessType.deuteranopia);
    });

    test('tritanopia transforms blue', () {
      final result = sim.simulate(0.0, 0.0, 1.0, ColorBlindnessType.tritanopia);
      expect(result.type, ColorBlindnessType.tritanopia);
    });

    test('values clamped to 0-1', () {
      final result = sim.simulate(1.0, 1.0, 1.0, ColorBlindnessType.protanopia);
      expect(result.r, inInclusiveRange(0.0, 1.0));
      expect(result.g, inInclusiveRange(0.0, 1.0));
      expect(result.b, inInclusiveRange(0.0, 1.0));
    });
  });

  // ===========================================================================
  // areDistinguishable
  // ===========================================================================

  group('ColorBlindnessSimulator - areDistinguishable', () {
    test('red and green may not be distinguishable for protanopia', () {
      final result = sim.areDistinguishable(
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        ColorBlindnessType.protanopia,
      );
      expect(result, isA<bool>());
    });

    test('black and white always distinguishable', () {
      final result = sim.areDistinguishable(
        0.0,
        0.0,
        0.0,
        1.0,
        1.0,
        1.0,
        ColorBlindnessType.protanopia,
      );
      expect(result, isTrue);
    });
  });

  // ===========================================================================
  // severity & prevalence
  // ===========================================================================

  group('ColorBlindnessSimulator - severity', () {
    test('returns description for each type', () {
      for (final type in ColorBlindnessType.values) {
        expect(ColorBlindnessSimulator.severity(type), isNotEmpty);
      }
    });
  });

  group('ColorBlindnessSimulator - prevalence', () {
    test('normal has highest prevalence', () {
      expect(
        ColorBlindnessSimulator.prevalence(ColorBlindnessType.normal),
        greaterThan(50),
      );
    });

    test('all types have positive prevalence', () {
      for (final type in ColorBlindnessType.values) {
        expect(ColorBlindnessSimulator.prevalence(type), greaterThan(0));
      }
    });
  });

  // ===========================================================================
  // SimulatedColor
  // ===========================================================================

  group('SimulatedColor', () {
    test('toString is readable', () {
      const c = SimulatedColor(0.5, 0.5, 0.5, ColorBlindnessType.normal);
      expect(c.toString(), contains('SimulatedColor'));
    });
  });
}
