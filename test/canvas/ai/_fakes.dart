import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/ai/ai_provider.dart';
import 'package:fluera_engine/src/ai/atlas_ai_service.dart';
import 'package:fluera_engine/src/canvas/ai/exam_session_model.dart';

/// Subclass of [GeminiProvider] used by the exam session tests.
///
/// We extend the real provider rather than implement [AiProvider] directly
/// because the controller does `(_provider as GeminiProvider)` at runtime —
/// only a real subclass survives that cast.
///
/// Every method that would hit the network is overridden to a deterministic
/// in-memory response. The constructor takes a fake API key so the parent
/// class doesn't try to read credentials.
class FakeGeminiProvider extends GeminiProvider {
  FakeGeminiProvider({this.questionsToReturn = const []})
      : super(apiKey: 'fake-key-for-tests');

  /// Pre-fabricated questions returned by [generateExamQuestions].
  /// Tests replace this list to simulate Gemini behaviour.
  List<ExamQuestion> questionsToReturn;

  /// If non-null, [generateExamQuestions] throws this on the next call.
  Object? throwOnNextGenerate;

  // ─── Socratic-batch fakes ──────────────────────────────────────────────────

  /// JSON string returned by [askSocraticBatch]. Defaults to an empty
  /// `clusters` array so the controller falls back to its built-in
  /// fallback questions (predictable for lifecycle tests).
  String socraticBatchResponse = '{"clusters":[]}';

  /// If non-null, [askSocraticBatch] throws this on the next call.
  Object? throwOnNextSocraticBatch;

  /// Captures every prompt + avoid list passed to [askSocraticBatch].
  /// Tests assert against this to verify avoid-list propagation.
  final List<({String prompt, List<String> avoidPrompts})> socraticCalls = [];

  bool _ready = true;
  @override
  bool get isInitialized => _ready;

  @override
  Future<void> initialize() async {
    _ready = true;
  }

  @override
  Future<List<ExamQuestion>> generateExamQuestions(
    Map<String, String> clusterTexts, {
    String language = 'Italian',
    int count = 7,
    String difficulty = 'normale',
    List<String> avoidPrompts = const [],
  }) async {
    final t = throwOnNextGenerate;
    if (t != null) {
      throwOnNextGenerate = null;
      throw t;
    }
    return List.of(questionsToReturn);
  }

  @override
  Future<ExamAnswerResult> evaluateOpenAnswer({
    required String question,
    required String correctAnswer,
    required String userAnswer,
    required String language,
    required void Function(String chunk) onTextChunk,
  }) async {
    onTextChunk('Risposta corretta.');
    return ExamAnswerResult.correct;
  }

  @override
  Future<String> generateHint({
    required String question,
    required String correctAnswer,
    String language = 'Italian',
  }) async {
    return '💡 Test hint';
  }

  /// Response returned by [askAtlas]. Tests override this to exercise
  /// surfaces like the index's title generator that consume Atlas.
  AtlasResponse askAtlasResponse = const AtlasResponse.empty();

  /// Captures every `askAtlas` prompt for assertion.
  final List<String> askAtlasPrompts = [];

  @override
  Future<AtlasResponse> askAtlas(
    String userPrompt,
    List<Map<String, dynamic>> canvasContext,
  ) async {
    askAtlasPrompts.add(userPrompt);
    return askAtlasResponse;
  }

  @override
  Future<String> askSocraticBatch(
    String userPrompt, {
    List<String> avoidPrompts = const [],
  }) async {
    socraticCalls.add((prompt: userPrompt, avoidPrompts: avoidPrompts));
    final t = throwOnNextSocraticBatch;
    if (t != null) {
      throwOnNextSocraticBatch = null;
      throw t;
    }
    return socraticBatchResponse;
  }

  /// Captures every per-stage stream call made by the V3.4 ω path so
  /// tests can assert on stage/lang propagation.
  final List<({String stage, String payload, String langCode})>
      streamForStageCalls = [];

  /// Optional per-stage response override. When set, `streamForStage`
  /// yields the matching string. When not set, the fake parses
  /// [socraticBatchResponse] (legacy batch JSON) and emits one entry per
  /// call in slot order — preserves backward-compat for tests written
  /// against the V3.3 batch fake.
  ///
  /// Key: `SocraticStage.name` (e.g. `'anchor'`).
  Map<String, String>? streamPerStageOverride;

  /// Internal cursor for legacy `socraticBatchResponse` dispatch. Reset
  /// it manually between sessions if a single test fires multiple
  /// activations.
  int _stageDispatchCursor = 0;

  /// Resets the per-stage dispatch cursor. Call between activations
  /// when reusing the same fake across sessions.
  void resetStreamDispatchCursor() {
    _stageDispatchCursor = 0;
  }

