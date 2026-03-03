import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import '../utils/key_value_store.dart';
import './liquid_canvas_config.dart';

/// 🌊 Controller for infinite canvas with zoom, pan, and liquid physics.
///
/// DESIGN PRINCIPLES:
/// - Momentum deceleration after pan lift (FrictionSimulation)
/// - Spring-back when zoom exceeds min/max bounds (SpringSimulation)
/// - Elastic overshoot: briefly shows beyond-limits view before springing back
/// - Immediate stop on new touch (zero latency response)
/// - All physics driven by a single Ticker for battery efficiency
/// - Backward compatible: works identically without attaching a ticker
///
/// ARCHITECTURE:
/// - Extends ChangeNotifier for widget reactivity (AnimatedBuilder, painters)
/// - Physics state machine: IDLE → MOMENTUM / SPRING → IDLE
/// - Ticker callback drives all active simulations each frame
class InfiniteCanvasController extends ChangeNotifier {
  // ============================================================================
  // 🎯 CORE STATE
  // ============================================================================

  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _rotation = 0.0; // radians, clockwise

  // Zoom limits (logical bounds — elastic overshoot can exceed these)
  static const double _minScale = 0.1;
  static const double _maxScale = 5.0;

  /// Tracks whether we're past zoom limits (for one-shot haptic).
  bool _wasAtZoomLimit = false;

  /// Callback fired once when zoom crosses min/max boundary.
  /// Set by the widget to trigger haptic feedback.
  VoidCallback? onZoomLimitReached;

  /// 🚀 Callback fired when zoom crosses LOD tier boundaries (0.2x, 0.5x).
  /// Used to invalidate tile cache and force repaint for LOD transitions.
  VoidCallback? onLodTierChanged;

  /// Track the last LOD tier to detect boundary crossings.
  int _lastLodTier = 0;

  /// 🚀 Callback fired when all physics animations settle.
  /// Used by the canvas to trigger LOD precomputation at the new zoom level.
  VoidCallback? onAnimationSettle;

  // Getters
  Offset get offset => _offset;
  double get scale => _scale;
  double get rotation => _rotation;

  /// 🚀 Current pan velocity from active momentum simulation.
  /// Returns Offset.zero if no momentum is active.
  Offset get panVelocity {
    if (!_isMomentumActive || _panSimX == null || _panSimY == null) {
      return Offset.zero;
    }
    return Offset(
      _panSimX!.dx(_momentumStartTime),
      _panSimY!.dx(_momentumStartTime),
    );
  }

  // 🌀 Rotation lock (persisted)
  static const String _rotationLockKey = 'fluera_rotation_locked';
  bool _rotationLocked = false;
  bool get rotationLocked => _rotationLocked;
  set rotationLocked(bool value) {
    _rotationLocked = value;
    notifyListeners();
    // Persist asynchronously
    KeyValueStore.getInstance().then((prefs) {
      prefs.setBool(_rotationLockKey, value);
    });
  }

