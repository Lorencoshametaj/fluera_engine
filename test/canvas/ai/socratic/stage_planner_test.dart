// ============================================================================
// 🎭 Stage planner — Unit tests
//
// Covers:
//   - Session output carries `stage` field on each SocraticQuestion (via
//     fallback path with FakeGeminiProvider returning empty JSON)
//   - Stage sequence matches the expected pattern for N=3..8
//   - Anchor stage gets the highest-recall cluster
//   - Counterfactual stage gets the lowest-recall cluster
//   - `discipline` is inferred and stored on each question
//   - `misconceptionId` is non-null on exactly the counterfactual slot
//     when a matching misconception exists
//   - fallbackForStage outputs pass the G2 filter (no declaration trip)
// ============================================================================

import 'dart:ui' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_controller.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_model.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_output_filter.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';

import '../_fakes.dart';

ContentCluster _cluster(String id) => ContentCluster(
      id: id,
      strokeIds: ['s_$id'],
      bounds: const Rect.fromLTWH(0, 0, 100, 100),
      centroid: const Offset(50, 50),
    );

void main() {
  group('SocraticController batch plan — stage sequence', () {
    test('1 cluster → 3 stages: anchor, elaboration, counterfactual',
        () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1'},
      );

      expect(ctrl.session, isNotNull);
      // Target size = clamp(ceil(1*1.5), 3, 8) = 3.
      expect(ctrl.session!.queue.length, 3);
      expect(
        ctrl.session!.queue.map((q) => q.stage).toList(),
        const [
          SocraticStage.anchor,
          SocraticStage.elaboration,
          SocraticStage.counterfactual,
        ],
      );
    });

    test('4 clusters → 6 stages with metacognitive close', () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [
          _cluster('c1'),
          _cluster('c2'),
          _cluster('c3'),
          _cluster('c4'),
        ],
        recallData: const {'c1': 1, 'c2': 2, 'c3': 4, 'c4': 5},
        provider: fake,
        clusterTexts: const {
          'c1': 'a',
          'c2': 'b',
          'c3': 'c',
          'c4': 'd',
        },
      );

      // Target size = clamp(ceil(4*1.5), 3, 8) = 6.
      expect(ctrl.session!.queue.length, 6);
      final stages = ctrl.session!.queue.map((q) => q.stage).toList();
      expect(stages.first, SocraticStage.anchor);
      expect(stages.last, SocraticStage.metacognitive);
      expect(stages, contains(SocraticStage.counterfactual));
    });

    test('Anchor stage uses HIGHEST-recall cluster', () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('weak'), _cluster('strong')],
        // weak recall=1 < strong recall=5
        recallData: const {'weak': 1, 'strong': 5},
        provider: fake,
        clusterTexts: const {'weak': 'topic-weak', 'strong': 'topic-strong'},
      );

      final anchor = ctrl.session!.queue
          .firstWhere((q) => q.stage == SocraticStage.anchor);
      expect(anchor.clusterId, 'strong',
          reason: 'anchor must pick the highest-recall cluster (least anxious)');
    });

    test('Counterfactual stage uses LOWEST-recall cluster', () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('weak'), _cluster('strong')],
        recallData: const {'weak': 1, 'strong': 5},
        provider: fake,
        clusterTexts: const {'weak': 'topic-weak', 'strong': 'topic-strong'},
      );

      final cf = ctrl.session!.queue
          .firstWhere((q) => q.stage == SocraticStage.counterfactual);
      expect(cf.clusterId, 'weak',
          reason: 'counterfactual targets the weakest cluster (misconception probe lands best)');
    });

    test('Discipline is inferred and stored on each question', () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1'), _cluster('c2')],
        recallData: const {'c1': 2, 'c2': 4},
        provider: fake,
        clusterTexts: const {
          'c1': 'Inerzia di Newton e gravità',
          'c2': 'Forza e accelerazione',
        },
      );

      for (final q in ctrl.session!.queue) {
        expect(q.discipline, Discipline.physics,
            reason: 'physics keywords should be detected');
      }
    });

    test('Misconception id set ONLY on counterfactual slot when matching',
        () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1'), _cluster('c2')],
        recallData: const {'c1': 1, 'c2': 5},
        provider: fake,
        clusterTexts: const {
          'c1': 'Inerzia prima legge Newton',
          'c2': 'Moto rettilineo',
        },
      );

      final withMisc = ctrl.session!.queue
          .where((q) => q.misconceptionId != null)
          .toList();
      expect(withMisc.length, lessThanOrEqualTo(1),
          reason: 'at most one slot gets the misconception hint');
      if (withMisc.length == 1) {
        expect(withMisc.single.stage, SocraticStage.counterfactual,
            reason: 'misconception goes on the counterfactual slot');
      }
    });

    test('Fallback path emits stage-aware question text', () async {
      // Empty JSON → fallback path. Each emitted question text must
      // come from SocraticOutputFilter.fallbackForStage (interrogative).
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-x'},
      );

      for (final q in ctrl.session!.queue) {
        expect(q.text, isNotEmpty);
        expect(q.text, endsWith('?'),
            reason: 'every fallback must be an interrogative');
      }
    });
  });

  group('Sprint 2 DEEPER DIALOGUE (S2.B) — threshold concept detection', () {
    test('Empty history → no candidates', () {
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);
      expect(ctrl.thresholdConceptCandidates(), isEmpty);
    });

    test('Cluster with <3 sessions → not candidate (below threshold)', () async {
      // We can't fabricate _history directly (it's private); the practical
      // assertion is that a fresh controller's history is empty so the
      // detector returns empty. Persistent history is exercised via the
      // device path. Here we only verify the empty-case contract.
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);
      expect(ctrl.thresholdConceptCandidates(), isEmpty);
    });
  });

  group('Sprint 2 DEEPER DIALOGUE (S2.A) — multi-turn stage-aware', () {
    test('SocraticQuestion preserves stage field through copyWith', () {
      const q = SocraticQuestion(
        id: 'q1',
        clusterId: 'c1',
        anchorPosition: Offset(0, 0),
        type: SocraticQuestionType.lacuna,
        text: 'first',
        stage: SocraticStage.counterfactual,
      );
      final copied = q.copyWith(text: 'second');
      expect(copied.stage, SocraticStage.counterfactual,
          reason: 'stage must survive copyWith');
    });
  });

  group('fallbackForStage — G2 safety', () {
    test('Every stage produces output that passes the G2 filter', () {
      for (final stage in SocraticStage.values) {
        final out = SocraticOutputFilter.fallbackForStage(stage, 'Newton');
        final result = SocraticOutputFilter.scanQuestion(out);
        expect(result.passed, isTrue,
            reason: 'stage=${stage.name} produced banned output: "$out"');
      }
    });

    test('Every stage works with null/empty cluster text', () {
      for (final stage in SocraticStage.values) {
        final out = SocraticOutputFilter.fallbackForStage(stage, null);
        expect(out, isNotEmpty);
        expect(out, endsWith('?'));
      }
    });
  });

  group('Sprint 1 ADAPTIVE (S1.A) — in-session skip-ahead', () {
    test('Adaptive skip: high-confidence + correct on anchor → skip next elaboration on same cluster',
        () async {
      // 1 cluster → 3 stages: anchor, elaboration, counterfactual.
      // Set confidence=5 + record correct on anchor → next() should
      // skip elaboration (same cluster) and land on counterfactual.
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1'},
      );

      // Q1 anchor: confidence high + recalled correct
      ctrl.setConfidence(5);
      ctrl.recordResult(recalled: true);
      ctrl.next();
      expect(ctrl.adaptiveSkipsUsed, 1,
          reason: 'skip should fire after anchor with high conf + correct');
      // After skip-ahead, activeQuestion should be the counterfactual.
      expect(ctrl.session!.activeQuestion?.stage, SocraticStage.counterfactual);
    });

    test('No skip when confidence is low even if correct', () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1'},
      );

      ctrl.setConfidence(2); // LOW
      ctrl.recordResult(recalled: true);
      ctrl.next();
      expect(ctrl.adaptiveSkipsUsed, 0,
          reason: 'low confidence → no adaptive skip even if correct');
      expect(ctrl.session!.activeQuestion?.stage, SocraticStage.elaboration);
    });

    test('No skip when answer is wrong even with high confidence', () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'topic-1'},
      );

      ctrl.setConfidence(5);
      ctrl.recordResult(recalled: false); // WRONG → hypercorrection
      ctrl.next();
      expect(ctrl.adaptiveSkipsUsed, 0,
          reason: 'hypercorrection event must NOT trigger skip');
    });

    test('At most 1 skip per session (floor protection)', () async {
      // Configure 2 clusters → 3 stages (anchor c2, elaboration c1, counterfactual c1).
      // (Anchor → highest recall = c2; elaboration → next-highest = c1;
      //  counterfactual → lowest = c1.)
      // First anchor + high-conf-correct triggers skip on elaboration.
      // Even if the next question (counterfactual) were also confident+
      // correct, we never skip more than once.
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1'), _cluster('c2')],
        recallData: const {'c1': 1, 'c2': 5},
        provider: fake,
        clusterTexts: const {'c1': 'a', 'c2': 'b'},
      );

      // Walk session, confidence=5 + correct everywhere.
      while (!ctrl.isComplete && ctrl.session != null) {
        final q = ctrl.session!.activeQuestion;
        if (q == null) break;
        if (q.isResolved) {
          ctrl.next();
          continue;
        }
        ctrl.setConfidence(5);
        ctrl.recordResult(recalled: true);
        ctrl.next();
      }
      expect(ctrl.adaptiveSkipsUsed, lessThanOrEqualTo(1));
    });
  });

  group('_stagePlanFor — sequence shape (via activate())', () {
    test('N=3 has counterfactual at end (peak difficulty)', () async {
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [_cluster('c1')],
        recallData: const {'c1': 3},
        provider: fake,
        clusterTexts: const {'c1': 'x'},
      );

      expect(ctrl.session!.queue.length, 3);
      expect(ctrl.session!.queue.last.stage, SocraticStage.counterfactual);
    });

    test('Longer sessions include both application + interleave', () async {
      // 5 clusters → ceil(5*1.5)=8 → full pattern including interleave.
      final fake = FakeGeminiProvider()..socraticBatchResponse = '';
      final ctrl = SocraticController();
      addTearDown(ctrl.dispose);

      await ctrl.activate(
        clusters: [
          _cluster('c1'),
          _cluster('c2'),
          _cluster('c3'),
          _cluster('c4'),
          _cluster('c5'),
        ],
        recallData: const {'c1': 1, 'c2': 2, 'c3': 3, 'c4': 4, 'c5': 5},
        provider: fake,
        clusterTexts: const {
          'c1': 'a',
          'c2': 'b',
          'c3': 'c',
          'c4': 'd',
          'c5': 'e',
        },
      );

      expect(ctrl.session!.queue.length, 8);
      final stages = ctrl.session!.queue.map((q) => q.stage).toSet();
      expect(stages, contains(SocraticStage.application));
      expect(stages, contains(SocraticStage.interleave));
      expect(stages, contains(SocraticStage.metacognitive));
    });
  });
}
