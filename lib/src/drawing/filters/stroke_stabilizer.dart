import 'dart:ui';
import 'dart:math' as math;
import '../../systems/organic_behavior_engine.dart';

/// 🎯 Professional Stroke Stabilizer — "String Pulling" Algorithm
///
/// Uses the same approach as SAI, Procreate, and Clip Studio Paint:
/// the stabilized point is connected to the raw cursor by a virtual
/// "string" of fixed length. The stabilized point only moves when
/// the raw input exceeds the string length, and it moves toward
/// the cursor by the excess distance.
///
/// Effect:
/// - Small hand tremor → stabilized point doesn't move (filtered out)
/// - Intentional direction changes → stabilized point follows with lag
/// - Higher level → longer string → straighter lines, more lag
///
/// Level 0 = no smoothing (passthrough)
/// Level 10 = very heavy smoothing (40px string, dramatic straightening)
class StrokeStabilizer {
  /// Smoothing level (0 = none, 10 = maximum)
  int _level;

  /// Last stabilized position (the "anchor" of the string)
  Offset? _lastStabilized;

  /// 🌱 Velocity tracking for elastic string length
  Offset? _previousRaw;
  int? _previousTimestamp;
  double _lastSpeed = 0.0;

  /// String length in logical pixels, based on level.
  /// This is the minimum distance the raw input must exceed
  /// before the stabilized point starts moving.
  /// 🌱 Elastic: velocity reduces string length (fast = responsive)
  double get _stringLength {
    if (_level == 0) return 0.0;
    final base = _level * 4.0;
    if (!OrganicBehaviorEngine.elasticStabilizerEnabled) return base;
    // Fast movement (>1200 px/s) reduces string length by up to 60%
    final velocityFactor = 1.0 - (_lastSpeed / 1200.0).clamp(0.0, 0.6);
    return base * velocityFactor;
  }

  /// Catchup factor: how much of the excess distance we move per sample.
  /// Lower = smoother but more lag. Higher = more responsive.
  /// 🌱 Elastic: uses easeInOut curve instead of linear
  double get _catchup {
    // Lower levels: more responsive (0.7). Higher levels: smoother (0.35).
    final linear = 0.70 - (_level * 0.035).clamp(0.0, 0.35);
    if (!OrganicBehaviorEngine.elasticStabilizerEnabled) return linear;
    // EaseInOut: smooth acceleration/deceleration
    final t = linear; // already in 0.35–0.70 range
    return t * t * (3.0 - 2.0 * t); // Hermite smoothstep
  }

  StrokeStabilizer({int level = 0}) : _level = level.clamp(0, 10);

  /// Current stabilizer level
  int get level => _level;

  /// Update the stabilizer level
  set level(int value) {
    _level = value.clamp(0, 10);
  }

  /// Stabilize a raw input point. Returns the smoothed position.
  ///
  /// For level 0, returns the raw point unchanged (zero-cost fast path).
  /// [timestampUs] optional microsecond timestamp (avoids DateTime.now syscall)
  Offset stabilize(Offset rawPoint, {int? timestampUs}) {
    if (_level == 0) return rawPoint;

    // 🌱 Track velocity from consecutive raw points
    // 🚀 PERF: use caller-supplied timestamp to avoid DateTime.now() syscall
    final nowUs = timestampUs ?? DateTime.now().microsecondsSinceEpoch;
    if (_previousRaw != null && _previousTimestamp != null) {
      final dtSec = (nowUs - _previousTimestamp!) / 1000000.0;
      if (dtSec > 0 && dtSec < 0.1) {
        _lastSpeed = (rawPoint - _previousRaw!).distance / dtSec;
      }
    }
    _previousRaw = rawPoint;
    _previousTimestamp = nowUs;

    // First point: anchor at raw position
    if (_lastStabilized == null) {
      _lastStabilized = rawPoint;
      return rawPoint;
    }

    final anchor = _lastStabilized!;
    final dx = rawPoint.dx - anchor.dx;
    final dy = rawPoint.dy - anchor.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    final sLen = _stringLength;

    if (dist <= sLen) {
      // Raw input is within string length — don't move (filter out tremor)
      return anchor;
    }

    // Move toward raw point by (distance - stringLength) * catchup
    final excess = dist - sLen;
    final move = excess * _catchup;
    final ratio = move / dist;

    final stabilized = Offset(anchor.dx + dx * ratio, anchor.dy + dy * ratio);

    _lastStabilized = stabilized;
    return stabilized;
  }

  /// Reset the stabilizer for a new stroke
  void reset() {
    _lastStabilized = null;
    _previousRaw = null;
    _previousTimestamp = null;
    _lastSpeed = 0.0;
  }
}
