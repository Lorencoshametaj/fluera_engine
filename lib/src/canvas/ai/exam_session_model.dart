/// 🎓 ATLAS EXAM MODE — Data models.
library;

import 'dart:math';

import 'bloom_classifier.dart' show BloomLevel;

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum ExamQuestionType {
  openEnded,
  multipleChoice,
  trueOrFalse,
  formulaRecall,
}

enum ExamAnswerResult {
  correct,
  partial,
  incorrect,
  skipped,
}

// ─────────────────────────────────────────────────────────────────────────────
// ExamQuestion
// ─────────────────────────────────────────────────────────────────────────────

class ExamQuestion {
  final String id;
  final String questionText;
  final ExamQuestionType type;
  final String correctAnswer;
  final String explanation;
  final List<String> choices;
  final int? correctChoiceIndex;
  final String sourceClusterId;
  final String sourceText;

  // Runtime state
  ExamAnswerResult? result;
  String? userAnswer;

  /// Metacognitive confidence (1-5) set BEFORE answering.
  /// Enables Hypercorrection Effect: high-confidence errors → 3× stronger memory.
  int? confidenceLevel;

  /// Post-error elaboration: student rewrites the correct answer in their words.
  /// Activates Generation Effect (Slamecka & Graf, 1978).
  String? elaboration;

  /// Bloom's Taxonomy classification (Anderson & Krathwohl 2001) populated
  /// post-generation by [BloomClassifier]. Used to verify the LLM produced
  /// questions at the requested cognitive depth (e.g. difficulty=normale
  /// must hit ≥40% Apply or higher).
  BloomLevel? bloomLevel;

  /// Student-flagged "review later" bookmark. Toggled from the question card
  /// during the session — appears in the post-completion filter chip and
  /// gets a small FSRS bump (the FSRS scheduler treats marked items with a
  /// shorter interval) so the system surfaces them sooner.
  bool markedForReview;

  /// 🌉 Passo 9: true when this question validates an accepted cross-zone
  /// bridge (asks the student to apply the transfer learning across two
  /// domains). Drives the "🌉 Cross-Domain" badge in the exam overlay
  /// and a separate telemetry bucket [exam_cross_domain_question_correct_rate].
  /// Unlike Socratic questions, these are NON-Socratic by design — they
  /// have a single correct answer and validate retention, not exploration.
  bool isCrossDomain;

  ExamQuestion({
    required this.id,
    required this.questionText,
    required this.type,
    required this.correctAnswer,
    required this.explanation,
    required this.sourceClusterId,
    required this.sourceText,
    this.choices = const [],
    this.correctChoiceIndex,
    this.result,
    this.userAnswer,
    this.confidenceLevel,
    this.elaboration,
    this.bloomLevel,
    this.markedForReview = false,
    this.isCrossDomain = false,
  });

  bool get isAnswered => result != null;
  bool get isCorrect => result == ExamAnswerResult.correct;

  /// True when student was confident (≥4) but got it wrong.
  /// Triggers Hypercorrection Effect UI (Butterfield & Metcalfe, 2001).
  bool get wasOverconfident =>
      confidenceLevel != null &&
      confidenceLevel! >= 4 &&
      result != null &&
      result != ExamAnswerResult.correct;

