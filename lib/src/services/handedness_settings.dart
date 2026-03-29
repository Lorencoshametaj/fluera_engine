import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../utils/key_value_store.dart';

/// 🖐️ HANDEDNESS — left/right hand preference
enum Handedness {
  right,
  left,
}

/// ✋ GRIP POSITION — where the palm rests relative to the pen
enum GripPosition {
  belowRight,
  belowLeft,
  aboveRight,
  aboveLeft,
}

/// 🛡️ REJECTION REASON — why a touch was rejected (for debug overlay)
enum PalmRejectionReason {
  temporal,       // stylus active or cooldown
  areaRatio,      // elliptical contact
  velocity,       // slow-landing touch
  multiPoint,     // 2+ simultaneous touches
  wristGuard,     // near pen position
  staticZone,     // corner exclusion
  hover,          // stylus hovering nearby
  pressureCurve,  // flat pressure profile
  drift,          // near-zero movement in first 100ms
}

/// 🖐️ HANDEDNESS SETTINGS SERVICE
///
/// Singleton managing handedness preferences and palm rejection.
/// Persisted via [KeyValueStore] so settings survive app restarts.
///
/// Features:
/// - Static zone-based rejection (grip position → corner exclusion)
/// - Temporal rejection with post-stylus cooldown
/// - Touch area ratio analysis (palm = elliptical)
/// - Velocity-based rejection (slow-landing = palm)
/// - Multi-point palm detection (2+ simultaneous touches)
/// - Dynamic wrist guard (rejection relative to pen position)
/// - Stylus hover detection (aggressive rejection while hovering)
/// - Adaptive palm size learning
/// - Auto-detect handedness from stroke direction
/// - First-launch onboarding trigger
class HandednessSettings {
  // ========================================================================
  // SINGLETON
  // ========================================================================

  static final HandednessSettings instance = HandednessSettings._();
  HandednessSettings._();

  // ========================================================================
  // PERSISTED STATE
  // ========================================================================

  Handedness _handedness = Handedness.right;
  GripPosition _gripPosition = GripPosition.belowRight;
  bool _palmRejectionEnabled = true;
  double _palmZoneRatio = 0.30;
  bool _hasCompletedOnboarding = false;

  /// 🧠 ADAPTIVE: Learned palm touch radius threshold.
  /// Starts at 20px, decreases if user has smaller hands.
  double _learnedPalmThreshold = 20.0;

  bool _loaded = false;

  // ========================================================================
  // RUNTIME STATE (not persisted)
  // ========================================================================

  /// 🔴 TEMPORAL: Whether a stylus is currently touching the screen.
  bool _stylusActive = false;

  /// ⏱️ COOLDOWN: Timestamp when stylus was last lifted (ms since epoch).
  int _stylusLiftTimestamp = 0;

  /// Post-stylus cooldown duration in milliseconds.
  static const int _cooldownMs = 300;

  /// 🎯 WRIST GUARD: Last known stylus position for dynamic rejection.
  Offset? _lastStylusPosition;

  /// 🖊️ HOVER: Whether stylus is currently hovering (proximity detected).
  bool _stylusHovering = false;

  /// 📊 AUTO-DETECT: Track stroke deltas to infer handedness.
  final List<double> _strokeDeltasX = [];
  bool _autoDetectCompleted = false;

  /// 👆 MULTI-POINT: Track recent non-stylus pointer down timestamps.
  /// If 2+ arrive within 50ms → palm.
  final List<int> _recentFingerDownTimestamps = [];

  /// 🧠 ADAPTIVE: Accumulate rejected touch radii to learn palm size.
  final List<double> _rejectedRadii = [];

  /// 🐛 DEBUG: Last rejected touch info (for debug overlay).
  Offset? lastRejectedPosition;
  PalmRejectionReason? lastRejectionReason;
  int rejectedTouchCount = 0;

  /// 🎯 AUTO-CALIBRATION: Collect rejected positions to refine zone.
  final List<Offset> _rejectedPositions = [];

  /// 📊 PRESSURE CURVE: Track per-pointer pressure history (pointer ID → pressures).
  /// After 4 samples, if pressure variance < threshold → palm (flat curve).
  final Map<int, List<double>> _pressureHistory = {};

