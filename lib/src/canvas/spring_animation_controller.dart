import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

// ============================================================================
// 🌊 SPRING ANIMATION CONTROLLER
// ============================================================================

/// Reusable, lightweight spring simulation driver for animating arbitrary
/// scalar and 2D (Offset) properties.
///
/// DESIGN PRINCIPLES:
/// - Decoupled from InfiniteCanvasController — usable for node drag, toolbar
///   transitions, UI springs, or any future animated property.
/// - Uses Flutter's built-in [SpringSimulation] and [FrictionSimulation]
///   (from `package:flutter/physics.dart`) — zero external deps.
/// - Single [Ticker] drives all active simulations for battery efficiency.
/// - Immediate cancel-and-restart semantics: calling [animateTo] while
///   a previous animation is running replaces it instantly.
///
/// Usage:
/// ```dart
/// final spring = SpringAnimationController();
/// spring.attachTicker(vsync);
/// spring.onOffsetUpdate = (offset) => setState(() => _pos = offset);
/// spring.animateOffsetTo(Offset(100, 200));
/// // Later:
/// spring.detachTicker();
/// spring.dispose();
/// ```
class SpringAnimationController {
  // ============================================================================
  // 🎯 DEFAULT SPRING DESCRIPTIONS
  // ============================================================================

  /// Snappy spring — fast settle, slight bounce. Good for node snapping.
  static const SpringDescription snappy = SpringDescription(
    mass: 1.0,
    stiffness: 400.0,
    damping: 28.0,
  );

  /// Smooth spring — gentle settle, no visible bounce. Good for camera moves.
  static const SpringDescription smooth = SpringDescription(
    mass: 1.0,
    stiffness: 200.0,
    damping: 22.0,
  );

  /// Bouncy spring — visible oscillation. Good for playful UI feedback.
  static const SpringDescription bouncy = SpringDescription(
    mass: 1.0,
    stiffness: 300.0,
    damping: 15.0,
  );

  // ============================================================================
  // 🎯 STATE
  // ============================================================================

  Ticker? _ticker;
  Duration _lastTickTime = Duration.zero;

  // — Scalar spring —
  SpringSimulation? _scalarSim;
  double _scalarStartTime = 0;
  double _scalarValue = 0;
  bool _isScalarActive = false;

  // — Offset spring (2D) —
  SpringSimulation? _offsetSimX;
  SpringSimulation? _offsetSimY;
  double _offsetStartTime = 0;
  Offset _offsetValue = Offset.zero;
  bool _isOffsetActive = false;

  // — Offset fling (friction-based) —
  FrictionSimulation? _flingSimX;
  FrictionSimulation? _flingSimY;
  double _flingStartTime = 0;
  bool _isFlingActive = false;

  // ============================================================================
  // 🎯 PUBLIC API — State
  // ============================================================================

  /// Whether any animation (scalar, offset, or fling) is currently running.
  bool get isAnimating => _isScalarActive || _isOffsetActive || _isFlingActive;

  /// Current scalar value (updated each frame during [animateTo]).
  double get value => _scalarValue;

  /// Current offset value (updated each frame during [animateOffsetTo] / [fling]).
  Offset get offsetValue => _offsetValue;

  // ============================================================================
  // 🎯 PUBLIC API — Callbacks
  // ============================================================================

  /// Called each frame with the updated scalar value.
  ValueChanged<double>? onUpdate;

  /// Called each frame with the updated offset value.
  ValueChanged<Offset>? onOffsetUpdate;

  /// Called when the current animation completes (spring settled or fling stopped).
  VoidCallback? onComplete;

  // ============================================================================
  // 🎯 PUBLIC API — Ticker Lifecycle
  // ============================================================================

