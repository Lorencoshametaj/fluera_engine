import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../ai/ai_provider.dart';
import '../../ai/ai_usage_tracker.dart' show AiQuotaExceededException;
import '../../ai/atlas_ai_service.dart';
import '../../ai/telemetry_recorder.dart';
import '../../utils/safe_path_provider.dart';
import '../../config/v1_feature_gate.dart'; // 🚀 v1 DEFER kill switches
import 'cluster_concept.dart';
import 'cluster_concept_index.dart';
import 'exam_session_model.dart';

/// Structured error codes for exam start/load failures. The UI layer maps
/// each code to a localized message via FlueraLocalizations — the controller
/// stays free of UI strings beyond a fallback.
enum ExamErrorCode {
  quotaExceeded,
  offline,
  timeout,
  unexpected,
}

/// 🎓 ATLAS EXAM MODE — Session controller.
///
/// Manages the full exam lifecycle including:
/// - Question generation via Atlas AI
/// - Answer submission and evaluation (choices + open-ended streaming)
/// - Adaptive difficulty: after 3 consecutive correct, requests harder questions
/// - Session history persistence (JSON in app documents dir)
class ExamSessionController extends ChangeNotifier {
  final AiProvider _provider;

  /// Language used for AI question generation and evaluation. Initialised
  /// from the device locale at construction; the picker's "Lingua" selector
  /// can override it before [startExam] via direct assignment. Made mutable
  /// 2026-05-07 — previously the selector was a dead UI control.
  String language;

  ExamSession? _session;
  ExamSession? get session => _session;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _loadingHint;
  String? get loadingHint => _loadingHint;

  String? _error;
  String? get error => _error;

  /// Structured error code so the UI can render a localized message.
  /// `null` when no error.
  ExamErrorCode? _errorCode;
  ExamErrorCode? get errorCode => _errorCode;

  /// Free-text detail (truncated exception toString) used only for
  /// [ExamErrorCode.unexpected]. Never contains stack traces.
  String _errorDetail = '';
  String get errorDetail => _errorDetail;

  // Streaming evaluation text
  final _evalTextController = StreamController<String>.broadcast();
  Stream<String> get evalTextStream => _evalTextController.stream;
  String _currentEvalText = '';
  String get currentEvalText => _currentEvalText;

  // History
  List<ExamHistoryRecord> _history = [];
  List<ExamHistoryRecord> get history => List.unmodifiable(_history);

  // Selected topic titles (set externally for history record)
  List<String> selectedTopicTitles = [];

  // Full cluster texts — saved at startExam, used for adaptive difficulty
  Map<String, String> _fullClusterTexts = {};

  // 🛌 Anti-cramming: tracks when the student last completed an exam on each
  // cluster. Used to warn before back-to-back sessions on the same topic
  // (Spacing Effect, Ebbinghaus 1885 + Yerkes-Dodson stress avoidance).
  // Persisted to disk via [_saveLastExamMap].
  Map<String, DateTime> _lastExamPerCluster = {};

  /// Callback fired after session complete with review schedule.
  /// Integrates with NativeNotifications for spaced repetition.
  void Function(Map<String, Duration> schedule)? onReviewScheduleReady;

  ExamSessionController({
    required AiProvider provider,
    this.language = 'Italian',
    this.onReviewScheduleReady,
    TelemetryRecorder? telemetry,
    int? difficultyBoostThreshold,
  })  : _provider = provider,
        _telemetry = telemetry ?? TelemetryRecorder.noop,
        difficultyBoostThreshold =
            difficultyBoostThreshold ?? defaultDifficultyBoostThreshold {
    _loadHistory();
    _loadLastExamMap();
  }

  /// Minimum gap between two exams on the same cluster before we warn.
  /// 4 hours is a conservative anti-cramming buffer — long enough to break
  /// the encoding-test loop, short enough to allow legitimate same-day review.
  static const Duration antiCrammingThreshold = Duration(hours: 4);

  /// Default number of consecutive-correct answers that triggers an adaptive
  /// difficulty boost. The original literal `3` was a guess — exposed as a
  /// constant + constructor override so we can A/B test 2 vs 3 vs 4 with
  /// cohort data (Sprint 3 P3.3 in the enterprise plan).
  static const int defaultDifficultyBoostThreshold = 3;

  /// How many consecutive-correct answers before [_boostDifficulty] fires.
  final int difficultyBoostThreshold;

  /// Per-cluster ring buffer of question texts asked in recent sessions.
  /// Passed to the next [generateExamQuestions] call so the model can
  /// explicitly avoid repeating them. In-memory only for V1 — clears at
  /// app restart, which is acceptable: students who retake within the
  /// same session (the common abuse case) get fresh questions, while
  /// students who come back days later get a "natural" variation from
  /// the temperature bump alone.
  final Map<String, List<String>> _recentQuestionsByCluster = {};
  static const int _recentQuestionsCapPerCluster = 8;

  /// Optional cross-feature avoid index. When set, exam questions are
  /// mirrored into the index so Socratic doesn't repeat them on the
  /// same clusters during the next session.
  ClusterConceptIndex? _conceptIndex;
  set conceptIndex(ClusterConceptIndex? value) {
    _conceptIndex = value;
  }

