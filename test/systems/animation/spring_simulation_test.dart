import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/spring_simulation.dart';

void main() {
  group('SpringSimulation Tests', () {
    test('Config properties calculated correctly', () {
      const config = SpringConfig(
        mass: 1.0,
        stiffness: 100.0,
        damping: 20.0,
      ); // Critically damped
      expect(config.naturalFrequency, 10.0);
      expect(config.dampingRatio, 1.0);
      expect(config.isCriticallyDamped, isTrue);
      expect(config.isUnderdamped, isFalse);
      expect(config.isOverdamped, isFalse);

      const bouncy = SpringConfig.bouncy;
      expect(bouncy.isUnderdamped, isTrue);

      const heavy = SpringConfig.heavy;
      // heavy: mass=3, stiffness=100, damping=22 → ζ = 22/(2*√300) ≈ 0.635, underdamped
      expect(heavy.isUnderdamped, isTrue);

      // Create a truly overdamped config for testing
      const overdamped = SpringConfig(
        mass: 1.0,
        stiffness: 100.0,
        damping: 40.0,
      );
      expect(overdamped.isOverdamped, isTrue);
    });

    test('evaluate critically damped spring', () {
      final sim = SpringSimulation(config: SpringConfig.criticallyDamped);

      expect(sim.evaluate(0.0), 0.0);

      // Should asymptotically approach 1.0 without exceeding it
      for (double t = 0.1; t < 2.0; t += 0.1) {
        final val = sim.evaluate(t);
        expect(val, lessThanOrEqualTo(1.0001)); // Float precision
      }

      expect(sim.evaluate(2.0), closeTo(1.0, 0.01));
    });

    test('evaluate underdamped spring (bouncy)', () {
      final sim = SpringSimulation(config: SpringConfig.bouncy);

      expect(sim.evaluate(0.0), 0.0);

      // Should overshoot 1.0 at some point
      bool didOvershoot = false;
      for (double t = 0.1; t < 2.0; t += 0.05) {
        if (sim.evaluate(t) > 1.001) {
          didOvershoot = true;
          break;
        }
      }
      expect(didOvershoot, isTrue);

      // Eventually settles
      expect(sim.evaluate(5.0), closeTo(1.0, 0.01));
    });

    test('evaluate overdamped spring', () {
      final sim = SpringSimulation(
        config: const SpringConfig(mass: 1.0, stiffness: 100.0, damping: 40.0),
      );
      expect(sim.config.isOverdamped, isTrue);

      expect(sim.evaluate(0.0), 0.0);

      // Approaches 1.0 slowly without overshoot
      for (double t = 0.1; t < 2.0; t += 0.1) {
        expect(sim.evaluate(t), lessThan(1.0));
      }
    });

    test('velocity calculations', () {
      final sim = SpringSimulation(config: SpringConfig.criticallyDamped);

      expect(sim.velocity(0.0), 0.0);
      // Velocity should be positive initially
      expect(sim.velocity(0.1), greaterThan(0));
      // Velocity should approach 0 eventually
      expect(sim.velocity(2.0).abs(), lessThan(0.05));
    });

    test('settling calculation', () {
      final sim = SpringSimulation(config: SpringConfig.criticallyDamped);

      expect(sim.isSettled(0.0), isFalse);
      expect(sim.isSettled(5.0), isTrue);

      final stTime = sim.settlingTime(threshold: 0.01);
      expect(stTime, greaterThan(0));
      expect(stTime, lessThan(2.0));
    });

    test('serialization roundtrip', () {
      final config = const SpringConfig(
        mass: 2.0,
        stiffness: 150.0,
        damping: 12.0,
      );
      final json = config.toJson();

      final restored = SpringConfig.fromJson(json);
      expect(restored.mass, 2.0);
      expect(restored.stiffness, 150.0);
      expect(restored.damping, 12.0);
    });
  });
}
