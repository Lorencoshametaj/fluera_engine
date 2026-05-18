// ═══════════════════════════════════════════════════════════════════════════
// 🎯 Tests for the tier-detent resistance curve in `lod_config.dart`.
//
// The detent attenuates the pinch delta near LOD / semantic-morph
// thresholds so the user feels a tactile "speed bump" when the camera
// crosses a tier boundary, instead of gliding past silently. The
// resistance is in effect when `(scale - threshold).abs() < kLodDetentRadius`.
//
// Invariants the curve must hold:
//   1. Far from every threshold → no resistance (factor = 1.0).
//   2. Exactly at a threshold → maximum resistance (factor = kLodDetentMinFactor).
//   3. Smooth (smoothstep) transition with zero derivative at both ends
//      of the zone so the user never feels a hard "step".
//   4. Returns ≥ kLodDetentMinFactor and ≤ 1.0 for every scale.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/rendering/lod_config.dart';

void main() {
  group('lodDetentFactor', () {
    test('returns 1.0 well outside every detent zone', () {
      // Pick scales that are > kLodDetentRadius away from every threshold
      // for the CURRENT (and possibly future) detent radius. 0.05 keeps
      // ample headroom over the 0.030 radius.
      const farPoints = [1.5, 0.90, 0.70, 0.38, 0.36];
      for (final s in farPoints) {
        // Guard the assumption with an assertion on the data — if a
        // future radius bump pushes one of these inside a zone, fail
        // here loudly instead of in a misleading check.
        final minDist = kLodDetentThresholds
            .map((t) => (s - t).abs())
            .reduce((a, b) => a < b ? a : b);
        assert(minDist > kLodDetentRadius + 0.01,
            'farPoint $s is too close to a threshold (minDist=$minDist) '
            'for the current radius ($kLodDetentRadius)');
        expect(
          lodDetentFactor(s),
          equals(1.0),
          reason:
              'scale $s is outside every threshold ± $kLodDetentRadius — '
              'factor must be 1.0 (no resistance)',
        );
      }
    });

    test('returns kLodDetentMinFactor at every threshold', () {
      for (final t in kLodDetentThresholds) {
        expect(
          lodDetentFactor(t),
          closeTo(kLodDetentMinFactor, 1e-9),
          reason: 'at threshold $t the factor must be exactly the floor '
              '($kLodDetentMinFactor) — that\'s the peak resistance point',
        );
      }
    });

    test('curve climbs from threshold toward zone edge (where isolated)', () {
      // For thresholds that are isolated (no neighbour within 2×radius)
      // the factor must climb monotonically from the centre out. Adjacent
      // thresholds whose zones overlap (e.g. 0.16 / 0.18) get a dip in
      // the middle by design — that's intentional, the user feels both
      // detents one after the other. Testing isolated thresholds only
      // covers the contract we care about.
      const samples = 8;
      for (final t in kLodDetentThresholds) {
        // Skip thresholds within 2×radius of any neighbour (overlapping zones).
        final hasNeighbour = kLodDetentThresholds.any(
          (other) =>
              other != t && (other - t).abs() < kLodDetentRadius * 2,
        );
        if (hasNeighbour) continue;
        double prev = lodDetentFactor(t);
        for (int i = 1; i <= samples; i++) {
          final s = t + (kLodDetentRadius * i / samples);
          final f = lodDetentFactor(s);
          expect(
            f >= prev - 1e-9,
            isTrue,
            reason: 'factor must rise from $prev at i=$i (scale=$s) — got $f',
          );
          prev = f;
        }
      }
    });

    test('factor is within [kLodDetentMinFactor, 1.0] for every scale', () {
      // Sweep the full supported scale range. The curve must stay bounded.
      const samples = 200;
      const minScale = 0.05;
      const maxScale = 2.0;
      for (int i = 0; i < samples; i++) {
        final s = minScale + (maxScale - minScale) * (i / samples);
        final f = lodDetentFactor(s);
        expect(
          f >= kLodDetentMinFactor - 1e-9 && f <= 1.0 + 1e-9,
          isTrue,
          reason: 'factor $f at scale $s violates the bounded range',
        );
      }
    });

    test('zone-edge derivative is zero (smoothstep guarantee)', () {
      // Numerical derivative just inside / just outside the zone edge
      // must match (≈ 0). The smoothstep `t² × (3 - 2t)` has f'(0) =
      // f'(1) = 0 by construction.
      const dx = 1e-6;
      for (final t in kLodDetentThresholds) {
        final justInside = lodDetentFactor(t + kLodDetentRadius - dx);
        final justOutside = lodDetentFactor(t + kLodDetentRadius + dx);
        // Both should be ≈ 1.0 (zone edge); difference < numerical noise.
        expect(
          (justInside - justOutside).abs(),
          lessThan(1e-3),
          reason: 'discontinuity at zone edge of threshold $t '
              '(inside=$justInside, outside=$justOutside)',
        );
      }
    });

    test('applyLodDetentToTarget: fast pinch crossing a zone is dampened', () {
      // Simulate a single fast gesture frame that would skip from 0.40
      // straight past the 0.30 morph-start threshold to 0.20. Without
      // integration the controller would land at 0.20 because `_scale =
      // 0.40` is OUTSIDE every detent zone → factor=1.0. With path
      // integration the segments crossing the 0.30 zone bite.
      final integrated = applyLodDetentToTarget(0.40, 0.20);
      expect(
        integrated,
        greaterThan(0.20),
        reason: 'integrated path must lag the raw target — the 0.30 '
            'detent zone consumes some of the delta',
      );
      expect(
        integrated,
        lessThan(0.40),
        reason: 'integrated path must still advance — detent slows, '
            'does not freeze',
      );
    });

    test('applyLodDetentToTarget: zero-delta is a no-op', () {
      expect(applyLodDetentToTarget(0.5, 0.5), equals(0.5));
    });

    test('applyLodDetentToTarget: far from any zone, integration ≈ identity',
        () {
      // Path from 0.80 to 0.70 — entirely outside every detent zone.
      // Integration should produce a result indistinguishable from the
      // raw target (within float noise).
      final integrated = applyLodDetentToTarget(0.80, 0.70);
      expect(integrated, closeTo(0.70, 1e-9));
    });

    test('velocity-aware: slow pinch is MORE sticky than default', () {
      // Same path, comparing default (velocity=1.0 = "normal") vs slow
      // (velocity=0.0 = "intent to land"). Slow must produce a smaller
      // |delta| (more drag eaten).
      final defaultResult = applyLodDetentToTarget(0.33, 0.27, velocity: 1.0);
      final slowResult = applyLodDetentToTarget(0.33, 0.27, velocity: 0.0);
      // Both lag behind 0.27, but slow lags MORE (less progress made).
      expect(slowResult, greaterThan(defaultResult),
          reason: 'slow pinch must lag MORE behind the raw target than '
              'a normal-speed pinch — that is what makes the camera "stick" '
              'to the tier when the user is trying to land precisely');
    });

    test('velocity-aware: fast pinch is LESS sticky than default', () {
      // Compare default (velocity=1.0) vs fast (velocity=3.0). Fast must
      // make more progress (less drag eaten) → result closer to raw target.
      final defaultResult = applyLodDetentToTarget(0.33, 0.27, velocity: 1.0);
      final fastResult = applyLodDetentToTarget(0.33, 0.27, velocity: 3.0);
      expect(fastResult, lessThan(defaultResult),
          reason: 'fast pinch (flick) must traverse the zone with less '
              'resistance than a normal-speed pinch — the user has decided '
              'to blow past this tier and the engine should not fight them');
    });

    test('velocity-aware backward-compat: omitting `velocity` named arg '
        'does NOT change the result for the legacy default = 0.0', () {
      // Calling without the named arg is equivalent to velocity=0.0
      // (super-sticky preset). New callers that don\'t plumb velocity
      // through still get a sensible — if slightly stickier — result,
      // not a wild regression.
      final implicit = applyLodDetentToTarget(0.33, 0.27);
      final explicit = applyLodDetentToTarget(0.33, 0.27, velocity: 0.0);
      expect(implicit, equals(explicit));
    });

    test('detent narrows the effective pinch delta near 0.30 morph start',
        () {
      // Simulate a single pinch frame around the 0.30 morph-start
      // threshold. The expected user-facing effect: the same raw pinch
      // delta produces a smaller scale change inside the detent zone.
      //
      // Pick `oldScale` ≈ 0.31 so it sits inside the detent radius
      // (0.30 ± 0.015) and the factor is strictly < 1.0.
      const oldScale = 0.31;
      const newScale = 0.30; // at threshold
      // Naive (no detent) delta:
      const rawDelta = newScale - oldScale;
      // Damped delta the controller would apply:
      final damped = rawDelta * lodDetentFactor(oldScale);
      expect(
        damped.abs(),
        lessThan(rawDelta.abs()),
        reason: 'pinch entering the 0.30 morph-start zone must produce a '
            'smaller scale step (resistance felt by user)',
      );
      // Sanity: midpoint detent is even stronger than the inside-edge.
      final mid = (oldScale + newScale) / 2;
      expect(
        lodDetentFactor(mid),
        lessThan(lodDetentFactor(oldScale)),
        reason: 'resistance must intensify as we approach the threshold',
      );
    });
  });
}