  /// Compute a single difficulty label for the whole batch from the
  /// FSRS schedule. Uses the MAX maturity across selected clusters
  /// rather than the average — the rationale is "target the deepest
  /// understanding present, not the weakest link".
  ///
  /// Tuning rationale (2026-05-10): the average rule caused exam
  /// sessions on mixed scopes (1 mature concept + 4 new) to fall to
  /// 'facile', meaning mature concepts were re-tested at remember-level
  /// indefinitely. Using max means: if ANY selected cluster is mature,
  /// the batch difficulty rises to challenge that concept. New cards
  /// in the same batch get harder questions too — slightly stretching,
  /// but Bloom's "Apply" is still reachable.
  ///
  /// Maturity scoring:
  ///   - new card / no SRS    → 0
  ///   - in-between           → 1
  ///   - mature (reps≥5, stability>30) → 2
  ///
  /// Max:  0 → 'facile', 2 → 'difficile', otherwise → 'normale'.
  /// Returns 'normale' if the index isn't wired (test harness etc.).
  String _deriveAdaptiveDifficulty(Iterable<String> clusterIds) {
    final idx = _conceptIndex;
    if (idx == null) return 'normale';
    final ids = clusterIds.toList();
    if (ids.isEmpty) return 'normale';
    var maxScore = 0;
    for (final id in ids) {
      final card = idx.srsFor(id);
      int score;
      if (card == null) {
        score = 0;
      } else if (card.reps >= 5 && card.stability > 30) {
        score = 2;
      } else {
        score = 1;
      }
      if (score > maxScore) maxScore = score;
    }
    if (maxScore == 0) return 'facile';
    if (maxScore == 2) return 'difficile';
    return 'normale';
  }

  void _recordRecentQuestions(ExamSession s) {
    for (final q in s.questions) {
      final list = _recentQuestionsByCluster
          .putIfAbsent(q.sourceClusterId, () => <String>[]);
      list.add(q.questionText);
      while (list.length > _recentQuestionsCapPerCluster) {
        list.removeAt(0);
      }
      _conceptIndex?.recordQuestionAsked(
        q.sourceClusterId,
        q.questionText,
        AskedBy.exam,
      );
    }
  }