  /// 🐌 DRIFT: Track per-pointer initial position and timestamp.
  /// If after 100ms the pointer moved < 2px → likely palm.
  final Map<int, _DriftEntry> _driftTracking = {};

  // ========================================================================
  // GETTERS
  // ========================================================================

  Handedness get handedness => _handedness;
  GripPosition get gripPosition => _gripPosition;
  bool get palmRejectionEnabled => _palmRejectionEnabled;
  double get palmZoneRatio => _palmZoneRatio;
  bool get isLeftHanded => _handedness == Handedness.left;
  bool get isRightHanded => _handedness == Handedness.right;
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;
  bool get isStylusActive => _stylusActive;
  bool get isStylusHovering => _stylusHovering;
  double get learnedPalmThreshold => _learnedPalmThreshold;

  /// Whether stylus is active OR within cooldown window.
  bool get _isInStylusWindow {
    if (_stylusActive) return true;
    if (_stylusLiftTimestamp == 0) return false;
    final elapsed =
        DateTime.now().millisecondsSinceEpoch - _stylusLiftTimestamp;
    return elapsed < _cooldownMs;
  }

  // ========================================================================
  // SETTERS (auto-persist)
  // ========================================================================

  set handedness(Handedness value) {
    if (_handedness == value) return;
    _handedness = value;
    _gripPosition = value == Handedness.right
        ? GripPosition.belowRight
        : GripPosition.belowLeft;
    _save();
  }

  set gripPosition(GripPosition value) {
    if (_gripPosition == value) return;
    _gripPosition = value;
    _save();
  }

  set palmRejectionEnabled(bool value) {
    if (_palmRejectionEnabled == value) return;
    _palmRejectionEnabled = value;
    _save();
  }

  set palmZoneRatio(double value) {
    final clamped = value.clamp(0.15, 0.50);
    if (_palmZoneRatio == clamped) return;
    _palmZoneRatio = clamped;
    _save();
  }

  void markOnboardingComplete() {
    if (_hasCompletedOnboarding) return;
    _hasCompletedOnboarding = true;
    _save();
  }

  // ========================================================================
  // STYLUS LIFECYCLE TRACKING
  // ========================================================================

  void onStylusDown(Offset position) {
    _stylusActive = true;
    _stylusHovering = false; // Down replaces hover
    _lastStylusPosition = position;
  }

  void onStylusMove(Offset position) {
    _lastStylusPosition = position;
  }

  /// ⏱️ FEATURE 1: Cooldown — records lift timestamp for grace period.
  void onStylusUp() {
    _stylusActive = false;
    _stylusLiftTimestamp = DateTime.now().millisecondsSinceEpoch;
  }

  /// 🖊️ FEATURE 7: Stylus hover detection.
  /// Call when PointerHoverEvent has stylus kind.
  void onStylusHover(Offset position) {
    _stylusHovering = true;
    _lastStylusPosition = position;
  }

  /// Call when stylus exits hover range.
  void onStylusHoverExit() {
    _stylusHovering = false;
  }

  // ========================================================================
  // 👆 FEATURE 2: MULTI-POINT PALM DETECTION
  // ========================================================================

  /// Register a non-stylus pointer down event.
  /// Returns true if multi-point palm is detected (2+ within 50ms).
  bool registerFingerDown() {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Remove stale entries (older than 80ms)
    _recentFingerDownTimestamps
        .removeWhere((t) => now - t > 80);

    _recentFingerDownTimestamps.add(now);

    // 2+ finger-downs within 80ms = palm landing
    return _recentFingerDownTimestamps.length >= 2;
  }

  /// 🛡️ Clear stale multi-point timestamps at gesture end.
  /// Prevents ghost timestamps from a previous gesture from
  /// contaminating the next gesture's palm rejection check.
  void clearRecentFingerDownTimestamps() {
    _recentFingerDownTimestamps.clear();
  }

  // ========================================================================
  // AUTO-DETECT HANDEDNESS
  // ========================================================================

