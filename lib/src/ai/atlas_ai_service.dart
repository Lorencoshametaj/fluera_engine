import 'dart:async' show TimeoutException, unawaited;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'ai_provider.dart';
import 'ai_usage_tracker.dart';
import 'atlas_action.dart';
import 'gemini_client.dart';
import 'noop_ai_usage_tracker.dart';
import '../canvas/ai/exam_session_model.dart';
import '../canvas/ai/ghost_map_model.dart';

/// Google Gemini implementation of [AiProvider].
///
/// Uses the `google_generative_ai` package to communicate with Gemini.
/// Configured with a system prompt that instructs Gemini to act as "Atlas",
/// the spatial AI assistant, and to respond exclusively in structured JSON.
///
/// The API key is passed directly instead of using dotenv, making this
/// work cleanly in both package and app contexts.
class GeminiProvider implements AiProvider {
  // ── Model tiers ────────────────────────────────────────────────────────────
  // Hybrid strategy (launch):
  //   • Flash Lite: canvas actions, chat, socratic, hints — cheap, low-reasoning.
  //   • Flash:      Ghost Map, exam generation, answer evaluation — pedagogical
  //                 quality is the product's core promise; Pro would be overkill
  //                 and shred margins (~20-26× Flash Lite).
  //
  // Both pinned to GA (not preview) — avoids breaking changes mid-launch and
  // already covers our needs. Flash has a 1M-token context window (plenty for
  // long OCR notes). Upgrade to `gemini-3-flash-preview` post-launch only if
  // telemetry proves it meaningfully improves Ghost Map quality.
  static const _modelFlashLite = 'gemini-2.5-flash-lite';
  static const _modelFlash = 'gemini-2.5-flash';

  GeminiClient? _model; // Flash Lite, JSON — canvas actions (askAtlas, hint)
  GeminiClient? _streamModel; // Flash Lite, no JSON — chat, stream, socratic
  GeminiClient? _ghostMapModel; // 🗺️ Flash, JSON, low temp — Ghost Map
  GeminiClient? _examModel; // 🎓 Flash, JSON — exam generation
  GeminiClient? _evaluationModel; // 🎓 Flash, streaming — answer evaluation
  bool _initialized = false;

  /// Direct-mode Gemini API key (baked into the client binary). Null when
  /// the proxy is configured — preferred for production.
  final String? _apiKey;

  /// Proxy mode config. When non-null, all outbound Gemini calls are routed
  /// through the Supabase Edge Function that holds the key server-side.
  /// Takes priority over [_apiKey].
  final GeminiProxyConfig? _proxyConfig;

  /// Usage tracker: metered pre-flight check + post-call reconciliation
  /// using `response.usageMetadata.totalTokenCount`. Defaults to no-op.
  final AiUsageTracker _tracker;

  /// Create a GeminiProvider.
  ///
  /// Either [apiKey] (direct mode, dev / testing) or [proxy] (production,
  /// key lives server-side in the Supabase Edge Function) must be given.
  /// If both are provided, [proxy] wins — security default.
  ///
  /// [tracker] — optional. When provided, every outbound Gemini call is
  /// metered and may throw [AiQuotaExceededException] on pre-flight check.
  /// Defaults to [NoopAiUsageTracker] (never enforces).
  GeminiProvider({
    String? apiKey,
    GeminiProxyConfig? proxy,
    AiUsageTracker? tracker,
  })  : _apiKey = apiKey,
        _proxyConfig = proxy,
        _tracker = tracker ?? NoopAiUsageTracker();

  /// True when the provider is configured to route through the Edge Function.
  bool get usesProxy => _proxyConfig != null;

  // ---------------------------------------------------------------------------
  // Metering
  // ---------------------------------------------------------------------------

  /// Pre-flight balance check + post-call reconciliation for one-shot calls.
  ///
  /// Throws [AiQuotaExceededException] if [estimate] exceeds remaining balance.
  /// Records actual tokens after the call (falls back to [estimate] if the
  /// provider omits `usageMetadata`).
  Future<T> _meter<T>(
    String feature, {
    required int estimate,
    required Future<({T value, FGeminiResponse response})> Function() run,
  }) async {
    // Client-side pre-flight from cached snapshot — saves a round trip if
    // the user is obviously over budget.
    await _tracker.ensureBalance(estimate: estimate);
    try {
      final r = await run();
      final tokens = r.response.usageMetadata?.totalTokenCount ?? estimate;
      if (usesProxy) {
        // Proxy mode: the Edge Function already called consume_ai_tokens
        // before invoking Gemini. The client must NOT re-consume, or we'd
        // double-count. Just refresh the local snapshot so the UI reflects
        // the new balance.
        unawaited(_tracker.refresh());
      } else {
        unawaited(_tracker.recordUsage(tokens, feature));
      }
      return r.value;
    } on GeminiProxyQuotaExceededException {
      // Unify proxy 429 with the engine-wide quota exception so callers
      // don't need to know which code path was taken.
      throw AiQuotaExceededException(
        needed: estimate,
        remaining: 0,
      );
    }
  }

  /// Streaming metering: pre-flight once, capture `usageMetadata` from the
  /// last chunk, reconcile in a `finally` so cancellation still records.
  Stream<String> _meterStream(
    String feature, {
    required int estimate,
    required Stream<FGeminiResponse> Function() start,
  }) async* {
    await _tracker.ensureBalance(estimate: estimate);
    int tokens = estimate; // fallback if the stream ends without metadata
    try {
      try {
        await for (final response in start()) {
          final m = response.usageMetadata?.totalTokenCount;
          if (m != null && m > 0) tokens = m;
          if (response.text != null && response.text!.isNotEmpty) {
            yield response.text!;
          }
        }
      } on GeminiProxyQuotaExceededException {
        throw AiQuotaExceededException(needed: estimate, remaining: 0);
      }
    } finally {
      if (usesProxy) {
        unawaited(_tracker.refresh());
      } else {
        unawaited(_tracker.recordUsage(tokens, feature));
      }
    }
  }

  @override
  String get name => 'Gemini Flash';

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    if (_proxyConfig == null && (_apiKey == null || _apiKey.isEmpty)) {
      throw Exception(
        'Atlas Error: né API Key né Proxy config forniti. '
        'Passa `apiKey` (dev) o `proxy` (prod) al costruttore di GeminiProvider.',
      );
    }

    // Detect device locale once — used by all models for language consistency.
    final langCode = ui.PlatformDispatcher.instance.locale.languageCode;
    const langMap = {'it': 'Italian', 'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German', 'pt': 'Portuguese', 'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese', 'ar': 'Arabic', 'ru': 'Russian'};
    final langName = langMap[langCode] ?? 'English';

    // Canvas actions: structured JSON output, low reasoning demand → Flash Lite.
    _model = _buildClient(
      modelName: _modelFlashLite,
      systemInstruction: _systemPrompt,
      generationConfig: const {'responseMimeType': 'application/json'},
    );

