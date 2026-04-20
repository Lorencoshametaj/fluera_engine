import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../ai/ai_provider.dart';
import '../../ai/atlas_ai_service.dart';
import '../../ai/telemetry_recorder.dart';
import '../../utils/safe_path_provider.dart';
import '../../config/v1_feature_gate.dart'; // 🚀 v1 DEFER kill switches
import 'exam_session_model.dart';

/// 🎓 ATLAS EXAM MODE — Session controller.
///
/// Manages the full exam lifecycle including:
/// - Question generation via Atlas AI
/// - Answer submission and evaluation (choices + open-ended streaming)
/// - Adaptive difficulty: after 3 consecutive correct, requests harder questions
/// - Session history persistence (JSON in app documents dir)
class ExamSessionController extends ChangeNotifier {
  final AiProvider _provider;
  final String language;

  ExamSession? _session;
  ExamSession? get session => _session;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _loadingHint;
  String? get loadingHint => _loadingHint;

  String? _error;
  String? get error => _error;

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

  /// Callback fired after session complete with review schedule.
  /// Integrates with NativeNotifications for spaced repetition.
  void Function(Map<String, Duration> schedule)? onReviewScheduleReady;

  ExamSessionController({
    required AiProvider provider,
    this.language = 'Italian',
    this.onReviewScheduleReady,
    TelemetryRecorder? telemetry,
  })  : _provider = provider,
        _telemetry = telemetry ?? TelemetryRecorder.noop {
    _loadHistory();
  }

  final TelemetryRecorder _telemetry;
  DateTime? _sessionStartedAt;

  // ─────────────────────────────────────────────────────────────────────────
  // Session lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> startExam(Map<String, String> selectedClusters, {int count = 7}) async {
    // 🚀 v1 DEFER: Exam Session gated
    if (!V1FeatureGate.examSession) return;
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    _loadingHint = 'Genero le domande…';
    _fullClusterTexts = Map.from(selectedClusters); // save full texts
    notifyListeners();

    try {
      if (!_provider.isInitialized) await _provider.initialize();

      final questions = await (_provider as GeminiProvider)
          .generateExamQuestions(selectedClusters, language: language, count: count);

      if (questions.isEmpty) {
        _error = 'Non ho trovato abbastanza contenuto. Aggiungi più appunti!';
        return;
      }

      _session = ExamSession(
        sessionId: 'exam_${DateTime.now().millisecondsSinceEpoch}',
        questions: questions,
      );
      _sessionStartedAt = DateTime.now();
      _telemetry.logEvent('step_11_exam_started', properties: {
        'question_count': questions.length,
        'topic_count': selectedClusters.length,
        'language': language,
      });
    } catch (e) {
      _error = 'Errore: ${e.toString().length > 100 ? '${e.toString().substring(0, 100)}...' : e}';
    } finally {
      _isLoading = false;
      _loadingHint = null;
      notifyListeners();
    }
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
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────────────────

  bool nextQuestion() {
    if (_session == null) return false;
    _session!.currentIndex++;
    _currentEvalText = '';
    if (_session!.isComplete) {
      _session!.completedAt = DateTime.now();
      _saveHistory();
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
        _sessionStartedAt = null;
      }
    }
    notifyListeners();
    return !_session!.isComplete;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Adaptive difficulty
  // ─────────────────────────────────────────────────────────────────────────

  void _updateAdaptiveTracking(ExamAnswerResult result) {
    final s = _session;
    if (s == null || s.difficultyBoosted) return;

    if (result == ExamAnswerResult.correct) {
      s.consecutiveCorrect++;
      if (s.consecutiveCorrect >= 3) {
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

    _isLoading = true;
    _error = null;
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
          .generateExamQuestions(clusterTexts, language: language, count: wrong.length);

      if (questions.isEmpty) {
        _error = 'Non riesco a generare varianti. Riprova!';
        return;
      }

      _session = ExamSession(
        sessionId: 'replay_${DateTime.now().millisecondsSinceEpoch}',
        questions: questions,
      );
    } catch (e) {
      _error = 'Errore: ${e.toString().length > 100 ? '${e.toString().substring(0, 100)}...' : e}';
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

  Future<void> _loadHistory() async {
    try {
      final file = await _historyFile();
      if (file == null || !await file.exists()) return;
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      _history = list
          .whereType<Map<String, dynamic>>()
          .map(ExamHistoryRecord.fromJson)
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ ExamHistory load error: $e');
    }
  }

  Future<void> _saveHistory() async {
    final s = _session;
    if (s == null) return;

    final record = ExamHistoryRecord(
      sessionId: s.sessionId,
      date: s.startedAt,
      score: s.score,
      totalQuestions: s.questions.length,
      correctCount: s.correctCount,
      durationSeconds: s.durationSeconds,
      topicTitles: selectedTopicTitles,
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
      await file.writeAsString(
        jsonEncode(_history.map((r) => r.toJson()).toList()),
      );
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