  void recordStrokeDirection(double deltaX) {
    if (_autoDetectCompleted || _hasCompletedOnboarding) return;

    _strokeDeltasX.add(deltaX);

    if (_strokeDeltasX.length >= 5) {
      _autoDetectCompleted = true;
      final avgDeltaX =
          _strokeDeltasX.reduce((a, b) => a + b) / _strokeDeltasX.length;

      if (avgDeltaX > 5.0 && _handedness != Handedness.right) {
        _handedness = Handedness.right;
        _gripPosition = GripPosition.belowRight;
        _save();
      } else if (avgDeltaX < -5.0 && _handedness != Handedness.left) {
        _handedness = Handedness.left;
        _gripPosition = GripPosition.belowLeft;
        _save();
      }
      _strokeDeltasX.clear();
    }
  }

  // ========================================================================
  // PALM EXCLUSION ZONE (static corner)
  // ========================================================================

  Rect getPalmExclusionZone(Size screenSize) {
    if (!_palmRejectionEnabled) return Rect.zero;

    final w = screenSize.width;
    final h = screenSize.height;
    final zoneW = w * _palmZoneRatio;
    final zoneH = h * _palmZoneRatio;

    switch (_gripPosition) {
      case GripPosition.belowRight:
        return Rect.fromLTWH(w - zoneW, h - zoneH, zoneW, zoneH);
      case GripPosition.belowLeft:
        return Rect.fromLTWH(0, h - zoneH, zoneW, zoneH);
      case GripPosition.aboveRight:
        return Rect.fromLTWH(w - zoneW, 0, zoneW, zoneH);
      case GripPosition.aboveLeft:
        return Rect.fromLTWH(0, 0, zoneW, zoneH);
    }
  }

  // ========================================================================
  // COMPREHENSIVE PALM REJECTION CHECK
  // ========================================================================

  /// Master rejection check combining ALL strategies.
  ///
  /// Returns true if the touch should be REJECTED.
  /// Stylus events must be pre-filtered — never call this for stylus.
  ///
  /// Priority order:
  /// 1. ⏱️ Temporal + cooldown
  /// 2. 🖊️ Stylus hover proximity
  /// 3. 👆 Multi-point detection
  /// 4. 🐌 Velocity-based (slow landing)
  /// 5. 📐 Touch area ratio (elliptical)
  /// 6. 🎯 Wrist guard (dynamic zone)
  /// 7. 📍 Static zone (corner)
  bool shouldRejectTouch({
    required Offset position,
    required double radiusMajor,
    required double radiusMinor,
    required Size screenSize,
    double speed = 0.0,
    Rect uiSafeZone = Rect.zero, // 🛡️ UI elements area (toolbar etc.)
  }) {
    if (!_palmRejectionEnabled) return false;

    // ── 🛡️ UI BYPASS ──
    // Never reject touches that land on toolbar or other UI elements.
    // This prevents false-positive rejection when the user intentionally
    // taps a button near a palm rejection zone.
    if (uiSafeZone != Rect.zero && uiSafeZone.contains(position)) {
      return false;
    }

    // ── ⏱️ FEATURE 1: TEMPORAL + COOLDOWN ──
    // Stylus active OR within 300ms grace period → reject ALL fingers
    if (_isInStylusWindow) {
      _recordRejection(position, PalmRejectionReason.temporal, radiusMajor);
      return true;
    }

    // ── 🖊️ FEATURE 7: STYLUS HOVER ──
    // If stylus is hovering above screen, reject all finger touches.
    // The user is about to draw → any finger is almost certainly palm.
    if (_stylusHovering) {
      _recordRejection(position, PalmRejectionReason.hover, radiusMajor);
      return true;
    }

    // 👆 FEATURE 2: MULTI-POINT DETECTION — moved to END of this method.
    // Previously here, but rejected-by-velocity touches still registered
    // timestamps that cascade-rejected the next finger (pan freeze bug).

    // ── 🐌 FEATURE 3: VELOCITY-BASED ──
    // Palm lands with near-zero velocity. Intentional touches have speed > 0.
    // Only trigger for large contact area (don't reject fingertip taps).
    if (speed < 0.5 && radiusMajor > _learnedPalmThreshold) {
      _recordRejection(position, PalmRejectionReason.velocity, radiusMajor);
      return true;
    }

    // ── 📐 TOUCH AREA RATIO ──
    if (radiusMajor > 0 && radiusMinor > 0) {
      final ratio = radiusMajor / radiusMinor;
      if (ratio > 1.8 && radiusMajor > _learnedPalmThreshold) {
        _recordRejection(position, PalmRejectionReason.areaRatio, radiusMajor);
        return true;
      }
    }

    // ── 🎯 WRIST GUARD (dynamic) ──
    if (_lastStylusPosition != null && radiusMajor > 15.0) {
      final wristZone = _getWristGuardZone(_lastStylusPosition!, screenSize);
      if (wristZone.contains(position)) {
        _recordRejection(position, PalmRejectionReason.wristGuard, radiusMajor);
        return true;
      }
    }

    // ── 📍 STATIC ZONE (corner) ──
    if (radiusMajor > 15.0) {
      final zone = getPalmExclusionZone(screenSize);
      if (zone != Rect.zero && zone.contains(position)) {
        _recordRejection(position, PalmRejectionReason.staticZone, radiusMajor);
        return true;
      }
    }

    // ── 👆 FEATURE 2: MULTI-POINT DETECTION ──
    // 🐛 FIX: Moved to END so that touches rejected by velocity/area/zone
    // checks above do NOT register a timestamp. Previously, a rejected
    // first-finger registered a timestamp, causing the second finger
    // (arriving within 80ms for pan) to be auto-rejected as "multi-point
    // palm", preventing _pointerCount from reaching 2 and blocking pan.
    if (registerFingerDown()) {
      _recordRejection(position, PalmRejectionReason.multiPoint, radiusMajor);
      return true;
    }

    return false;
  }

