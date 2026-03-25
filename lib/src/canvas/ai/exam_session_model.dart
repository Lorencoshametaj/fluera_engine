/// 🎓 ATLAS EXAM MODE — Data models.
library;

import 'dart:math';

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

  const ExamHistoryRecord({
    required this.sessionId,
    required this.date,
    required this.score,
    required this.totalQuestions,
    required this.correctCount,
    required this.durationSeconds,
    required this.topicTitles,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'date': date.toIso8601String(),
        'score': score,
        'totalQuestions': totalQuestions,
        'correctCount': correctCount,
        'durationSeconds': durationSeconds,
        'topicTitles': topicTitles,
      };

  factory ExamHistoryRecord.fromJson(Map<String, dynamic> j) =>
      ExamHistoryRecord(
        sessionId: j['sessionId'] as String,
        date: DateTime.parse(j['date'] as String),
        score: (j['score'] as num).toDouble(),
        totalQuestions: (j['totalQuestions'] as num).toInt(),
        correctCount: (j['correctCount'] as num).toInt(),
        durationSeconds: (j['durationSeconds'] as num).toInt(),
        topicTitles: (j['topicTitles'] as List<dynamic>).cast<String>(),
      );
}