  // ── Serialization (mid-session checkpoint resume) ──────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'questionText': questionText,
        'type': type.name,
        'correctAnswer': correctAnswer,
        'explanation': explanation,
        'choices': choices,
        'correctChoiceIndex': correctChoiceIndex,
        'sourceClusterId': sourceClusterId,
        'sourceText': sourceText,
        'result': result?.name,
        'userAnswer': userAnswer,
        'confidenceLevel': confidenceLevel,
        'elaboration': elaboration,
        'bloomLevel': bloomLevel?.name,
        'markedForReview': markedForReview,
        if (isCrossDomain) 'isCrossDomain': true,
      };

  factory ExamQuestion.fromJson(Map<String, dynamic> j) {
    final resultName = j['result'] as String?;
    final typeName = j['type'] as String? ?? ExamQuestionType.openEnded.name;
    final bloomName = j['bloomLevel'] as String?;
    return ExamQuestion(
      id: j['id'] as String,
      questionText: j['questionText'] as String,
      type: ExamQuestionType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => ExamQuestionType.openEnded,
      ),
      correctAnswer: j['correctAnswer'] as String,
      explanation: j['explanation'] as String,
      sourceClusterId: j['sourceClusterId'] as String,
      sourceText: j['sourceText'] as String,
      choices: ((j['choices'] as List<dynamic>?) ?? const [])
          .map((e) => e as String)
          .toList(),
      correctChoiceIndex: j['correctChoiceIndex'] as int?,
      result: resultName == null
          ? null
          : ExamAnswerResult.values.firstWhere(
              (r) => r.name == resultName,
              orElse: () => ExamAnswerResult.skipped,
            ),
      userAnswer: j['userAnswer'] as String?,
      confidenceLevel: j['confidenceLevel'] as int?,
      elaboration: j['elaboration'] as String?,
      bloomLevel: bloomName == null
          ? null
          : BloomLevel.values.firstWhere(
              (b) => b.name == bloomName,
              orElse: () => BloomLevel.remember,
            ),
      markedForReview: (j['markedForReview'] as bool?) ?? false,
      isCrossDomain: (j['isCrossDomain'] as bool?) ?? false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ExamSession
// ─────────────────────────────────────────────────────────────────────────────

class ExamSession {
  final String sessionId;
  final List<ExamQuestion> questions;
  int currentIndex;
  final DateTime startedAt;
  DateTime? completedAt;

  /// Tracks consecutive correct answers for adaptive difficulty.
  int consecutiveCorrect = 0;
  bool difficultyBoosted = false;

  // 📦 PROGRESSIVE CHUNKING — break exam into digestible blocks
  static const chunkSize = 4;

  ExamSession({
    required this.sessionId,
    required List<ExamQuestion> questions,
    this.currentIndex = 0,
  })  : questions = _interleaveShuffle(List.from(questions)),
        startedAt = DateTime.now();

  /// Restore from a persisted checkpoint. Preserves question order
  /// (no re-shuffle) and answered state, so the student continues
  /// exactly where they left off.
  ExamSession.fromCheckpoint({
    required this.sessionId,
    required this.questions,
    required this.currentIndex,
    required this.startedAt,
    this.completedAt,
    int consecutiveCorrect = 0,
    bool difficultyBoosted = false,
  }) {
    this.consecutiveCorrect = consecutiveCorrect;
    this.difficultyBoosted = difficultyBoosted;
  }

  ExamQuestion? get currentQuestion =>
      currentIndex < questions.length ? questions[currentIndex] : null;

  bool get isComplete => currentIndex >= questions.length;

  int get answeredCount => questions.where((q) => q.result != null).length;
  int get correctCount =>
      questions.where((q) => q.result == ExamAnswerResult.correct).length;
  int get partialCount =>
      questions.where((q) => q.result == ExamAnswerResult.partial).length;

  double get score {
    if (questions.isEmpty) return 0;
    final total = correctCount + partialCount * 0.5;
    return total / questions.length;
  }

  int get stars {
    if (score >= 0.85) return 3;
    if (score >= 0.60) return 2;
    if (score >= 0.40) return 1;
    return 0;
  }

  // ── CHUNKING GETTERS ───────────────────────────────────────────────
  int get currentChunk => currentIndex ~/ chunkSize;
  int get totalChunks => (questions.length / chunkSize).ceil();
  bool get isChunkBoundary =>
      currentIndex > 0 &&
      currentIndex % chunkSize == 0 &&
      currentIndex < questions.length;

  int chunkCorrectCount(int chunk) => questions
      .skip(chunk * chunkSize)
      .take(chunkSize)
      .where((q) => q.result == ExamAnswerResult.correct)
      .length;

  int chunkTotalCount(int chunk) => questions
      .skip(chunk * chunkSize)
      .take(chunkSize)
      .where((q) => q.result != null)
      .length;

  // ── CONSCIOUS INTERLEAVING (Rohrer & Taylor, 2007) ─────────────────
  /// Topic-aware round-robin shuffle that guarantees topic alternation.
  /// Within each topic, questions are randomized; across topics, questions
  /// alternate to create desirable difficulty (interleaving effect).
  static List<ExamQuestion> _interleaveShuffle(List<ExamQuestion> questions) {
    if (questions.length <= 2) return questions..shuffle(Random());

    // Group by sourceClusterId (topic)
    final byTopic = <String, List<ExamQuestion>>{};
    for (final q in questions) {
      byTopic.putIfAbsent(q.sourceClusterId, () => []).add(q);
    }
    // Shuffle within each topic
    for (final list in byTopic.values) {
      list.shuffle(Random());
    }

    // Round-robin across topics
    final result = <ExamQuestion>[];
    final queues = byTopic.values.toList()..shuffle(Random());
    final indices = List.filled(queues.length, 0);

    while (result.length < questions.length) {
      for (int t = 0; t < queues.length; t++) {
        if (indices[t] < queues[t].length) {
          result.add(queues[t][indices[t]++]);
        }
      }
    }

    // Secondary pass: alternate question types where possible
    // Swap adjacent same-type questions if alternative exists
    for (int i = 1; i < result.length - 1; i++) {
      if (result[i].type == result[i - 1].type) {
        // Look ahead for a different type to swap
        for (int j = i + 1; j < min(i + 3, result.length); j++) {
          if (result[j].type != result[i - 1].type &&
              result[j].sourceClusterId != result[i - 1].sourceClusterId) {
            final tmp = result[i];
            result[i] = result[j];
            result[j] = tmp;
            break;
          }
        }
      }
    }
    return result;
  }

  List<String> get clustersToReview => questions
      .where((q) =>
          q.result == ExamAnswerResult.incorrect ||
          q.result == ExamAnswerResult.skipped)
      .map((q) => q.sourceText)
      .toSet()
      .toList();

  /// Duration in seconds.
  int get durationSeconds =>
      (completedAt ?? DateTime.now()).difference(startedAt).inSeconds;

  // ── Serialization (mid-session checkpoint resume) ──────────────────────────

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'currentIndex': currentIndex,
        'consecutiveCorrect': consecutiveCorrect,
        'difficultyBoosted': difficultyBoosted,
        'questions': questions.map((q) => q.toJson()).toList(),
      };

  factory ExamSession.fromJson(Map<String, dynamic> j) =>
      ExamSession.fromCheckpoint(
        sessionId: j['sessionId'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        completedAt: j['completedAt'] == null
            ? null
            : DateTime.parse(j['completedAt'] as String),
        currentIndex: (j['currentIndex'] as num).toInt(),
        consecutiveCorrect:
            ((j['consecutiveCorrect'] as num?) ?? 0).toInt(),
        difficultyBoosted: (j['difficultyBoosted'] as bool?) ?? false,
        questions: (j['questions'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(ExamQuestion.fromJson)
            .toList(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ExamScopeEntry
// ─────────────────────────────────────────────────────────────────────────────

class ExamScopeEntry {
  final String clusterId;
  final String displayTitle;
  final String rawText;
  bool selected;

  ExamScopeEntry({
    required this.clusterId,
    required this.displayTitle,
    required this.rawText,
    this.selected = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// ExamHistoryQuestion — per-question snapshot stored inside a history record.
// ─────────────────────────────────────────────────────────────────────────────

/// Captured at session completion so the review screen can show the
/// `<question> → <my answer> → <my strokes>` triple per card. Slim by
/// design — we don't persist the AI explanation text or the choice list,
/// only the strings the student actually sees.
class ExamHistoryQuestion {
  /// Mirrors [ExamQuestion.id] — used to match strokes saved by
  /// [ExamStrokeStorage] under `<sessionId>__<questionId>__answer`.
  final String id;
  final String questionText;

  /// User's final answer text. For multiple-choice this is the choice
  /// label (e.g. "B: Forza"); for open answers it's the OCR'd transcript
  /// or typed answer.
  final String? userAnswer;

  /// Correct answer for context. Useful when the user sees a wrong
  /// answer in review and wants to see what they should have written.
  final String correctAnswer;

  /// Result enum stringified (`correct`, `incorrect`, `partial`,
  /// `skipped`, or empty if never answered).
  final String resultLabel;

  const ExamHistoryQuestion({
    required this.id,
    required this.questionText,
    required this.correctAnswer,
    this.userAnswer,
    this.resultLabel = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'questionText': questionText,
        'correctAnswer': correctAnswer,
        if (userAnswer != null && userAnswer!.isNotEmpty) 'userAnswer': userAnswer,
        if (resultLabel.isNotEmpty) 'resultLabel': resultLabel,
      };

  factory ExamHistoryQuestion.fromJson(Map<String, dynamic> j) {
    return ExamHistoryQuestion(
      id: j['id'] as String,
      questionText: j['questionText'] as String? ?? '',
      correctAnswer: j['correctAnswer'] as String? ?? '',
      userAnswer: j['userAnswer'] as String?,
      resultLabel: j['resultLabel'] as String? ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ExamHistoryRecord — saved per-session stats
// ─────────────────────────────────────────────────────────────────────────────

class ExamHistoryRecord {
  final String sessionId;
  final DateTime date;
  final double score;
  final int totalQuestions;
  final int correctCount;
  final int durationSeconds;
  final List<String> topicTitles;

  // ── Schema v2 (added 2026-05-07 for Dashboard analytics) ──────────────────
  // All fields below are optional with sensible defaults so legacy v1
  // records on disk still deserialise cleanly.

  /// Per-topic accuracy on this session. Key = topic title (matches one of
  /// [topicTitles]); value = correct/total within that topic, in [0..1].
  final Map<String, double> topicScores;

  /// Difficulty level used for this session (`facile`/`normale`/`difficile`).
  final String difficultyUsed;

  /// Bloom distribution of generated questions, keyed by level name
  /// (`remember`, `understand`, `apply`, `analyze`, `evaluate`, `create`).
  /// Useful for the Dashboard's cognitive depth chart.
  final Map<String, int> bloomDistribution;

  /// Number of questions the student bookmarked for review during this exam.
  final int markedForReviewCount;

  // ── Schema v3 (added 2026-05-08 for Review screen UX) ────────────────────
  // Per-question detail captured at session completion. Empty list on legacy
  // records — review screen falls back to "stroke-only" rendering.

  /// Snapshot of every question in the order asked, with the student's
  /// answer text + correctness. Drives the review screen so the student
  /// sees `<question> → <my OCR answer> → <my strokes>` instead of an
  /// anonymous "Domanda 1" without context.
  final List<ExamHistoryQuestion> questions;

  const ExamHistoryRecord({
    required this.sessionId,
    required this.date,
    required this.score,
    required this.totalQuestions,
    required this.correctCount,
    required this.durationSeconds,
    required this.topicTitles,
    this.topicScores = const {},
    this.difficultyUsed = 'normale',
    this.bloomDistribution = const {},
    this.markedForReviewCount = 0,
    this.questions = const [],
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'date': date.toIso8601String(),
        'score': score,
        'totalQuestions': totalQuestions,
        'correctCount': correctCount,
        'durationSeconds': durationSeconds,
        'topicTitles': topicTitles,
        'topicScores': topicScores,
        'difficultyUsed': difficultyUsed,
        'bloomDistribution': bloomDistribution,
        'markedForReviewCount': markedForReviewCount,
        if (questions.isNotEmpty)
          'questions': questions.map((q) => q.toJson()).toList(),
        'schemaVersion': 3,
      };

  factory ExamHistoryRecord.fromJson(Map<String, dynamic> j) {
    Map<String, double> parseTopicScores() {
      final raw = j['topicScores'];
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry(k.toString(),
          (v is num) ? v.toDouble() : 0.0));
    }
    Map<String, int> parseBloom() {
      final raw = j['bloomDistribution'];
      if (raw is! Map) return const {};
      return raw.map((k, v) =>
          MapEntry(k.toString(), (v is num) ? v.toInt() : 0));
    }
    List<ExamHistoryQuestion> parseQuestions() {
      final raw = j['questions'];
      if (raw is! List) return const [];
      final out = <ExamHistoryQuestion>[];
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          out.add(ExamHistoryQuestion.fromJson(
              Map<String, dynamic>.from(item)));
        } catch (_) {/* skip malformed */}
      }
      return out;
    }
    return ExamHistoryRecord(
      sessionId: j['sessionId'] as String,
      date: DateTime.parse(j['date'] as String),
      score: (j['score'] as num).toDouble(),
      totalQuestions: (j['totalQuestions'] as num).toInt(),
      correctCount: (j['correctCount'] as num).toInt(),
      durationSeconds: (j['durationSeconds'] as num).toInt(),
      topicTitles: (j['topicTitles'] as List<dynamic>).cast<String>(),
      topicScores: parseTopicScores(),
      difficultyUsed: (j['difficultyUsed'] as String?) ?? 'normale',
      bloomDistribution: parseBloom(),
      markedForReviewCount: (j['markedForReviewCount'] as num?)?.toInt() ?? 0,
      questions: parseQuestions(),
    );
  }
}