  /// Load persisted rotation lock state. Call once after construction.
  Future<void> loadPersistedState() async {
    final prefs = await KeyValueStore.getInstance();
    final locked = prefs.getBool(_rotationLockKey) ?? false;
    if (locked != _rotationLocked) {
      _rotationLocked = locked;
      notifyListeners();
    }
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS
  // ============================================================================

  /// Physics configuration (injectable, immutable)
  LiquidCanvasConfig _liquidConfig = const LiquidCanvasConfig();
  LiquidCanvasConfig get liquidConfig => _liquidConfig;
  set liquidConfig(LiquidCanvasConfig config) {
    _liquidConfig = config;
  }

  /// Ticker provided by the widget tree (TickerProviderStateMixin)
  Ticker? _ticker;
  Duration _lastTickTime = Duration.zero;

  // — Pan momentum state —
  FrictionSimulation? _panSimX;
  FrictionSimulation? _panSimY;
  double _momentumStartTime = 0;
  bool _isMomentumActive = false;

  // — Zoom spring state —
  SpringSimulation? _zoomSim;
  double _springStartTime = 0;
  bool _isZoomSpringActive = false;
  Offset _zoomSpringFocalPoint = Offset.zero;
  double _zoomSpringStartScale = 1.0;

  // — Rotation momentum state —
  FrictionSimulation? _rotationSim;
  double _rotationMomentumStartTime = 0;
  bool _isRotationMomentumActive = false;

  // — Rotation spring state —
  SpringSimulation? _rotationSpring;
  bool _isRotationSpringActive = false;

  // — Zoom momentum state (Gap 4) —
  FrictionSimulation? _zoomMomentumSim;
  double _zoomMomentumStartTime = 0;
  bool _isZoomMomentumActive = false;
  Offset _zoomMomentumFocalPoint = Offset.zero;

  /// Whether any physics animation is running.
  bool get isAnimating =>
      _isMomentumActive ||
      _isZoomSpringActive ||
      _isZoomMomentumActive ||
      _isRotationMomentumActive ||
      _isRotationSpringActive ||
      _isPanSpringActive;

  /// 🚀 Whether the canvas is actively panning (user gesture or momentum).
  /// Painters use this to skip expensive work during scroll.
  bool _isPanning = false;
  bool get isPanning => _isPanning || _isMomentumActive;
  set isPanning(bool value) {
    _isPanning = value;
  }

  /// Request a repaint for all painters listening to this controller.
  ///
  /// Use when external state (e.g. image list) has changed and painters
  /// need to re-render, but a full widget rebuild is unnecessary.
  void markNeedsPaint() => notifyListeners();

  // ============================================================================
  // 🎛️ CORE API
  // ============================================================================

  /// Apply offset (pan)
  void setOffset(Offset newOffset) {
    _offset = newOffset;
    notifyListeners();
  }

  /// Apply zoom with hard clamp (no elastic overshoot)
  void setScale(double newScale) {
    _scale = newScale.clamp(_minScale, _maxScale);
    notifyListeners();
    _checkLodTier();
  }

  /// Apply combined transform (zoom + pan + rotation) with optional elastic bounds.
  ///
  /// When [elastic] is true and liquid physics are enabled, the scale
  /// is allowed to overshoot the limits with increasing resistance,
  /// creating the signature rubber-band feel.
  void updateTransform({
    required Offset offset,
    required double scale,
    double? rotation,
    bool elastic = false,
  }) {
    _offset = offset;
    if (rotation != null && !_rotationLocked) _rotation = rotation;
    if (elastic && _liquidConfig.enabled && _liquidConfig.enableElasticZoom) {
      // Allow overshoot with rubber-band resistance
      _scale = _applyElasticClamp(scale);

      // Fire haptic once when crossing the zoom boundary
      final isAtLimit = scale < _minScale || scale > _maxScale;
      if (isAtLimit && !_wasAtZoomLimit) {
        onZoomLimitReached?.call();
      }
      _wasAtZoomLimit = isAtLimit;
    } else {
      _scale = scale.clamp(_minScale, _maxScale);
      _wasAtZoomLimit = false;
    }
    notifyListeners();
    _checkLodTier();
  }

  /// Check if zoom crossed an LOD tier boundary and fire callback.
  /// Uses hysteresis to prevent flickering at boundaries.
  void _checkLodTier() {
    // Hysteresis: different thresholds for zooming in vs out.
    // Zooming OUT uses lower thresholds → tier change happens later.
    // Zooming IN uses higher thresholds → tier change happens later.
    // This prevents rapid toggling at the boundary.
    final int tier;
    if (_lastLodTier == 2) {
      // Currently in sections-only mode → need to zoom IN past 0.22 to exit
      tier = _scale < 0.22 ? 2 : (_scale < 0.5 ? 1 : 0);
    } else if (_lastLodTier == 0) {
      // Currently in full quality → need to zoom OUT past 0.45 to exit
      tier = _scale < 0.18 ? 2 : (_scale < 0.45 ? 1 : 0);
    } else {
      // Tier 1 (batched) → standard thresholds
      tier = _scale < 0.18 ? 2 : (_scale < 0.5 ? 1 : 0);
    }
    if (tier != _lastLodTier) {
      _lastLodTier = tier;
      onLodTierChanged?.call();
    }
  }

  /// Preview what scale value [updateTransform] would actually apply.
  ///
  /// When elastic zoom is enabled, returns the elastically-clamped value.
  /// Otherwise returns the hard-clamped value. Does NOT mutate state.
  double getEffectiveScale(double rawScale, {bool elastic = true}) {
    if (elastic && _liquidConfig.enabled && _liquidConfig.enableElasticZoom) {
      return _applyElasticClamp(rawScale);
    }
    return rawScale.clamp(_minScale, _maxScale);
  }

  /// Reset to initial view
  void reset() {
    stopAnimation();
    _offset = Offset.zero;
    _scale = 1.0;
    _rotation = 0.0;
    notifyListeners();
  }

  /// 🎯 Center the viewport on the canvas origin (0,0)
  void centerCanvas(
    Size viewportSize, {
    Size canvasSize = const Size(5000, 5000),
  }) {
    _offset = Offset(viewportSize.width / 2, viewportSize.height / 2);
    notifyListeners();
  }

  /// Convert screen coordinates to canvas coordinates
  Offset screenToCanvas(Offset screenPoint) {
    if (_rotation == 0.0) {
      return (screenPoint - _offset) / _scale;
    }
    // Undo translate → undo rotate → undo scale
    final translated = screenPoint - _offset;
    final cosR = math.cos(-_rotation);
    final sinR = math.sin(-_rotation);
    final rotated = Offset(
      translated.dx * cosR - translated.dy * sinR,
      translated.dx * sinR + translated.dy * cosR,
    );
    return rotated / _scale;
  }

  /// Convert canvas coordinates to screen coordinates
  Offset canvasToScreen(Offset canvasPoint) {
    if (_rotation == 0.0) {
      return canvasPoint * _scale + _offset;
    }
    // Scale → rotate → translate
    final scaled = canvasPoint * _scale;
    final cosR = math.cos(_rotation);
    final sinR = math.sin(_rotation);
    final rotated = Offset(
      scaled.dx * cosR - scaled.dy * sinR,
      scaled.dx * sinR + scaled.dy * cosR,
    );
    return rotated + _offset;
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Ticker Lifecycle
  // ============================================================================

  /// Attach a ticker from the widget tree for physics animations.
  /// Call from initState() — the State must use TickerProviderStateMixin.
  void attachTicker(TickerProvider vsync) {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTick);
  }

  /// Detach the ticker. Call from dispose().
  void detachTicker() {
    _ticker?.dispose();
    _ticker = null;
    _isMomentumActive = false;
    _isZoomSpringActive = false;
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Pan Momentum
  // ============================================================================

  /// Launch pan momentum from terminal velocity (called on gesture end).
  ///
  /// Uses [FrictionSimulation] for natural exponential deceleration.
  /// The simulation is driven per-axis for independent X/Y damping.
  void startMomentum(Offset velocity) {
    if (!_liquidConfig.enabled) return;
    if (_ticker == null) return;

    // Don't start momentum for tiny velocities
    final speed = velocity.distance;
    if (speed < _liquidConfig.momentumThreshold) return;

    // Create friction simulations for each axis
    _panSimX = FrictionSimulation(
      _liquidConfig.panFriction,
      _offset.dx,
      velocity.dx,
    );
    _panSimY = FrictionSimulation(
      _liquidConfig.panFriction,
      _offset.dy,
      velocity.dy,
    );

    _isMomentumActive = true;
    _momentumStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  /// Immediately stop all running animations.
  /// Call on new touch-down for instant response.
  void stopAnimation() {
    _isMomentumActive = false;
    _isZoomSpringActive = false;
    _isZoomMomentumActive = false;
    _isRotationMomentumActive = false;
    _isRotationSpringActive = false;
    _isPanSpringActive = false;
    _isTransformSpringActive = false;
    _panSimX = null;
    _panSimY = null;
    _zoomSim = null;
    _zoomMomentumSim = null;
    _rotationSim = null;
    _rotationSpring = null;
    _panSpringSimX = null;
    _panSpringSimY = null;
    if (_ticker?.isTicking ?? false) {
      _ticker!.stop();
    }
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Zoom Spring-Back
  // ============================================================================

  /// Start spring animation to bounce zoom back to limits.
  ///
  /// Called when the gesture ends with the scale beyond [_minScale, _maxScale].
  /// The focal point is preserved so the spring-back feels anchored.
  void startZoomSpringBack(Offset focalPointScreen) {
    if (!_liquidConfig.enabled || !_liquidConfig.enableElasticZoom) return;
    if (_ticker == null) return;

    // Determine target: clamp to nearest limit
    final targetScale = _scale.clamp(_minScale, _maxScale);
    if ((_scale - targetScale).abs() < 0.001) return; // Already within bounds

    final spring = SpringDescription(
      mass: _liquidConfig.zoomSpringMass,
      stiffness: _liquidConfig.zoomSpringStiffness,
      damping: _liquidConfig.zoomSpringDamping,
    );

    _zoomSim = SpringSimulation(
      spring,
      _scale, // current position
      targetScale, // target position
      0.0, // initial velocity (at rest relative to spring)
    );

    _zoomSpringFocalPoint = focalPointScreen;
    _zoomSpringStartScale = _scale;
    _isZoomSpringActive = true;
    _springStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  /// 🎯 Animate zoom to a specific scale, centered on a focal point.
  ///
  /// Used by double-tap zoom: smoothly springs from the current scale to
  /// [targetScale], keeping the [focalPointScreen] visually anchored.
  /// The animation is driven by the same ticker as zoom spring-back.
  void animateZoomTo(double targetScale, Offset focalPointScreen) {
    if (_ticker == null) return;

    // Clamp target within allowed bounds
    final clampedTarget = targetScale.clamp(_minScale, _maxScale);
    if ((_scale - clampedTarget).abs() < 0.001) return; // Already there

    // Stiffer spring for intentional zoom (feels snappy, not floaty)
    const spring = SpringDescription(
      mass: 1.0,
      stiffness: 180.0,
      damping: 22.0,
    );

    _zoomSim = SpringSimulation(
      spring,
      _scale, // current
      clampedTarget, // target
      0.0, // start at rest
    );

    _zoomSpringFocalPoint = focalPointScreen;
    _zoomSpringStartScale = _scale;
    _isZoomSpringActive = true;
    _springStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Pan-to-Target Spring
  // ============================================================================

  // — Pan spring state —
  SpringSimulation? _panSpringSimX;
  SpringSimulation? _panSpringSimY;
  double _panSpringStartTime = 0;
  bool _isPanSpringActive = false;

  // — Combined transform spring state —
  bool _isTransformSpringActive = false;

  /// 🎯 Animate pan offset to a target position with spring physics.
  ///
  /// Used for "scroll-to-selection", "scroll-to-origin", or any
  /// programmatic camera move that should feel organic.
  void animateOffsetTo(Offset targetOffset, {Offset velocity = Offset.zero}) {
    if (_ticker == null) return;

    final config = _liquidConfig;
    if ((targetOffset - _offset).distance < 0.5) return; // Already there

    final spring = SpringDescription(
      mass: 1.0,
      stiffness: config.panSpringStiffness,
      damping: config.panSpringDamping,
    );

    _panSpringSimX = SpringSimulation(
      spring,
      _offset.dx,
      targetOffset.dx,
      velocity.dx,
    );
    _panSpringSimY = SpringSimulation(
      spring,
      _offset.dy,
      targetOffset.dy,
      velocity.dy,
    );

    _isPanSpringActive = true;
    _isTransformSpringActive = false;
    _panSpringStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  /// 🎯 Animate both offset and scale to target values simultaneously.
  ///
  /// Used for "fit selection in viewport", "fit all content", or any
  /// combined camera transition. The [focalPoint] (in screen coords)
  /// stays visually anchored during the animation.
  void animateToTransform({
    required Offset targetOffset,
    required double targetScale,
    Offset? focalPoint,
  }) {
    if (_ticker == null) return;

    final clampedScale = targetScale.clamp(_minScale, _maxScale);
    final offsetDist = (targetOffset - _offset).distance;
    final scaleDist = (_scale - clampedScale).abs();
    if (offsetDist < 0.5 && scaleDist < 0.001) return; // Already there

    final config = _liquidConfig;

    final spring = SpringDescription(
      mass: 1.0,
      stiffness: config.panSpringStiffness,
      damping: config.panSpringDamping,
    );

    _panSpringSimX = SpringSimulation(spring, _offset.dx, targetOffset.dx, 0.0);
    _panSpringSimY = SpringSimulation(spring, _offset.dy, targetOffset.dy, 0.0);

    // Reuse zoom spring for the scale component
    final zoomSpring = SpringDescription(
      mass: config.zoomSpringMass,
      stiffness: config.panSpringStiffness,
      damping: config.panSpringDamping,
    );

    _zoomSim = SpringSimulation(zoomSpring, _scale, clampedScale, 0.0);
    _zoomSpringFocalPoint = focalPoint ?? Offset.zero;
    _zoomSpringStartScale = _scale;

    _isPanSpringActive = true;
    _isTransformSpringActive = true;
    _isZoomSpringActive = true;
    _panSpringStartTime = 0;
    _springStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Rotation Momentum
  // ============================================================================

  /// Launch rotation momentum from terminal angular velocity.
  /// Called on gesture end when the user was rotating the canvas.
  void startRotationMomentum(double angularVelocity) {
    if (!_liquidConfig.enabled) return;
    if (_ticker == null) return;
    if (_rotationLocked) return;

    // Don't start for small angular velocities (prevent accidental spin)
    if (angularVelocity.abs() < 0.5) return;

    // Cap angular velocity to prevent wild spins from noisy gesture data
    final clampedVelocity = angularVelocity.clamp(-3.0, 3.0);

    _rotationSim = FrictionSimulation(
      _liquidConfig.panFriction * 4.0, // High friction — rotation dies fast
      _rotation,
      clampedVelocity,
    );

    _isRotationMomentumActive = true;
    _rotationMomentumStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Zoom Momentum (Gap 4)
  // ============================================================================

  /// Launch zoom momentum from terminal pinch velocity.
  ///
  /// Called on gesture end when the user was actively zooming.
  /// Uses [FrictionSimulation] on **log-scale** for natural multiplicative
  /// deceleration (zoom 2x→ 4x feels the same as 0.5x→0.25x).
  /// The focal point is preserved so the momentum feels anchored.
  void startZoomMomentum(double scaleVelocity, Offset focalPointScreen) {
    if (!_liquidConfig.enabled) return;
    if (_ticker == null) return;

    // Don't start for small velocities (threshold in scale-units/second)
    if (scaleVelocity.abs() < 0.3) return;

    // If already past limits, skip momentum and let spring-back handle it
    if (_scale < _minScale || _scale > _maxScale) return;

    // Friction on log-scale: log(scale) + velocity → exp() back to scale.
    // This gives multiplicative deceleration (2x→4x feels same as 0.5x→0.25x).
    final logScale = math.log(_scale);
    final logVelocity = scaleVelocity / _scale; // Convert to log-space velocity

    _zoomMomentumSim = FrictionSimulation(
      _liquidConfig.panFriction * 3.0, // Higher friction than pan
      logScale,
      logVelocity,
    );

    _zoomMomentumFocalPoint = focalPointScreen;
    _isZoomMomentumActive = true;
    _zoomMomentumStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  // — Rotation spring state (for animated reset / snap) —
  double _rotationSpringStartTime = 0;
  double _rotationSpringTarget = 0.0;

  /// Snap rotation back to 0° with a spring animation.
  void resetRotation() {
    _animateRotationTo(0.0);
  }

  /// Animate rotation to a target angle with a spring.
  void _animateRotationTo(double targetRotation) {
    if (_ticker == null) return;
    if ((_rotation - targetRotation).abs() < 0.001) {
      _rotation = targetRotation;
      notifyListeners();
      return;
    }

    final spring = SpringDescription(
      mass: 1.0,
      stiffness: 300.0,
      damping: 22.0,
    );

    _rotationSpring = SpringSimulation(
      spring,
      _rotation, // current
      targetRotation, // target
      0.0, // initial velocity
    );

    _rotationSpringTarget = targetRotation;
    _isRotationSpringActive = true;
    _isRotationMomentumActive = false; // Cancel any momentum
    _rotationSim = null;
    _rotationSpringStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  // 🌀 Snap angles: 0°, 45°, 90°, 135°, 180°, 225°, 270°, 315°
  static const double _snapThreshold =
      0.18; // ~10° tolerance (matches gesture magnetic zone)
  static const List<double> _snapAngles = [
    0.0,
    math.pi / 4, // 45°
    math.pi / 2, // 90°
    3 * math.pi / 4, // 135°
    math.pi, // 180°
    -3 * math.pi / 4, // -135° / 225°
    -math.pi / 2, // -90° / 270°
    -math.pi / 4, // -45° / 315°
    -math.pi, // -180°
  ];

  /// Check if the current rotation is close to a snap angle.
  /// Returns the snap angle if within threshold, null otherwise.
  double? checkSnapAngle(double rotation) {
    for (final snap in _snapAngles) {
      if ((rotation - snap).abs() < _snapThreshold) {
        return snap;
      }
    }
    return null;
  }

  /// Convert rotation in radians to degrees string for display.
  String get rotationDegrees {
    final degrees = (_rotation * 180.0 / math.pi) % 360;
    final normalized = degrees < 0 ? degrees + 360 : degrees;
    return '${normalized.toStringAsFixed(1)}°';
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Ticker Callback
  // ============================================================================

  void _onTick(Duration elapsed) {
    if (!isAnimating) {
      _ticker?.stop();
      return;
    }

    // Calculate delta time in seconds
    final double t;
    if (_lastTickTime == Duration.zero) {
      t = 0.016; // First frame: assume 60fps
      _lastTickTime = elapsed;
    } else {
      t = (elapsed - _lastTickTime).inMicroseconds / 1000000.0;
      _lastTickTime = elapsed;
    }

    bool needsNotify = false;

    // — PAN MOMENTUM —
    if (_isMomentumActive && _panSimX != null && _panSimY != null) {
      _momentumStartTime += t;

      final newX = _panSimX!.x(_momentumStartTime);
      final newY = _panSimY!.x(_momentumStartTime);

      // Check if momentum has effectively stopped
      final vx = _panSimX!.dx(_momentumStartTime).abs();
      final vy = _panSimY!.dx(_momentumStartTime).abs();

      if (vx < _liquidConfig.stopVelocity && vy < _liquidConfig.stopVelocity) {
        _isMomentumActive = false;
        _panSimX = null;
        _panSimY = null;
        needsNotify = true; // 🚀 SCROLL OPT: Final repaint with isPanning=false
      } else {
        _offset = Offset(newX, newY);
        needsNotify = true;
      }
    }

    // — ZOOM SPRING-BACK —
    if (_isZoomSpringActive && _zoomSim != null) {
      _springStartTime += t;

      final newScale = _zoomSim!.x(_springStartTime);

      // Apply focal-point-preserving zoom (rotation-aware)
      // screenToCanvas: undo translate → undo rotate → undo scale
      final translated = _zoomSpringFocalPoint - _offset;
      final cosR = math.cos(-_rotation);
      final sinR = math.sin(-_rotation);
      final unrotated = Offset(
        translated.dx * cosR - translated.dy * sinR,
        translated.dx * sinR + translated.dy * cosR,
      );
      final focalCanvas = unrotated / _scale;

      _scale = newScale;

      // canvasToScreen: scale → rotate → translate
      final scaled = focalCanvas * _scale;
      final cosRf = math.cos(_rotation);
      final sinRf = math.sin(_rotation);
      final rotated = Offset(
        scaled.dx * cosRf - scaled.dy * sinRf,
        scaled.dx * sinRf + scaled.dy * cosRf,
      );
      _offset = _zoomSpringFocalPoint - rotated;

      needsNotify = true;

      // Check if spring has settled
      if (_zoomSim!.isDone(_springStartTime)) {
        _scale = _scale.clamp(_minScale, _maxScale);
        // Recalculate offset for the exact clamped scale
        final settledScaled = focalCanvas * _scale;
        final settledRotated = Offset(
          settledScaled.dx * cosRf - settledScaled.dy * sinRf,
          settledScaled.dx * sinRf + settledScaled.dy * cosRf,
        );
        _offset = _zoomSpringFocalPoint - settledRotated;
        _isZoomSpringActive = false;
        _zoomSim = null;
        needsNotify = true;
      }
    }

    // — ZOOM MOMENTUM (Gap 4) —
    if (_isZoomMomentumActive && _zoomMomentumSim != null) {
      _zoomMomentumStartTime += t;

      // Simulation runs in log-space; convert back to linear scale
      final logScale = _zoomMomentumSim!.x(_zoomMomentumStartTime);
      final newScale = math.exp(logScale);
      final logVelocity = _zoomMomentumSim!.dx(_zoomMomentumStartTime).abs();

      // Focal-point-preserving zoom (same math as spring-back)
      final translated = _zoomMomentumFocalPoint - _offset;
      final cosR = math.cos(-_rotation);
      final sinR = math.sin(-_rotation);
      final unrotated = Offset(
        translated.dx * cosR - translated.dy * sinR,
        translated.dx * sinR + translated.dy * cosR,
      );
      final focalCanvas = unrotated / _scale;

      _scale = newScale;

      final scaled = focalCanvas * _scale;
      final cosRf = math.cos(_rotation);
      final sinRf = math.sin(_rotation);
      final rotated = Offset(
        scaled.dx * cosRf - scaled.dy * sinRf,
        scaled.dx * sinRf + scaled.dy * cosRf,
      );
      _offset = _zoomMomentumFocalPoint - rotated;

      needsNotify = true;

      // Stop conditions: very slow, or past limits (let spring-back handle)
      if (logVelocity < 0.01 || newScale < _minScale || newScale > _maxScale) {
        _isZoomMomentumActive = false;
        _zoomMomentumSim = null;

        // If past limits, trigger spring-back for seamless elastic bounce
        if (newScale < _minScale || newScale > _maxScale) {
          startZoomSpringBack(_zoomMomentumFocalPoint);
        }
      }
    }

    // — ROTATION MOMENTUM —
    if (_isRotationMomentumActive && _rotationSim != null) {
      _rotationMomentumStartTime += t;

      final newRotation = _rotationSim!.x(_rotationMomentumStartTime);
      final angularV = _rotationSim!.dx(_rotationMomentumStartTime).abs();

      if (angularV < 0.001) {
        // Check if we're near a snap angle when momentum ends
        final snapAngle = checkSnapAngle(newRotation);
        if (snapAngle != null) {
          _rotation = snapAngle;
        } else {
          _rotation = newRotation;
        }
        _isRotationMomentumActive = false;
        _rotationSim = null;
      } else {
        _rotation = newRotation;
      }
      needsNotify = true;
    }

    // — ROTATION SPRING (animated reset/snap) —
    if (_isRotationSpringActive && _rotationSpring != null) {
      _rotationSpringStartTime += t;

      _rotation = _rotationSpring!.x(_rotationSpringStartTime);
      needsNotify = true;

      if (_rotationSpring!.isDone(_rotationSpringStartTime)) {
        _rotation = _rotationSpringTarget;
        _isRotationSpringActive = false;
        _rotationSpring = null;
        needsNotify = true;
      }
    }

    // — PAN SPRING (programmatic camera move) —
    if (_isPanSpringActive &&
        _panSpringSimX != null &&
        _panSpringSimY != null) {
      _panSpringStartTime += t;

      final newX = _panSpringSimX!.x(_panSpringStartTime);
      final newY = _panSpringSimY!.x(_panSpringStartTime);

      // When running a combined transform spring, the zoom spring
      // handles offset via focal-point anchoring. For pan-only spring,
      // we drive offset directly here.
      if (!_isTransformSpringActive) {
        _offset = Offset(newX, newY);
      }

      needsNotify = true;

      final doneX = _panSpringSimX!.isDone(_panSpringStartTime);
      final doneY = _panSpringSimY!.isDone(_panSpringStartTime);
      if (doneX && doneY) {
        if (!_isTransformSpringActive) {
          _offset = Offset(newX, newY);
        }
        _isPanSpringActive = false;
        _isTransformSpringActive = false;
        _panSpringSimX = null;
        _panSpringSimY = null;
        needsNotify = true;
      }
    }

    if (needsNotify) {
      notifyListeners();
    }

    // Stop ticker if all simulations are done
    if (!isAnimating) {
      _ticker?.stop();
      // 🚀 Notify that all animations have settled (LOD precompute, etc.)
      onAnimationSettle?.call();
    }
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Helpers
  // ============================================================================

  /// Ensure the ticker is running (idempotent — safe to call multiple times).
  void _ensureTickerRunning() {
    if (_ticker != null && !_ticker!.isTicking) {
      _lastTickTime = Duration.zero;
      _ticker!.start();
    }
  }

  /// Apply rubber-band elastic clamping for zoom.
  ///
  /// When the scale is within bounds, returns it unchanged.
  /// When beyond bounds, applies logarithmic resistance so the user can
  /// "pull" past the limit but with increasing difficulty.
  double _applyElasticClamp(double rawScale) {
    final config = _liquidConfig;
    final minElastic = config.minElasticScale(_minScale);
    final maxElastic = config.maxElasticScale(_maxScale);

    if (rawScale >= _minScale && rawScale <= _maxScale) {
      return rawScale;
    }

    if (rawScale > _maxScale) {
      // How far past the limit (0.0 = at limit, 1.0+ = way past)
      final overshoot = (rawScale - _maxScale) / _maxScale;
      // 🎯 FIX: Cap overshoot — elastic is ~11% (5.0→5.55x) for liquid rubber-band,
      // but locks quickly (no asymptotic creep). The fast cap keeps drift bounded.
      final cappedOvershoot = overshoot.clamp(0.0, 0.15);
      // Logarithmic resistance: diminishing overshoot
      final dampedOvershoot =
          cappedOvershoot / (1.0 + cappedOvershoot * config.elasticResistance);
      return (_maxScale * (1.0 + dampedOvershoot)).clamp(_maxScale, maxElastic);
    }

    // rawScale < _minScale
    final undershoot = (_minScale - rawScale) / _minScale;
    // 🎯 FIX: Same cap for undershoot (zoom out past min)
    final cappedUndershoot = undershoot.clamp(0.0, 0.15);
    final dampedUndershoot =
        cappedUndershoot / (1.0 + cappedUndershoot * config.elasticResistance);
    return (_minScale * (1.0 - dampedUndershoot)).clamp(minElastic, _minScale);
  }

  // ============================================================================
  // DISPOSE
  // ============================================================================

  @override
  void dispose() {
    stopAnimation();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}