    // 🗺️ Ghost Map — low temperature (0.3) for factual accuracy (A3-02).
    // The reference concept map MUST be correct — creativity is harmful here.
    // Upgraded to Flash: knowledge-gap reasoning is the product's core promise.
    _ghostMapModel = _buildClient(
      modelName: _modelFlash,
      systemInstruction:
          'You are Atlas, an AI tutor embedded in Fluera — a cognitive learning engine. '
          'Your role is to analyze student handwritten notes and identify knowledge gaps. '
          'You must be factually accurate, domain-specific, and pedagogically constructive. '
          'Always respond in $langName. Never invent facts. Keep concepts and explanations concise.',
      generationConfig: const {
        'responseMimeType': 'application/json',
        'temperature': 0.3,
      },
    );

    // 🎓 Exam generation — pedagogically sound questions require real reasoning.
    _examModel = _buildClient(
      modelName: _modelFlash,
      systemInstruction:
          'You are an expert educational assessment designer. You create precise, '
          'pedagogically-sound exam questions from student handwritten notes. '
          'Always respond in $langName. Output strictly valid JSON. No prose.',
      generationConfig: const {
        'responseMimeType': 'application/json',
        'temperature': 0.4,
      },
    );

    // 🎓 Answer evaluation — nuanced grading, streaming output.
    _evaluationModel = _buildClient(
      modelName: _modelFlash,
      systemInstruction:
          'You are a rigorous but encouraging professor evaluating a student answer. '
          'Be precise, concise (1-2 sentences), growth-mindset. Always in $langName.',
    );

    _streamModel = _buildClient(
      modelName: _modelFlashLite,
      systemInstruction:
          'You are ATLAS, an advanced spatial intelligence AI. '
          'Respond directly with the analysis text. No JSON wrapping. '
          'You MUST always respond in $langName.',
    );

