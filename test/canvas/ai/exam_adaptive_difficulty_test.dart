// ============================================================================
// 🎯 Exam adaptive difficulty (B2) — End-to-end test
//
// Verifies that ExamSessionController.startExam picks `'facile' /
// 'normale' / 'difficile'` based on the FSRS schedule of the cluster's
// concepts, when a ClusterConceptIndex is wired.
//
// New cards (no SRS history)         → 'facile'
// Mature cards (reps≥5, stability>30) → 'difficile'
// In-between                         → 'normale'
// No index wired                     → 'normale' (backward compat)
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/cluster_concept.dart';
import 'package:fluera_engine/src/canvas/ai/cluster_concept_index.dart';
import 'package:fluera_engine/src/canvas/ai/exam_session_controller.dart';
import 'package:fluera_engine/src/canvas/ai/exam_session_model.dart';
import 'package:fluera_engine/src/canvas/ai/fsrs_scheduler.dart';

import '_fakes.dart';

/// Captured difficulty from the most recent FakeGeminiProvider call.
/// We extend FakeGeminiProvider to record the difficulty parameter the
/// controller passes to generateExamQuestions.
class _DifficultyRecordingProvider extends FakeGeminiProvider {
  _DifficultyRecordingProvider({super.questionsToReturn});

  String? lastDifficultyArg;

  @override
  Future<List<ExamQuestion>> generateExamQuestions(
    Map<String, String> clusterTexts, {
    String language = 'Italian',
    int count = 7,
    String difficulty = 'normale',
    List<String> avoidPrompts = const [],
  }) async {
    lastDifficultyArg = difficulty;
    return super.generateExamQuestions(
      clusterTexts,
      language: language,
      count: count,
      difficulty: difficulty,
      avoidPrompts: avoidPrompts,
    );
  }
}

ClusterConceptIndex _makeIndex(Map<String, SrsCardData> schedule) {
  return ClusterConceptIndex(
    providerFn: () => null,
    strokeMapFn: () => const {},
    reviewScheduleFn: () => schedule,
    languageNameFn: () => 'Italian',
  );
}

SrsCardData _matureCard() => SrsCardData(
      stability: 60.0, // > 30 days
      difficulty: 0.4,
      elapsedDays: 0,
      scheduledDays: 30,
      reps: 6, // ≥ 5
      lapses: 0,
      state: FsrsState.review,
      nextReview: DateTime.now().add(const Duration(days: 30)),
      lastReview: DateTime.now(),
    );

SrsCardData _midCard() => SrsCardData(
      stability: 5.0, // < 30
      difficulty: 0.5,
      elapsedDays: 0,
      scheduledDays: 5,
      reps: 2,
      lapses: 0,
      state: FsrsState.review,
      nextReview: DateTime.now().add(const Duration(days: 5)),
      lastReview: DateTime.now(),
    );

void main() {
  group('Exam adaptive difficulty (B2)', () {
    test('No index wired → falls back to "normale"', () async {
      final fake = _DifficultyRecordingProvider(
        questionsToReturn: [buildTestQuestion(id: 'q1', clusterId: 'c1')],
      );
      final ctrl = ExamSessionController(provider: fake);
      addTearDown(ctrl.dispose);

      await ctrl.startExam({'c1': 'first cluster'});
      expect(fake.lastDifficultyArg, 'normale');
    });

    test('All clusters new (no SRS) → "facile"', () async {
      // Empty schedule + concepts referencing missing entries =
      // "all newCard" branch → average maturity 0 → 'facile'.
      final index = _makeIndex({});
      addTearDown(index.dispose);
      // Seed a concept whose `concepts` list refers to entities NOT in
      // the schedule → srsFor() returns null → counted as newCard.
      index.seed(ClusterConcept(
        clusterId: 'c1',
        concepts: ['Newton', 'Inerzia'],
      ));

      final fake = _DifficultyRecordingProvider(
        questionsToReturn: [buildTestQuestion(id: 'q1', clusterId: 'c1')],
      );
      final ctrl = ExamSessionController(provider: fake)
        ..conceptIndex = index;
      addTearDown(ctrl.dispose);

      await ctrl.startExam({'c1': 'first cluster'});
      expect(fake.lastDifficultyArg, 'facile');
    });

    test('All clusters mature → "difficile"', () async {
      final mature = _matureCard();
      final index = _makeIndex({'Newton': mature, 'Forza': mature});
      addTearDown(index.dispose);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        concepts: ['Newton', 'Forza'],
      ));
      index.seed(ClusterConcept(
        clusterId: 'c2',
        concepts: ['Forza'],
      ));

      final fake = _DifficultyRecordingProvider(
        questionsToReturn: [
          buildTestQuestion(id: 'q1', clusterId: 'c1'),
          buildTestQuestion(id: 'q2', clusterId: 'c2'),
        ],
      );
      final ctrl = ExamSessionController(provider: fake)
        ..conceptIndex = index;
      addTearDown(ctrl.dispose);

      await ctrl.startExam({'c1': 'cluster one', 'c2': 'cluster two'});
      expect(fake.lastDifficultyArg, 'difficile');
    });

    test('Mid-maturity cards → "normale"', () async {
      final mid = _midCard();
      final index = _makeIndex({'Newton': mid});
      addTearDown(index.dispose);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        concepts: ['Newton'],
      ));

      final fake = _DifficultyRecordingProvider(
        questionsToReturn: [buildTestQuestion(id: 'q1', clusterId: 'c1')],
      );
      final ctrl = ExamSessionController(provider: fake)
        ..conceptIndex = index;
      addTearDown(ctrl.dispose);

      await ctrl.startExam({'c1': 'first cluster'});
      expect(fake.lastDifficultyArg, 'normale');
    });

    test('Explicit difficulty argument overrides FSRS computation',
        () async {
      // Even with mature cards (which would auto-pick 'difficile'),
      // an explicit 'facile' from the caller wins.
      final mature = _matureCard();
      final index = _makeIndex({'Newton': mature});
      addTearDown(index.dispose);
      index.seed(ClusterConcept(
        clusterId: 'c1',
        concepts: ['Newton'],
      ));

      final fake = _DifficultyRecordingProvider(
        questionsToReturn: [buildTestQuestion(id: 'q1', clusterId: 'c1')],
      );
      final ctrl = ExamSessionController(provider: fake)
        ..conceptIndex = index;
      addTearDown(ctrl.dispose);

      await ctrl.startExam({'c1': 'first cluster'}, difficulty: 'facile');
      expect(fake.lastDifficultyArg, 'facile');
    });
  });
}
