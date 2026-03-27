import 'dart:math' as math;

/// 💧 WETNESS STATE — Mutable temporal state for surface wetness.
///
/// Tracks how "wet" a surface region is after ink is deposited.
/// Wetness decays exponentially over time:
///
///     w(t) = w₀ × e^(-λ × Δt)
///
/// where λ is the [decayRate] and Δt is elapsed time in milliseconds.
///
/// Wetness affects rendering via [SurfaceMaterial.computeModifiers]:
/// - Wet surfaces increase ink spread (pigment migrates to wet areas)
/// - Wet surfaces reduce pigment retention (ink doesn't stick as well)
/// - Wet-on-wet interactions produce color blending
///
/// ```dart
/// final wetness = WetnessState();
/// wetness.deposit(0.5); // ink deposited
///
/// // Later...
/// final w = wetness.getWetness(nowMs: currentTimeMs);
/// // w < 0.5 (has decayed since deposit)
/// ```
class WetnessState {
  /// Current wetness level [0.0–1.0].
  double _wetness;

  /// Timestamp of the last update (milliseconds since epoch).
  double _lastUpdateMs;

  /// Decay rate constant λ. Higher = faster drying.
  /// Default 0.001 ≈ ~50% dry after 700ms, ~90% dry after 2300ms.
  final double decayRate;

  WetnessState({
    double initialWetness = 0.0,
    double? initialTimeMs,
    this.decayRate = 0.001,
  }) : _wetness = initialWetness.clamp(0.0, 1.0),
       _lastUpdateMs = initialTimeMs ?? 0.0;

  /// Deposit ink, increasing wetness.
  ///
  /// [amount] is additive: multiple deposits accumulate up to 1.0.
  /// [nowMs] is the current time in milliseconds.
  void deposit(double amount, {required double nowMs}) {
    // First, decay any existing wetness to current time
    _applyDecay(nowMs);
    // Then add the new deposit
    _wetness = (_wetness + amount).clamp(0.0, 1.0);
    _lastUpdateMs = nowMs;
  }

  /// Get the current wetness level, applying temporal decay.
  ///
  /// [nowMs] is the current time in milliseconds.
  /// Returns a value in [0.0, 1.0].
  double getWetness({required double nowMs}) {
    _applyDecay(nowMs);
    return _wetness;
  }

  /// Whether the surface is effectively dry (wetness below threshold).
  bool isDry({required double nowMs, double threshold = 0.01}) {
    return getWetness(nowMs: nowMs) < threshold;
  }

  /// Reset to completely dry state.
  void reset() {
    _wetness = 0.0;
    _lastUpdateMs = 0.0;
  }

  /// Apply exponential decay: w(t) = w₀ × e^(-λ × Δt)
  void _applyDecay(double nowMs) {
    if (_wetness <= 0.0) return;

    final deltaMs = nowMs - _lastUpdateMs;
    if (deltaMs <= 0) return;

    _wetness *= math.exp(-decayRate * deltaMs);
    _lastUpdateMs = nowMs;

    // Snap to zero when negligible (avoid floating point noise)
    if (_wetness < 0.001) _wetness = 0.0;
  }

  // ===========================================================================
  // SERIALIZATION
  // ===========================================================================

  Map<String, dynamic> toJson() => {
    'w': _wetness,
    't': _lastUpdateMs,
    'dr': decayRate,
  };

  factory WetnessState.fromJson(Map<String, dynamic>? json) {
    if (json == null) return WetnessState();

    return WetnessState(
      initialWetness: (json['w'] as num?)?.toDouble() ?? 0.0,
      initialTimeMs: (json['t'] as num?)?.toDouble() ?? 0.0,
      decayRate: (json['dr'] as num?)?.toDouble() ?? 0.001,
    );
  }

  @override
  String toString() =>
      'WetnessState(wetness: $_wetness, '
      'lastUpdate: $_lastUpdateMs, decayRate: $decayRate)';
}
