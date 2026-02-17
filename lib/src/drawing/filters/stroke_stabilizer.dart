import 'dart:collection';
import 'dart:ui';

/// 🎯 Phase 4B: SAI-style Stroke Stabilizer
///
/// Applies weighted moving average smoothing to raw input points,
/// producing smoother strokes at the cost of slight input lag.
///
/// Level 0 = no smoothing (passthrough)
/// Level 10 = heavy smoothing (20-point window, significant lag)
///
/// The algorithm uses a weighted moving average where recent points
/// have exponentially higher weight than older points. This produces
/// natural-feeling smoothing that preserves intentional direction
/// changes while eliminating hand tremor.
///
/// Usage:
///   1. Call `reset()` at stroke start
///   2. Call `stabilize(rawPoint)` for each input point
///   3. Use the returned Offset as the smoothed position
class StrokeStabilizer {
  /// Smoothing level (0 = none, 10 = maximum)
  int _level;

  /// History of recent raw points
  final Queue<Offset> _history = Queue<Offset>();

  /// Maximum history size based on current level
  int get _windowSize => _level == 0 ? 1 : (_level * 2).clamp(2, 20);

  /// Weight decay factor — higher level = more uniform weights (stronger smooth)
  double get _decay => 1.0 - (_level * 0.05).clamp(0.0, 0.5);

  StrokeStabilizer({int level = 0}) : _level = level.clamp(0, 10);

  /// Current stabilizer level
  int get level => _level;

  /// Update the stabilizer level
  set level(int value) {
    _level = value.clamp(0, 10);
    // Trim history if window shrank
    while (_history.length > _windowSize) {
      _history.removeFirst();
    }
  }

  /// Stabilize a raw input point. Returns the smoothed position.
  ///
  /// For level 0, returns the raw point unchanged (zero-cost fast path).
  Offset stabilize(Offset rawPoint) {
    if (_level == 0) return rawPoint;

    // Add to history
    _history.addLast(rawPoint);
    while (_history.length > _windowSize) {
      _history.removeFirst();
    }

    // Single point: return as-is
    if (_history.length == 1) return rawPoint;

    // Weighted moving average — iterate Queue directly (no .toList())
    double totalWeight = 0.0;
    double sumX = 0.0;
    double sumY = 0.0;

    final count = _history.length;
    int i = 0;
    for (final point in _history) {
      // Exponential weight: most recent = highest weight
      // weight = decay^(count - 1 - i)
      final age = count - 1 - i;
      final weight = _pow(_decay, age.toDouble());

      sumX += point.dx * weight;
      sumY += point.dy * weight;
      totalWeight += weight;
      i++;
    }

    if (totalWeight <= 0) return rawPoint;

    return Offset(sumX / totalWeight, sumY / totalWeight);
  }

  /// Reset the stabilizer for a new stroke
  void reset() {
    _history.clear();
  }

  /// Fast power for small integer-like exponents
  static double _pow(double base, double exp) {
    if (exp <= 0) return 1.0;
    if (exp <= 1) return base;
    double result = 1.0;
    final n = exp.toInt();
    for (int i = 0; i < n; i++) {
      result *= base;
    }
    return result;
  }
}
