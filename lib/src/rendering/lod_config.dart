/// ═══════════════════════════════════════════════════════════════════════════
/// 🎯 LOD (Level of Detail) threshold constants and tier computation.
///
/// SINGLE SOURCE OF TRUTH for all zoom-based LOD decisions across the engine.
/// Used by DrawingPainter, InfiniteCanvasController, and the UI canvas layer.
///
/// TIER OVERVIEW:
///   0 = Full quality   (scale ≥ 0.50)
///   1 = Simplified     (0.25 ≤ scale < 0.50)
///   2 = Thumbnails     (scale < 0.25)
/// ═══════════════════════════════════════════════════════════════════════════

/// Tier 0→1 / 1→2 boundary when zooming OUT: strokes become thumbnails.
const double kLodTier2Threshold = 0.25;

/// Tier 0→1 boundary when zooming OUT: full quality → simplified.
const double kLodTier1Threshold = 0.45;

/// Tier 1→0 boundary when zooming IN (hysteresis): back to full quality.
const double kLodTier0UpThreshold = 0.55;

/// Tier 2→1 boundary when zooming IN (hysteresis): thumbnails → simplified.
const double kLodTier1UpThreshold = 0.30;

/// Standard tier 1 upper boundary (no hysteresis context).
const double kLodTier1Standard = 0.50;

/// Budget threshold for low-zoom rendering (PDF inflation, tile budget).
const double kLodLowZoomThreshold = 0.30;