  // ========================================================================
  // 🐛 DEBUG + 🧠 ADAPTIVE LEARNING
  // ========================================================================

  /// Public API for recording a deferred rejection (from gesture detector).
  /// Used when pressure curve or drift analysis detects a palm after initial check.
  void recordDeferredRejection(
      Offset position, PalmRejectionReason reason, double radiusMajor) {
    _recordRejection(position, reason, radiusMajor);
  }

  /// ⏱️ Throttle: last time haptic fired for rejection (ms since epoch).
  int _lastRejectionHapticTime = 0;

  void _recordRejection(
      Offset position, PalmRejectionReason reason, double radiusMajor) {
    // 🐛 Debug info
    lastRejectedPosition = position;
    lastRejectionReason = reason;
    rejectedTouchCount++;

    // 📳 Haptic — throttled to max 1x per 500ms to avoid infinite vibration
    // when palm rests on screen during stylus drawing.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRejectionHapticTime > 500) {
      _lastRejectionHapticTime = now;
      HapticFeedback.lightImpact();
    }

    // 🧠 ADAPTIVE LEARNING — collect radii to refine threshold
    if (radiusMajor > 5.0) {
      _rejectedRadii.add(radiusMajor);
      if (_rejectedRadii.length >= 20) {
        _updateLearnedThreshold();
      }
    }

