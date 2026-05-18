// ============================================================================
// 🎬 TIME TRAVEL RETENTION POLICY — Per-tier behaviour tests
//
// Locks the V1 launch contract for the time-travel ring buffer:
//   • Free → 90-day eviction window
//   • Plus / Pro / Essential → unlimited retention
//   • Playback UI (scrubber) gated to Pro only
// ============================================================================

import 'package:fluera_engine/fluera_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TimeTravelRetentionPolicy policy(FlueraSubscriptionTier tier) =>
      TimeTravelRetentionPolicy(tier: tier);

  group('retentionDays', () {
    test('Free has a 90-day window', () {
      expect(policy(FlueraSubscriptionTier.free).retentionDays, 90);
    });

    test('Plus is unlimited (-1 sentinel)', () {
      expect(policy(FlueraSubscriptionTier.plus).retentionDays,
          timeTravelRetentionUnlimited);
    });

    test('Pro is unlimited (-1 sentinel)', () {
      expect(policy(FlueraSubscriptionTier.pro).retentionDays,
          timeTravelRetentionUnlimited);
    });

    test('Essential is unlimited (legacy tier kept on parity with Plus)', () {
      expect(policy(FlueraSubscriptionTier.essential).retentionDays,
          timeTravelRetentionUnlimited);
    });
  });

  group('hasFiniteRetention', () {
    test('Only Free hits a finite retention window', () {
      expect(policy(FlueraSubscriptionTier.free).hasFiniteRetention, isTrue);
      expect(policy(FlueraSubscriptionTier.plus).hasFiniteRetention, isFalse);
      expect(policy(FlueraSubscriptionTier.pro).hasFiniteRetention, isFalse);
    });
  });

  group('evictionCutoff', () {
    test('Free cutoff is exactly 90 days before now (UTC)', () {
      final now = DateTime.utc(2026, 6, 1);
      final cutoff = policy(FlueraSubscriptionTier.free).evictionCutoff(now: now);
      expect(cutoff, isNotNull);
      expect(now.difference(cutoff!).inDays, 90);
    });

    test('Plus / Pro cutoff is null (no pruning sweep needed)', () {
      final now = DateTime.utc(2026, 6, 1);
      expect(
        policy(FlueraSubscriptionTier.plus).evictionCutoff(now: now),
        isNull,
      );
      expect(
        policy(FlueraSubscriptionTier.pro).evictionCutoff(now: now),
        isNull,
      );
    });

    test('Cutoff defaults to current wall clock when `now` is omitted', () {
      final cutoff =
          policy(FlueraSubscriptionTier.free).evictionCutoff();
      expect(cutoff, isNotNull);
      // Sanity check the cutoff is ~90 days behind now, ± a few seconds.
      final delta = DateTime.now().toUtc().difference(cutoff!).inDays;
      expect(delta, inInclusiveRange(89, 91));
    });
  });

  group('canShowPlaybackUi (Pro-only pillar)', () {
    test('Only Pro can show the scrubber overlay', () {
      expect(policy(FlueraSubscriptionTier.free).canShowPlaybackUi, isFalse);
      expect(policy(FlueraSubscriptionTier.plus).canShowPlaybackUi, isFalse,
          reason: 'Plus keeps recordings but cannot replay (Pro pillar #1)');
      expect(policy(FlueraSubscriptionTier.essential).canShowPlaybackUi,
          isFalse);
      expect(policy(FlueraSubscriptionTier.pro).canShowPlaybackUi, isTrue);
    });
  });

  group('toString carries the diagnostic fields', () {
    test('Free description contains 90 d marker', () {
      expect(policy(FlueraSubscriptionTier.free).toString(), contains('90 d'));
      expect(policy(FlueraSubscriptionTier.free).toString(),
          contains('playbackUi: false'));
    });
    test('Pro description contains ∞ marker', () {
      expect(policy(FlueraSubscriptionTier.pro).toString(), contains('∞'));
      expect(policy(FlueraSubscriptionTier.pro).toString(),
          contains('playbackUi: true'));
    });
  });

  group('Coherence with TierGateController.canUseFeature', () {
    test('Pro tier: canShowPlaybackUi ↔ tier gate canUseFeature(timeTravel)',
        () {
      final tg = TierGateController(tier: FlueraSubscriptionTier.pro);
      expect(tg.canUseFeature(GatedFeature.timeTravel), isTrue);
      expect(policy(FlueraSubscriptionTier.pro).canShowPlaybackUi, isTrue);
    });

    test('Plus tier: blocked on both sides (playback UI is Pro-only)', () {
      final tg = TierGateController(tier: FlueraSubscriptionTier.plus);
      expect(tg.canUseFeature(GatedFeature.timeTravel), isFalse);
      expect(policy(FlueraSubscriptionTier.plus).canShowPlaybackUi, isFalse);
    });

    test('Free tier: blocked on both sides', () {
      final tg = TierGateController(tier: FlueraSubscriptionTier.free);
      expect(tg.canUseFeature(GatedFeature.timeTravel), isFalse);
      expect(policy(FlueraSubscriptionTier.free).canShowPlaybackUi, isFalse);
    });
  });

  group('V1FeatureGate flag', () {
    test('timeTravel compile flag is enabled (V1 launch)', () {
      // Sanity check: the flag was flipped 2026-05-14 as part of the Pro
      // pillar #1 unlock. Recording / overlay code lives behind this
      // gate; UI access is then gated per-tier at runtime.
      expect(V1FeatureGate.timeTravel, isTrue);
    });
  });
}
