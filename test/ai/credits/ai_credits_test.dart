// ============================================================================
// 💎 AI CREDITS — Unit tests for the engine-side primitives
//
// Covers:
//   • AiCreditsCosts: cost table values match the V1 pricing decision
//   • AiCreditsSnapshot: derived getters (total, canAfford, usedFraction)
//   • NoopAiCreditsController: every operation succeeds without blocking
//
// The Supabase-backed implementation lives in the Fluera app layer; its
// tests run against a real Supabase test project and live in
// Fluera/test/services/supabase_ai_credits_controller_test.dart.
// ============================================================================

import 'package:fluera_engine/fluera_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiCreditsCosts', () {
    test('matches the V1 pricing decision 2026-05-14', () {
      expect(AiCreditsCosts.atlas, 0,
          reason: 'Atlas must stay free — UX core conversational pillar');
      expect(AiCreditsCosts.chat, 1,
          reason: 'Chat is high-frequency, cheapest premium feature');
      expect(AiCreditsCosts.backgroundOcr, 1);
      expect(AiCreditsCosts.ghostMap, 8);
      expect(AiCreditsCosts.socraticStage, 4);
      expect(AiCreditsCosts.examQuestion, 12);
    });

    test('costOf returns the right credit value per feature', () {
      expect(AiCreditsCosts.costOf(AiCreditFeature.atlas), 0);
      expect(AiCreditsCosts.costOf(AiCreditFeature.chat), 1);
      expect(AiCreditsCosts.costOf(AiCreditFeature.backgroundOcr), 1);
      expect(AiCreditsCosts.costOf(AiCreditFeature.ghostMap), 8);
      expect(AiCreditsCosts.costOf(AiCreditFeature.socraticStage), 4);
      expect(AiCreditsCosts.costOf(AiCreditFeature.examQuestion), 12);
    });

    test('monthlyAllowance contains the V1 tiers', () {
      expect(AiCreditsCosts.monthlyAllowance['free'], 100);
      expect(AiCreditsCosts.monthlyAllowance['plus'], 500);
      expect(AiCreditsCosts.monthlyAllowance['pro'], 2000);
    });

    test('Pro is 4× Plus to support the "studio amplificato" narrative', () {
      final plus = AiCreditsCosts.monthlyAllowance['plus']!;
      final pro = AiCreditsCosts.monthlyAllowance['pro']!;
      expect(pro, plus * 4);
    });

    test('sparkPackCredits exposes 250 and 500 sizes', () {
      expect(AiCreditsCosts.sparkPackCredits['spark.250'], 250);
      expect(AiCreditsCosts.sparkPackCredits['spark.500'], 500);
    });

    test('Plus tier covers ~30 Ghost Map sessions per month', () {
      // 500 credits / 8 cr per Ghost Map = 62 sessions max (single-use).
      // Realistic mix sanity check: a study month spends ≤ 500 credits when
      // doing 30 Ghost Map + 5 Socratic + 5 Exam + 60 chat msgs.
      final mix = 30 * AiCreditsCosts.ghostMap +
          5 * 7 * AiCreditsCosts.socraticStage + // 7 stages per session
          5 * AiCreditsCosts.examQuestion +
          60 * AiCreditsCosts.chat;
      // 240 + 140 + 60 + 60 = 500 — exactly the Plus allowance by design.
      expect(mix, lessThanOrEqualTo(AiCreditsCosts.monthlyAllowance['plus']!));
    });
  });

  group('AiCreditsSnapshot', () {
    AiCreditsSnapshot snap({
      int monthly = 100,
      int pack = 0,
      String tier = 'free',
    }) =>
        AiCreditsSnapshot(
          monthlyCredits: monthly,
          packCredits: pack,
          tier: tier,
          monthlyResetAt: DateTime.utc(2030, 1, 1),
        );

    test('total sums pack + monthly', () {
      expect(snap(monthly: 100, pack: 50).total, 150);
      expect(snap(monthly: 0, pack: 0).total, 0);
    });

    test('canAfford respects total balance', () {
      final s = snap(monthly: 50, pack: 50);
      expect(s.canAfford(100), isTrue);
      expect(s.canAfford(101), isFalse);
    });

    test('isExhausted only at total == 0', () {
      expect(snap(monthly: 0, pack: 0).isExhausted, isTrue);
      expect(snap(monthly: 0, pack: 1).isExhausted, isFalse);
      expect(snap(monthly: 1, pack: 0).isExhausted, isFalse);
    });

    test('monthlyUsedFraction reports consumed share of the tier allowance', () {
      // Free user with 25/100 monthly credits left → 75% used.
      final s = snap(monthly: 25, tier: 'free');
      expect(s.monthlyUsedFraction, closeTo(0.75, 0.0001));
    });

    test('monthlyUsedFraction is 0 for unknown tiers (no division by zero)', () {
      final s = snap(monthly: 50, tier: 'mystery_tier');
      expect(s.monthlyUsedFraction, 0.0);
    });
  });

  group('NoopAiCreditsController', () {
    test('consume always succeeds and returns a receipt with the right cost',
        () async {
      final ctrl = NoopAiCreditsController();
      final receipt = await ctrl.consume(AiCreditFeature.ghostMap);
      expect(receipt.feature, AiCreditFeature.ghostMap);
      expect(receipt.cost, AiCreditsCosts.ghostMap);
      expect(receipt.idempotencyKey, startsWith('noop-'));
      ctrl.dispose();
    });

    test('refund is a no-op (does not throw)', () async {
      final ctrl = NoopAiCreditsController();
      await ctrl.refund('any-key'); // should not throw
      ctrl.dispose();
    });

    test('credits.value carries a default snapshot for UI binding', () {
      final ctrl = NoopAiCreditsController();
      final snap = ctrl.credits.value;
      expect(snap, isNotNull);
      expect(snap!.tier, 'free');
      expect(snap.total, greaterThan(0),
          reason: 'Default snapshot must let happy-path call sites run');
      ctrl.dispose();
    });

    test('updateTier mutates the snapshot tier field', () async {
      final ctrl = NoopAiCreditsController();
      await ctrl.updateTier('pro');
      expect(ctrl.credits.value?.tier, 'pro');
      ctrl.dispose();
    });
  });

  group('AiCreditsExhaustedException', () {
    test('carries needed/available/resetAt for UI rendering', () {
      final exc = AiCreditsExhaustedException(
        feature: AiCreditFeature.ghostMap,
        needed: 8,
        available: 3,
        resetAt: DateTime.utc(2030, 1, 1),
      );
      expect(exc.feature, AiCreditFeature.ghostMap);
      expect(exc.needed, 8);
      expect(exc.available, 3);
      expect(exc.resetAt, DateTime.utc(2030, 1, 1));
    });
  });
}