  @override
  Stream<String> streamForStage({
    required String stage,
    required String payload,
    required String langCode,
  }) async* {
    streamForStageCalls.add((
      stage: stage,
      payload: payload,
      langCode: langCode,
    ));

    final override = streamPerStageOverride?[stage];
    if (override != null) {
      yield override;
      return;
    }

    // Legacy fallback: parse `socraticBatchResponse` and emit one
    // entry per call in slot order. Lets tests written against the
    // batch fake continue to work without rewriting fixtures.
    final raw = socraticBatchResponse.trim();
    if (raw.isEmpty) {
      yield '{"q":"","h":[]}';
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['clusters'] is List) {
        final clusters = decoded['clusters'] as List;
        if (clusters.isEmpty) {
          yield '{"q":"","h":[]}';
          return;
        }
        // V3.4 ω fake: each stage call consumes ONE entry in order.
        // When entries are exhausted, yield empty so the controller's
        // `_generatePerStageStreams` filter drops the slot (preserves
        // V3.3 batch semantic: queue length tracks JSON entry count
        // when batchPlan exceeds JSON).
        final idx = _stageDispatchCursor;
        _stageDispatchCursor++;
        if (idx >= clusters.length) {
          yield '{"q":"","h":[]}';
          return;
        }
        final entry = clusters[idx];
        yield jsonEncode(entry);
        return;
      }
      // Already a single-question payload → emit as-is.
      yield raw;
    } catch (_) {
      // Malformed legacy fixture → emit empty so caller falls back.
      yield '{"q":"","h":[]}';
    }
  }

  /// Returned by [cleanOcrItalian]. Tests can override to assert OCR
  /// cleanup propagation. Defaults to identity ("returns input").
  String Function(String raw)? cleanOcrItalianOverride;

  /// Call counter for [cleanOcrItalian] — used by cross-feature tests
  /// to assert that the index dedups OCR cleanup across Exam/Socratic.
  int cleanOcrItalianCalls = 0;

  @override
  Future<String> cleanOcrItalian(
    String raw, {
    String language = 'Italian',
    bool isFreeBackground = false,
  }) async {
    cleanOcrItalianCalls += 1;
    return cleanOcrItalianOverride?.call(raw) ?? raw;
  }

  /// Optional callback that lets tests inject deterministic follow-up
  /// questions. Receives `(role, priorQuestion, sketchOcr)`, returns
  /// the next question + isAporetic flag.
  ({String question, bool isAporetic}) Function(
    dynamic role,
    String priorQuestion,
    String sketchOcr,
  )? socraticFollowUpOverride;

  /// Call counter for [askSocraticFollowUp] — for multi-turn tests.
  int socraticFollowUpCalls = 0;

  @override
  Future<({String question, bool isAporetic})> askSocraticFollowUp({
    required String tipo,
    required String tema,
    required String priorQuestion,
    required String sketchOcr,
    required dynamic role,
    String? stage,
  }) async {
    socraticFollowUpCalls += 1;
    final override = socraticFollowUpOverride;
    if (override != null) return override(role, priorQuestion, sketchOcr);
    return (question: '', isAporetic: false);
  }

  /// Response returned by [askFreeText]. Cross-zone tests override this to
  /// simulate the AI emitting JSON arrays (or markdown-wrapped JSON) of
  /// suggested bridges. Defaults to empty string (no suggestions).
  String askFreeTextResponse = '';

  /// Captures every prompt passed to [askFreeText] for assertion (lets
  /// tests inspect what the controller sent to the AI).
  final List<String> askFreeTextPrompts = [];

  @override
  Future<String> askFreeText(
    String prompt, {
    bool isFreeBackground = false,
  }) async {
    askFreeTextPrompts.add(prompt);
    return askFreeTextResponse;
  }

  /// Tests always accept G4 — language-drift detection depends on the
  /// runtime device locale (default 'en' in headless tests), which would
  /// reject Italian fixtures. Override returns max score so the test
  /// suite asserts on content (B4/pedagogy), not on locale-coupled
  /// validation that's covered by `language_signature_test.dart`.
  @override
  Future<double> validateSocraticQuestion({
    required String questionText,
    required String clusterTopic,
    String? clusterRawOcr,
    String? stage,
    String? targetLang,
  }) async =>
      1.0;

  /// Pre-fabricated questions returned by [generateCrossDomainQuestions].
  /// Cross-zone integration tests replace this list to simulate the AI's
  /// validation pass over accepted bridges.
  List<ExamQuestion> crossDomainQuestionsToReturn = const [];

  /// Captures every call to [generateCrossDomainQuestions] (bridges + texts).
  final List<({
    int bridgeCount,
    int clusterTextsCount,
  })> crossDomainCalls = [];

  @override
  Future<List<ExamQuestion>> generateCrossDomainQuestions({
    required List<({
      String sourceLabel,
      String targetLabel,
      String socraticQuestion,
      String sourceClusterId,
      String targetClusterId,
    })> bridges,
    required Map<String, String> clusterTexts,
    String language = 'Italian',
  }) async {
    crossDomainCalls.add((
      bridgeCount: bridges.length,
      clusterTextsCount: clusterTexts.length,
    ));
    return List.of(crossDomainQuestionsToReturn);
  }

  @override
  void dispose() {}
}

/// Wires up [path_provider] so that disk persistence tests can write to a
/// disposable temp directory instead of the real app docs folder. Returns
/// the temp directory; tests should `addTearDown(() => tempDir.delete(...))`.
Directory installTempPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync('fluera_exam_test_');

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
      case 'getApplicationSupportDirectory':
      case 'getTemporaryDirectory':
        return tempDir.path;
    }
    return null;
  });

  return tempDir;
}

/// Build a deterministic exam question used in tests.
ExamQuestion buildTestQuestion({
  required String id,
  String text = 'Domanda di test',
  ExamQuestionType type = ExamQuestionType.multipleChoice,
  String clusterId = 'c1',
  String? sourceText,
  int correctIndex = 0,
}) {
  return ExamQuestion(
    id: id,
    questionText: text,
    type: type,
    correctAnswer: 'A',
    explanation: 'spiegazione',
    sourceClusterId: clusterId,
    // Default to a per-id source text so reviewSchedule keys (derived from
    // the first 3 words of sourceText) stay unique across questions.
    sourceText: sourceText ?? 'src $id $clusterId',
    choices: const ['A: prima', 'B: seconda', 'C: terza', 'D: quarta'],
    correctChoiceIndex: correctIndex,
  );
}
