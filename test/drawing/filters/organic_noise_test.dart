import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/drawing/filters/organic_noise.dart';

void main() {
  group('OrganicNoise.simplexNoise2D', () {
    test('returns value in [-1, 1]', () {
      for (double x = -10; x <= 10; x += 0.7) {
        for (double y = -10; y <= 10; y += 0.7) {
          final v = OrganicNoise.simplexNoise2D(x, y);
          expect(v, greaterThanOrEqualTo(-1.0));
          expect(v, lessThanOrEqualTo(1.0));
        }
      }
    });

    test('is deterministic', () {
      final a = OrganicNoise.simplexNoise2D(3.14, 2.71);
      final b = OrganicNoise.simplexNoise2D(3.14, 2.71);
      expect(a, equals(b));
    });

    test('varies with input', () {
      final a = OrganicNoise.simplexNoise2D(0.0, 0.0);
      final b = OrganicNoise.simplexNoise2D(1.0, 1.0);
      final c = OrganicNoise.simplexNoise2D(2.0, 2.0);
      // Not all the same
      expect(a == b && b == c, isFalse);
    });

    test('has spatial coherence (nearby values are similar)', () {
      // Two very close points should have similar values
      final a = OrganicNoise.simplexNoise2D(5.0, 5.0);
      final b = OrganicNoise.simplexNoise2D(5.001, 5.001);
      expect((a - b).abs(), lessThan(0.1));
    });
  });

  group('OrganicNoise.fbm', () {
    test('returns approximately in [-1, 1]', () {
      for (double x = -5; x <= 5; x += 1.3) {
        for (double y = -5; y <= 5; y += 1.3) {
          final v = OrganicNoise.fbm(x, y, octaves: 4);
          expect(v, greaterThanOrEqualTo(-1.5)); // fbm can slightly exceed
          expect(v, lessThanOrEqualTo(1.5));
        }
      }
    });

    test('more octaves produce more detail', () {
      // Higher octaves shouldn't change the macro shape much
      final low = OrganicNoise.fbm(3.0, 3.0, octaves: 1);
      final high = OrganicNoise.fbm(3.0, 3.0, octaves: 6);
      // They should differ (extra detail) but not wildly
      expect((low - high).abs(), lessThan(1.0));
    });
  });

  group('OrganicNoise.biologicalTremor', () {
    test('higher velocity reduces tremor amplitude', () {
      final tremSlow = OrganicNoise.biologicalTremor(50.0, 0.0);
      final tremFast = OrganicNoise.biologicalTremor(50.0, 800.0);
      // At the same arc length, fast velocity should have smaller absolute value
      expect(tremFast.abs(), lessThanOrEqualTo(tremSlow.abs() + 0.01));
    });

    test('returns value in [-1, 1]', () {
      for (double arc = 0; arc < 500; arc += 10) {
        final v = OrganicNoise.biologicalTremor(arc, 200.0, seed: 42.0);
        expect(v, greaterThanOrEqualTo(-1.0));
        expect(v, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('OrganicNoise.fatigueFactor', () {
    test('returns 1.0 below 200 points', () {
      expect(OrganicNoise.fatigueFactor(0), 1.0);
      expect(OrganicNoise.fatigueFactor(100), 1.0);
      expect(OrganicNoise.fatigueFactor(199), 1.0);
    });

    test('increases after 200 points', () {
      expect(OrganicNoise.fatigueFactor(300), greaterThan(1.0));
      expect(OrganicNoise.fatigueFactor(500), closeTo(1.3, 0.01));
    });

    test('plateaus at 1.3', () {
      expect(OrganicNoise.fatigueFactor(1000), closeTo(1.3, 0.01));
    });
  });

  group('OrganicNoise.breathingModulation', () {
    test('returns value in [-1, 1]', () {
      for (double arc = 0; arc < 2000; arc += 50) {
        final v = OrganicNoise.breathingModulation(arc);
        expect(v, greaterThanOrEqualTo(-1.0));
        expect(v, lessThanOrEqualTo(1.0));
      }
    });

    test('oscillates with period ~1000px', () {
      // Half period should be approximately opposite sign
      final a = OrganicNoise.breathingModulation(0.0);
      final b = OrganicNoise.breathingModulation(500.0);
      // b should be roughly at the peak/trough relative to a
      expect((a - b).abs(), greaterThan(0.5));
    });
  });
}
