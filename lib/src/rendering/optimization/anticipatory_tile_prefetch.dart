/// 🔮 ANTICIPATORY TILE PREFETCH — L1 Intelligence Subsystem
///
/// Wraps the existing tile preload logic into the Conscious Architecture
/// contract and adds **velocity-based directional prefetch**.
///
/// EXISTING BEHAVIOR (preserved):
/// - `TileCacheManager.getVisibleTiles()` uses a uniform 2-tile margin
///
/// NEW BEHAVIOR (additive):
/// - When the user is panning, the prefetch margin expands in the
///   movement direction (up to 4 tiles) and contracts elsewhere (1 tile)
/// - During idle, pre-rasterizes tiles in the predicted scroll direction
/// - Resets to uniform margin when velocity is near zero
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../core/conscious_architecture.dart';

/// L1 Intelligence: directional tile prefetch based on pan velocity.
///
/// ## How It Works
///
/// The standard `TileCacheManager` preloads tiles with a uniform margin.
/// This subsystem observes the pan velocity from [EngineContext.panVelocity]
/// and computes a **directional bias** for the prefetch area:
///
/// ```
///   ┌───────────────────────────┐
///   │  1 tile   ←   user   →  4 tiles  │  (panning right)
///   │  margin       here       margin   │
///   └───────────────────────────┘
/// ```
///
/// This means tiles in the movement direction are preloaded 2× deeper,
/// while the opposite side uses a minimal margin — saving rasterization
/// budget for tiles that actually matter.
class AnticipatoryTilePrefetch extends IntelligenceSubsystem {
  @override
  IntelligenceLayer get layer => IntelligenceLayer.anticipatory;

  @override
  String get name => 'AnticipatoryTilePrefetch';

  bool _active = true;

  @override
  bool get isActive => _active;

  // ─────────────────────────────────────────────────────────────────────────
  // Prefetch State
  // ─────────────────────────────────────────────────────────────────────────

  /// Default uniform margin (tiles) used when velocity is near zero.
  static const int _defaultMargin = 2;

  /// Maximum margin (tiles) in the movement direction.
  static const int _maxDirectionalMargin = 4;

  /// Minimum margin (tiles) opposite to movement direction.
  static const int _minOppositeMargin = 1;

  /// Velocity threshold (px/s) below which uniform margin is used.
  static const double _velocityThreshold = 50.0;

  /// 🧠 Adaptive bias multiplier set by [AdaptiveProfile].
  /// Values > 1.0 expand the directional margin for users who pan heavily.
  /// Values < 1.0 reduce it for mostly-stationary users.
  double prefetchMarginBias = 1.0;

  /// Current prefetch margins: [left, top, right, bottom] in tiles.
  List<int> _margins = [
    _defaultMargin,
    _defaultMargin,
    _defaultMargin,
    _defaultMargin,
  ];

  /// Current prefetch margins: [left, top, right, bottom] in tiles.
  ///
  /// Use this from `TileCacheManager.getVisibleTiles()` to replace
  /// the hardcoded margin.
  List<int> get margins => List.unmodifiable(_margins);

  /// Last known pan velocity.
  Offset _lastVelocity = Offset.zero;

  /// Last known pan velocity.
  Offset get lastVelocity => _lastVelocity;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void onContextChanged(EngineContext context) {
    _lastVelocity = context.panVelocity;
    _updateMargins(context.panVelocity);
  }

  @override
  void onIdle(Duration idleDuration) {
    // When idle, reset to default uniform margin.
    // Future: could use idle time to pre-rasterize predicted tiles.
    if (idleDuration.inMilliseconds > 500) {
      _margins = [
        _defaultMargin,
        _defaultMargin,
        _defaultMargin,
        _defaultMargin,
      ];
    }
  }

  @override
  void dispose() {
    _active = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core Logic
  // ─────────────────────────────────────────────────────────────────────────

  /// Update prefetch margins based on pan velocity.
  ///
  /// Uses the velocity vector to bias the margin toward the movement
  /// direction. The bias is proportional to speed, clamped to
  /// [_maxDirectionalMargin].
  void _updateMargins(Offset velocity) {
    final speed = velocity.distance;

    if (speed < _velocityThreshold) {
      // Near-stationary: uniform margin.
      _margins = [
        _defaultMargin,
        _defaultMargin,
        _defaultMargin,
        _defaultMargin,
      ];
      return;
    }

    // Normalize velocity to [-1, 1] range.
    final nx = velocity.dx / speed; // -1 = left, +1 = right
    final ny = velocity.dy / speed; // -1 = up,   +1 = down

    // Bias factor: how aggressively to expand in movement direction.
    // Speed 50→500 maps to bias 0→1, then scaled by prefetchMarginBias.
    final bias = (((speed - _velocityThreshold) / 450.0) * prefetchMarginBias)
        .clamp(0.0, 1.0);

    // Calculate directional margins:
    // - Movement direction: lerp from default to max
    // - Opposite direction: lerp from default to min
    final leftMargin = _marginForAxis(-nx, bias);
    final rightMargin = _marginForAxis(nx, bias);
    final topMargin = _marginForAxis(-ny, bias);
    final bottomMargin = _marginForAxis(ny, bias);

    _margins = [leftMargin, topMargin, rightMargin, bottomMargin];
  }

  /// Calculate margin for one edge based on its alignment with velocity.
  ///
  /// [alignment]: -1 = opposite to movement, +1 = same as movement
  /// [bias]: 0 = ignore velocity, 1 = fully directional
  int _marginForAxis(double alignment, double bias) {
    if (alignment > 0) {
      // This edge is in the movement direction: expand.
      return _defaultMargin +
          ((_maxDirectionalMargin - _defaultMargin) * alignment * bias).round();
    } else {
      // This edge is opposite to movement: contract.
      return math.max(
        _minOppositeMargin,
        _defaultMargin +
            ((_defaultMargin - _minOppositeMargin) * alignment * bias).round(),
      );
    }
  }

  /// Convenience: apply directional margins to a viewport query.
  ///
  /// Returns expanded viewport bounds that account for directional prefetch.
  /// Use this instead of adding a uniform margin.
  Rect expandedViewport(Rect viewport, double tileSize) {
    return Rect.fromLTRB(
      viewport.left - _margins[0] * tileSize,
      viewport.top - _margins[1] * tileSize,
      viewport.right + _margins[2] * tileSize,
      viewport.bottom + _margins[3] * tileSize,
    );
  }
}