  /// Attach a ticker from the widget tree.
  /// Call from initState() — the State must use TickerProviderStateMixin.
  void attachTicker(TickerProvider vsync) {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTick);
  }

  /// Detach the ticker. Call from dispose().
  void detachTicker() {
    stop();
    _ticker?.dispose();
    _ticker = null;
  }

  // ============================================================================
  // 🎯 PUBLIC API — Scalar Spring
  // ============================================================================

  /// Animate a scalar value to [target] using spring physics.
  ///
  /// Cancels any running scalar animation. The current [value] is used
  /// as the start position. [velocity] is the initial velocity (default 0).
  void animateTo(
    double target, {
    SpringDescription spring = snappy,
    double velocity = 0.0,
  }) {
    if (_ticker == null) return;

    _scalarSim = SpringSimulation(spring, _scalarValue, target, velocity);
    _scalarStartTime = 0;
    _isScalarActive = true;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  /// Snap scalar value immediately (no animation).
  void snapTo(double target) {
    _isScalarActive = false;
    _scalarSim = null;
    _scalarValue = target;
    onUpdate?.call(_scalarValue);
  }

  // ============================================================================
  // 🎯 PUBLIC API — Offset Spring (2D)
  // ============================================================================

  /// Animate an offset to [target] using spring physics (independent X/Y springs).
  ///
  /// Cancels any running offset or fling animation.
  void animateOffsetTo(
    Offset target, {
    SpringDescription spring = smooth,
    Offset velocity = Offset.zero,
  }) {
    if (_ticker == null) return;

    // Cancel fling if running
    _isFlingActive = false;
    _flingSimX = null;
    _flingSimY = null;

    _offsetSimX = SpringSimulation(
      spring,
      _offsetValue.dx,
      target.dx,
      velocity.dx,
    );
    _offsetSimY = SpringSimulation(
      spring,
      _offsetValue.dy,
      target.dy,
      velocity.dy,
    );

    _offsetStartTime = 0;
    _isOffsetActive = true;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  /// Snap offset immediately (no animation).
  void snapOffsetTo(Offset target) {
    _isOffsetActive = false;
    _isFlingActive = false;
    _offsetSimX = null;
    _offsetSimY = null;
    _flingSimX = null;
    _flingSimY = null;
    _offsetValue = target;
    onOffsetUpdate?.call(_offsetValue);
  }

  // ============================================================================
  // 🎯 PUBLIC API — Fling (Friction-based deceleration)
  // ============================================================================

  /// Launch a friction-based fling from the current offset with initial [velocity].
  ///
  /// The offset decelerates exponentially and stops when velocity drops
  /// below [stopVelocity]. Cancels any running offset spring.
  void fling(
    Offset velocity, {
    double friction = 0.02,
    double stopVelocity = 1.0,
  }) {
    if (_ticker == null) return;
    if (velocity.distance < stopVelocity) return;

    // Cancel offset spring if running
    _isOffsetActive = false;
    _offsetSimX = null;
    _offsetSimY = null;

    _flingSimX = FrictionSimulation(friction, _offsetValue.dx, velocity.dx);
    _flingSimY = FrictionSimulation(friction, _offsetValue.dy, velocity.dy);

    _flingStartTime = 0;
    _isFlingActive = true;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  // ============================================================================
  // 🎯 PUBLIC API — Control
  // ============================================================================

  /// Stop all running animations immediately.
  void stop() {
    _isScalarActive = false;
    _isOffsetActive = false;
    _isFlingActive = false;
    _scalarSim = null;
    _offsetSimX = null;
    _offsetSimY = null;
    _flingSimX = null;
    _flingSimY = null;
    if (_ticker?.isTicking ?? false) {
      _ticker!.stop();
    }
  }

  /// Release resources. Call when the controller is no longer needed.
  void dispose() {
    stop();
    _ticker?.dispose();
    _ticker = null;
    onUpdate = null;
    onOffsetUpdate = null;
    onComplete = null;
  }

  // ============================================================================
  // 🌊 TICKER CALLBACK
  // ============================================================================

  void _onTick(Duration elapsed) {
    if (!isAnimating) {
      _ticker?.stop();
      return;
    }

    // Calculate delta time in seconds
    final double dt;
    if (_lastTickTime == Duration.zero) {
      dt = 0.016; // First frame: assume 60fps
      _lastTickTime = elapsed;
    } else {
      dt = (elapsed - _lastTickTime).inMicroseconds / 1000000.0;
      _lastTickTime = elapsed;
    }

    bool anyCompleted = false;

    // — SCALAR SPRING —
    if (_isScalarActive && _scalarSim != null) {
      _scalarStartTime += dt;
      _scalarValue = _scalarSim!.x(_scalarStartTime);
      onUpdate?.call(_scalarValue);

      if (_scalarSim!.isDone(_scalarStartTime)) {
        _scalarValue = _scalarSim!.x(_scalarStartTime);
        _isScalarActive = false;
        _scalarSim = null;
        onUpdate?.call(_scalarValue);
        anyCompleted = true;
      }
    }

    // — OFFSET SPRING —
    if (_isOffsetActive && _offsetSimX != null && _offsetSimY != null) {
      _offsetStartTime += dt;

      final newX = _offsetSimX!.x(_offsetStartTime);
      final newY = _offsetSimY!.x(_offsetStartTime);
      _offsetValue = Offset(newX, newY);
      onOffsetUpdate?.call(_offsetValue);

      final doneX = _offsetSimX!.isDone(_offsetStartTime);
      final doneY = _offsetSimY!.isDone(_offsetStartTime);
      if (doneX && doneY) {
        _isOffsetActive = false;
        _offsetSimX = null;
        _offsetSimY = null;
        onOffsetUpdate?.call(_offsetValue);
        anyCompleted = true;
      }
    }

    // — FLING (FRICTION) —
    if (_isFlingActive && _flingSimX != null && _flingSimY != null) {
      _flingStartTime += dt;

      final newX = _flingSimX!.x(_flingStartTime);
      final newY = _flingSimY!.x(_flingStartTime);
      _offsetValue = Offset(newX, newY);
      onOffsetUpdate?.call(_offsetValue);

      final vx = _flingSimX!.dx(_flingStartTime).abs();
      final vy = _flingSimY!.dx(_flingStartTime).abs();
      if (vx < 1.0 && vy < 1.0) {
        _isFlingActive = false;
        _flingSimX = null;
        _flingSimY = null;
        onOffsetUpdate?.call(_offsetValue);
        anyCompleted = true;
      }
    }

    if (anyCompleted && !isAnimating) {
      onComplete?.call();
    }

    // Stop ticker if all done
    if (!isAnimating) {
      _ticker?.stop();
    }
  }

  // ============================================================================
  // 🔧 HELPERS
  // ============================================================================

  /// Ensure the ticker is running (idempotent).
  /// If already ticking, just resets the time base for the new simulation.
  void _ensureTickerRunning() {
    if (_ticker == null) return;
    if (_ticker!.isTicking) {
      // Already running — just reset time base for the new sim
      _lastTickTime = Duration.zero;
      return;
    }
    _lastTickTime = Duration.zero;
    _ticker!.start();
  }
}