/// Compute LOD tier from [scale], with optional hysteresis based on [currentTier].
///
/// Without [currentTier]: simple non-hysteretic check.
/// With [currentTier]: uses asymmetric boundaries to prevent oscillation.
int computeLodTier(double scale, [int? currentTier]) {
  if (currentTier == null) {
    return scale < kLodTier2Threshold ? 2 : (scale < kLodTier1Standard ? 1 : 0);
  }
  if (currentTier == 0) {
    return scale < kLodTier2Threshold ? 2 : (scale < kLodTier1Threshold ? 1 : 0);
  } else if (currentTier == 1) {
    return scale < kLodTier2Threshold ? 2 : (scale >= kLodTier0UpThreshold ? 0 : 1);
  } else {
    return scale >= kLodTier0UpThreshold ? 0 : (scale >= kLodTier1UpThreshold ? 1 : 2);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🎯 TIER DETENT (resistance zones around LOD / morph thresholds).
//
// Pure asymmetric hysteresis prevents per-frame flicker but doesn't give
// the user any tactile feedback during a pinch — the camera glides past
// the boundary as if nothing happened, and the tier changes silently.
//
// Detent zones add a brief "speed bump" the user can feel: when the scale
// is within ±[kLodDetentRadius] of any threshold, the pinch delta is
// attenuated by [lodDetentFactor], so the camera lingers briefly at the
// tier change before snapping through. Pair this with the haptic clicks
// already emitted by `_checkLodTier` to get the iOS Photos / Apple Maps
// "magnetic" zoom feel.
//
// Apply ONLY during interactive gestures (`elastic = true` in
// `InfiniteCanvasController.updateTransform`). Programmatic animations
// (zoomToRect, return-to-origin, cinematic flight) must NOT be slowed —
// those are scripted moves where the detent would introduce wrong-feeling
// stutter.
// ═══════════════════════════════════════════════════════════════════════════

/// Scale points that trigger detent resistance. Match the LOD + semantic
/// morph + god-view thresholds the renderer actually keys off:
///   • 0.10 — god-view fully active (mappamondo)
///   • 0.16 — god-view starts
///   • 0.18 — semantic morph completes
///   • 0.25 — tier 1 ↔ tier 2 (zoom-out direction)
///   • 0.30 — semantic morph starts
///   • 0.45 — tier 0 → tier 1 down boundary
///   • 0.55 — tier 1 → tier 0 up boundary (zoom-in hysteresis)
const List<double> kLodDetentThresholds = [
  0.10,
  0.16,
  0.18,
  0.25,
  0.30,
  0.45,
  0.55,
];

/// Half-width of each detent zone, in scale units. The resistance is in
/// effect when `(scale - threshold).abs() < kLodDetentRadius`.
///
/// 🔧 2026-05-18 (round 2): 0.015 → 0.030 after a second "non sento
/// resistenza" device pass. At a typical pinch velocity the user covers
/// ~0.027 scale units per frame; a 0.015 zone fit in 1-2 frames of
/// damping → almost imperceptible. 0.030 fills 3-4 frames inside the
/// zone, long enough that the slowdown is felt as a tactile speed bump.
const double kLodDetentRadius = 0.030;

/// Resistance factor at the very centre of a detent zone. 0.10 means the
/// pinch delta is attenuated to 10% — the user must push 10× harder to
/// traverse the boundary. Outside the zone the factor is 1.0 (no effect).
///
/// 🔧 2026-05-18 (round 2): 0.20 → 0.10 to push the resistance over the
/// perceptual threshold during a normal-speed pinch.
const double kLodDetentMinFactor = 0.10;

/// Compute the detent resistance factor for `scale`. Returns 1.0 outside
/// any detent zone; smoothly drops toward [kLodDetentMinFactor] as the
/// scale approaches the nearest threshold.
///
/// Curve: smoothstep on the distance-to-threshold, so the transition
/// in/out of the zone has zero derivative at both ends (no perceptible
/// "edge" — the resistance fades in and out smoothly).
double lodDetentFactor(double scale) {
  double minDist = double.infinity;
  for (final t in kLodDetentThresholds) {
    final d = (scale - t).abs();
    if (d < minDist) minDist = d;
  }
  if (minDist >= kLodDetentRadius) return 1.0;
  // smoothstep: 0 at threshold, 1 at zone edge.
  final t = minDist / kLodDetentRadius;
  final eased = t * t * (3.0 - 2.0 * t);
  return kLodDetentMinFactor + (1.0 - kLodDetentMinFactor) * eased;
}

/// Integrate the detent resistance along the path from `from` → `to`.
///
/// Returns the dampened target scale: instead of accepting `to` verbatim,
/// the controller advances in [_kDetentIntegrationSteps] sub-steps,
/// multiplying each sub-step delta by [lodDetentFactor] of the segment's
/// midpoint. This is what makes a FAST pinch feel resistance — without
/// integration, a single 1.0 → 0.10 frame would jump straight past every
/// detent zone with `_scale` never sitting inside one long enough for
/// the dampening to bite.
///
/// [velocity] (scale-units/sec) modulates the resistance: slow pinch
/// (≤ [_kDetentSlowVelocity]) gets full stickiness × [_kSlowStickyBoost];
/// fast pinch (≥ [_kDetentFastVelocity]) gets reduced stickiness so
/// flicks aren't fought ([_kFastStickyDrop]). Smoothstep between.
///
/// Cost: ~12 multiply/add per call, negligible vs gesture frame budget.
double applyLodDetentToTarget(
  double from,
  double to, {
  double velocity = 0.0,
}) {
  if (from == to) return from;
  const int steps = _kDetentIntegrationSteps;
  final segment = (to - from) / steps;

  // Map velocity (abs scale-units/sec) → multiplier on the "drag" term
  // (1 − factor). Slow gesture → drag boosted, factor falls closer to 0
  // (super sticky). Fast → drag attenuated, factor rises toward 1 (light).
  final v = velocity.abs();
  final double velocityModifier;
  if (v <= _kDetentSlowVelocity) {
    velocityModifier = _kSlowStickyBoost;
  } else if (v >= _kDetentFastVelocity) {
    velocityModifier = _kFastStickyDrop;
  } else {
    // smoothstep transition between slow and fast.
    final t = (v - _kDetentSlowVelocity) /
        (_kDetentFastVelocity - _kDetentSlowVelocity);
    final eased = t * t * (3.0 - 2.0 * t);
    velocityModifier =
        _kSlowStickyBoost + (_kFastStickyDrop - _kSlowStickyBoost) * eased;
  }

  double current = from;
  for (int i = 0; i < steps; i++) {
    // Factor is evaluated at the segment MIDPOINT so the integration is
    // 2nd-order accurate (trapezoidal-rule equivalent for piecewise-
    // linear factor); avoids over-/under-damping at zone edges.
    final mid = current + segment * 0.5;
    final baseFactor = lodDetentFactor(mid);
    // Apply velocity modifier to the DRAG term, not the factor itself.
    // drag = 1 − baseFactor. Adjusted drag = drag × modifier.
    // Adjusted factor = 1 − drag × modifier.
    // Then clamp to [0, 1] so velocity boost can never invert the sign.
    final drag = 1.0 - baseFactor;
    final adjFactor = (1.0 - drag * velocityModifier).clamp(0.0, 1.0);
    current += segment * adjFactor;
  }
  return current;
}

/// Velocity (|Δscale|/sec) below which the user is treated as wanting to
/// "land" on a tier — stickiness boosted by [_kSlowStickyBoost].
const double _kDetentSlowVelocity = 0.5;

/// Velocity above which the user is treated as "flicking through" — the
/// drag is dropped to [_kFastStickyDrop] so the gesture isn't fought.
const double _kDetentFastVelocity = 2.0;

/// Drag multiplier at slow velocity. Was 1.6 (super-sticky) in the
/// first device pass → user reported "too much resistance". 1.0 means
/// slow pinch uses the BASE detent factor unchanged; only fast flicks
/// get the relief.
const double _kSlowStickyBoost = 1.0;

/// Drag multiplier at fast velocity. < 1 attenuates the drag so a flick
/// crosses zones with only a "tick" of resistance.
const double _kFastStickyDrop = 0.35;

/// Number of sub-steps used by [applyLodDetentToTarget]. 12 sub-steps
/// keep each segment ≪ [kLodDetentRadius] even for fast pinch frames
/// (Δscale ≈ 0.30 → 12 × 0.025 sub-steps), so a fast pinch lands inside
/// every detent zone the trajectory crosses. Cost: ~12 multiplies per
/// gesture frame, negligible.
const int _kDetentIntegrationSteps = 12;

/// Return the INDEX of the detent zone `scale` is currently inside, or
/// `null` when outside every zone. Used by the controller to fire a
/// single haptic click per zone entry — without this signal, the user
/// feels the dampening as "slow zoom" rather than as a tactile bump.
///
/// When two detent thresholds are close enough that their zones overlap
/// (e.g. 0.16 / 0.18), returns the index of the threshold CLOSEST to
/// `scale` so each near-pair fires two distinct entries as the camera
/// passes through.
int? lodDetentZoneAt(double scale) {
  int? bestIndex;
  double bestDist = kLodDetentRadius;
  for (int i = 0; i < kLodDetentThresholds.length; i++) {
    final d = (scale - kLodDetentThresholds[i]).abs();
    if (d < bestDist) {
      bestDist = d;
      bestIndex = i;
    }
  }
  return bestIndex;
}
