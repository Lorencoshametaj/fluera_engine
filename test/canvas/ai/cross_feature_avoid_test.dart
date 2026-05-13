// ============================================================================
// 🤝 Cross-feature avoid — Integration test
//
// Verifies the architectural promise of the consolidation sprint:
//   • A question asked by Atlas Exam shows up in Socratic's avoid list
//     (and vice versa) when both controllers share a ClusterConceptIndex.
//   • Without the index, controllers fall back to their isolated rings
//     (backward-compat for tests / older deployments).
// ============================================================================

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/ai_provider.dart';
import 'package:fluera_engine/src/canvas/ai/cluster_concept.dart';
import 'package:fluera_engine/src/canvas/ai/cluster_concept_index.dart';
import 'package:fluera_engine/src/canvas/ai/exam_session_controller.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_controller.dart';
import 'package:fluera_engine/src/canvas/ai/socratic/socratic_model.dart';
import 'package:fluera_engine/src/reflow/content_cluster.dart';

import '_fakes.dart';

ClusterConceptIndex _makeIndex({
  AiProvider? provider,
}) =>
    ClusterConceptIndex(
      providerFn: () => provider,
      strokeMapFn: () => const {},
      reviewScheduleFn: () => const {},
      languageNameFn: () => 'Italian',
    );

ContentCluster _makeCluster(String id, int strokeCount) {
  return ContentCluster(
    id: id,
    strokeIds: List.generate(strokeCount, (i) => 'stroke-$id-$i'),
    bounds: const Rect.fromLTWH(0, 0, 100, 50),
    centroid: const Offset(50, 25),
  );
}

void main() {
  group('Cross-feature avoid (B1)', () {
    test('Exam question appears in Socratic recentQuestionsForClusters',
        () async {
      final index = _makeIndex();

      // Simulate Exam recording a question (without spinning up the full
      // controller — the index is what carries the cross-feature signal).
      index.recordQuestionAsked(
        'cluster-A',
        'Spiega la prima legge di Newton.',
        AskedBy.exam,
      );

      final socraticCtrl = SocraticController()..conceptIndex = index;
      addTearDown(socraticCtrl.dispose);

      final avoid = socraticCtrl.recentQuestionsForClusters(['cluster-A']);
      expect(
        avoid,
        contains('Spiega la prima legge di Newton.'),
      );
    });

    test(
        'Socratic question appears in Exam recentQuestionsForClusters',
        () async {
      final index = _makeIndex();
      index.recordQuestionAsked(
        'cluster-B',
        'Cosa connette inerzia e forza netta?',
        AskedBy.socratic,
      );

      final examCtrl = ExamSessionController(
        provider: FakeGeminiProvider(),
        language: 'Italian',
      )..conceptIndex = index;
      addTearDown(examCtrl.dispose);

      final avoid = examCtrl.recentQuestionsForClusters(['cluster-B']);
      expect(avoid, contains('Cosa connette inerzia e forza netta?'));
    });

    test(
        'Without an index, Socratic and Exam stay isolated (backward-compat)',
        () {
      final socraticCtrl = SocraticController();
      final examCtrl = ExamSessionController(
        provider: FakeGeminiProvider(),
        language: 'Italian',
      );
      addTearDown(socraticCtrl.dispose);
      addTearDown(examCtrl.dispose);

      // Neither controller has an index → no cross-feature visibility.
      expect(socraticCtrl.recentQuestionsForClusters(['cluster-X']), isEmpty);
      expect(examCtrl.recentQuestionsForClusters(['cluster-X']), isEmpty);
    });

    test('cleanOcrItalian fires AT MOST ONCE per cluster across consumers',
        () async {
      // Architectural promise: opening Semantic → Exam → Socratic on the
      // same cluster set burns ONE cleanOcrItalian call, not three.
      final fake = FakeGeminiProvider();
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);

      final cluster = _makeCluster('c-shared', 5); // ≥3 strokes → eligible

      // Seed rawOcr so resolve() doesn't try to hit MyScript (unavailable
      // in unit tests). Real-world equivalent: a previous OCR pass.
      index.seed(ClusterConcept(
        clusterId: cluster.id,
        rawOcr: 'Leggi di Newton',
        strokeChecksum: Object.hashAll([
          ...List<String>.from(cluster.strokeIds)..sort(),
        ]),
      ));

      // First consumer (e.g. Atlas Exam) asks for cleaned OCR.
      await index.resolve(cluster, needsCleanedOcr: true);
      expect(fake.cleanOcrItalianCalls, 1,
          reason: 'first consumer triggers cleanup');

      // Second consumer (e.g. Socratic) asks for cleaned OCR — cache hit.
      await index.resolve(cluster, needsCleanedOcr: true);
      expect(fake.cleanOcrItalianCalls, 1,
          reason: 'second consumer must reuse cached cleanedOcr');

      // Third consumer (e.g. Ghost Map) asks with concepts AND cleanedOcr.
      await index.resolve(
        cluster,
        needsCleanedOcr: true,
        needsConcepts: true,
      );
      expect(fake.cleanOcrItalianCalls, 1,
          reason: 'third consumer must still hit cache for cleanedOcr');
    });

    test('Concurrent resolve calls deduplicate the in-flight Future', () async {
      final fake = FakeGeminiProvider();
      final index = _makeIndex(provider: fake);
      addTearDown(index.dispose);

      final cluster = _makeCluster('c-concurrent', 5);
      index.seed(ClusterConcept(
        clusterId: cluster.id,
        rawOcr: 'F=ma',
        strokeChecksum: Object.hashAll([
          ...List<String>.from(cluster.strokeIds)..sort(),
        ]),
      ));

      // Two consumers race to resolve at the same time.
      final f1 = index.resolve(cluster, needsCleanedOcr: true);
      final f2 = index.resolve(cluster, needsCleanedOcr: true);
      expect(identical(f1, f2), isTrue,
          reason: 'memoize-while-pending — same Future identity');
      await Future.wait([f1, f2]);

      // Even with two concurrent calls, only ONE Gemini round-trip fires.
      expect(fake.cleanOcrItalianCalls, 1);
    });

    test('Socratic local ring buffer still works alongside the index', () {
      final index = _makeIndex();
      index.recordQuestionAsked('cluster-Z', 'Q-from-exam', AskedBy.exam);

      final ctrl = SocraticController()..conceptIndex = index;
      addTearDown(ctrl.dispose);

      // Inject a session into the controller so we can record the local
      // ring buffer too. We synthesize a session manually because the
      // public activate() requires AI provider plumbing — overkill for
      // this isolated test.
      final session = SocraticSession(
        sessionId: 'test',
        queue: const [
          SocraticQuestion(
            id: 'q1',
            clusterId: 'cluster-Z',
            anchorPosition: Offset(0, 0),
            type: SocraticQuestionType.lacuna,
            text: 'Q-from-socratic',
          ),
        ],
        maxQuestions: 5,
      );
      // `_recordRecentQuestions` is private; the public path is dismiss().
      // Drive it via the public state machine to keep the test in API land.
      ctrl.testRecordRecentQuestions(session);

      final avoid = ctrl.recentQuestionsForClusters(['cluster-Z']);
      expect(avoid, contains('Q-from-exam'));
      expect(avoid, contains('Q-from-socratic'));
    });
  });
}
