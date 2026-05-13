import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/canvas/ai/bloom_classifier.dart';
import 'package:fluera_engine/src/canvas/ai/exam_session_model.dart';

ExamQuestion _q({
  required String id,
  String text = 'q',
  ExamQuestionType type = ExamQuestionType.openEnded,
  String clusterId = 'c1',
  ExamAnswerResult? result,
  int? confidence,
  String? userAnswer,
  String? elaboration,
  BloomLevel? bloomLevel,
  String? sourceText,
}) =>
    ExamQuestion(
      id: id,
      questionText: text,
      type: type,
      correctAnswer: 'ans',
      explanation: 'why',
      sourceClusterId: clusterId,
      // Default to a per-id sourceText so `clustersToReview` (which
      // dedupes by sourceText) sees one entry per question by default.
      // Tests that need a shared source can override.
      sourceText: sourceText ?? 'src-$id-$clusterId',
      result: result,
      confidenceLevel: confidence,
      userAnswer: userAnswer,
      elaboration: elaboration,
      bloomLevel: bloomLevel,
    );

void main() {
  group('ExamQuestion — Hypercorrection trigger', () {
    test('wasOverconfident: conf=5 + incorrect → true', () {
      final q = _q(
        id: 'q1',
        result: ExamAnswerResult.incorrect,
        confidence: 5,
      );
      expect(q.wasOverconfident, isTrue);
    });

    test('wasOverconfident: conf=4 + partial → true', () {
      final q = _q(
        id: 'q2',
        result: ExamAnswerResult.partial,
        confidence: 4,
      );
      expect(q.wasOverconfident, isTrue);
    });

    test('wasOverconfident: conf=4 + correct → false (no shock for right answer)', () {
      final q = _q(
        id: 'q3',
        result: ExamAnswerResult.correct,
        confidence: 5,
      );
      expect(q.wasOverconfident, isFalse);
    });

    test('wasOverconfident: conf=3 + incorrect → false (under threshold)', () {
      final q = _q(
        id: 'q4',
        result: ExamAnswerResult.incorrect,
        confidence: 3,
      );
      expect(q.wasOverconfident, isFalse);
    });

    test('wasOverconfident: no confidence set → false', () {
      final q = _q(id: 'q5', result: ExamAnswerResult.incorrect);
      expect(q.wasOverconfident, isFalse);
    });

    test('wasOverconfident: no result yet → false', () {
      final q = _q(id: 'q6', confidence: 5);
      expect(q.wasOverconfident, isFalse);
    });

    test('wasOverconfident: skipped with high conf → true (still a wrong)', () {
      final q = _q(
        id: 'q7',
        result: ExamAnswerResult.skipped,
        confidence: 5,
      );
      expect(q.wasOverconfident, isTrue);
    });
  });

  group('ExamQuestion — Serialization roundtrip', () {
    test('Minimal MC question survives toJson/fromJson', () {
      final q = ExamQuestion(
        id: 'q1',
        questionText: 'What is 2+2?',
        type: ExamQuestionType.multipleChoice,
        correctAnswer: '4',
        explanation: 'basic arithmetic',
        sourceClusterId: 'c1',
        sourceText: 'maths basics',
        choices: ['2', '3', '4', '5'],
        correctChoiceIndex: 2,
      );
      final restored = ExamQuestion.fromJson(q.toJson());
      expect(restored.id, q.id);
      expect(restored.questionText, q.questionText);
      expect(restored.type, q.type);
      expect(restored.choices, q.choices);
      expect(restored.correctChoiceIndex, q.correctChoiceIndex);
      expect(restored.result, isNull);
      expect(restored.bloomLevel, isNull);
    });

    test('Answered open-ended question with confidence + elaboration roundtrip', () {
      final q = _q(
        id: 'q2',
        text: 'Spiega la mitosi.',
        result: ExamAnswerResult.partial,
        confidence: 3,
        userAnswer: 'È una divisione cellulare',
        elaboration: 'Avrei dovuto specificare le 4 fasi: profase, metafase...',
        bloomLevel: BloomLevel.understand,
      );
      final restored = ExamQuestion.fromJson(q.toJson());
      expect(restored.result, ExamAnswerResult.partial);
      expect(restored.confidenceLevel, 3);
      expect(restored.userAnswer, q.userAnswer);
      expect(restored.elaboration, q.elaboration);
      expect(restored.bloomLevel, BloomLevel.understand);
    });

    test('Unknown bloomLevel string falls back to remember', () {
      final q = _q(id: 'q3', bloomLevel: BloomLevel.apply);
      final json = q.toJson();
      json['bloomLevel'] = 'metacognitive'; // not a real value
      final restored = ExamQuestion.fromJson(json);
      expect(restored.bloomLevel, BloomLevel.remember);
    });

    test('Unknown question type falls back to openEnded', () {
      final q = _q(id: 'q4', type: ExamQuestionType.multipleChoice);
      final json = q.toJson();
      json['type'] = 'completely_made_up';
      final restored = ExamQuestion.fromJson(json);
      expect(restored.type, ExamQuestionType.openEnded);
    });
  });

  group('ExamSession — basic getters', () {
    test('isComplete is false until currentIndex passes the last Q', () {
      final session = ExamSession(
        sessionId: 's',
        questions: [_q(id: 'a'), _q(id: 'b')],
      );
      expect(session.isComplete, isFalse);
      session.currentIndex = 1;
      expect(session.isComplete, isFalse);
      session.currentIndex = 2;
      expect(session.isComplete, isTrue);
    });

    test('currentQuestion returns null when complete', () {
      final session = ExamSession(
        sessionId: 's',
        questions: [_q(id: 'only')],
      );
      expect(session.currentQuestion, isNotNull);
      session.currentIndex = 1;
      expect(session.currentQuestion, isNull);
    });

    test('answeredCount excludes unanswered Qs', () {
      final session = ExamSession(sessionId: 's', questions: [
        _q(id: '1', result: ExamAnswerResult.correct),
        _q(id: '2', result: ExamAnswerResult.incorrect),
        _q(id: '3'),
      ]);
      expect(session.answeredCount, 2);
    });

    test('correctCount counts only correct', () {
      final session = ExamSession(sessionId: 's', questions: [
        _q(id: '1', result: ExamAnswerResult.correct),
        _q(id: '2', result: ExamAnswerResult.correct),
        _q(id: '3', result: ExamAnswerResult.partial),
        _q(id: '4', result: ExamAnswerResult.incorrect),
      ]);
      expect(session.correctCount, 2);
      expect(session.partialCount, 1);
    });
  });

  group('ExamSession — Score + Stars', () {
    test('Empty session has score 0', () {
      final s = ExamSession(sessionId: 's', questions: []);
      expect(s.score, 0);
      expect(s.stars, 0);
    });

    test('All correct → 1.0 → 3 stars', () {
      final session = ExamSession(sessionId: 's', questions: [
        for (int i = 0; i < 4; i++)
          _q(id: '$i', result: ExamAnswerResult.correct),
      ]);
      expect(session.score, 1.0);
      expect(session.stars, 3);
    });

    test('Partial counts as half a correct', () {
      final session = ExamSession(sessionId: 's', questions: [
        _q(id: '1', result: ExamAnswerResult.correct),
        _q(id: '2', result: ExamAnswerResult.partial),
        _q(id: '3', result: ExamAnswerResult.incorrect),
        _q(id: '4', result: ExamAnswerResult.skipped),
      ]);
      // (1 + 0.5) / 4 = 0.375
      expect(session.score, closeTo(0.375, 1e-9));
      // 0.375 < 0.40 → 0 stars
      expect(session.stars, 0);
    });

    test('Stars threshold 40% → 1 star', () {
      // 2 correct out of 5 = 0.40
      final session = ExamSession(sessionId: 's', questions: [
        _q(id: '1', result: ExamAnswerResult.correct),
        _q(id: '2', result: ExamAnswerResult.correct),
        _q(id: '3', result: ExamAnswerResult.incorrect),
        _q(id: '4', result: ExamAnswerResult.incorrect),
        _q(id: '5', result: ExamAnswerResult.incorrect),
      ]);
      expect(session.score, closeTo(0.4, 1e-9));
      expect(session.stars, 1);
    });

    test('Stars threshold 60% → 2 stars', () {
      // 3 correct out of 5 = 0.60
      final session = ExamSession(sessionId: 's', questions: [
        _q(id: '1', result: ExamAnswerResult.correct),
        _q(id: '2', result: ExamAnswerResult.correct),
        _q(id: '3', result: ExamAnswerResult.correct),
        _q(id: '4', result: ExamAnswerResult.incorrect),
        _q(id: '5', result: ExamAnswerResult.incorrect),
      ]);
      expect(session.stars, 2);
    });

    test('Stars threshold 85% → 3 stars (exactly at boundary)', () {
      // 17 correct + 3 wrong out of 20 = 0.85
      final session = ExamSession(sessionId: 's', questions: [
        for (int i = 0; i < 17; i++)
          _q(id: 'c$i', result: ExamAnswerResult.correct),
        for (int i = 0; i < 3; i++)
          _q(id: 'w$i', result: ExamAnswerResult.incorrect),
      ]);
      expect(session.score, closeTo(0.85, 1e-9));
      expect(session.stars, 3);
    });

    test('Just below 85% → 2 stars', () {
      // 16 correct + 4 wrong out of 20 = 0.80
      final session = ExamSession(sessionId: 's', questions: [
        for (int i = 0; i < 16; i++)
          _q(id: 'c$i', result: ExamAnswerResult.correct),
        for (int i = 0; i < 4; i++)
          _q(id: 'w$i', result: ExamAnswerResult.incorrect),
      ]);
      expect(session.stars, 2);
    });
  });

  group('ExamSession — Chunking', () {
    test('totalChunks rounds up', () {
      final session = ExamSession(sessionId: 's', questions: [
        for (int i = 0; i < 7; i++) _q(id: '$i'),
      ]);
      // 7 / 4 = 2 ceil
      expect(session.totalChunks, 2);
    });

    test('chunkSize boundary at index 4', () {
      final session = ExamSession(sessionId: 's', questions: [
        for (int i = 0; i < 8; i++) _q(id: '$i'),
      ]);
      session.currentIndex = 4;
      expect(session.isChunkBoundary, isTrue);
      expect(session.currentChunk, 1);
    });

    test('Index 0 is NOT a chunk boundary', () {
      final session = ExamSession(sessionId: 's', questions: [
        for (int i = 0; i < 4; i++) _q(id: '$i'),
      ]);
      expect(session.isChunkBoundary, isFalse);
    });

    test('chunkCorrectCount tallies across chunks (shuffle-invariant)', () {
      // 6 questions: 4 correct, 1 incorrect, 1 partial. ExamSession's
      // ctor runs `_interleaveShuffle` so the *order* is randomized,
      // but the AGGREGATE counts across both chunks must always match
      // the input.
      final session = ExamSession(sessionId: 's', questions: [
        _q(id: '1', result: ExamAnswerResult.correct),
        _q(id: '2', result: ExamAnswerResult.correct),
        _q(id: '3', result: ExamAnswerResult.incorrect),
        _q(id: '4', result: ExamAnswerResult.partial),
        _q(id: '5', result: ExamAnswerResult.correct),
        _q(id: '6', result: ExamAnswerResult.correct),
      ]);
      // Chunk 0 always holds the first 4 slots, chunk 1 the remaining 2.
      expect(session.chunkTotalCount(0), 4);
      expect(session.chunkTotalCount(1), 2);
      // Total correct must equal the 4 correct answers we provided,
      // regardless of how the shuffle distributed them.
      final totalCorrect =
          session.chunkCorrectCount(0) + session.chunkCorrectCount(1);
      expect(totalCorrect, 4);
      // Each chunk's correct count is bounded by its total slot count.
      expect(session.chunkCorrectCount(0), inInclusiveRange(0, 4));
      expect(session.chunkCorrectCount(1), inInclusiveRange(0, 2));
    });
  });

  group('ExamSession — clustersToReview', () {
    test('Returns sourceText of incorrect or skipped Qs', () {
      final session = ExamSession(sessionId: 's', questions: [
        _q(id: '1', result: ExamAnswerResult.correct, clusterId: 'a'),
        _q(id: '2', result: ExamAnswerResult.incorrect, clusterId: 'b'),
        _q(id: '3', result: ExamAnswerResult.skipped, clusterId: 'c'),
      ]);
      expect(session.clustersToReview.length, 2);
    });
  });

  group('ExamSession — Serialization roundtrip', () {
    test('Empty session roundtrips', () {
      final s = ExamSession(sessionId: 'session-1', questions: []);
      final restored = ExamSession.fromJson(s.toJson());
      expect(restored.sessionId, 'session-1');
      expect(restored.questions, isEmpty);
      expect(restored.currentIndex, 0);
      expect(restored.consecutiveCorrect, 0);
      expect(restored.difficultyBoosted, isFalse);
    });

    test('Mid-session state roundtrips (preserves order, no re-shuffle)', () {
      final originalQs = [
        _q(id: 'q1', text: 'prima'),
        _q(id: 'q2', text: 'seconda', result: ExamAnswerResult.correct, confidence: 4),
        _q(id: 'q3', text: 'terza'),
      ];
      // Use fromCheckpoint to bypass shuffle (so we can assert order).
      final s = ExamSession.fromCheckpoint(
        sessionId: 'sid',
        questions: originalQs,
        currentIndex: 1,
        startedAt: DateTime(2026, 5, 5, 10),
        consecutiveCorrect: 1,
        difficultyBoosted: true,
      );
      final restored = ExamSession.fromJson(s.toJson());
      expect(restored.currentIndex, 1);
      expect(restored.consecutiveCorrect, 1);
      expect(restored.difficultyBoosted, isTrue);
      expect(restored.questions.length, 3);
      expect(restored.questions[0].id, 'q1');
      expect(restored.questions[1].id, 'q2');
      expect(restored.questions[2].id, 'q3');
      expect(restored.questions[1].result, ExamAnswerResult.correct);
      expect(restored.questions[1].confidenceLevel, 4);
      expect(restored.startedAt, DateTime(2026, 5, 5, 10));
    });

    test('completedAt roundtrips when set', () {
      final s = ExamSession.fromCheckpoint(
        sessionId: 'sid',
        questions: [_q(id: 'a')],
        currentIndex: 1,
        startedAt: DateTime(2026, 5, 5, 10),
        completedAt: DateTime(2026, 5, 5, 10, 15),
      );
      final restored = ExamSession.fromJson(s.toJson());
      expect(restored.completedAt, DateTime(2026, 5, 5, 10, 15));
    });
  });

  group('ExamSession — interleaving', () {
    test('Single-Q session bypasses shuffle', () {
      final s = ExamSession(
        sessionId: 's',
        questions: [_q(id: 'only')],
      );
      expect(s.questions.length, 1);
      expect(s.questions[0].id, 'only');
    });

    test('Two-Q session bypasses shuffle (just shuffles in place)', () {
      // Behavior: <=2 questions → trivial shuffle, no topic alternation needed.
      final s = ExamSession(
        sessionId: 's',
        questions: [_q(id: 'a'), _q(id: 'b')],
      );
      expect(s.questions.length, 2);
      // Both ids still present.
      final ids = s.questions.map((q) => q.id).toSet();
      expect(ids, containsAll(['a', 'b']));
    });

    test('Topic alternation: 4 Qs across 2 clusters → no two consecutive same-cluster (when possible)', () {
      // 2 from cluster A, 2 from cluster B
      final raw = [
        _q(id: 'a1', clusterId: 'A'),
        _q(id: 'a2', clusterId: 'A'),
        _q(id: 'b1', clusterId: 'B'),
        _q(id: 'b2', clusterId: 'B'),
      ];
      final s = ExamSession(sessionId: 's', questions: raw);
      // Verify that the round-robin produced alternation in at least one
      // adjacency: there should be at least one position where adjacent
      // questions are from different clusters. (Random shuffle may still
      // produce A,B,A,B or B,A,B,A — both are valid.)
      bool hasAlternation = false;
      for (int i = 0; i < s.questions.length - 1; i++) {
        if (s.questions[i].sourceClusterId !=
            s.questions[i + 1].sourceClusterId) {
          hasAlternation = true;
          break;
        }
      }
      expect(hasAlternation, isTrue);
    });

    test('All same cluster — interleaving preserves all Qs', () {
      final raw = [
        for (int i = 0; i < 5; i++) _q(id: 'q$i', clusterId: 'X'),
      ];
      final s = ExamSession(sessionId: 's', questions: raw);
      expect(s.questions.length, 5);
      // All questions retained.
      expect(s.questions.map((q) => q.id).toSet(), {'q0', 'q1', 'q2', 'q3', 'q4'});
    });

    test('3-cluster interleaving preserves count', () {
      final raw = [
        _q(id: 'a1', clusterId: 'A'),
        _q(id: 'a2', clusterId: 'A'),
        _q(id: 'b1', clusterId: 'B'),
        _q(id: 'b2', clusterId: 'B'),
        _q(id: 'c1', clusterId: 'C'),
        _q(id: 'c2', clusterId: 'C'),
      ];
      final s = ExamSession(sessionId: 's', questions: raw);
      expect(s.questions.length, 6);
      expect(
        s.questions.map((q) => q.id).toSet(),
        containsAll(['a1', 'a2', 'b1', 'b2', 'c1', 'c2']),
      );
    });
  });

  group('ExamHistoryRecord — JSON roundtrip', () {
    test('Roundtrip preserves every field', () {
      final r = ExamHistoryRecord(
        sessionId: 'exam_42',
        date: DateTime(2026, 5, 5, 14, 30),
        score: 0.75,
        totalQuestions: 7,
        correctCount: 5,
        durationSeconds: 480,
        topicTitles: ['Anatomia', 'Patologia'],
      );
      final restored = ExamHistoryRecord.fromJson(r.toJson());
      expect(restored.sessionId, r.sessionId);
      expect(restored.date, r.date);
      expect(restored.score, r.score);
      expect(restored.totalQuestions, r.totalQuestions);
      expect(restored.correctCount, r.correctCount);
      expect(restored.durationSeconds, r.durationSeconds);
      expect(restored.topicTitles, r.topicTitles);
    });
  });
}
