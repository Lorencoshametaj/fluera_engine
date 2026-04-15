// ============================================================================
// 🧪 UNIT TESTS — Onboarding, Celebrations, Tier Gating
//
// QA Criteria: CA-A13.8, CA-A17, CA-A20.1
// ============================================================================

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/onboarding_controller.dart';
import 'package:fluera_engine/src/canvas/ai/celebration_controller.dart';
import 'package:fluera_engine/src/canvas/ai/tier_gate_controller.dart';
import 'package:fluera_engine/src/canvas/fluera_canvas_config.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // ONBOARDING (A20.1)
  // ═══════════════════════════════════════════════════════════════════════════

  group('OnboardingController', () {
    test('new user sees seed node', () {
      final ctrl = OnboardingController();
      expect(ctrl.isComplete, isFalse);
      expect(ctrl.shouldShowSeed, isTrue);
      expect(ctrl.seedNode, isNotNull);
    });

    test('seed node has correct Italian content (A20.1-01)', () {
      expect(OnboardingSeedNode.it.paragraphs.first,
          'Come funziona la memoria?');
      expect(OnboardingSeedNode.it.locale, 'it');
    });

    test('seed node has correct English content', () {
      expect(OnboardingSeedNode.en.paragraphs.first,
          'How does memory work?');
      expect(OnboardingSeedNode.en.locale, 'en');
    });

    test('forLocale falls back to Italian', () {
      expect(OnboardingSeedNode.forLocale('de').locale, 'it');
      expect(OnboardingSeedNode.forLocale('en-US').locale, 'en');
    });

    test('write prompt vanishes on first stroke (A20.1-05)', () {
      final ctrl = OnboardingController();
      expect(ctrl.isPromptVisible, isTrue);
      ctrl.onFirstStroke();
      expect(ctrl.isPromptVisible, isFalse);
      // But seed is still visible.
      expect(ctrl.shouldShowSeed, isTrue);
    });

    test('markComplete removes seed (A20.1-10)', () {
      final ctrl = OnboardingController();
      ctrl.markComplete();
      expect(ctrl.isComplete, isTrue);
      expect(ctrl.shouldShowSeed, isFalse);
      expect(ctrl.seedNode, isNull);
    });

    test('seed is freely deletable (A20.1-09)', () {
      final ctrl = OnboardingController();
      ctrl.onSeedDeleted();
      expect(ctrl.isComplete, isTrue);
    });

    test('returning user does not see seed', () {
      final ctrl = OnboardingController(isComplete: true);
      expect(ctrl.shouldShowSeed, isFalse);
      expect(ctrl.isPromptVisible, isFalse);
    });

    test('serialization round-trip', () {
      final ctrl = OnboardingController();
      ctrl.markComplete();
      final json = ctrl.toJson();
      final restored = OnboardingController.fromJson(json);
      expect(restored.isComplete, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CELEBRATIONS (A13.8)
  // ═══════════════════════════════════════════════════════════════════════════

  group('CelebrationController', () {
    late CelebrationController ctrl;

    setUp(() {
      ctrl = CelebrationController();
      ctrl.setHasEverRecalled(true); // Skip first-recall logic
    });
    tearDown(() => ctrl.dispose());

    test('no pending celebration initially', () {
      expect(ctrl.hasPending, isFalse);
      expect(ctrl.pendingCelebration, isNull);
    });

    test('perfect recall triggers "Solido." (A13.8-01)', () {
      ctrl.onRecallSessionComplete(remembered: 8, total: 8);
      expect(ctrl.hasPending, isTrue);
      final event = ctrl.pendingCelebration!;
      expect(event.type, CelebrationType.recallPerfect);
      expect(event.message, 'Solido.');
      expect(event.durationMs, lessThanOrEqualTo(2000));
    });

    test('imperfect recall does not trigger celebration', () {
      ctrl.onRecallSessionComplete(remembered: 7, total: 8);
      expect(ctrl.hasPending, isFalse);
    });

    test('< 5 nodes does not trigger celebration', () {
      ctrl.onRecallSessionComplete(remembered: 3, total: 3);
      expect(ctrl.hasPending, isFalse);
    });

    test('first ever recall triggers special message', () {
      final fresh = CelebrationController();
      fresh.onRecallSessionComplete(remembered: 1, total: 5);
      expect(fresh.hasPending, isTrue);
      expect(fresh.pendingCelebration!.type, CelebrationType.firstRecall);
      expect(fresh.pendingCelebration!.message,
          'Il primo ricordo è il più importante.');
      fresh.dispose();
    });

    test('stability milestone: stage 4 = Radicato', () {
      ctrl.onStabilityMilestone(newStage: 4,
          nodePosition: const Offset(100, 100));
      final event = ctrl.pendingCelebration!;
      expect(event.type, CelebrationType.stabilityGain);
      expect(event.message, '🌳 Radicato');
      expect(event.anchorPosition, const Offset(100, 100));
    });

    test('stability milestone: stage 5 = Padroneggiato', () {
      ctrl.onStabilityMilestone(newStage: 5);
      expect(ctrl.pendingCelebration!.message, '⭐ Padroneggiato');
    });

    test('stage 3 does not trigger celebration', () {
      ctrl.onStabilityMilestone(newStage: 3);
      expect(ctrl.hasPending, isFalse);
    });

    test('bridge formed triggers celebration', () {
      ctrl.onBridgeFormed(bridgeMidpoint: const Offset(50, 50));
      final event = ctrl.pendingCelebration!;
      expect(event.type, CelebrationType.bridgeFormed);
      expect(event.message, '🌉 Ponte creato');
    });

    test('fog cleared ≥90% triggers "Sei pronto."', () {
      ctrl.onFogCleared(correctCount: 18, totalCount: 20);
      final event = ctrl.pendingCelebration!;
      expect(event.type, CelebrationType.fogCleared);
      expect(event.message, 'Sei pronto.');
    });

    test('fog cleared <90% does not trigger', () {
      ctrl.onFogCleared(correctCount: 17, totalCount: 20);
      expect(ctrl.hasPending, isFalse);
    });

    test('all celebrations ≤ 2000ms (A13.8-03)', () {
      ctrl.onRecallSessionComplete(remembered: 5, total: 5);
      expect(ctrl.pendingCelebration!.durationMs, lessThanOrEqualTo(2000));
      ctrl.consumeCelebration();

      ctrl.onStabilityMilestone(newStage: 4);
      expect(ctrl.pendingCelebration!.durationMs, lessThanOrEqualTo(2000));
      ctrl.consumeCelebration();

      ctrl.onBridgeFormed();
      expect(ctrl.pendingCelebration!.durationMs, lessThanOrEqualTo(2000));
      ctrl.consumeCelebration();

      ctrl.onFogCleared(correctCount: 19, totalCount: 20);
      expect(ctrl.pendingCelebration!.durationMs, lessThanOrEqualTo(2000));
    });

    test('consumeCelebration clears pending', () {
      ctrl.onBridgeFormed();
      expect(ctrl.hasPending, isTrue);
      ctrl.consumeCelebration();
      expect(ctrl.hasPending, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TIER GATING (A17)
  // ═══════════════════════════════════════════════════════════════════════════

  group('TierGateController', () {
    test('Plus/Pro tier: unlimited access (A17-01)', () {
      final ctrl = TierGateController(tier: FlueraSubscriptionTier.plus);
      final result = ctrl.checkFeature(GatedFeature.socraticSession);
      expect(result.allowed, isTrue);
      expect(result.remainingToday, isNull); // Unlimited
      ctrl.dispose();
    });

    test('Free tier: 3 Socratic sessions per week', () {
      final ctrl = TierGateController(tier: FlueraSubscriptionTier.free);

      // Should have 3 remaining this week.
      var result = ctrl.checkFeature(GatedFeature.socraticSession);
      expect(result.allowed, isTrue);
      expect(result.remainingToday, 3);

      // Use 3 sessions.
      for (int i = 0; i < 3; i++) {
        ctrl.recordUsage(GatedFeature.socraticSession);
      }

      // 4th session should be blocked.
      result = ctrl.checkFeature(GatedFeature.socraticSession);
      expect(result.allowed, isFalse);
      expect(result.upgradeMessage, contains('3 sessioni'));

      ctrl.dispose();
    });

    test('Free tier: 1 FoW session per zone', () {
      final ctrl = TierGateController(tier: FlueraSubscriptionTier.free);

      // Zone A: first session allowed.
      var result = ctrl.checkFeature(GatedFeature.fogOfWarSession,
          zoneId: 'zone_a');
      expect(result.allowed, isTrue);

      // Use it.
      ctrl.recordUsage(GatedFeature.fogOfWarSession, zoneId: 'zone_a');

      // Zone A: second session blocked.
      result = ctrl.checkFeature(GatedFeature.fogOfWarSession,
          zoneId: 'zone_a');
      expect(result.allowed, isFalse);

      // Zone B: still allowed (different zone).
      result = ctrl.checkFeature(GatedFeature.fogOfWarSession,
          zoneId: 'zone_b');
      expect(result.allowed, isTrue);

      ctrl.dispose();
    });

    test('Free tier: cross-domain is view-only (blocked)', () {
      final ctrl = TierGateController(tier: FlueraSubscriptionTier.free);
      final result =
          ctrl.checkFeature(GatedFeature.crossDomainInteractive);
      expect(result.allowed, isFalse);
      expect(result.upgradeMessage, contains('Pro'));
      ctrl.dispose();
    });

    test('weekly reset clears counts', () {
      final ctrl = TierGateController(tier: FlueraSubscriptionTier.free);
      for (int i = 0; i < 3; i++) {
        ctrl.recordUsage(GatedFeature.socraticSession);
      }
      expect(
        ctrl.checkFeature(GatedFeature.socraticSession).allowed,
        isFalse,
      );

      // Simulate weekly reset.
      ctrl.resetWeekly();
      expect(
        ctrl.checkFeature(GatedFeature.socraticSession).allowed,
        isTrue,
      );
      ctrl.dispose();
    });

    test('upgrade messages are in Italian (A17-03)', () {
      final ctrl = TierGateController(tier: FlueraSubscriptionTier.free);
      for (int i = 0; i < 3; i++) {
        ctrl.recordUsage(GatedFeature.socraticSession);
      }
      final msg =
          ctrl.checkFeature(GatedFeature.socraticSession).upgradeMessage!;
      // Must be informative Italian with pricing.
      expect(msg, contains('sessioni socratiche'));
      expect(msg, contains('Pro'));
      ctrl.dispose();
    });

    test('tier update unlocks features', () {
      final ctrl = TierGateController(tier: FlueraSubscriptionTier.free);
      for (int i = 0; i < 5; i++) {
        ctrl.recordUsage(GatedFeature.socraticSession);
      }
      expect(
        ctrl.checkFeature(GatedFeature.socraticSession).allowed,
        isFalse,
      );

      // User upgrades!
      ctrl.updateTier(FlueraSubscriptionTier.plus);
      expect(
        ctrl.checkFeature(GatedFeature.socraticSession).allowed,
        isTrue,
      );
      ctrl.dispose();
    });

    test('serialization round-trip preserves counts', () {
      final ctrl = TierGateController(tier: FlueraSubscriptionTier.free);
      ctrl.recordUsage(GatedFeature.socraticSession);
      ctrl.recordUsage(GatedFeature.socraticSession);
      ctrl.recordUsage(GatedFeature.fogOfWarSession, zoneId: 'zone_a');

      final json = ctrl.toJson();
      final restored = TierGateController.fromJson(
        json,
        tier: FlueraSubscriptionTier.free,
      );

      expect(
        restored.checkFeature(GatedFeature.socraticSession).remainingToday,
        1, // 3 - 2
      );
      expect(
        restored
            .checkFeature(GatedFeature.fogOfWarSession, zoneId: 'zone_a')
            .allowed,
        isFalse,
      );

      ctrl.dispose();
      restored.dispose();
    });
  });
}