    // 🎯 AUTO-CALIBRATION — collect positions for zone refinement
    _rejectedPositions.add(position);
    // screenSize not available here, will be called from gesture detector
  }

  /// Trigger auto-calibration check. Call from gesture detector with screen size.
  void triggerAutoCalibration(Size screenSize) {
    if (_rejectedPositions.length >= 15) {
      _autoCalibrate(screenSize);
    }
  }

  /// 🧠 Recalculate palm threshold from observed rejected touch radii.
  ///
  /// Uses p25 (25th percentile) of rejected radii — this ensures we
  /// catch palms that are smaller than average while not rejecting
  /// normal fingertips.
  void _updateLearnedThreshold() {
    if (_rejectedRadii.length < 10) return;

    final sorted = List<double>.from(_rejectedRadii)..sort();
    final p25Index = (sorted.length * 0.25).floor();
    final newThreshold = sorted[p25Index].clamp(12.0, 30.0);

    if ((newThreshold - _learnedPalmThreshold).abs() > 1.0) {
      _learnedPalmThreshold = newThreshold;
      _save(); // Persist learned threshold
    }

    // Keep only last 10 for rolling average
    _rejectedRadii.removeRange(0, _rejectedRadii.length - 10);
  }

  // ========================================================================
  // 📊 PRESSURE CURVE ANALYSIS
  // ========================================================================

  /// Record a pressure sample for a given pointer.
  /// Call on every PointerMoveEvent for non-stylus pointers.
  /// Returns true if the touch should now be rejected (flat pressure = palm).
  bool recordPressureSample(int pointerId, double pressure) {
    if (!_palmRejectionEnabled) return false;

    final history = _pressureHistory.putIfAbsent(pointerId, () => []);
    history.add(pressure);

    // Need at least 4 samples for analysis
    if (history.length < 4) return false;

    // Keep only last 6 samples
    if (history.length > 6) history.removeAt(0);

    // Calculate pressure variance
    final mean = history.reduce((a, b) => a + b) / history.length;
    double variance = 0;
    for (final p in history) {
      variance += (p - mean) * (p - mean);
    }
    variance /= history.length;

    // Palm = very flat pressure (variance < 0.001)
    // Finger = variable pressure (variance > 0.005)
    // Only reject if pressure is also high (> 0.5) — low flat = hovering
    if (variance < 0.001 && mean > 0.5) {
      clearPointerTracking(pointerId);
      return true;
    }

    return false;
  }

  // ========================================================================
  // 🐌 TOUCH DRIFT ANALYSIS
  // ========================================================================

  /// Begin tracking drift for a new pointer.
  void beginDriftTracking(int pointerId, Offset startPosition) {
    if (!_palmRejectionEnabled) return;
    _driftTracking[pointerId] = _DriftEntry(
      startPosition: startPosition,
      startTime: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Check if a pointer is drifting (barely moving) — indicates palm.
  /// Call on PointerMoveEvent. Returns true if drift pattern detected.
  bool checkDrift(int pointerId, Offset currentPosition, double radiusMajor) {
    if (!_palmRejectionEnabled) return false;

    final entry = _driftTracking[pointerId];
    if (entry == null) return false;

    final elapsed =
        DateTime.now().millisecondsSinceEpoch - entry.startTime;

    // Only check after 100ms
    if (elapsed < 100) return false;

    // Already checked — only check once
    _driftTracking.remove(pointerId);

    final distance = (currentPosition - entry.startPosition).distance;

    // < 2px movement in 100ms + large contact = palm resting
    if (distance < 2.0 && radiusMajor > 15.0) {
      return true;
    }

    return false;
  }

  /// Clean up tracking for a removed pointer.
  void clearPointerTracking(int pointerId) {
    _pressureHistory.remove(pointerId);
    _driftTracking.remove(pointerId);
  }

  // ========================================================================
  // 🎯 AUTO-CALIBRATION — learn zone from rejected touches
  // ========================================================================

  /// Auto-calibrate zone position and size from rejected touch clusters.
  /// Called periodically from _recordRejection.
  void _autoCalibrate(Size screenSize) {
    if (_rejectedPositions.length < 15) return;

    // Compute centroid and spread of rejected positions
    double sumX = 0, sumY = 0;
    for (final p in _rejectedPositions) {
      sumX += p.dx;
      sumY += p.dy;
    }
    final cx = sumX / _rejectedPositions.length;
    final cy = sumY / _rejectedPositions.length;

    // Determine which corner the centroid is closest to
    final w = screenSize.width;
    final h = screenSize.height;
    final isRight = cx > w / 2;
    final isBelow = cy > h / 2;

    final inferred = isBelow
        ? (isRight ? GripPosition.belowRight : GripPosition.belowLeft)
        : (isRight ? GripPosition.aboveRight : GripPosition.aboveLeft);

    // Only auto-calibrate if user hasn't set onboarding
    // (respect manual setting)
    if (!_hasCompletedOnboarding && inferred != _gripPosition) {
      _gripPosition = inferred;
      // Also infer handedness
      _handedness = (inferred == GripPosition.belowRight ||
              inferred == GripPosition.aboveRight)
          ? Handedness.right
          : Handedness.left;
      _save();
    }

    // Compute spread to auto-tune zone ratio
    double maxDist = 0;
    for (final p in _rejectedPositions) {
      final dist = (p - Offset(cx, cy)).distance;
      if (dist > maxDist) maxDist = dist;
    }
    // Map spread to zone ratio (120px spread → 25%, 250px → 45%)
    final suggestedRatio = (maxDist / (w * 0.8)).clamp(0.20, 0.45);
    if ((suggestedRatio - _palmZoneRatio).abs() > 0.05) {
      _palmZoneRatio = suggestedRatio;
      _save();
    }

    // Keep last 5 for next calibration
    _rejectedPositions.removeRange(0, _rejectedPositions.length - 5);
  }

  // ========================================================================
  // WRIST GUARD — dynamic zone around pen position
  // ========================================================================

  Rect _getWristGuardZone(Offset penPos, Size screenSize) {
    const double guardRadius = 120.0;

    double dx = 0, dy = 0;
    switch (_gripPosition) {
      case GripPosition.belowRight:
        dx = guardRadius * 0.7;
        dy = guardRadius;
        break;
      case GripPosition.belowLeft:
        dx = -guardRadius * 0.7;
        dy = guardRadius;
        break;
      case GripPosition.aboveRight:
        dx = guardRadius * 0.7;
        dy = -guardRadius;
        break;
      case GripPosition.aboveLeft:
        dx = -guardRadius * 0.7;
        dy = -guardRadius;
        break;
    }

    final center = Offset(
      (penPos.dx + dx).clamp(0, screenSize.width),
      (penPos.dy + dy).clamp(0, screenSize.height),
    );

    return Rect.fromCenter(
        center: center, width: guardRadius * 2, height: guardRadius * 2);
  }

  // ========================================================================
  // PERSISTENCE
  // ========================================================================

  static const String _keyHandedness = 'fluera_handedness';
  static const String _keyGripPosition = 'fluera_grip_position';
  static const String _keyPalmRejection = 'fluera_palm_rejection_enabled';
  static const String _keyPalmZoneRatio = 'fluera_palm_zone_ratio';
  static const String _keyOnboarding = 'fluera_handedness_onboarding';
  static const String _keyLearnedThreshold = 'fluera_palm_learned_threshold';

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final prefs = await KeyValueStore.getInstance();

    final h = prefs.getString(_keyHandedness);
    if (h == 'left') _handedness = Handedness.left;
    if (h == 'right') _handedness = Handedness.right;

    final g = prefs.getString(_keyGripPosition);
    switch (g) {
      case 'belowRight':
        _gripPosition = GripPosition.belowRight;
        break;
      case 'belowLeft':
        _gripPosition = GripPosition.belowLeft;
        break;
      case 'aboveRight':
        _gripPosition = GripPosition.aboveRight;
        break;
      case 'aboveLeft':
        _gripPosition = GripPosition.aboveLeft;
        break;
    }

    _palmRejectionEnabled = prefs.getBool(_keyPalmRejection) ?? true;
    _palmZoneRatio = prefs.getDouble(_keyPalmZoneRatio) ?? 0.30;
    _hasCompletedOnboarding = prefs.getBool(_keyOnboarding) ?? false;
    _learnedPalmThreshold = prefs.getDouble(_keyLearnedThreshold) ?? 20.0;
  }

  Future<void> _save() async {
    final prefs = await KeyValueStore.getInstance();
    await prefs.setString(_keyHandedness, _handedness.name);
    await prefs.setString(_keyGripPosition, _gripPosition.name);
    await prefs.setBool(_keyPalmRejection, _palmRejectionEnabled);
    await prefs.setDouble(_keyPalmZoneRatio, _palmZoneRatio);
    await prefs.setBool(_keyOnboarding, _hasCompletedOnboarding);
    await prefs.setDouble(_keyLearnedThreshold, _learnedPalmThreshold);
  }
}

/// 🐌 Drift tracking entry for a single pointer.
class _DriftEntry {
  final Offset startPosition;
  final int startTime;

  const _DriftEntry({
    required this.startPosition,
    required this.startTime,
  });
}