    _initialized = true;
  }

  /// Build a GeminiClient pointing at either the direct Gemini API (dev)
  /// or the Supabase Edge Function proxy (prod).
  GeminiClient _buildClient({
    required String modelName,
    required String systemInstruction,
    Map<String, dynamic>? generationConfig,
  }) {
    if (_proxyConfig != null) {
      return ProxiedGeminiClient(
        modelName: modelName,
        systemInstructionText: systemInstruction,
        generationConfig: generationConfig,
        config: _proxyConfig,
      );
    }
    // Direct mode: construct a GenerativeModel from google_generative_ai.
    // generationConfig translates to GenerationConfig fields we use.
    final genConfig = generationConfig == null
        ? null
        : GenerationConfig(
            responseMimeType: generationConfig['responseMimeType'] as String?,
            temperature: (generationConfig['temperature'] as num?)?.toDouble(),
          );
    final model = GenerativeModel(
      model: modelName,
      apiKey: _apiKey!,
      generationConfig: genConfig,
      systemInstruction: Content.system(systemInstruction),
    );
    return DirectGeminiClient(model);
  }

  @override
  Future<AtlasResponse> askAtlas(
    String userPrompt,
    List<Map<String, dynamic>> canvasContext,
  ) async {
    if (!_initialized || _model == null) {
      throw StateError('Atlas non inizializzato. Chiama initialize() prima.');
    }

    // Compute bounding box of all nodes in context
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final node in canvasContext) {
      final pos = node['posizione'] as Map<String, dynamic>?;
      final dim = node['dimensioni'] as Map<String, dynamic>?;
      if (pos != null) {
        final nx = (pos['x'] as num?)?.toDouble() ?? 0;
        final ny = (pos['y'] as num?)?.toDouble() ?? 0;
        final nw = (dim?['larghezza'] as num?)?.toDouble() ?? 100;
        final nh = (dim?['altezza'] as num?)?.toDouble() ?? 50;
        if (nx < minX) minX = nx;
        if (ny < minY) minY = ny;
        if (nx + nw > maxX) maxX = nx + nw;
        if (ny + nh > maxY) maxY = ny + nh;
      }
    }

    final payload = jsonEncode({
      'comando_utente': userPrompt,
      'area_selezione': {
        'x_min': minX.isFinite ? minX.roundToDouble() : 0,
        'y_min': minY.isFinite ? minY.roundToDouble() : 0,
        'x_max': maxX.isFinite ? maxX.roundToDouble() : 800,
        'y_max': maxY.isFinite ? maxY.roundToDouble() : 600,
        'centro_x': minX.isFinite ? ((minX + maxX) / 2).roundToDouble() : 400,
        'centro_y': minY.isFinite ? ((minY + maxY) / 2).roundToDouble() : 300,
      },
      'nodi_nel_contesto': canvasContext,
    });

    try {
      return await _meter<AtlasResponse>(
        'askAtlas',
        estimate: 500,
        run: () async {
          final response = await _model!.generateContent(
            [Content.text(payload)],
            featureTag: 'askAtlas',
            estimate: 500,
          );
          AtlasResponse value = const AtlasResponse.empty();
          if (response.text != null) {
            final rawText = response.text!
                .replaceAll('```json', '')
                .replaceAll('```', '')
                .trim();
            final json = jsonDecode(rawText) as Map<String, dynamic>;
            final actions = AtlasAction.parseAll(json);
            final explanation = json['spiegazione'] as String?
                ?? json['explanation'] as String?;
            value = AtlasResponse(
              actions: actions,
              explanation: explanation,
              rawJson: json,
            );
          }
          return (value: value, response: response);
        },
      );
    } on AiQuotaExceededException {
      rethrow;
    } catch (e) {
      return const AtlasResponse.empty();
    }
  }

  /// 🔶 Free-text prompt — sends raw text, returns raw text.
  /// Used for Socratic questions, breadcrumbs, and other non-structured prompts.
  /// Uses _streamModel (no JSON constraint, no canvas system prompt).
  @override
  Future<String> askFreeText(String prompt) async {
    if (!_initialized || _streamModel == null) {
      throw StateError('Atlas non inizializzato. Chiama initialize() prima.');
    }

    try {
      return await _meter<String>(
        'askFreeText',
        estimate: 500,
        run: () async {
          final response = await _streamModel!.generateContent(
            [Content.text(prompt)],
            featureTag: 'askFreeText',
            estimate: 500,
          );
          final text = response.text?.trim() ?? '';
          debugPrint('🔶 askFreeText response: $text');
          return (value: text, response: response);
        },
      );
    } on AiQuotaExceededException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ askFreeText error: $e');
      return '';
    }
  }

  @override
  Stream<String> askAtlasStream(
    String userPrompt,
    List<Map<String, dynamic>> canvasContext,
  ) async* {
    if (!_initialized || _streamModel == null) {
      throw StateError('Atlas not initialized. Call initialize() first.');
    }

    // Build a simple payload (no JSON wrapping needed for streaming)
    final payload = '$userPrompt\n\nCONTEXT: ${canvasContext.isNotEmpty ? canvasContext.first['contenuto'] ?? '' : ''}';

    yield* _meterStream(
      'askAtlasStream',
      estimate: 1500,
      start: () => _streamModel!.generateContentStream(
        [Content.text(payload)],
        featureTag: 'askAtlasStream',
        estimate: 1500,
      ),
    );
  }

  @override
  Stream<String> askChatStream(
    String conversationHistory,
    String userMessage,
    String canvasContext,
  ) async* {
    if (!_initialized || _streamModel == null) {
      throw StateError('Atlas not initialized. Call initialize() first.');
    }

    final langCode = ui.PlatformDispatcher.instance.locale.languageCode;
    const langMap = {
      'it': 'Italian', 'en': 'English', 'es': 'Spanish',
      'fr': 'French', 'de': 'German', 'pt': 'Portuguese',
      'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese',
    };
    final langName = langMap[langCode] ?? 'English';

    final prompt = '''
You are ATLAS, the student's personal AI tutor and study companion.
You have access to the student's handwritten notes, audio transcripts, and PDF content.
ALWAYS ground your answers in the student's actual notes when possible.
When referencing a specific note, mention it naturally.
Respond in $langName. Be warm, concise, and pedagogically effective.

$canvasContext

$conversationHistory

STUDENT: $userMessage

ATLAS:''';

    yield* _meterStream(
      'askChatStream',
      estimate: 1500,
      start: () => _streamModel!.generateContentStream(
        [Content.text(prompt)],
        featureTag: 'askChatStream',
        estimate: 1500,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🎓 EXAM MODE — Question generation
  // ---------------------------------------------------------------------------

  /// Generate a set of exam questions from [clusterTexts] (clusterId → OCR text).
  ///
  /// Returns an empty list if the AI cannot generate valid questions.
  Future<List<ExamQuestion>> generateExamQuestions(
    Map<String, String> clusterTexts, {
    String language = 'Italian',
    int count = 7,
    String difficulty = 'normale', // 'facile' | 'normale' | 'difficile'
  }) async {
    if (!_initialized || _examModel == null) {
      throw StateError('Atlas non inizializzato. Chiama initialize() prima.');
    }

    // Filter out low-quality/garbled OCR clusters before generating
    final validTexts = <String, String>{};
    for (final entry in clusterTexts.entries) {
      final text = entry.value.trim();
      // Heuristic: must have at least 15 chars and decent ratio of spaces/alphanumeric
      if (text.length < 15) continue;
      final alphaCount = RegExp(r'[a-zA-Z0-9]').allMatches(text).length;
      if (alphaCount / text.length < 0.4) continue; // Too many symbols/garbage
      validTexts[entry.key] = text;
    }

    if (validTexts.isEmpty) {

      return [];
    }

    // Build compact representation — hide internal IDs from the AI
    // Use human-readable labels: "Appunto 1", "Appunto 2", etc.
    final entries = validTexts.entries.take(10).toList();
    final labelToId = <String, String>{}; // "appunto_1" → real cluster ID
    final parts = <String>[];
    for (int i = 0; i < entries.length; i++) {
      final label = 'appunto_${i + 1}';
      labelToId[label] = entries[i].key;
      final text = entries[i].value.trim();
      final truncated = text.length > 300 ? text.substring(0, 300) : text;
      parts.add('[[Appunto ${i + 1}]]\n$truncated');
    }
    final clusterSummary = parts.join('\n\n---\n\n');

    final prompt = '''
<SYSTEM>
You are an expert educational assessment designer specializing in formative evaluation and Bloom's Taxonomy. You create precise, pedagogically-sound exam questions from student handwritten notes.
</SYSTEM>

<TASK>
Generate exactly $count exam questions from the student notes below.
- Output language for ALL text fields (question, answer, explanation, choices): **$language**
- Think step-by-step: (1) identify key concepts in the notes, (2) determine testable knowledge, (3) craft questions at the appropriate Bloom level, (4) verify each question tests CONTENT not META-structure.
</TASK>

<HARD_CONSTRAINTS>
These are non-negotiable rules. Violating ANY of them makes the output invalid:

1. LANGUAGE: Every single text field MUST be written in $language. No exceptions.
2. CONTENT-ONLY: Questions MUST test understanding of the CONCEPTS in the notes. NEVER ask about the notes themselves (their structure, organization, pairing, classification, or purpose).
3. NO GENERIC QUESTIONS: Never ask "What is X?" or "Define X". Instead ask for applications, comparisons, cause-effect, calculations, or scenario analysis.
4. OCR AWARENESS: The text comes from handwriting OCR and may contain garbled/partial words. Extract recognizable keywords, infer the topic, and generate questions about that topic. Ignore unreadable fragments entirely.
5. PLAUSIBLE DISTRACTORS: Multiple choice distractors must be from the same conceptual domain and genuinely plausible. Never use absurd or obviously wrong options.
6. SELF-CONTAINED: Each question must be independently answerable without seeing the original notes.
</HARD_CONSTRAINTS>

<DIFFICULTY level="$difficulty">
Map questions to Bloom's Taxonomy levels:
- "facile" → Remember & Understand: recall definitions, identify correct statements, match terms
- "normale" → Apply & Analyze: solve problems, compare concepts, explain cause-effect relationships  
- "difficile" → Evaluate & Create: critique arguments, predict outcomes in novel scenarios, synthesize across concepts, edge cases
</DIFFICULTY>

<QUESTION_MIX>
Distribute question types proportionally across $count questions:
- ~30% open-ended (tipo: "aperta") — require explanation/reasoning
- ~30% multiple choice with exactly 4 options (tipo: "scelta_multipla") — test discrimination
- ~20% true/false (tipo: "vero_falso") — test precise understanding of statements
- ~20% formula/calculation (tipo: "formula") — ONLY if mathematical content exists in notes; otherwise redistribute to other types
</QUESTION_MIX>

<EXAMPLES>
Given notes: "F = ma. Newton's second law. Force equals mass times acceleration."

✅ GOOD open-ended ($language): "A 5 kg object experiences an acceleration of 3 m/s². Calculate the net force and explain what happens if the mass doubles while force remains constant."
→ WHY GOOD: Tests application (Bloom L3), requires calculation + reasoning, specific to note content.

✅ GOOD multiple choice ($language): "If you double the mass of an object while keeping the applied force constant, the acceleration will: A) Double B) Halve C) Stay the same D) Quadruple"
→ WHY GOOD: Plausible distractors, tests inverse relationship understanding, single correct answer.

✅ GOOD true/false ($language): "According to Newton's second law, an object with zero net force can still be accelerating." (Answer: False)
→ WHY GOOD: Tests precise understanding, common misconception as distractor.

❌ BAD: "What is written in these notes?" → Meta-question about notes, not content.
❌ BAD: "What is force?" → Too generic, not specific to notes.
❌ BAD: "How are these concepts organized?" → Meta-question about structure.
❌ BAD: "The intersection of cluster_stroke_abc and..." → Exposes internal IDs.
</EXAMPLES>

<STUDENT_NOTES>
$clusterSummary
</STUDENT_NOTES>

<OUTPUT_SCHEMA>
Return ONLY valid JSON. No markdown, no explanation, no wrapping. Strictly this schema:
{
  "domande": [
    {
      "id": "q1",
      "tipo": "aperta|scelta_multipla|vero_falso|formula",
      "domanda": "question text in $language — must be self-contained and specific",
      "risposta_corretta": "complete, accurate answer in $language",
      "spiegazione": "1-2 sentence pedagogical explanation of WHY this is the answer, in $language",
      "scelte": ["A: option", "B: option", "C: option", "D: option"],
      "indice_corretto": 0,
      "cluster_id": "appunto_1",
      "testo_sorgente": "exact excerpt from notes this question is based on"
    }
  ]
}
Fields "scelte" and "indice_corretto" are REQUIRED for "scelta_multipla" and "vero_falso", OMIT for other types.
Field "cluster_id" must use the note labels: appunto_1, appunto_2, etc.
</OUTPUT_SCHEMA>''';

    try {
      return await _meter<List<ExamQuestion>>(
        'generateExamQuestions',
        estimate: 2500,
        run: () async {
          final response = await _examModel!.generateContent(
            [Content.text(prompt)],
            featureTag: 'generateExamQuestions',
            estimate: 2500,
          );
          if (response.text == null) {
            return (value: <ExamQuestion>[], response: response);
          }
          final raw = response.text!
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final domande = json['domande'] as List<dynamic>? ?? [];
          final questions = domande
              .whereType<Map<String, dynamic>>()
              .map((d) => _parseExamQuestion(d, clusterTexts, labelToId))
              .where((q) => q != null)
              .cast<ExamQuestion>()
              .toList();
          return (value: questions, response: response);
        },
      );
    } on AiQuotaExceededException {
      rethrow;
    } catch (e) {
      return [];
    }
  }

  ExamQuestion? _parseExamQuestion(
    Map<String, dynamic> d,
    Map<String, String> clusterTexts,
    [Map<String, String>? labelToId]
  ) {
    try {
      final tipoStr = d['tipo'] as String? ?? 'aperta';
      final type = _parseQuestionType(tipoStr);

      final choices = (d['scelte'] as List<dynamic>?)?.cast<String>() ?? [];
      final correctIndex = (d['indice_corretto'] as num?)?.toInt();

      // Resolve label ("appunto_1") → real cluster ID
      final rawId = d['cluster_id'] as String? ?? '';
      final clusterId = labelToId?[rawId] ?? rawId;
      final resolvedId = clusterTexts.containsKey(clusterId) ? clusterId : clusterTexts.keys.first;
      final sourceText = d['testo_sorgente'] as String?
          ?? clusterTexts[resolvedId]?.substring(
                0,
                (clusterTexts[resolvedId]?.length ?? 0).clamp(0, 60),
              )
          ?? '';

      return ExamQuestion(
        id: d['id'] as String? ?? 'q_${DateTime.now().microsecondsSinceEpoch}',
        questionText: d['domanda'] as String? ?? '',
        type: type,
        correctAnswer: d['risposta_corretta'] as String? ?? '',
        explanation: d['spiegazione'] as String? ?? '',
        choices: choices,
        correctChoiceIndex: correctIndex,
        sourceClusterId: resolvedId,
        sourceText: sourceText,
      );
    } catch (e) {

      return null;
    }
  }

  ExamQuestionType _parseQuestionType(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'scelta_multipla': return ExamQuestionType.multipleChoice;
      case 'vero_falso': return ExamQuestionType.trueOrFalse;
      case 'formula': return ExamQuestionType.formulaRecall;
      default: return ExamQuestionType.openEnded;
    }
  }

  // ---------------------------------------------------------------------------
  // 🎓 EXAM MODE — Open-answer evaluation
  // ---------------------------------------------------------------------------

  /// Evaluate a user's open-ended answer and stream back feedback.
  ///
  /// Returns the resolved [ExamAnswerResult] after streaming completes.
  Future<ExamAnswerResult> evaluateOpenAnswer({
    required String question,
    required String correctAnswer,
    required String userAnswer,
    required String language,
    required void Function(String chunk) onTextChunk,
  }) async {
    if (!_initialized || _evaluationModel == null) {
      throw StateError('Atlas non inizializzato.');
    }

    final prompt = '''
<SYSTEM>
You are a rigorous but encouraging university professor. You evaluate a student's answer against the correct answer.
</SYSTEM>

<TASK>
Evaluate the student's answer in $language.
- Is it completely correct? (CORRETTO)
- Is it partially correct but missing key elements? (PARZIALE)
- Is it wrong, fundamentally flawed, or completely missing? (SBAGLIATO)
</TASK>

<CONTEXT>
Question: $question
Correct Answer: $correctAnswer
Student's Answer: ${userAnswer.isEmpty ? "(no answer provided)" : userAnswer}
</CONTEXT>

<CONSTRAINTS>
1. LANGUAGE: The feedback MUST be written in $language.
2. FORMAT: You must strictly follow the output format below. Do not add markdown blocks or conversational filler.
3. CONCISENESS: Provide exactly 1-2 sentences of specific, actionable feedback explaining WHY the answer is correct, partial, or wrong.
4. TONE: Be constructive and adopt a "growth mindset" tone. Emphasize learning from mistakes.
</CONSTRAINTS>

<OUTPUT_FORMAT>
VOTO: [CORRETTO | PARZIALE | SBAGLIATO]
FEEDBACK: [Your 1-2 sentence constructive feedback in $language]
</OUTPUT_FORMAT>
''';

    String fullText = '';
    ExamAnswerResult result = ExamAnswerResult.incorrect;
    int tokens = 800; // fallback estimate

    try {
      await _tracker.ensureBalance(estimate: 800);
      try {
        final stream = _evaluationModel!.generateContentStream(
          [Content.text(prompt)],
          featureTag: 'evaluateOpenAnswer',
          estimate: 800,
        );
        await for (final chunk in stream) {
          final m = chunk.usageMetadata?.totalTokenCount;
          if (m != null && m > 0) tokens = m;
          if (chunk.text != null && chunk.text!.isNotEmpty) {
            fullText += chunk.text!;
            onTextChunk(chunk.text!);
          }
        }

        // Parse VOTO from response
        final voto = RegExp(r'VOTO:\s*(CORRETTO|PARZIALE|SBAGLIATO)', caseSensitive: false)
            .firstMatch(fullText)
            ?.group(1)
            ?.toUpperCase();

        if (voto == 'CORRETTO') result = ExamAnswerResult.correct;
        else if (voto == 'PARZIALE') result = ExamAnswerResult.partial;
        else result = ExamAnswerResult.incorrect;
      } finally {
        if (usesProxy) {
          unawaited(_tracker.refresh());
        } else {
          unawaited(_tracker.recordUsage(tokens, 'evaluateOpenAnswer'));
        }
      }
    } on GeminiProxyQuotaExceededException {
      throw AiQuotaExceededException(needed: 800, remaining: 0);
    } on AiQuotaExceededException {
      rethrow;
    } catch (e) {
      onTextChunk('\n⚠️ Errore nella valutazione. La risposta corretta è: $correctAnswer');
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // 🗺️ GHOST MAP — Knowledge gap analysis
  // ---------------------------------------------------------------------------

  /// Analyze student notes and generate a Ghost Map overlay with missing
  /// concepts, weak spots, and correct assessments.
  ///
  /// [clusterTexts] — clusterId → OCR recognized text.
  /// [clusterTitles] — clusterId → AI-generated semantic title.
  /// [clusterPositions] — clusterId → centroid position on canvas.
  /// [clusterSizes] — clusterId → bounds width/height.
  /// [existingConnections] — current knowledge graph edges.
  Future<GhostMapResult> generateGhostMap({
    required Map<String, String> clusterTexts,
    Map<String, String> clusterTitles = const {},
    Map<String, Map<String, double>> clusterPositions = const {},
    Map<String, Map<String, double>> clusterSizes = const {},
    List<Map<String, String>> existingConnections = const [],
    Map<String, Map<String, dynamic>> socraticContext = const {},
    String? language,
  }) async {
    if (!_initialized || _model == null) {
      throw StateError('Atlas non inizializzato. Chiama initialize() prima.');
    }

    // Resolve language from parameter or device locale
    final langCode = ui.PlatformDispatcher.instance.locale.languageCode;
    const langMap = {'it': 'Italian', 'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German', 'pt': 'Portuguese', 'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese', 'ar': 'Arabic', 'ru': 'Russian'};
    final resolvedLanguage = language ?? (langMap[langCode] ?? 'English');

    // Filter low-quality OCR clusters + sanitize input
    final validTexts = <String, String>{};
    for (final entry in clusterTexts.entries) {
      final text = entry.value.trim();
      if (text.length < 3) continue;
      final alphaCount = RegExp(r'[a-zA-Z0-9]').allMatches(text).length;
      if (alphaCount / text.length < 0.35) continue;
      // 🔒 SEC-01: Sanitize input — strip XML/HTML tags and prompt injection markers
      validTexts[entry.key] = _sanitizeInput(text);
    }

    if (validTexts.isEmpty) {
      return GhostMapResult.empty();
    }

    // Build compact representation with labels (hide internal IDs)
    final entries = validTexts.entries.take(10).toList();
    final labelToId = <String, String>{};
    final idToLabel = <String, String>{};
    final parts = <String>[];

    for (int i = 0; i < entries.length; i++) {
      final label = 'nodo_${i + 1}';
      labelToId[label] = entries[i].key;
      idToLabel[entries[i].key] = label;
      final text = entries[i].value.trim();
      final truncated = text.length > 300 ? text.substring(0, 300) : text;
      final title = clusterTitles[entries[i].key];
      final pos = clusterPositions[entries[i].key];
      final posStr = pos != null
          ? ' (x: ${pos['x']?.round()}, y: ${pos['y']?.round()})'
          : '';

      parts.add('[[Nodo ${i + 1}${title != null ? ": $title" : ""}]]$posStr\n$truncated');
    }
    final notesSummary = parts.join('\n\n---\n\n');

    // Build existing connections in label form
    final connParts = <String>[];
    for (final conn in existingConnections) {
      final src = idToLabel[conn['source'] ?? ''];
      final tgt = idToLabel[conn['target'] ?? ''];
      if (src != null && tgt != null) {
        connParts.add('$src → $tgt${conn['label'] != null ? " (${conn['label']})" : ""}');
      }
    }
    final connSummary = connParts.isEmpty ? 'Nessuna connessione' : connParts.join('\n');

    // 🗺️ P4-21/22/23: Build Passo 3 Socratic context section
    String socraticSection = '';
    if (socraticContext.isNotEmpty) {
      final socraticParts = <String>[];
      for (final entry in entries) {
        final label = idToLabel[entry.key];
        final sData = socraticContext[entry.key];
        if (label == null || sData == null) continue;

        final parts = <String>[];
        final confidence = sData['confidence'] as int?;
        if (confidence != null) parts.add('confidenza: $confidence/5');
        if (sData['isHypercorrection'] == true) parts.add('⚡ IPERCORREZIONE (era sicuro ma sbagliato)');
        if (sData['isBelowZPD'] == true) parts.add('📚 SOTTO ZPD (concetto troppo avanzato)');
        if (sData['wasCorrect'] == true) parts.add('✅ risposta corretta');
        if (sData['wasWrong'] == true) parts.add('❌ risposta errata');
        final breadcrumbs = sData['breadcrumbsUsed'] as int?;
        if (breadcrumbs != null && breadcrumbs > 0) parts.add('indizi usati: $breadcrumbs/3');

        if (parts.isNotEmpty) {
          socraticParts.add('$label: ${parts.join(", ")}');
        }
      }
      if (socraticParts.isNotEmpty) {
        socraticSection = '''

<SOCRATIC_SESSION_DATA>
Dati dalla sessione Socratica (Passo 3) — queste informazioni descrivono le PRESTAZIONI REALI dello studente:
${socraticParts.join('\n')}

Usa questi dati per:
- Nodi con ⚡ IPERCORREZIONE: genera missing/weak nodes con MASSIMA PRIORITÀ (l'errore sicuro ha il maggior potenziale di apprendimento)
- Nodi con 📚 SOTTO ZPD: genera concepts più semplici come prerequisiti, non lo stesso concetto
- Nodi con ❌ + alta confidenza: concentrati su PERCHÉ l'errore, non solo COSA manca
- Nodi con ✅ + alta confidenza: confermali come "corretto" con spiegazione di rinforzo
</SOCRATIC_SESSION_DATA>''';
      }
    }

    // Compute bounding box for positioning hints
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final pos in clusterPositions.values) {
      final x = pos['x'] ?? 0;
      final y = pos['y'] ?? 0;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
    final centerX = minX.isFinite ? ((minX + maxX) / 2).round() : 400;
    final centerY = minY.isFinite ? ((minY + maxY) / 2).round() : 300;

    final prompt = '''
<ROLE>
You are Atlas, a cognitive tutor embedded in a note-taking app for university students. Your expertise: Bloom's Taxonomy, spaced repetition, and concept mapping. You analyze handwritten notes (received via OCR) to find knowledge gaps.
</ROLE>

<CRITICAL_FIRST_STEP>
The input text comes from handwriting OCR and WILL contain errors, garbled fragments, and misspellings. You MUST first reconstruct what the student actually wrote before analyzing.

Example OCR errors you will encounter:
- "SCIGNZ' ATO" → "scienziato"
- "Ii GENE" → "il genio" or "il gene"
- "RELHIVITA" → "relatività"
- "Gravha" → "gravità"
- "NEWT-N" → "Newton"
- "MECANIA" → "meccanica"
- "rFu+1v+A'" → (garbled, skip this fragment)

Strategy: Focus on RECOGNIZABLE KEYWORDS. If you can identify ≥1 meaningful word in a cluster, use it. Skip fragments that are 100% unintelligible.

CRITICAL: In ALL output fields (concetto, spiegazione, valutazione), ALWAYS use the RECONSTRUCTED word, NEVER the raw OCR. Write "gravità" not "Gravha", "Newton" not "NEWT-N".
</CRITICAL_FIRST_STEP>

<TASK>
Analyze the student's reconstructed notes and generate a Ghost Map:

1. **MISSING** ("mancante") — Key concepts the student SHOULD know for this topic but did NOT write. These are the most valuable: they reveal blind spots. Each mancante node MUST have a "nodo_correlato" pointing to the most relevant existing cluster.
2. **WEAK** ("debole") — ONLY when the student wrote something factually WRONG. A single keyword without details is NOT weak. Use sparingly (0-1 nodes max).
3. **CORRECT** ("corretto") — Mark ALL clusters the student mentioned as correct. A single keyword (e.g. "gravità") counts — it shows the student knows the concept exists.

CONSISTENCY RULE: Apply the same standard to ALL clusters. If "energia" written alone is "corretto", then "gravità" written alone MUST also be "corretto". Never treat identical situations differently.

Think step-by-step:
(a) Reconstruct the OCR text into the student's actual intended words
(b) Identify the subject/topic and academic level
(c) List the 5-10 key concepts a complete understanding requires
(d) Compare against what the student wrote
(e) Mark ALL mentioned clusters as corretto, then add 2-5 mancante gaps distributed across different clusters
</TASK>

<CONSTRAINTS>
1. LANGUAGE: The user's device language is $resolvedLanguage. All output fields MUST be written in $resolvedLanguage.
2. CONCISENESS: "concetto" ≤ 8 words. "spiegazione" ≤ 15 words. These appear in small UI bubbles.
3. SPECIFICITY: Missing concepts must be specific to the student's topic. "Newton" + "scienziato" → suggest "Tre leggi del moto", NOT "la scienza è importante".
4. POSITIONING: Do NOT include x/y coordinates. The app computes positions automatically. Just specify the correct "nodo_correlato" for each node. Distribute mancante nodes across DIFFERENT nodo_correlato values.
5. COUNT: 2-5 "mancante" nodes, 0-1 "debole" nodes, mark ALL mentioned clusters as "corretto". Never more than 10 total.
6. CROSS-DOMAIN: If the notes span multiple disciplines, include 1-2 missing connections with "cross_dominio": true.
</CONSTRAINTS>

<STUDENT_NOTES>
$notesSummary
</STUDENT_NOTES>

<EXISTING_CONNECTIONS>
$connSummary
</EXISTING_CONNECTIONS>
$socraticSection

<FEW_SHOT_EXAMPLE>
Input notes: "[[Nodo 1: Fisica]] NEWTON É UN- SCIGNZ' ATO" + "[[Nodo 2]] GRAVITA"

Good output:
{
  "ricostruzione": "Lo studente ha scritto: (1) 'Newton è uno scienziato' (2) 'Gravità'. Argomento: fisica, livello universitario.",
  "valutazione": "Lo studente conosce Newton e la gravità ma non ha specificato leggi o formule.",
  "nodi": [
    {"id": "ghost_1", "stato": "corretto", "concetto": "Newton", "spiegazione": "Correttamente identificato come argomento chiave", "nodo_correlato": "nodo_1"},
    {"id": "ghost_2", "stato": "corretto", "concetto": "Gravità", "spiegazione": "Concetto fondamentale riconosciuto", "nodo_correlato": "nodo_2"},
    {"id": "ghost_3", "stato": "mancante", "concetto": "Tre leggi del moto", "spiegazione": "Fondamento della meccanica newtoniana", "nodo_correlato": "nodo_1"},
    {"id": "ghost_4", "stato": "mancante", "concetto": "Legge di gravitazione universale", "spiegazione": "F = Gm₁m₂/r², scoperta chiave di Newton", "nodo_correlato": "nodo_2"},
    {"id": "ghost_5", "stato": "mancante", "concetto": "Calcolo infinitesimale", "spiegazione": "Newton co-inventò il calcolo con Leibniz", "nodo_correlato": "nodo_1"}
  ],
  "connessioni_mancanti": [
    {"id": "gconn_1", "sorgente": "nodo_1", "destinazione": "nodo_2", "etichetta": "scoprì", "spiegazione": "Newton formulò la legge di gravità", "cross_dominio": false}
  ]
}
</FEW_SHOT_EXAMPLE>

<OUTPUT_FORMAT>
Return ONLY valid JSON. No markdown fences, no explanation outside JSON.
{
  "ricostruzione": "1-2 sentences: what the student ACTUALLY wrote (reconstructed from OCR) + detected topic + academic level",
  "valutazione": "1 sentence overall assessment of the student's understanding",
  "nodi": [
    {
      "id": "ghost_N",
      "stato": "mancante|debole|corretto",
      "concetto": "≤8 words, the concept name",
      "spiegazione": "≤15 words, why it matters",
      "nodo_correlato": "nodo_N or null"
    }
  ],
  "connessioni_mancanti": [
    {
      "id": "gconn_N",
      "sorgente": "nodo_N or ghost_N",
      "destinazione": "nodo_N or ghost_N",
      "etichetta": "≤4 words",
      "spiegazione": "≤10 words",
      "cross_dominio": false
    }
  ]
}
</OUTPUT_FORMAT>''';

    int ghostMapTokens = 3500; // fallback if usageMetadata missing (e.g. timeout)
    try {
      await _tracker.ensureBalance(estimate: 3500);
      // 🗺️ Use dedicated ghost map model (temperature 0.3) with 12s timeout (A3-03)
      final ghostModel = _ghostMapModel ?? _model!;
      final response = await ghostModel
          .generateContent(
            [Content.text(prompt)],
            featureTag: 'generateGhostMap',
            estimate: 3500,
          )
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw TimeoutException(
              'Ghost Map generation exceeded 12s timeout',
            ),
          );
      final m = response.usageMetadata?.totalTokenCount;
      if (m != null && m > 0) ghostMapTokens = m;
      if (usesProxy) {
        unawaited(_tracker.refresh());
      } else {
        unawaited(_tracker.recordUsage(ghostMapTokens, 'generateGhostMap'));
      }
      if (response.text == null) return GhostMapResult.empty();

      final raw = response.text!
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final json = jsonDecode(raw) as Map<String, dynamic>;

      // Log AI's OCR reconstruction for debugging
      final ricostruzione = json['ricostruzione'] as String?;
      final valutazione = json['valutazione'] as String?;
      if (ricostruzione != null) debugPrint('🗺️ Atlas ricostruzione: $ricostruzione');
      if (valutazione != null) debugPrint('🗺️ Atlas valutazione: $valutazione');
      // Debug: log each node's nodo_correlato for positioning diagnosis
      final nodiDebug = json['nodi'] as List<dynamic>? ?? [];
      for (final n in nodiDebug) {
        if (n is Map<String, dynamic>) {
          debugPrint('🗺️ Node: id=${n['id']}, stato=${n['stato']}, '
              'correlato=${n['nodo_correlato']}, concetto=${n['concetto']}');
        }
      }
      debugPrint('🗺️ labelToId: $labelToId');

      // Parse nodes
      final nodiList = json['nodi'] as List<dynamic>? ?? [];
      // 🔒 SEC-04: Hard cap on node count to prevent resource exhaustion
      if (nodiList.length > 15) {
        debugPrint('🗺️ SEC: AI returned ${nodiList.length} nodes, capping at 15');
      }
      final nodes = <GhostNode>[];
      for (final n in nodiList.take(15)) {
        if (n is! Map<String, dynamic>) continue;
        final statusStr = n['stato'] as String? ?? 'mancante';
        final status = statusStr == 'debole'
            ? GhostNodeStatus.weak
            : statusStr == 'corretto'
                ? GhostNodeStatus.correct
                : GhostNodeStatus.missing;

        // Resolve nodo_correlato label → real cluster ID
        final relatedLabelRaw = n['nodo_correlato'] as String?;
        // Normalize: Gemini may return "Nodo 1" instead of "nodo_1"
        final relatedLabel = relatedLabelRaw != null
            ? relatedLabelRaw.toLowerCase().replaceAll(' ', '_')
            : null;
        final relatedClusterId = relatedLabel != null
            ? labelToId[relatedLabel]
            : null;

        // ── DETERMINISTIC POSITIONING (no AI for layout) ──────────────
        // Gemini decides WHAT is missing and WHICH cluster it relates to.
        // The code decides WHERE to render it. 100% deterministic.
        double nodeX;
        double nodeY;

        if (status == GhostNodeStatus.missing) {
          // Placeholder — final position computed in post-pass below
          nodeX = centerX.toDouble();
          nodeY = centerY.toDouble();
        } else if (relatedClusterId != null) {
          // Weak/correct: snap exactly to the related cluster
          final relPos = clusterPositions[relatedClusterId];
          nodeX = relPos?['x'] ?? centerX.toDouble();
          nodeY = relPos?['y'] ?? centerY.toDouble();
        } else {
          nodeX = centerX.toDouble();
          nodeY = centerY.toDouble();
        }

        // 🔒 SEC-03: Clamp string lengths to prevent UI overflow
        final concept = _clampString(n['concetto'] as String? ?? '', 80)!;
        final explanation = _clampString(n['spiegazione'] as String?, 200);

        nodes.add(GhostNode(
          id: n['id'] as String? ?? 'ghost_${nodes.length}',
          concept: concept,
          estimatedPosition: ui.Offset(nodeX, nodeY),
          estimatedSize: status == GhostNodeStatus.missing
              ? const ui.Size(220, 90)
              : (clusterSizes[relatedClusterId] != null
                  ? ui.Size(
                      clusterSizes[relatedClusterId]!['w'] ?? 200,
                      clusterSizes[relatedClusterId]!['h'] ?? 80,
                    )
                  : const ui.Size(200, 80)),
          status: status,
          relatedClusterId: relatedClusterId,
          explanation: explanation,
        ));
      }

      // ── DETERMINISTIC LAYOUT for missing nodes ─────────────────────────
      // Each missing node goes below its related cluster. Nodes sharing a
      // cluster spread horizontally. Zero reliance on Gemini coordinates.
      final missingNodes = nodes.where((n) => n.status == GhostNodeStatus.missing).toList();
      if (missingNodes.isNotEmpty) {
        // Find the actual bottom edge of all clusters
        double lowestBottom = centerY.toDouble();
        for (final entry in clusterPositions.entries) {
          final cy = entry.value['y'] ?? 0.0;
          final ch = clusterSizes[entry.key]?['h'] ?? 80.0;
          final bottom = cy + ch / 2;
          if (bottom > lowestBottom) lowestBottom = bottom;
        }
        // Group by relatedClusterId
        final groups = <String?, List<GhostNode>>{};
        for (final node in missingNodes) {
          groups.putIfAbsent(node.relatedClusterId, () => []).add(node);
        }

        // Position each group below ITS OWN related cluster
        for (final entry in groups.entries) {
          final clusterId = entry.key;
          final group = entry.value;

          // Anchor: below THIS cluster (not the global lowest)
          double anchorX;
          double anchorY;
          if (clusterId != null && clusterPositions.containsKey(clusterId)) {
            anchorX = clusterPositions[clusterId]!['x'] ?? centerX.toDouble();
            final clusterY = clusterPositions[clusterId]!['y'] ?? centerY.toDouble();
            final clusterH = clusterSizes[clusterId]?['h'] ?? 80.0;
            anchorY = clusterY + clusterH / 2 + 120; // below THIS cluster
          } else {
            anchorX = centerX.toDouble();
            anchorY = lowestBottom + 120; // orphans below everything
          }

          // Spread horizontally within group
          const spacing = 350.0;
          final totalSpan = (group.length - 1) * spacing;
          final startX = anchorX - totalSpan / 2;

          for (int i = 0; i < group.length; i++) {
            group[i].estimatedPosition = ui.Offset(
              (startX + i * spacing).clamp(-50000.0, 50000.0),
              anchorY.clamp(-50000.0, 50000.0),
            );
          }
        }

        // Final pass: push apart groups that overlap across different clusters
        final allPositioned = missingNodes.toList()
          ..sort((a, b) => a.estimatedPosition.dx.compareTo(b.estimatedPosition.dx));
        for (int i = 0; i < allPositioned.length - 1; i++) {
          final dx = allPositioned[i + 1].estimatedPosition.dx -
              allPositioned[i].estimatedPosition.dx;
          if (dx < 300) {
            final push = (300 - dx) / 2 + 10;
            allPositioned[i].estimatedPosition =
                allPositioned[i].estimatedPosition.translate(-push, 0);
            allPositioned[i + 1].estimatedPosition =
                allPositioned[i + 1].estimatedPosition.translate(push, 0);
          }
        }
      }

      // Parse connections
      final connList = json['connessioni_mancanti'] as List<dynamic>? ?? [];
      final connections = <GhostConnection>[];
      // 🔒 SEC-04b: Hard cap on connection count
      for (final c in connList.take(20)) {
        if (c is! Map<String, dynamic>) continue;
        // Resolve labels → real IDs (or keep ghost IDs as-is)
        final srcLabel = c['sorgente'] as String? ?? '';
        final tgtLabel = c['destinazione'] as String? ?? '';
        final srcId = labelToId[srcLabel] ?? srcLabel;
        final tgtId = labelToId[tgtLabel] ?? tgtLabel;

        // 🔒 SEC-06: Reject self-loops
        if (srcId == tgtId) continue;

        connections.add(GhostConnection(
          id: c['id'] as String? ?? 'gconn_${connections.length}',
          sourceId: srcId,
          targetId: tgtId,
          label: _clampString(c['etichetta'] as String?, 50),
          explanation: _clampString(c['spiegazione'] as String?, 150),
          isCrossDomain: c['cross_dominio'] == true,
        ));
      }

      return GhostMapResult(
        nodes: nodes,
        connections: connections,
        summary: json['valutazione'] as String? ?? '',
      );
    } on GeminiProxyQuotaExceededException {
      throw AiQuotaExceededException(needed: 3500, remaining: 0);
    } on AiQuotaExceededException {
      rethrow;
    } on TimeoutException {
      debugPrint('🗺️ Ghost Map generation timed out (12s)');
      return GhostMapResult.empty();
    } catch (e) {
      debugPrint('🗺️ Ghost Map generation error: $e');
      return GhostMapResult.empty();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Security helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// 🔒 SEC-01: Sanitize user input before injecting into AI prompt.
  ///
  /// Defenses:
  /// - Strip HTML/XML tags (prevent prompt structure manipulation)
  /// - Remove common prompt injection markers (<ROLE>, <SYSTEM>, etc.)
  /// - Remove control characters (prevent terminal escape sequences)
  /// - Truncate to 500 chars (OCR text shouldn't be longer)
  static String _sanitizeInput(String text) {
    var sanitized = text
        // Strip HTML/XML tags
        .replaceAll(RegExp(r'<[^>]*>'), '')
        // Remove prompt injection markers (case-insensitive)
        .replaceAll(RegExp(
          r'</?(?:ROLE|SYSTEM|TASK|CONSTRAINTS|OUTPUT_FORMAT|CRITICAL|INSTRUCTIONS?|IGNORE)[^>]*>',
          caseSensitive: false,
        ), '')
        // Remove control characters (except newline/tab)
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        .trim();

    // Truncate to 500 chars per cluster
    if (sanitized.length > 500) {
      sanitized = sanitized.substring(0, 500);
    }

    return sanitized;
  }

  /// 🔒 SEC-03: Clamp a string to a maximum length, appending '…' if truncated.
  static String? _clampString(String? text, int maxLength) {
    if (text == null) return null;
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 1)}…';
  }

  @override
  void dispose() {
    _model = null;
    _streamModel = null;
    _ghostMapModel = null;
    _examModel = null;
    _evaluationModel = null;
    _initialized = false;
  }

  // ---------------------------------------------------------------------------
  // System prompt
  // ---------------------------------------------------------------------------

  static const String _systemPrompt = '''
Sei Atlas, assistente AI di un Canvas. Esegui il comando dell'utente sui nodi selezionati. Rispondi SOLO con JSON.

## FORMATO OUTPUT
{"spiegazione": "...", "azioni": [...]}

## AZIONI
- crea_nodo: {"tipo": "crea_nodo", "contenuto": "...", "x": N, "y": N, "colore": "neon_cyan"}
- sposta_nodo: {"tipo": "sposta_nodo", "nodo_id": "ID_ESISTENTE", "x": N, "y": N}
- raggruppa: {"tipo": "raggruppa", "nodi": ["ID1", "ID2"]}

## POSIZIONAMENTO
Nuovi nodi: x = centro_x, y = y_max + 80 (poi +160, +240...). Mai sovrapporre.

## ESEMPI

Comando: "converti la scrittura a mano in testo digitale"
Nodi: [scrittura "CIAO", scrittura "COME STAI"]
✅ CORRETTO: {"azioni": [{"tipo": "crea_nodo", "contenuto": "CIAO COME STAI", "x": 400, "y": 600, "colore": "neon_cyan"}]}
❌ SBAGLIATO: {"azioni": [{"tipo": "crea_nodo", "contenuto": "Analisi della comunicazione testuale...", ...}]}

Comando: "rispondi al contenuto"
Nodi: [scrittura "CIAO"]
✅ CORRETTO: {"azioni": [{"tipo": "crea_nodo", "contenuto": "Ciao! Come posso aiutarti?", "x": 400, "y": 600, "colore": "neon_green"}]}
❌ SBAGLIATO: {"azioni": [{"tipo": "crea_nodo", "contenuto": "Creare un sistema di messaggistica...", ...}]}

Comando: "organizza in mappa"
✅ CORRETTO: sposta_nodo per riordinare i nodi in griglia
❌ SBAGLIATO: crea_nodo con descrizioni dei nodi

## REGOLE
1. Per "converti": COPIA il testo esatto, non riformularlo.
2. Per "rispondi": rispondi come un umano, max 1 frase.
3. Per "organizza/allinea": usa sposta_nodo, NON creare nodi nuovi.
4. MAI creare nodi che DESCRIVONO i nodi ("I nodi contengono...", "Analisi...", "Trasformazione...").
5. ID: usa SOLO gli id dal campo "id" dei nodi_nel_contesto.
6. Max 1-2 azioni. Colori: neon_cyan, neon_green, neon_orange, neon_purple.
''';

  // ─── 🎓 EXAM HINT ─────────────────────────────────────────────────────────

  /// Returns one short clue for [question] without revealing [correctAnswer].
  Future<String> generateHint({
    required String question,
    required String correctAnswer,
    String language = 'Italian',
  }) async {
    if (!_initialized || _model == null) return '💡 Pensa ai concetti fondamentali!';
    try {
      final prompt = '''
<SYSTEM>
You are an expert tutor providing scaffolding hints to a student who is stuck on an exam question.
</SYSTEM>

<CONTEXT>
Question: $question
Correct Answer (DO NOT REVEAL): $correctAnswer
</CONTEXT>

<TASK>
Provide EXACTLY ONE short, conceptual hint in $language.
</TASK>

<CONSTRAINTS>
1. MAX LENGTH: The hint MUST be less than 12 words.
2. NO SPOILERS: Never reveal the actual answer, terminology, or keyword.
3. SCAFFOLDING: Point the student to the underlying concept, principle, or formula.
4. FORMAT: Output ONLY the hint text. No preamble, no quotes.
</CONSTRAINTS>

<EXAMPLES>
✅ GOOD: "Think about the relationship between mass and acceleration."
✅ GOOD: "Remember the unit of measurement used here."
❌ BAD: "The answer is Force." (Reveals answer)
❌ BAD: "Here is a hint: Newton described it as mass times acceleration." (Too long, contains preamble)
</EXAMPLES>
''';
      return await _meter<String>(
        'generateHint',
        estimate: 200,
        run: () async {
          final result = await _model!.generateContent(
            [Content.text(prompt)],
            featureTag: 'generateHint',
            estimate: 200,
          );
          return (
            value: result.text?.trim() ?? '💡 Pensa ai concetti fondamentali!',
            response: result,
          );
        },
      );
    } on AiQuotaExceededException {
      rethrow;
    } catch (_) {
      return '💡 Pensa ai concetti fondamentali!';
    }
  }
}