  /// Flat list of recent question texts across all clusters in [ids].
  /// Deduplicated. Capped at 30 entries to keep prompt token cost sane.
  /// Merges the local Exam ring buffer with the cross-feature index
  /// (Socratic-asked questions are pulled in via [_conceptIndex]).
  List<String> recentQuestionsForClusters(Iterable<String> ids) {
    final out = <String>{};
    final idx = _conceptIndex;
    for (final id in ids) {
      final list = _recentQuestionsByCluster[id];
      if (list != null) out.addAll(list);
      if (idx != null) {
        out.addAll(idx.recentQuestionsFor(id));
      }
    }
    if (out.length <= 30) return out.toList();
    return out.toList().sublist(out.length - 30);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Anti-cramming check (P1.2)
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the most recent exam timestamp among the given cluster IDs
  /// if it falls inside [antiCrammingThreshold]. Otherwise returns null.
  ///
  /// The UI uses this BEFORE calling [startExam] to show a "studied recently"
  /// warning dialog. Returning null means "no warning needed".
  AntiCrammingWarning? recentExamFor(Iterable<String> clusterIds) {
    DateTime? mostRecent;
    String? recentClusterId;
    for (final id in clusterIds) {
      final last = _lastExamPerCluster[id];
      if (last == null) continue;
      if (mostRecent == null || last.isAfter(mostRecent)) {
        mostRecent = last;
        recentClusterId = id;
      }
    }
    if (mostRecent == null) return null;
    final diff = DateTime.now().difference(mostRecent);
    if (diff >= antiCrammingThreshold) return null;
    return AntiCrammingWarning(
      lastExamAt: mostRecent,
      sinceLastExam: diff,
      clusterId: recentClusterId!,
    );
  }

  final TelemetryRecorder _telemetry;
  DateTime? _sessionStartedAt;

  // ─────────────────────────────────────────────────────────────────────────
  // Session lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> startExam(
    Map<String, String> selectedClusters, {
    int count = 7,
    String? difficulty,
  }) async {
    // 🚀 v1 DEFER: Exam Session gated
    if (!V1FeatureGate.examSession) return;
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    _errorDetail = '';
    _loadingHint = 'Genero le domande…';
    _fullClusterTexts = Map.from(selectedClusters); // save full texts
    notifyListeners();

    try {
      if (!_provider.isInitialized) await _provider.initialize();

      // 🎯 B2: derive difficulty from FSRS schedule when caller didn't
      // pass an explicit override and the index is wired. New cards
      // (no spaced-repetition history) → 'facile'. Mature concepts
      // (≥5 successful reviews and stability >30 days) → 'difficile'.
      // Mixed / unknown → 'normale'.
      final effectiveDifficulty =
          difficulty ?? _deriveAdaptiveDifficulty(selectedClusters.keys);

      final avoid = recentQuestionsForClusters(selectedClusters.keys);
      final questions = await (_provider as GeminiProvider)
          .generateExamQuestions(
        selectedClusters,
        language: language,
        count: count,
        difficulty: effectiveDifficulty,
        avoidPrompts: avoid,
      );

      if (questions.isEmpty) {
        _error = 'Non ho trovato abbastanza contenuto. Aggiungi più appunti!';
        _errorCode = ExamErrorCode.unexpected;
        _errorDetail = 'empty_content';
        return;
      }

      _session = ExamSession(
        sessionId: 'exam_${DateTime.now().millisecondsSinceEpoch}',
        questions: questions,
      );
      _sessionStartedAt = DateTime.now();
      // Save initial checkpoint so a crash on Q1 still resumes correctly.
      unawaited(_persistCheckpoint());
      _telemetry.logEvent('step_11_exam_started', properties: {
        'question_count': questions.length,
        'topic_count': selectedClusters.length,
        'language': language,
      });
    } catch (e) {
      _setExamError(e);
    } finally {
      _isLoading = false;
      _loadingHint = null;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 🌉 Cross-Domain Bridge integration (Passo 9 → Passo 11)
  // ─────────────────────────────────────────────────────────────────────────

  /// Append AI-generated validation questions for recently accepted
  /// cross-zone bridges to the current session. Each bridge produces
  /// one NON-Socratic question — assertive, single-answer — that tests
  /// whether the student can apply the transfer-learning the bridge
  /// implied. The added questions carry [ExamQuestion.isCrossDomain] = true
  /// so the UI can badge them and the telemetry can bucket the correct-rate.
  ///
  /// Safe to call as a no-op when no session is active, no bridges qualify,
  /// or the underlying provider doesn't support the cross-domain path.
  /// Returns the number of questions actually appended.
  ///
  /// Must be called AFTER [startExam] (or [resumeFromCheckpoint]) so the
  /// session list is initialised — typically right after a successful
  /// start, from the canvas state's exam-launch flow.
  Future<int> appendCrossDomainQuestions({
    required List<({String sourceLabel, String targetLabel, String socraticQuestion, String sourceClusterId, String targetClusterId})>
        bridges,
    required Map<String, String> clusterTexts,
  }) async {
    final session = _session;
    if (session == null) return 0;
    if (bridges.isEmpty) return 0;
    final gemini = _provider;
    if (gemini is! GeminiProvider) return 0;
    if (!gemini.isInitialized) return 0;

    try {
      final extras = await gemini.generateCrossDomainQuestions(
        bridges: bridges,
        clusterTexts: clusterTexts,
        language: language,
      );
      if (extras.isEmpty) return 0;

      session.questions.addAll(extras);
      _telemetry.logEvent('step_11_exam_cross_domain_added', properties: {
        'count': extras.length,
        'bridges_in': bridges.length,
      });
      unawaited(_persistCheckpoint());
      notifyListeners();
      return extras.length;
    } catch (e) {
      debugPrint('🌉 [Exam] appendCrossDomainQuestions error: $e');
      return 0;
    }
  }

  /// Correct-rate across the cross-domain validation questions in the
  /// current session. Returns null when no such question has been answered
  /// yet (avoids misleading "0%" before any data). Consumed by both the
  /// post-completion summary UI and the telemetry bucket
  /// `exam_cross_domain_question_correct_rate`.
  double? get crossDomainCorrectRate {
    final session = _session;
    if (session == null) return null;
    final cd = session.questions.where((q) => q.isCrossDomain).toList();
    if (cd.isEmpty) return null;
    final answered = cd.where((q) => q.result != null).toList();
    if (answered.isEmpty) return null;
    final correct =
        answered.where((q) => q.result == ExamAnswerResult.correct).length;
    return correct / answered.length;
  }

  /// Map a raw exception from the Gemini path to a user-friendly Italian
  /// message. The Exam UI shows [_error] verbatim as a fallback when the
  /// localised [errorCode]/[errorDetail] path isn't wired by the caller.
  /// We pattern-match on the most common failure modes (no network, quota
  /// exhausted, timeout) and reserve a generic fallback for everything else.
  /// Maps an exception to an [ExamErrorCode] for localization-friendly
  /// rendering at the UI layer. The legacy [error] string is still set
  /// (in Italian, for backward compat) — newer call sites should prefer
  /// [errorCode] + [errorDetail].
  static ExamErrorCode _classifyExamError(Object e) {
    final msg = e.toString().toLowerCase();
    if (e is AiQuotaExceededException ||
        msg.contains('quota') ||
        msg.contains('rate limit') ||
        msg.contains('429')) {
      return ExamErrorCode.quotaExceeded;
    }
    if (e is SocketException ||
        msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused') ||
        msg.contains('connection closed')) {
      return ExamErrorCode.offline;
    }
    if (e is TimeoutException ||
        msg.contains('timeout') ||
        msg.contains('timed out')) {
      return ExamErrorCode.timeout;
    }
    return ExamErrorCode.unexpected;
  }

  static String _humanizeExamError(Object e) {
    switch (_classifyExamError(e)) {
      case ExamErrorCode.quotaExceeded:
        return 'Hai raggiunto il limite AI di oggi. Riprova più tardi o passa a Pro per quota maggiore.';
      case ExamErrorCode.offline:
        return 'Connessione assente. La modalità esame richiede internet — riconnettiti e riprova.';
      case ExamErrorCode.timeout:
        return 'L\'AI ci sta mettendo troppo. Riprova tra un momento.';
      case ExamErrorCode.unexpected:
        final raw = e.toString();
        final tail = raw.length > 100 ? '${raw.substring(0, 100)}…' : raw;
        return 'Errore inatteso: $tail';
    }
  }

  void _setExamError(Object e) {
    _errorCode = _classifyExamError(e);
    _error = _humanizeExamError(e);
    if (_errorCode == ExamErrorCode.unexpected) {
      final raw = e.toString();
      _errorDetail = raw.length > 100 ? '${raw.substring(0, 100)}…' : raw;
    } else {
      _errorDetail = '';
    }
  }

  /// Resume an exam from a previously persisted checkpoint.
  /// The session keeps original question order, answered state, confidence,
  /// elaboration, and adaptive-difficulty progress.
  Future<bool> resumeFromCheckpoint() async {
    if (!V1FeatureGate.examSession) return false;
    if (_isLoading) return false;

    final cp = await _readCheckpoint();
    if (cp == null) return false;

    _session = cp.session;
    _fullClusterTexts = cp.fullClusterTexts;
    selectedTopicTitles = cp.topicTitles;
    _sessionStartedAt = cp.session.startedAt;
    _error = null;
    _telemetry.logEvent('step_11_exam_resumed', properties: {
      'question_count': cp.session.questions.length,
      'current_index': cp.session.currentIndex,
      'answered_count': cp.session.answeredCount,
    });
    notifyListeners();
    return true;
  }

  /// Discard any pending checkpoint without resuming.
  /// Use when the user opts out of the resume dialog.
  Future<void> discardCheckpoint() async {
    await _deleteCheckpoint();
  }

  /// Sprint 6 — fired once per ExamOverlay lifetime when the
  /// surgicalPath layout is actually rendered. Keeps the telemetry call
  /// out of the widget so all step_11 events live in the controller.
  void logSurgicalPathRendered() {
    _telemetry.logEvent('step_11_exam_surgical_path_used', properties: {
      'language': language,
    });
  }

  /// Returns a preview of the pending checkpoint, if any.
  /// Used by the resume dialog to show "Domanda 3/7 · Anatomia, Patologia".
  Future<ExamCheckpointPreview?> peekCheckpoint() async {
    final cp = await _readCheckpoint();
    if (cp == null) return null;
    return ExamCheckpointPreview(
      currentIndex: cp.session.currentIndex,
      totalQuestions: cp.session.questions.length,
      topicTitles: cp.topicTitles,
      startedAt: cp.session.startedAt,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Answer submission
  // ─────────────────────────────────────────────────────────────────────────

  void submitChoiceAnswer(int choiceIndex) {
    final q = _session?.currentQuestion;
    if (q == null || q.isAnswered) return;
    final correct = choiceIndex == q.correctChoiceIndex;
    q.result = correct ? ExamAnswerResult.correct : ExamAnswerResult.incorrect;
    q.userAnswer = q.choices.isNotEmpty ? q.choices[choiceIndex] : choiceIndex.toString();
    _updateAdaptiveTracking(q.result!);
    unawaited(_persistCheckpoint());
    notifyListeners();
  }

  Future<void> submitOpenAnswer(String userAnswer) async {
    final q = _session?.currentQuestion;
    if (q == null || q.isAnswered) return;
    q.userAnswer = userAnswer;

    // If empty → skip, don't waste an API call
    if (userAnswer.trim().isEmpty) {
      q.result = ExamAnswerResult.skipped;
      _currentEvalText = q.explanation;
      _evalTextController.add(_currentEvalText);
      _updateAdaptiveTracking(q.result!);
      unawaited(_persistCheckpoint());
      notifyListeners();
      return;
    }

    _currentEvalText = '';
    _isLoading = true;
    _loadingHint = 'Valuto la risposta…';
    notifyListeners();

    try {
      final result = await (_provider as GeminiProvider).evaluateOpenAnswer(
        question: q.questionText,
        correctAnswer: q.correctAnswer,
        userAnswer: userAnswer,
        language: language,
        onTextChunk: (chunk) {
          _currentEvalText += chunk;
          _evalTextController.add(_currentEvalText);
        },
      );
      q.result = result;
      _updateAdaptiveTracking(result);
    } catch (e) {
      q.result = ExamAnswerResult.skipped;
      _evalTextController.add('\n⚠️ Errore. Risposta corretta: ${q.correctAnswer}');
    } finally {
      _isLoading = false;
      _loadingHint = null;
      unawaited(_persistCheckpoint());
      notifyListeners();
    }
  }

  void skipQuestion() {
    final q = _session?.currentQuestion;
    if (q == null) return;
    q.result = ExamAnswerResult.skipped;
    _currentEvalText = q.explanation;
    _evalTextController.add(_currentEvalText);
    _updateAdaptiveTracking(q.result!);
    unawaited(_persistCheckpoint());
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────────────────

  /// Move back one question. Returns `true` if navigation succeeded,
  /// `false` if already at the first question. The student can re-edit
  /// their answer — `result`, `userAnswer`, `confidenceLevel`, and
  /// `elaboration` are preserved from when they first answered. Submitting
  /// a new answer (via [submitChoiceAnswer] / [submitOpenAnswer]) overwrites
  /// the prior result.
  bool previousQuestion() {
    if (_session == null) return false;
    if (_session!.currentIndex == 0) return false;
    _session!.currentIndex--;
    _currentEvalText = '';
    unawaited(_persistCheckpoint());
    notifyListeners();
    return true;
  }

  /// Whether [previousQuestion] would advance backward.
  bool get canGoPrevious =>
      _session != null && _session!.currentIndex > 0;

  bool nextQuestion() {
    if (_session == null) return false;
    _session!.currentIndex++;
    _currentEvalText = '';
    if (_session!.isComplete) {
      _session!.completedAt = DateTime.now();
      _saveHistory();
      // Track per-cluster completion for anti-cramming gating (P1.2).
      _recordExamCompletion(_session!);
      // Push completed question texts into the per-cluster ring buffer so
      // the next exam on the same notes deliberately avoids them.
      _recordRecentQuestions(_session!);
      // Clean up checkpoint — session is done, nothing to resume.
      unawaited(_deleteCheckpoint());
      final startedAt = _sessionStartedAt;
      if (startedAt != null) {
        final s = _session!;
        final correctCount = s.questions
            .where((q) => q.result == ExamAnswerResult.correct)
            .length;
        _telemetry.logEvent('step_11_exam_completed', properties: {
          'question_count': s.questions.length,
          'correct_count': correctCount,
          'difficulty_boosted': s.difficultyBoosted,
          'duration_sec':
              DateTime.now().difference(startedAt).inSeconds,
        });

        // 🌉 Passo 9 telemetry: separate bucket for cross-domain validation
        // questions so we can A/B whether accepting bridges actually
        // consolidates transfer learning (Bjork 1994 prediction).
        final cd = s.questions.where((q) => q.isCrossDomain).toList();
        final cdAnswered = cd.where((q) => q.result != null).toList();
        if (cdAnswered.isNotEmpty) {
          final cdCorrect = cdAnswered
              .where((q) => q.result == ExamAnswerResult.correct)
              .length;
          _telemetry.logEvent(
            'exam_cross_domain_question_correct_rate',
            properties: {
              'count': cdAnswered.length,
              'correct': cdCorrect,
              'rate': cdCorrect / cdAnswered.length,
              'total_appended': cd.length,
            },
          );
        }

        _sessionStartedAt = null;
      }
    } else {
      // Index advanced — re-checkpoint so resume points at the right Q.
      unawaited(_persistCheckpoint());
    }
    notifyListeners();
    return !_session!.isComplete;
  }

  /// Persist the student's elaboration on a wrong answer (Generation Effect,
  /// Slamecka & Graf 1978). Checkpoint after save so a crash after typing
  /// 200 chars of elaboration doesn't lose the work.
  void saveElaboration(String text) {
    final q = _session?.currentQuestion;
    if (q == null) return;
    q.elaboration = text;
    unawaited(_persistCheckpoint());
    notifyListeners();
  }

  /// Persist the metacognitive confidence rating (1-5) set BEFORE answering.
  /// Checkpoint immediately so that even if the student crashes between
  /// confidence pick and answer submit, we don't lose the rating
  /// (which is critical for the Hypercorrection Effect).
  void setConfidence(int level) {
    final q = _session?.currentQuestion;
    if (q == null) return;
    q.confidenceLevel = level;
    unawaited(_persistCheckpoint());
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Adaptive difficulty
  // ─────────────────────────────────────────────────────────────────────────

  void _updateAdaptiveTracking(ExamAnswerResult result) {
    final s = _session;
    if (s == null || s.difficultyBoosted) return;

    if (result == ExamAnswerResult.correct) {
      s.consecutiveCorrect++;
      if (s.consecutiveCorrect >= difficultyBoostThreshold) {
        // Trigger async boost — don't block UI
        _boostDifficulty();
      }
    } else {
      s.consecutiveCorrect = 0;
    }
  }

  Future<void> _boostDifficulty() async {
    final s = _session;
    if (s == null || s.difficultyBoosted) return;
    s.difficultyBoosted = true;

    // Find unanswered questions and replace with harder versions
    final unansweredIndices = s.questions
        .asMap()
        .entries
        .where((e) => !e.value.isAnswered && e.key > s.currentIndex + 1)
        .map((e) => e.key)
        .toList();

    if (unansweredIndices.isEmpty) return;

    // Build source texts for unanswered cluster IDs
    final clusterIds = unansweredIndices
        .map((i) => s.questions[i].sourceClusterId)
        .toSet()
        .toList();

    // Use saved full cluster texts if available, fallback to sourceText
    final Map<String, String> clusterTexts = {};
    for (final id in clusterIds) {
      clusterTexts[id] = _fullClusterTexts[id] ??
          s.questions.firstWhere((q) => q.sourceClusterId == id).sourceText;
    }

    if (clusterTexts.isEmpty) return;

    try {
      _loadingHint = '🎯 Livello aumentato — domande più difficili!';
      notifyListeners();

      final harderQuestions = await (_provider as GeminiProvider)
          .generateExamQuestions(
        clusterTexts,
        language: language,
        count: unansweredIndices.length,
        difficulty: 'difficile',
      );

      if (!mounted) return;

      // Swap in the harder questions for unanswered slots
      for (int i = 0;
          i < unansweredIndices.length && i < harderQuestions.length;
          i++) {
        s.questions[unansweredIndices[i]] = harderQuestions[i];
      }
    } catch (e) {
      debugPrint('⚠️ adaptiveDifficulty: $e');
    } finally {
      _loadingHint = null;
      notifyListeners();
    }
  }

  bool get mounted => !_evalTextController.isClosed;

  // ─────────────────────────────────────────────────────────────────────────
  // Hint
  // ─────────────────────────────────────────────────────────────────────────

  /// Asks Atlas for a one-clue hint for the current question.
  /// Returns empty string if not applicable.
  Future<String> getHint() async {
    final q = _session?.currentQuestion;
    if (q == null) return '';
    try {
      if (!_provider.isInitialized) await _provider.initialize();
      return await (_provider as GeminiProvider).generateHint(
        question: q.questionText,
        correctAnswer: q.correctAnswer,
        language: language,
      );
    } catch (_) {
      return '💡 Pensa ai concetti fondamentali!';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Error Replay
  // ─────────────────────────────────────────────────────────────────────────

  /// Questions the student got wrong or skipped in the current session.
  List<ExamQuestion> get incorrectQuestions => _session?.questions
      .where((q) => q.result == ExamAnswerResult.incorrect ||
                    q.result == ExamAnswerResult.skipped)
      .toList() ?? [];

  /// Starts a mini error-replay session with variant questions from failed clusters.
  Future<void> startErrorReplay() async {
    final wrong = incorrectQuestions;
    if (wrong.isEmpty || _isLoading) return;

    // The completed exam's questions are already in
    // `_recentQuestionsByCluster` (recorded by [nextQuestion] when the
    // last question marked the session complete). Pass them as
    // [avoidPrompts] below so Gemini doesn't return the same prompts
    // the student just failed — without this the "Strengthen N concepts"
    // button shipped variants that were verbatim duplicates and the
    // student rage-quit assuming the feature was broken.

    // Drop the completed session NOW so the build path enters the
    // loading branch (`session == null && isLoading`). Without this the
    // results screen stayed visible while Gemini ran in the background
    // and the button looked unresponsive on slow networks.
    _session = null;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    _errorDetail = '';
    _loadingHint = '🔄 Genero varianti per il ripasso...';
    notifyListeners();

    try {
      // Build cluster texts from wrong questions
      final Map<String, String> clusterTexts = {};
      for (final q in wrong) {
        clusterTexts[q.sourceClusterId] =
            _fullClusterTexts[q.sourceClusterId] ?? q.sourceText;
      }

      if (!_provider.isInitialized) await _provider.initialize();
      final questions = await (_provider as GeminiProvider)
          .generateExamQuestions(
        clusterTexts,
        language: language,
        count: wrong.length,
        avoidPrompts: recentQuestionsForClusters(clusterTexts.keys),
      );

      if (questions.isEmpty) {
        _error = 'Non riesco a generare varianti. Riprova!';
        _errorCode = ExamErrorCode.unexpected;
        _errorDetail = 'replay_failed';
        return;
      }

      _session = ExamSession(
        sessionId: 'replay_${DateTime.now().millisecondsSinceEpoch}',
        questions: questions,
      );
    } catch (e) {
      _setExamError(e);
    } finally {
      _isLoading = false;
      _loadingHint = null;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Spaced repetition export
  // ─────────────────────────────────────────────────────────────────────────

  List<String> get masteredConcepts => _session?.questions
      .where((q) => q.result == ExamAnswerResult.correct)
      .map((q) => q.sourceText.split(' ').take(3).join(' '))
      .toList() ?? [];

  Map<String, Duration> get reviewSchedule {
    final map = <String, Duration>{};
    for (final q in _session?.questions ?? []) {
      final key = q.sourceText.split(' ').take(3).join(' ');
      if (q.result == ExamAnswerResult.partial) {
        map[key] = const Duration(days: 1);
      } else if (q.result == ExamAnswerResult.incorrect ||
          q.result == ExamAnswerResult.skipped) {
        map[key] = const Duration(days: 3);
      }
    }
    return map;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mid-session checkpoint persistence (crash-safe resume)
  // ─────────────────────────────────────────────────────────────────────────

  /// Path to the checkpoint file holding the in-progress session.
  /// Single file (not per-session) because we only support one active exam
  /// at a time — starting a new one discards any previous checkpoint.
  Future<File?> _checkpointFile() async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return null;
      return File('${dir.path}/fluera_exam_checkpoint.json');
    } catch (_) {
      return null;
    }
  }

  /// Persist current in-progress session atomically.
  /// Called after every answer submission, so a crash never costs more
  /// than the current question.
  Future<void> _persistCheckpoint() async {
    final s = _session;
    if (s == null) return;
    if (s.isComplete) {
      // Don't checkpoint a finished session — clean up instead.
      await _deleteCheckpoint();
      return;
    }

    try {
      final file = await _checkpointFile();
      if (file == null) return;

      final payload = <String, dynamic>{
        'version': 1,
        'session': s.toJson(),
        'fullClusterTexts': _fullClusterTexts,
        'topicTitles': selectedTopicTitles,
      };

      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('⚠️ ExamCheckpoint save error: $e');
    }
  }

  /// Read the pending checkpoint, if any.
  Future<_ExamCheckpointPayload?> _readCheckpoint() async {
    try {
      final file = await _checkpointFile();
      if (file == null || !await file.exists()) return null;

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;

      final j = jsonDecode(raw) as Map<String, dynamic>;
      final session = ExamSession.fromJson(
        j['session'] as Map<String, dynamic>,
      );
      // Don't resume a session that was already completed.
      if (session.isComplete) {
        await _deleteCheckpoint();
        return null;
      }

      final fullClusterTexts = ((j['fullClusterTexts'] as Map<String, dynamic>?) ?? {})
          .map((k, v) => MapEntry(k, v as String));
      final topicTitles = ((j['topicTitles'] as List<dynamic>?) ?? [])
          .map((e) => e as String)
          .toList();

      return _ExamCheckpointPayload(
        session: session,
        fullClusterTexts: fullClusterTexts,
        topicTitles: topicTitles,
      );
    } catch (e) {
      debugPrint('⚠️ ExamCheckpoint load error: $e');
      // Corrupted checkpoint — remove it so the user isn't stuck.
      await _deleteCheckpoint();
      return null;
    }
  }

  Future<void> _deleteCheckpoint() async {
    try {
      final file = await _checkpointFile();
      if (file != null && await file.exists()) await file.delete();
      final tmp = File('${file?.path}.tmp');
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {
      // best-effort cleanup
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Anti-cramming persistence (per-cluster last-exam timestamps, P1.2)
  // ─────────────────────────────────────────────────────────────────────────

  Future<File?> _lastExamFile() async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return null;
      return File('${dir.path}/fluera_exam_last_per_cluster.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadLastExamMap() async {
    try {
      final file = await _lastExamFile();
      if (file == null || !await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _lastExamPerCluster = j.map(
        (k, v) => MapEntry(k, DateTime.parse(v as String)),
      );
    } catch (e) {
      debugPrint('⚠️ ExamLastMap load error: $e');
    }
  }

  Future<void> _saveLastExamMap() async {
    try {
      final file = await _lastExamFile();
      if (file == null) return;
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(_lastExamPerCluster.map(
          (k, v) => MapEntry(k, v.toIso8601String()),
        )),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('⚠️ ExamLastMap save error: $e');
    }
  }

  /// Stamp every cluster touched by [session] with [DateTime.now], so a
  /// subsequent [recentExamFor] picks them up as "studied recently".
  void _recordExamCompletion(ExamSession session) {
    final now = DateTime.now();
    final clusterIds =
        session.questions.map((q) => q.sourceClusterId).toSet();
    for (final id in clusterIds) {
      _lastExamPerCluster[id] = now;
    }
    unawaited(_saveLastExamMap());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // History persistence
  // ─────────────────────────────────────────────────────────────────────────

  Future<File?> _historyFile() async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return null;
      return File('${dir.path}/fluera_exam_history.json');
    } catch (_) {
      return null;
    }
  }

  /// Standalone loader — reads the saved exam history from disk WITHOUT
  /// needing a controller instance (which would require an [AiProvider]).
  /// Used by the [ExamDashboardScreen] which runs outside any active exam.
  /// Returns an empty list if the file is missing or unreadable.
  static Future<List<ExamHistoryRecord>> loadHistoryStandalone() async {
    try {
      final dir = await getSafeDocumentsDirectory();
      if (dir == null) return const [];
      final primary = File('${dir.path}/fluera_exam_history.json');
      final backup = File('${primary.path}.bak');
      for (final candidate in [primary, backup]) {
        if (!await candidate.exists()) continue;
        try {
          final raw = await candidate.readAsString();
          if (raw.trim().isEmpty) continue;
          final list = jsonDecode(raw) as List<dynamic>;
          return list
              .whereType<Map<String, dynamic>>()
              .map(ExamHistoryRecord.fromJson)
              .toList();
        } catch (e) {
          debugPrint('⚠️ ExamHistory standalone load error: $e');
        }
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _loadHistory() async {
    final file = await _historyFile();
    if (file == null) return;

    // Try primary file first, fall back to .bak if corrupted.
    for (final candidate in [file, File('${file.path}.bak')]) {
      if (!await candidate.exists()) continue;
      try {
        final raw = await candidate.readAsString();
        if (raw.trim().isEmpty) continue;
        final list = jsonDecode(raw) as List<dynamic>;
        _history = list
            .whereType<Map<String, dynamic>>()
            .map(ExamHistoryRecord.fromJson)
            .toList();
        notifyListeners();
        return;
      } catch (e) {
        debugPrint('⚠️ ExamHistory load error from ${candidate.path}: $e');
      }
    }
  }

  Future<void> _saveHistory() async {
    final s = _session;
    if (s == null) return;

    // Per-topic accuracy: group questions by their sourceClusterId, look up
    // the friendly title from selectedTopicTitles when the cluster ID
    // matches a synth `topic_N` (topic-grouping path), else fall back to
    // the cluster ID itself (legacy / fog of war flows).
    final byTopic = <String, List<ExamQuestion>>{};
    for (final q in s.questions) {
      byTopic.putIfAbsent(q.sourceClusterId, () => []).add(q);
    }
    final topicScores = <String, double>{};
    for (final entry in byTopic.entries) {
      final correct = entry.value
          .where((q) => q.result == ExamAnswerResult.correct)
          .length;
      // Map synthetic topic_N IDs back to their picker title when available.
      String label = entry.key;
      if (label.startsWith('topic_')) {
        final idx = int.tryParse(label.substring(6)) ?? -1;
        if (idx >= 0 && idx < selectedTopicTitles.length) {
          label = selectedTopicTitles[idx];
        }
      }
      topicScores[label] = entry.value.isEmpty
          ? 0.0
          : correct / entry.value.length;
    }

    final bloomDist = <String, int>{};
    for (final q in s.questions) {
      final lvl = q.bloomLevel?.name ?? 'remember';
      bloomDist[lvl] = (bloomDist[lvl] ?? 0) + 1;
    }

    final markedCount =
        s.questions.where((q) => q.markedForReview).length;

    // Schema v3: snapshot every question for the review screen so the
    // student sees `<question> → <my answer> → <strokes>` instead of an
    // anonymous "Domanda 1". Stores user answer, correct answer, and
    // result label — enough for context, no AI explanation kept here.
    final questionSnapshots = [
      for (final q in s.questions)
        ExamHistoryQuestion(
          id: q.id,
          questionText: q.questionText,
          correctAnswer: q.correctAnswer,
          userAnswer: q.userAnswer,
          resultLabel: q.result?.name ?? '',
        ),
    ];

    final record = ExamHistoryRecord(
      sessionId: s.sessionId,
      date: s.startedAt,
      score: s.score,
      totalQuestions: s.questions.length,
      correctCount: s.correctCount,
      durationSeconds: s.durationSeconds,
      topicTitles: selectedTopicTitles,
      topicScores: topicScores,
      difficultyUsed: s.difficultyBoosted ? 'difficile' : 'normale',
      bloomDistribution: bloomDist,
      markedForReviewCount: markedCount,
      questions: questionSnapshots,
    );

    _history.insert(0, record);
    // Keep last 50 sessions
    if (_history.length > 50) _history = _history.take(50).toList();

    // Fire SR notification callback
    if (onReviewScheduleReady != null) {
      onReviewScheduleReady!(reviewSchedule);
    }

    try {
      final file = await _historyFile();
      if (file == null) return;

      // Atomic write: keep previous as .bak, write to .tmp, then rename.
      // This protects against partial writes if app/device crashes mid-save.
      final tmp = File('${file.path}.tmp');
      final bak = File('${file.path}.bak');

      await tmp.writeAsString(
        jsonEncode(_history.map((r) => r.toJson()).toList()),
        flush: true,
      );

      if (await file.exists()) {
        if (await bak.exists()) await bak.delete();
        await file.rename(bak.path);
      }
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('⚠️ ExamHistory save error: $e');
    }
  }

  @override
  void dispose() {
    _evalTextController.close();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Checkpoint payload (internal — full state for resume)
// ─────────────────────────────────────────────────────────────────────────────

class _ExamCheckpointPayload {
  final ExamSession session;
  final Map<String, String> fullClusterTexts;
  final List<String> topicTitles;

  const _ExamCheckpointPayload({
    required this.session,
    required this.fullClusterTexts,
    required this.topicTitles,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Checkpoint preview (public — minimal info for the resume dialog)
// ─────────────────────────────────────────────────────────────────────────────

/// Lightweight summary of a pending exam checkpoint.
/// Returned by [ExamSessionController.peekCheckpoint] so the caller can
/// render a "Riprendi esame interrotto?" dialog without rehydrating the
/// full session state.
class ExamCheckpointPreview {
  /// 0-based index of the question the student was on when interrupted.
  final int currentIndex;

  /// Total number of questions in the interrupted session.
  final int totalQuestions;

  /// Display titles of the topics being examined.
  final List<String> topicTitles;

  /// When the interrupted exam was originally started.
  final DateTime startedAt;

  const ExamCheckpointPreview({
    required this.currentIndex,
    required this.totalQuestions,
    required this.topicTitles,
    required this.startedAt,
  });

  /// 1-based question number for display ("Domanda 3 di 7").
  int get questionNumber => currentIndex + 1;
}

// ─────────────────────────────────────────────────────────────────────────────
// Anti-cramming warning
// ─────────────────────────────────────────────────────────────────────────────

/// Returned by [ExamSessionController.recentExamFor] when the student tries
/// to start an exam on a cluster they already examined inside the
/// [ExamSessionController.antiCrammingThreshold] window.
///
/// Theory: spaced repetition + Yerkes-Dodson — back-to-back testing on the
/// same material under stress produces transient performance gains but poor
/// long-term retention. The dialog should let the student override (their
/// agency stays intact) but with informed friction.
class AntiCrammingWarning {
  /// When the most recent exam touching this cluster completed.
  final DateTime lastExamAt;

  /// How long ago that was (always < 4h when this object exists).
  final Duration sinceLastExam;

  /// Cluster id that triggered the warning (most-recently-examined among
  /// the selected scope).
  final String clusterId;

  const AntiCrammingWarning({
    required this.lastExamAt,
    required this.sinceLastExam,
    required this.clusterId,
  });

  /// Human label like "2 ore fa" / "45 minuti fa" / "pochi secondi fa".
  String get humanRelative {
    final m = sinceLastExam.inMinutes;
    if (m < 1) return 'pochi secondi fa';
    if (m < 60) return '$m minuti fa';
    final h = sinceLastExam.inHours;
    return h == 1 ? '1 ora fa' : '$h ore fa';
  }
}
