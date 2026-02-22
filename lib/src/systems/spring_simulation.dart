/// 🌊 SPRING SIMULATION — Physics-based spring animation curves.
///
/// Implements critically damped, underdamped, and overdamped spring dynamics
/// for natural-feeling animations.
///
/// ```dart
/// final spring = SpringSimulation(config: SpringConfig.bouncy);
/// final value = spring.evaluate(0.5); // value at t=0.5s
/// ```
library;

import 'dart:math' as math;

/// Spring physics configuration.
class SpringConfig {
  final double mass;
  final double stiffness;
  final double damping;

  const SpringConfig({
    this.mass = 1.0,
    this.stiffness = 100.0,
    this.damping = 10.0,
  });

  /// Damping ratio ζ = c / (2 * √(k * m)).
  double get dampingRatio => damping / (2 * math.sqrt(stiffness * mass));

  /// Natural frequency ω₀ = √(k / m).
  double get naturalFrequency => math.sqrt(stiffness / mass);

  /// Whether the spring is critically damped (ζ = 1).
  bool get isCriticallyDamped => (dampingRatio - 1.0).abs() < 0.001;

  /// Whether the spring is underdamped (ζ < 1, bouncy).
  bool get isUnderdamped => dampingRatio < 1.0;

  /// Whether the spring is overdamped (ζ > 1, sluggish).
  bool get isOverdamped => dampingRatio > 1.0;

  // Presets.

  /// Bouncy spring with visible oscillation.
  static const bouncy = SpringConfig(mass: 1.0, stiffness: 120.0, damping: 8.0);

  /// Gentle spring with minimal overshoot.
  static const gentle = SpringConfig(mass: 1.0, stiffness: 80.0, damping: 14.0);

  /// Snappy spring — fast with slight bounce.
  static const snappy = SpringConfig(
    mass: 1.0,
    stiffness: 300.0,
    damping: 20.0,
  );

  /// Critically damped — fastest without oscillation.
  static const criticallyDamped = SpringConfig(
    mass: 1.0,
    stiffness: 100.0,
    damping: 20.0,
  );

  /// Slow, heavy spring.
  static const heavy = SpringConfig(mass: 3.0, stiffness: 100.0, damping: 22.0);

  Map<String, dynamic> toJson() => {
    'mass': mass,
    'stiffness': stiffness,
    'damping': damping,
  };

  factory SpringConfig.fromJson(Map<String, dynamic> json) => SpringConfig(
    mass: (json['mass'] as num?)?.toDouble() ?? 1.0,
    stiffness: (json['stiffness'] as num?)?.toDouble() ?? 100.0,
    damping: (json['damping'] as num?)?.toDouble() ?? 10.0,
  );
}

/// Physics-based spring simulation.
///
/// Evaluates a spring from 0.0 (start) to 1.0 (rest) at any time t.
class SpringSimulation {
  final SpringConfig config;

  const SpringSimulation({required this.config});

  /// Evaluate the spring at time [t] seconds.
  ///
  /// Returns a value that oscillates around 1.0 and settles to 1.0.
  /// The initial value is 0.0 and initial velocity is 0.0.
  double evaluate(double t) {
    if (t <= 0) return 0.0;

    final zeta = config.dampingRatio;
    final omega = config.naturalFrequency;

    if (config.isCriticallyDamped) {
      // x(t) = 1 - (1 + ω₀t) * e^(-ω₀t)
      final exp = math.exp(-omega * t);
      return 1.0 - (1.0 + omega * t) * exp;
    } else if (config.isUnderdamped) {
      // ωd = ω₀ * √(1 - ζ²)
      final wd = omega * math.sqrt(1.0 - zeta * zeta);
      final exp = math.exp(-zeta * omega * t);
      // x(t) = 1 - e^(-ζω₀t) * (cos(ωdt) + (ζω₀/ωd) * sin(ωdt))
      return 1.0 -
          exp * (math.cos(wd * t) + (zeta * omega / wd) * math.sin(wd * t));
    } else {
      // Overdamped: two real roots.
      final s1 = -omega * (zeta - math.sqrt(zeta * zeta - 1.0));
      final s2 = -omega * (zeta + math.sqrt(zeta * zeta - 1.0));
      final a = s1 / (s1 - s2);
      final b = -s2 / (s1 - s2);
      return 1.0 - a * math.exp(s2 * t) - b * math.exp(s1 * t);
    }
  }

  /// Evaluate the velocity at time [t].
  double velocity(double t) {
    if (t <= 0) return 0.0;
    const dt = 0.001;
    return (evaluate(t + dt) - evaluate(t)) / dt;
  }

  /// Whether the spring has settled within [threshold] of 1.0.
  bool isSettled(double t, {double threshold = 0.001}) {
    return (evaluate(t) - 1.0).abs() < threshold &&
        velocity(t).abs() < threshold;
  }

  /// Find the approximate settling time.
  double settlingTime({double threshold = 0.001, double maxTime = 10.0}) {
    for (double t = 0; t < maxTime; t += 0.01) {
      if (isSettled(t, threshold: threshold)) return t;
    }
    return maxTime;
  }
}
