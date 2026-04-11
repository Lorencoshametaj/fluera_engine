import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/scheduler.dart';
import './reflow_controller.dart';

/// 🌊 ANIMATED REFLOW CONTROLLER — Spring-animated content displacement.
///
/// Wraps [ReflowController] with smooth spring-based animations so content
/// "flows" organically when displaced, rather than jumping instantly.
///
/// DESIGN:
/// - Uses [Ticker] for frame-synchronous animation (no extra allocation)
/// - Spring curve: underdamped (slight overshoot) for organic feel
/// - Throttle: minimum 500ms between successive reflows to prevent jitter
/// - Applies displacement via callback (caller knows how to translate elements)
class AnimatedReflowController {
  final ReflowController reflowController;

  /// The TickerProvider (usually the State's vsync).
  final TickerProvider vsync;

  /// Ticker for driving the spring animation.
  Ticker? _ticker;

  /// Current animation progress (0.0 → 1.0).
  double _animationProgress = 0.0;

  /// Whether an animation is currently running.
  bool get isAnimating => _ticker?.isActive == true;

  /// Last reflow timestamp — for throttling.
  DateTime _lastReflowTime = DateTime(2000);

  /// Minimum interval between auto-reflows (ms).
  static const int _throttleMs = 500;

  /// Spring animation duration.
  static const Duration _animDuration = Duration(milliseconds: 300);

  /// Minimum total displacement magnitude to trigger animation.
  /// Below this, the reflow is too subtle to animate.
  static const double _minDisplacementMagnitude = 3.0;

  /// Pending displacement data for current animation.
  ReflowResult? _pendingResult;

  /// Accumulated displacement applied so far (per-element).
  /// Tracks how much of the total has been applied to avoid drift.
  Map<String, Offset> _appliedSoFar = {};

  /// Callback to apply element translations.
  /// Called with: { elementId: incrementalDelta }
  /// The caller is responsible for translating strokes/shapes/text/images.
  final void Function(Map<String, Offset> deltas) onApplyDeltas;

  /// Callback after reflow animation completes.
  final VoidCallback? onReflowComplete;

  AnimatedReflowController({
    required this.reflowController,
    required this.vsync,
    required this.onApplyDeltas,
    this.onReflowComplete,
  });

  // ===========================================================================
  // Public API
  // ===========================================================================

  /// Trigger auto-reflow after a stroke is committed.
  ///
  /// Computes displacements, then animates them with spring physics.
  /// Returns true if a reflow was triggered, false if skipped.
  bool triggerAutoReflow({
    required Rect disturbance,
    required Set<String> excludeIds,
  }) {
    // Throttle check
    final now = DateTime.now();
    if (now.difference(_lastReflowTime).inMilliseconds < _throttleMs) {
      return false;
    }

    // Reflow must be enabled
    if (!reflowController.isEnabled) return false;

    // If already animating, skip (don't interrupt)
    if (isAnimating) return false;

    // Compute displacements
    final result = reflowController.computeFinalDisplacements(
      disturbance: disturbance,
      excludeIds: excludeIds,
    );

    if (result.isEmpty) return false;

    // Check minimum displacement magnitude
    double maxMagnitude = 0.0;
    for (final d in result.elementDisplacements.values) {
      final mag = d.distance;
      if (mag > maxMagnitude) maxMagnitude = mag;
    }
    if (maxMagnitude < _minDisplacementMagnitude) return false;

    _lastReflowTime = now;
    _pendingResult = result;
    _animationProgress = 0.0;
    _appliedSoFar = {};

    // Start spring animation
    _startAnimation();

    return true;
  }

  /// Cancel any running animation and apply remaining displacement instantly.
  void cancelAnimation() {
    if (!isAnimating) return;
    _ticker?.stop();

    // Apply remaining displacement instantly
    if (_pendingResult != null) {
      _applyToProgress(1.0);
      _finalizeReflow();
    }
    _cleanup();
  }

  /// Dispose resources.
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }

  // ===========================================================================
  // Animation
  // ===========================================================================

  void _startAnimation() {
    _ticker?.stop();
    _ticker?.dispose();

    Duration? animStartTime;

    _ticker = vsync.createTicker((elapsed) {
      animStartTime ??= elapsed;
      final animElapsed = elapsed - animStartTime!;

      // Calculate raw time progress
      final t = (animElapsed.inMicroseconds / _animDuration.inMicroseconds)
          .clamp(0.0, 1.0);

      // Apply spring-curved progress
      final newProgress = _springCurve(t);
      _applyToProgress(newProgress);
      _animationProgress = newProgress;

      // Animation complete
      if (t >= 1.0) {
        _ticker?.stop();
        _finalizeReflow();
        _cleanup();
      }
    });

    _ticker!.start();
  }

  /// Apply deltas to reach the given progress level.
  void _applyToProgress(double targetProgress) {
    if (_pendingResult == null) return;

    final deltas = <String, Offset>{};
    for (final entry in _pendingResult!.elementDisplacements.entries) {
      final elementId = entry.key;
      final totalDelta = entry.value;

      // How much should have been applied at this progress
      final targetApplied = totalDelta * targetProgress;

      // How much has already been applied
      final alreadyApplied = _appliedSoFar[elementId] ?? Offset.zero;

      // Incremental delta
      final increment = targetApplied - alreadyApplied;
      if (increment.distance > 0.01) {
        deltas[elementId] = increment;
        _appliedSoFar[elementId] = targetApplied;
      }
    }

    if (deltas.isNotEmpty) {
      onApplyDeltas(deltas);
    }
  }

  /// Underdamped spring curve.
  ///
  /// Slight overshoot (~5%) then settle — gives the organic "alive" feel.
  /// x(t) = 1 - e^(-βt) * (cos(ωt) + (β/ω) * sin(ωt))
  /// β = 8.0 (damping), ω = 12.0 (frequency)
  static double _springCurve(double t) {
    if (t >= 1.0) return 1.0;
    if (t <= 0.0) return 0.0;

    const beta = 8.0;
    const omega = 12.0;
    const betaOverOmega = beta / omega;

    final expDecay = math.exp(-beta * t);
    final cosT = math.cos(omega * t);
    final sinT = math.sin(omega * t);

    return 1.0 - expDecay * (cosT + betaOverOmega * sinT);
  }

  // ===========================================================================
  // Finalization
  // ===========================================================================

  void _finalizeReflow() {
    if (_pendingResult == null) return;

    // Update cluster cache bounds
    reflowController.updateClusterBoundsAfterReflow(
      _pendingResult!.clusterDisplacements,
    );

    onReflowComplete?.call();
  }

  void _cleanup() {
    _pendingResult = null;
    _animationProgress = 0.0;
    _appliedSoFar = {};
  }
}
