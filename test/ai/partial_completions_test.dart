// ============================================================================
// 🧪 UNIT TESTS — Partial Gap Completions
//
// Step Onboarding (A13.6), Hypercorrection (P3-21), FoW Cinematic (P10-21),
// Ghost Map Cache (A3-04), FSRS Calibration (A5-06), SRS Pull (A9)
// ============================================================================

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/step_onboarding_controller.dart';
import 'package:fluera_engine/src/canvas/ai/hypercorrection_effect.dart';
import 'package:fluera_engine/src/canvas/ai/fog_cinematic_controller.dart';
import 'package:fluera_engine/src/canvas/ai/ghost_map_cache.dart';
import 'package:fluera_engine/src/canvas/ai/fsrs_calibration.dart';
import 'package:fluera_engine/src/canvas/ai/srs_pull_controller.dart';
import 'package:fluera_engine/src/canvas/ai/fsrs_scheduler.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // STEP ONBOARDING (A13.6)
  // ═══════════════════════════════════════════════════════════════════════════

  group('StepOnboardingController', () {
    late StepOnboardingController ctrl;

    setUp(() => ctrl = StepOnboardingController());
    tearDown(() => ctrl.dispose());

    test('shows overlay on first step entry', () {
      ctrl.onStepEntered(1);
      expect(ctrl.hasPending, isTrue);
      expect(ctrl.pendingOverlay!.step, 1);
      expect(ctrl.pendingOverlay!.title, 'Appunti a Mano');
    });

    test('does not show overlay for already seen step', () {
      ctrl.onStepEntered(1);
      ctrl.dismissOverlay();
      ctrl.onStepEntered(1);
      expect(ctrl.hasPending, isFalse);
    });

    test('dismissOverlay marks step as seen', () {
      ctrl.onStepEntered(3);
      ctrl.dismissOverlay();
      expect(ctrl.hasSeenStep(3), isTrue);
      expect(ctrl.hasPending, isFalse);
    });

    test('all 12 steps have overlay content', () {
      for (int step = 1; step <= 12; step++) {
        final fresh = StepOnboardingController();
        fresh.onStepEntered(step);
        expect(fresh.hasPending, isTrue,
            reason: 'Step $step should have overlay content');
        expect(fresh.pendingOverlay!.icon, isNotEmpty);
        fresh.dispose();
      }
    });

    test('auto-fade duration is 5000ms', () {
      ctrl.onStepEntered(1);
      expect(ctrl.pendingOverlay!.autoFadeMs, 5000);
    });

    test('globallyDisabled suppresses all overlays', () {
      ctrl.disableAll();
      ctrl.onStepEntered(1);
      expect(ctrl.hasPending, isFalse);
    });

    test('serialization round-trip', () {
      ctrl.onStepEntered(1);
      ctrl.dismissOverlay();
      ctrl.onStepEntered(5);
      ctrl.dismissOverlay();
      final json = ctrl.toJson();
      final restored = StepOnboardingController.fromJson(json);
      expect(restored.hasSeenStep(1), isTrue);
      expect(restored.hasSeenStep(5), isTrue);
      expect(restored.hasSeenStep(3), isFalse);
      restored.dispose();
    });

    test('ignores invalid steps', () {
      ctrl.onStepEntered(0);
      expect(ctrl.hasPending, isFalse);
      ctrl.onStepEntered(13);
      expect(ctrl.hasPending, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // HYPERCORRECTION (P3-21)
  // ═══════════════════════════════════════════════════════════════════════════

  group('HypercorrectionController', () {
    late HypercorrectionController ctrl;

    setUp(() => ctrl = HypercorrectionController());
    tearDown(() => ctrl.dispose());

    test('no pending effect initially', () {
      expect(ctrl.hasPending, isFalse);
    });

    test('triggers at confidence ≥ 3', () {
      ctrl.trigger(
        questionId: 'q1',
        confidence: 3,
        anchorPosition: const Offset(100, 200),
      );
      expect(ctrl.hasPending, isTrue);
      expect(ctrl.pendingEffect!.confidence, 3);
    });

    test('does not trigger at confidence < 3', () {
      ctrl.trigger(
        questionId: 'q1',
        confidence: 2,
        anchorPosition: const Offset(100, 200),
      );
      expect(ctrl.hasPending, isFalse);
    });

    test('isStrong at confidence ≥ 4', () {
      ctrl.trigger(
        questionId: 'q1',
        confidence: 4,
        anchorPosition: Offset.zero,
      );
      expect(ctrl.pendingEffect!.isStrong, isTrue);
    });

    test('duration is 600ms (P3-21)', () {
      expect(HypercorrectionEvent.durationMs, 600);
      expect(HypercorrectionEvent.flashPhaseMs, 200);
    });

    test('message is positive (no shame)', () {
      expect(HypercorrectionEvent.debugMessage,
          contains('ricorderà meglio'));
      expect(HypercorrectionEvent.debugMessage.toLowerCase(),
          isNot(contains('sbagliato')));
    });

    test('consumeEffect clears pending', () {
      ctrl.trigger(
        questionId: 'q1',
        confidence: 5,
        anchorPosition: Offset.zero,
      );
      ctrl.consumeEffect();
      expect(ctrl.hasPending, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FOG CINEMATIC (P10-21)
  // ═══════════════════════════════════════════════════════════════════════════

  group('FogCinematicController', () {
    late FogCinematicController ctrl;

    setUp(() => ctrl = FogCinematicController());
    tearDown(() => ctrl.dispose());

    test('no reveal initially', () {
      expect(ctrl.isRevealing, isFalse);
    });

    test('node reveal: 800ms, no sound', () {
      ctrl.revealNode(const Offset(100, 200));
      expect(ctrl.isRevealing, isTrue);
      final event = ctrl.currentReveal!;
      expect(event.type, FogRevealType.nodeReveal);
      expect(event.durationMs, 800);
      expect(event.playSound, isFalse);
      expect(event.completionMessage, isNull);
    });

    test('cinematic reveal: 3000ms, sound, "Sei pronto." at ≥90%', () {
      ctrl.revealCinematic(
        canvasCenter: const Offset(500, 400),
        correctCount: 18,
        totalCount: 20,
      );
      final event = ctrl.currentReveal!;
      expect(event.type, FogRevealType.cinematicReveal);
      expect(event.durationMs, 3000);
      expect(event.playSound, isTrue);
      expect(event.completionMessage, 'Sei pronto.');
    });

    test('cinematic reveal: no message at < 90%', () {
      ctrl.revealCinematic(
        canvasCenter: Offset.zero,
        correctCount: 17,
        totalCount: 20,
      );
      expect(ctrl.currentReveal!.completionMessage, isNull);
    });

    test('3 phases in cinematic reveal', () {
      expect(FogCinematicController.cinematicPhases.length, 3);
      expect(FogCinematicController.cinematicPhases[0].name, 'radialExpand');
      expect(FogCinematicController.cinematicPhases[2].name, 'messageAppear');
      expect(FogCinematicController.cinematicPhases.first.startFraction, 0.0);
      expect(FogCinematicController.cinematicPhases.last.endFraction, 1.0);
    });

    test('completeReveal clears state', () {
      ctrl.revealNode(Offset.zero);
      ctrl.completeReveal();
      expect(ctrl.isRevealing, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GHOST MAP CACHE (A3-04)
  // ═══════════════════════════════════════════════════════════════════════════

  group('GhostMapCache', () {
    late GhostMapCache cache;

    setUp(() => cache = GhostMapCache());

    test('empty cache returns null', () {
      expect(cache.get('zone1', 'hash1'), isNull);
      expect(cache.size, 0);
    });

    test('put + get returns cached entry', () {
      cache.put('zone1', 'hash1', {'nodes': []});
      final entry = cache.get('zone1', 'hash1');
      expect(entry, isNotNull);
      expect(entry!.conceptMapData['nodes'], []);
    });

    test('content hash mismatch invalidates cache', () {
      cache.put('zone1', 'hash1', {'data': 'old'});
      final entry = cache.get('zone1', 'hash2');
      expect(entry, isNull);
      expect(cache.size, 0);
    });

    test('LRU eviction at capacity', () {
      for (int i = 0; i < 55; i++) {
        cache.put('zone_$i', 'hash_$i', {'i': i});
      }
      expect(cache.size, 50);
      expect(cache.get('zone_0', 'hash_0'), isNull);
      expect(cache.get('zone_54', 'hash_54'), isNotNull);
    });

    test('invalidate removes specific entry', () {
      cache.put('zone1', 'hash1', {});
      cache.put('zone2', 'hash2', {});
      cache.invalidate('zone1');
      expect(cache.get('zone1', 'hash1'), isNull);
      expect(cache.get('zone2', 'hash2'), isNotNull);
    });

    test('clear removes all entries', () {
      cache.put('zone1', 'hash1', {});
      cache.put('zone2', 'hash2', {});
      cache.clear();
      expect(cache.size, 0);
    });

    test('serialization round-trip', () {
      cache.put('zone1', 'hash1', {'nodes': [1, 2]});
      cache.put('zone2', 'hash2', {'nodes': [3]});
      final json = cache.toJson();
      final restored = GhostMapCache.fromJson(json);
      expect(restored.size, 2);
      expect(restored.get('zone1', 'hash1')!.conceptMapData['nodes'], [1, 2]);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FSRS CALIBRATION (A5-06)
  // ═══════════════════════════════════════════════════════════════════════════

  group('FsrsCalibration', () {
    test('rejects fewer than 100 reviews', () {
      final reviews = List.generate(
        50,
        (i) => ReviewRecord(
          stabilityBefore: 5.0,
          difficulty: 0.3,
          elapsedDays: 3.0,
          wasCorrect: true,
        ),
      );
      expect(FsrsCalibration.calibrate(reviews), isNull);
    });

    test('produces result with 100+ reviews', () {
      final reviews = List.generate(
        120,
        (i) => ReviewRecord(
          stabilityBefore: 5.0 + i * 0.1,
          difficulty: 0.3,
          elapsedDays: 3.0 + (i % 7),
          wasCorrect: i % 5 != 0,
        ),
      );
      final result = FsrsCalibration.calibrate(reviews);
      expect(result, isNotNull);
      expect(result!.reviewCount, 120);
      expect(result.iterations, greaterThanOrEqualTo(0));
      expect(result.finalLoss.isFinite, isTrue);
      expect(result.finalLoss, greaterThanOrEqualTo(0));
    });

    test('weights stay within bounds', () {
      final reviews = List.generate(
        150,
        (i) => ReviewRecord(
          stabilityBefore: 2.0,
          difficulty: 0.9,
          elapsedDays: 1.0,
          wasCorrect: i % 3 == 0,
        ),
      );
      final result = FsrsCalibration.calibrate(reviews)!;
      final w = result.weights;
      expect(w.w0, inInclusiveRange(0.01, 2.0));
      expect(w.w1, inInclusiveRange(0.01, 2.0));
      expect(w.w2, inInclusiveRange(0.5, 5.0));
      expect(w.w3, inInclusiveRange(0.01, 1.0));
      expect(w.w4, inInclusiveRange(1.0, 15.0));
      expect(w.w5, inInclusiveRange(0.01, 1.0));
      expect(w.w6, inInclusiveRange(0.1, 3.0));
      expect(w.w7, inInclusiveRange(0.01, 1.0));
    });

    test('ReviewRecord serialization', () {
      final r = ReviewRecord(
        stabilityBefore: 5.0,
        difficulty: 0.3,
        elapsedDays: 7.0,
        wasCorrect: true,
      );
      final json = r.toJson();
      final restored = ReviewRecord.fromJson(json);
      expect(restored.stabilityBefore, 5.0);
      expect(restored.wasCorrect, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SRS PULL (A9)
  // ═══════════════════════════════════════════════════════════════════════════

  group('SrsPullController', () {
    late SrsPullController ctrl;

    setUp(() => ctrl = SrsPullController());
    tearDown(() => ctrl.dispose());

    test('empty schedules produce empty badges', () {
      ctrl.update({});
      expect(ctrl.badges, isEmpty);
      expect(ctrl.totalDue, 0);
      expect(ctrl.hasAnyDue, isFalse);
    });

    test('counts due nodes correctly', () {
      final yesterday = DateTime.now().subtract(const Duration(hours: 25));
      final tomorrow = DateTime.now().add(const Duration(hours: 25));

      ctrl.update({
        'canvas1': {
          'concept_a': _cardWithNextReview(yesterday),
          'concept_b': _cardWithNextReview(yesterday),
          'concept_c': _cardWithNextReview(tomorrow),
        },
      });

      expect(ctrl.totalDue, 2);
      expect(ctrl.badgeFor('canvas1')!.dueCount, 2);
      expect(ctrl.badgeFor('canvas1')!.isVisible, isTrue);
      expect(ctrl.badgeFor('canvas1')!.displayText, '2');
    });

    test('badge is grey (A9-01)', () {
      expect(SrsDueBadge.badgeColor, const Color(0xFF666666));
    });

    test('badge shows 9+ for large counts', () {
      const badge = SrsDueBadge(canvasId: 'c', dueCount: 15);
      expect(badge.displayText, '9+');
    });

    test('calendar has 7 days', () {
      final future = DateTime.now().add(const Duration(days: 2));
      ctrl.update({
        'canvas1': {
          'a': _cardWithNextReview(future),
        },
      });
      expect(ctrl.calendar.length, 7);
      expect(ctrl.calendar.first.isToday, isTrue);
      expect(ctrl.calendar.first.label, 'Oggi');
    });

    test('overdue cards count toward today', () {
      final yesterday = DateTime.now().subtract(const Duration(hours: 25));
      ctrl.update({
        'canvas1': {
          'a': _cardWithNextReview(yesterday),
        },
      });
      expect(ctrl.calendar.first.reviewCount, 1);
    });

    test('dot intensity scales with count', () {
      final now = DateTime.now();
      expect(UpcomingReviewDay(date: now, reviewCount: 1).dotIntensity, 1);
      expect(UpcomingReviewDay(date: now, reviewCount: 4).dotIntensity, 2);
      expect(UpcomingReviewDay(date: now, reviewCount: 8).dotIntensity, 3);
    });

    test('second day is labeled Domani', () {
      ctrl.update({
        'canvas1': {
          'a': _cardWithNextReview(
              DateTime.now().add(const Duration(hours: 30))),
        },
      });
      expect(ctrl.calendar[1].label, 'Domani');
    });
  });
}

/// Helper: create an SrsCardData with a specific nextReview date.
SrsCardData _cardWithNextReview(DateTime nextReview) {
  return SrsCardData(
    stability: 5.0,
    difficulty: 0.3,
    elapsedDays: 0,
    scheduledDays: 3,
    reps: 1,
    lapses: 0,
    state: FsrsState.review,
    nextReview: nextReview,
    lastReview: nextReview.subtract(const Duration(days: 3)),
    desiredRetention: 0.90,
    recentResults: [true],
  );
}
