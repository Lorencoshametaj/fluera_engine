import 'dart:async' show TimeoutException, unawaited;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_generative_ai/google_generative_ai.dart';

import '../utils/ai_language_preference.dart';
import 'ai_provider.dart';
import 'ai_usage_tracker.dart';
import 'atlas_action.dart';
import 'cluster_action.dart';
import 'gemini_client.dart';
import 'noop_ai_usage_tracker.dart';
import 'telemetry_recorder.dart';
import '../canvas/ai/bloom_classifier.dart';
import '../canvas/ai/exam_session_model.dart';
import 'exam/pedagogy/exam_pedagogy_registry.dart';
import 'exam/pedagogy/exam_phase.dart';
import '../canvas/ai/socratic/socratic_model.dart' show SocraticStage;
import 'socratic/pedagogy/pedagogy_registry.dart';
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
  GeminiClient? _streamModel; // Flash Lite, no JSON — askAtlasStream, askFreeText (canvas analysis, hints)
  GeminiClient? _chatModel; // 💬 Flash Lite, no JSON — "Chiedi a Fluera AI" chat with Socratic hard-rules (system-cached)
  GeminiClient? _clusterModel; // 🧩 Flash Lite, JSON, low temp — Atlas Prompt cluster-level dispatcher (F8)
  GeminiClient? _ghostMapModel; // 🗺️ Flash, JSON, low temp — Ghost Map
  GeminiClient? _examModel; // 🎓 Flash, JSON — exam generation
  GeminiClient? _evaluationModel; // 🎓 Flash, streaming — answer evaluation
  GeminiClient? _socraticFollowUpModel; // 🔶 Flash (upgraded 2026-05-12), JSON — Socratic multi-turn follow-up (system-cached rules, slightly higher temp for variety)

  /// 🌊 Socratic V3.4 ω — per-(stage, lang) cached models for streaming
  /// per-stage parallel generation. Replaces the monolithic
  /// `_socraticModel` post-Sprint-A.9. Lazily populated by
  /// [_socraticStageModelFor]. Key format: `"$stageName::$langCode"`.
  final Map<String, GeminiClient> _stageModels = <String, GeminiClient>{};

  /// 🎓 Atlas Exam V3.4 ω — per-ExamPhase cached models. Each phase has
  /// its own `systemInstruction` (~1.5-3KB) loaded from
  /// `ExamPedagogyRegistry.phasePromptFor(phase, langCode)`. Active only
  /// when [_useExamPedagogyV34] is true (Sprint EX-D wire); otherwise
  /// the legacy `_examModel`/`_evaluationModel` path is used.
  final Map<ExamPhase, GeminiClient> _examPhaseModels =
      <ExamPhase, GeminiClient>{};

  /// 🚦 Sprint EX-D feature flag. When true:
  ///   - `initialize()` builds the per-ExamPhase model cache
  ///   - `generateExamQuestions` / `evaluateOpenAnswer` / `generateHint`
  ///      route through the V2 (lang-native cells) pipeline
  /// When false (default), legacy monolithic prompts in
  /// `_buildExamPrompt`, `_buildHintPrompt`, inline eval prompt are
  /// used unchanged → zero behavior delta until Sprint EX-G flips.
  final bool _useExamPedagogyV34;

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

  /// Product telemetry sink. Every metered call emits an `ai_call` event
  /// with feature + tokens + model + latency. Defaults to no-op.
  final TelemetryRecorder _telemetry;

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
    TelemetryRecorder? telemetry,
    bool useExamPedagogyV34 = false,
  })  : _apiKey = apiKey,
        _proxyConfig = proxy,
        _tracker = tracker ?? NoopAiUsageTracker(),
        _telemetry = telemetry ?? TelemetryRecorder.noop,
        _useExamPedagogyV34 = useExamPedagogyV34;

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
    required GeminiClient client,
    required Future<({T value, FGeminiResponse response})> Function() run,
  }) async {
    // Client-side pre-flight from cached snapshot — saves a round trip if
    // the user is obviously over budget.
    await _tracker.ensureBalance(estimate: estimate, feature: feature);
    final sw = Stopwatch()..start();
    try {
      final r = await run();
      final meta = r.response.usageMetadata;
      final tokens = meta?.totalTokenCount ?? estimate;
      final inputTokens = meta?.promptTokenCount;
      final outputTokens = meta?.candidatesTokenCount;
      sw.stop();
      _telemetry.logEvent('ai_call', properties: {
        'feature': feature,
        'tokens_used': tokens,
        if (inputTokens != null) 'input_tokens': inputTokens,
        if (outputTokens != null) 'output_tokens': outputTokens,
        'model': client.modelName,
        'latency_ms': sw.elapsedMilliseconds,
        'mode': usesProxy ? 'proxy' : 'direct',
      });
      if (usesProxy) {
        // Proxy mode: the Edge Function already called consume_ai_tokens
        // before invoking Gemini. The client must NOT re-consume, or we'd
        // double-count. Just refresh the local snapshot so the UI reflects
        // the new balance.
        unawaited(_tracker.refresh());
      } else {
        unawaited(_tracker.recordUsage(
          tokens,
          feature,
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          model: client.modelName,
        ));
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
    required GeminiClient client,
    required Stream<FGeminiResponse> Function() start,
  }) async* {
    await _tracker.ensureBalance(estimate: estimate, feature: feature);
    int tokens = estimate; // fallback if the stream ends without metadata
    int? inputTokens;
    int? outputTokens;
    final sw = Stopwatch()..start();
    try {
      try {
        await for (final response in start()) {
          final meta = response.usageMetadata;
          final m = meta?.totalTokenCount;
          if (m != null && m > 0) tokens = m;
          if (meta?.promptTokenCount != null) {
            inputTokens = meta!.promptTokenCount;
          }
          if (meta?.candidatesTokenCount != null) {
            outputTokens = meta!.candidatesTokenCount;
          }
          if (response.text != null && response.text!.isNotEmpty) {
            yield response.text!;
          }
        }
      } on GeminiProxyQuotaExceededException {
        throw AiQuotaExceededException(needed: estimate, remaining: 0);
      }
    } finally {
      sw.stop();
      _telemetry.logEvent('ai_call', properties: {
        'feature': feature,
        'tokens_used': tokens,
        if (inputTokens != null) 'input_tokens': inputTokens,
        if (outputTokens != null) 'output_tokens': outputTokens,
        'model': client.modelName,
        'latency_ms': sw.elapsedMilliseconds,
        'mode': usesProxy ? 'proxy' : 'direct',
        'streaming': true,
      });
      if (usesProxy) {
        unawaited(_tracker.refresh());
      } else {
        unawaited(_tracker.recordUsage(
          tokens,
          feature,
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          model: client.modelName,
        ));
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

    // Resolve target language via AiLanguagePreference (user-selected
    // override → device locale fallback). 2026-05-12: introduces
    // `preferredLanguage` setting so cross-language sessions (IT notes
    // on EN device locale) work correctly when the user picks IT.
    final langCode = AiLanguagePreference.code();
    final langName = AiLanguagePreference.displayName();

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
          'Always respond in $langName. Never invent facts. Keep concepts and explanations concise. '
          // Native-discipline terminology rule — always use the local
          // canonical term of $langName for the discipline. IT physics:
          // "forza risultante" not "forza netta"; IT math: "tasso di '
          'variazione" not "tasso di cambiamento". Never produce literal '
          'translations from English or another language — those confuse '
          'students who learned the discipline in $langName.',
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
          'Always respond in $langName. Output strictly valid JSON. No prose. '
          // 🗣️ Native-discipline terminology rule (same as Socratic prompt):
          // use the canonical local term, never a literal English calque.
          // IT physics: "forza risultante" not "forza netta"; "tasso di '
          'variazione" not "tasso di cambiamento". Same principle for every '
          'language × discipline pair.',
      generationConfig: const {
        'responseMimeType': 'application/json',
        // 0.85 (was 0.4) — students reported the same questions every time
        // they re-took an exam on the same notes. With temp=0.4 the model
        // is near-deterministic for identical input → identical output.
        // 0.85 produces meaningful variation (different angles on the same
        // concept, different MC distractors, different example values)
        // while keeping pedagogical coherence. Pushing >0.9 starts to
        // hallucinate concepts not in the notes.
        'temperature': 0.85,
      },
    );

    // 🎓 Answer evaluation — nuanced grading, streaming output.
    _evaluationModel = _buildClient(
      modelName: _modelFlash,
      systemInstruction:
          'You are a rigorous but encouraging professor evaluating a student answer. '
          'Be precise, concise (1-2 sentences), growth-mindset. Always in $langName. '
          // Use native-discipline terminology of $langName (e.g. for Italian '
          'physics: "forza risultante" not "forza netta"). No literal '
          'translations from other languages.',
    );

    _streamModel = _buildClient(
      modelName: _modelFlashLite,
      systemInstruction:
          'You are ATLAS, an advanced spatial intelligence AI. '
          'Respond directly with the analysis text. No JSON wrapping. '
          'You MUST always respond in $langName.',
    );

    // 💬 Chat model: Socratic hard-rules cached in systemInstruction so the
    // "Chiedi a Fluera AI" surface never reverts to ChatGPT-clone behaviour
    // (no summaries, no direct explanations, always end with a generative
    // question). Per-call payload carries only conversation + canvas context.
    // Temperature 0.4 mirrors _socraticModel — low enough for rule adherence,
    // high enough for question variety.
    _chatModel = _buildClient(
      modelName: _modelFlashLite,
      systemInstruction: _chatSystemPrompt(langName),
      generationConfig: const {
        'temperature': 0.4,
      },
    );

    // 🧩 Cluster-level dispatcher (F8). Operates on concept groups, not
    // individual strokes — fixes the "Organize scatters handwriting" bug.
    // Temperature 0.3: actions should be deterministic, not creative.
    _clusterModel = _buildClient(
      modelName: _modelFlashLite,
      systemInstruction: _clusterSystemPrompt(langName),
      generationConfig: const {
        'responseMimeType': 'application/json',
        'temperature': 0.3,
      },
    );

    // 🔶 Socratic batch: rules in systemInstruction (cached by Gemini),
    // per-call input is just the cluster list → ~60% input-token savings.
    // 🚀 2026-05-12 device upgrade: Flash Lite → Flash. V3 pedagogical
    // prompt (stage + misconception + counterfactual + discipline) was
    // at the edge of Flash Lite's reasoning + drifted IT→EN on titles
    // and timed out at 8s on Xiaomi. Flash is 3x cost but counterfactual
    // + misconception injection is the product's core pedagogical value
    // (Hestenes FCI, Butterfield hypercorrection) — €0.10-0.30/month per
    // active user is trivial vs. the quality bump. System instruction
    // cached → per-call cost is OUTPUT-dominated, where the 3x ratio
    // applies to only ~2k tokens.
    // 🌍 Tokenization-tax compensation (Sprint C, §9.6.8 doc) — scale
    // maxOutputTokens by fertility ratio so JA/KO/HI/AR outputs aren't
    // truncated mid-JSON. Applied to the multi-turn follow-up model
    // (Socratic V3.4 ω no longer builds a batch model; per-stage models
    // are lazy-built per (stage, lang) in `_socraticStageModelFor`).
    final socraticFollowUpMaxOut = maxOutTokensForLang(langCode, 400);

    // 🔶 Socratic multi-turn follow-up: separate system instruction so
    // the cached rules don't dilute the "no judgement" contract. Higher
    // temperature than the batch (0.5 vs 0.4) for follow-up variety.
    _socraticFollowUpModel = _buildClient(
      modelName: _modelFlash,
      systemInstruction: _socraticFollowUpSystemPrompt(langName),
      generationConfig: {
        'responseMimeType': 'application/json',
        'temperature': 0.5,
        'maxOutputTokens': socraticFollowUpMaxOut,
      },
    );

    // 🎓 Sprint EX-D 2026-05-14 — per-ExamPhase model cache when the V3.4
    // ω flag is on. Each phase loads its `systemInstruction` from the
    // ExamPedagogyRegistry (production_native IT/EN or ai_bootstrap),
    // and the per-call payload becomes a short vars-only block. The
    // legacy `_examModel` / `_evaluationModel` stay alive in parallel
    // until Sprint EX-G flips the default and cleans up.
    if (_useExamPedagogyV34) {
      for (final phase in ExamPhase.values) {
        final systemPrompt =
            ExamPedagogyRegistry.phasePromptFor(phase, langCode);
        _examPhaseModels[phase] = _buildClient(
          modelName: _modelFlash,
          systemInstruction: systemPrompt,
          generationConfig: switch (phase) {
            // Generation: JSON output, high temp for variation (same as
            // legacy `_examModel`).
            ExamPhase.generation => const {
                'responseMimeType': 'application/json',
                'temperature': 0.85,
              },
            // Evaluation: streaming text, default temp.
            ExamPhase.evaluation => const {},
            // Hint: short text, low temp for predictability.
            ExamPhase.hint => const {'temperature': 0.4},
          },
        );
      }
    }

    _initialized = true;
  }

  /// 💬 Chat hard-rules. The "Chiedi a Fluera AI" surface aligns with the
  /// cognitive theory (Generation Effect §3, Productive Failure T4, Antidote
  /// to Passivity §30): the AI must make the student think, not think for
  /// the student. Cached in systemInstruction so the per-call payload is
  /// just conversation history + canvas context.
  ///
  /// See [teoria_cognitiva_apprendimento.md] §§2-3, T4, §30 and the
  /// Manifesto Fluera (line ~754).
  static String _chatSystemPrompt(String langName) =>
      '''You are Fluera AI, embedded in a cognitive learning canvas.
Your job is to make the student think — never to think for them.

HARD RULES (non-negotiable):
1. NEVER summarize the student's notes. If asked, refuse softly in 1 sentence and offer to start a Ghost Map gap analysis.
2. NEVER explain a concept directly in more than 1 sentence. After 1 sentence of context, ALWAYS ask a question that forces the student to write on canvas.
3. NEVER generate flashcards. If asked, offer to start a Socratic mini-session on the same scope.
4. Default response shape:
   - 1 short statement OR clarifying question (max 1 sentence)
   - 1 generative question that requires a written/drawn answer
5. Cite the student's own clusters by title when context provides them ("vedo che hai già scritto su X, ma cosa lega X a Y?").
6. If the student insists on a direct answer after 2 refusals, provide the smallest possible answer (1-2 sentences) followed by a meta-question ("hai notato che hai dovuto chiedermelo due volte? cosa ti mancava?").

OCR AWARENESS: Cluster texts come from handwriting OCR and may contain garbled tokens. Infer the underlying topic; never quote garbled fragments verbatim.

Tone: warm, growth-mindset, never condescending. Always respond in $langName.''';

  /// 🧩 Cluster-level Atlas Prompt rules. Cached in systemInstruction so
  /// the per-call payload is just the user command + cluster list.
  ///
  /// Cluster mode is the dispatcher used when the AI must reshape the
  /// canvas at the semantic level — moving CONCEPTS around, not the
  /// individual strokes that compose them. Operating on strokes for these
  /// commands explodes handwriting into scattered letters (the bug this
  /// dispatcher exists to fix, 2026-05-12).
  static String _clusterSystemPrompt(String langName) =>
      '''You are Atlas operating in CLUSTER MODE.

You receive a list of clusters — each one is a concept (a group of strokes the student perceives as a single idea). Your job is to issue cluster-level actions that reshape the canvas without ever touching individual strokes.

OUTPUT (JSON only, no prose, no markdown fences):
{
  "spiegazione": "1 short sentence in $langName describing what you did",
  "azioni": [ ... up to 2 actions ... ]
}

ALLOWED ACTIONS (use ONLY these tipos):

1. {"tipo": "sposta_cluster", "cluster_id": "<id from cluster_nel_contesto>", "dx": <number>, "dy": <number>}
2. {"tipo": "allinea_clusters", "cluster_ids": ["<id>", "<id>", ...], "alignment": "left|right|top|bottom|center_h|center_v"}
3. {"tipo": "distribuisci_clusters", "cluster_ids": ["<id>", ...], "asse": "horizontal|vertical"}
4. {"tipo": "colora_cluster", "cluster_id": "<id>", "colore": "neon_cyan|neon_green|neon_orange|neon_purple"}
5. {"tipo": "collega_clusters", "from_id": "<id>", "to_id": "<id>", "etichetta": "<optional short label>"}

HARD RULES (non-negotiable):
- NEVER emit node-level actions (sposta_nodo, crea_nodo, raggruppa, allinea, riassumi). They are forbidden in cluster mode.
- NEVER invent cluster ids. Only use ids that appear verbatim in `cluster_nel_contesto[].id`.
- NEVER split a cluster: its strokes are atomic, treat the whole cluster as one unit.
- Max 2 actions per response — pick the highest-leverage ones for the user's intent.
- Stay inside the supplied viewport: do not propose dx/dy that would push cluster centroids outside `viewport` (x_min/y_min/x_max/y_max).
- Colors must be one of the four neon presets above. No hex.

INTENT GUIDE:
- "organizza" → group clusters by `topic`, place related topics near each other. Use `sposta_cluster` for the few clusters that need the biggest displacement; favor minimum motion.
- "allinea" → pick `allinea_clusters` with the alignment that needs the smallest total motion.
- "distribuisci" → only when ≥3 clusters share a topic or are visually close on one axis.
- "colora" → assign one neon color per distinct `topic`. One `colora_cluster` per cluster.
- "collega" / "connetti" → `collega_clusters` between clusters whose `topic` or `concepts` overlap.

EXAMPLES:

User: "organizza per argomento"
Context: 3 clusters with topics "Newton 1", "Newton 2", "Termodinamica".
CORRECT: [{"tipo":"sposta_cluster","cluster_id":"c_v2_a","dx":0,"dy":0},{"tipo":"sposta_cluster","cluster_id":"c_v2_b","dx":250,"dy":0}]
WRONG: {"tipo":"sposta_nodo", ...}  — forbidden, this is cluster mode.
WRONG: {"tipo":"riassumi", ...}     — never generate content for the student to read.

User: "allinea a sinistra"
CORRECT: [{"tipo":"allinea_clusters","cluster_ids":["c1","c2","c3"],"alignment":"left"}]

User: "spiegami newton"
CORRECT: {"spiegazione":"Non genero spiegazioni — usa \\"Chiedi a Fluera AI\\".","azioni":[]}

Tone of `spiegazione`: warm, concise, $langName.''';

  /// 🛡️ 2026-05-12 — native-language instruction. Far more effective than
  /// English "respond in $langName" for preventing Gemini Flash drift on
  /// scientific names (device repro: "First Law of Thermodynamics"
  /// emitted in EN on an IT-language Socratic session). Prepended to
  /// the Socratic system prompts.
  /// 🌍 Tokenization tax compensator. Languages have different
  /// tokens-per-word ratios in Gemini's SentencePiece tokenizer.
  /// Reference: Hugging Face — "Tokenization is Killing our Multilingual
  /// LLM Dream"; PromptCost.org empirical 2-6× ratios.
  ///
  /// Without scaling, a Socratic batch with `maxOutputTokens: 800` would
  /// produce truncated JSON on HI/JA/KO/AR (output gets cut mid-question,
  /// parse fail). Returns the appropriate ceiling for the target language.
  static int maxOutTokensForLang(String langCode, int baseEnTokens) {
    final ratio = switch (langCode) {
      'en' => 1.0,
      'it' || 'es' || 'pt' || 'fr' || 'de' || 'nl' => 1.3,
      'sv' || 'da' || 'no' || 'fi' || 'pl' => 1.6,
      'ru' || 'ar' => 2.2,
      'ja' || 'ko' || 'zh' => 2.8,
      'hi' => 3.2,
      _ => 1.5,
    };
    return (baseEnTokens * ratio).ceil();
  }

  /// 🎭 Cultural register block — declares formality / directness /
  /// mitigation expected for the target language's tutor-student context.
  /// Research basis: arxiv 2509.11921 (English-Japanese cultural sensitivity),
  /// arxiv 2402.14531 (politeness cross-lingual study).
  ///
  /// Pure-EN dispatcher (the system master prompt is in EN); only the
  /// **target-language-specific examples** are interpolated. The model
  /// receives explicit cues for T/V choice, softener verbs, and
  /// register-degrading anti-patterns research has documented.
  static String culturalRegisterFor(String langName) => switch (langName) {
        'Italian' =>
          '🎭 CULTURAL REGISTER: use "tu" form (student-app context, not formal lei). '
              'Use softeners (potresti, considera, prova a) — never bare imperative "Spiega!". '
              'Allow elaborate syntax (Italian academic register tolerates it).',
        'Spanish' =>
          '🎭 CULTURAL REGISTER: use "tú" form (app context). Use softeners '
              '(podrías, considera, intenta). Avoid "usted" (too cold for app).',
        'French' =>
          '🎭 CULTURAL REGISTER: use "tu" form (peer-style app). For very formal '
              'university contexts, allow vouvoiement. Use softeners (pourrais-tu, '
              'considère). Avoid bare impératif.',
        'German' =>
          '🎭 CULTURAL REGISTER: use "Sie" form for university tutor authority. '
              'Use Konjunktiv II for hypotheticals (könntest du, überlegen Sie). '
              'Avoid bare Imperativ (Erkläre!).',
        'Portuguese' =>
          '🎭 CULTURAL REGISTER: use "você" form (app context). Use softeners. '
              'For PT-PT consider "tu"; for PT-BR "você" is standard.',
        'Japanese' =>
          '🎭 CULTURAL REGISTER: use desu/masu polite-informal base (です/ます). '
              '🚫 NEVER use keigo (尊敬語/謙譲語) — research (arxiv 2402.14531) shows '
              'it DEGRADES output quality on JMMLU. Include softeners '
              '(〜てみましょう, 〜と思いますか, 〜のではないでしょうか). '
              'Sentences naturally end with のでしょうか or と思いますか for Socratic '
              'questions. Avoid bare imperative (〜しろ).',
        'Korean' =>
          '🎭 CULTURAL REGISTER: use 해요체 (haeyo-che, polite informal). NEVER use '
              '합쇼체 (hapsyo-che, formal-supreme — too distant) NOR 반말 (banmal, '
              'informal — disrespectful from AI tutor). Use softeners (〜해 보세요, '
              '〜라고 생각해 보시면). Typical Socratic ending: 어떻게 생각하세요?',
        'Chinese' =>
          '🎭 CULTURAL REGISTER: use neutral-polite register, no overly formal '
              '"敬语". Research (arxiv 2402.14531) shows over-politeness DEGRADES '
              'output on CMMLU. Use 你 (informal "you") in app context. '
              'Standard academic Mandarin (Simplified) unless target is Traditional.',
        'Arabic' =>
          '🎭 CULTURAL REGISTER: use MSA (الفصحى, Modern Standard Arabic) — NEVER '
              'dialect (Levantine/Egyptian/Gulf/Maghrebi). MSA is inherently formal, '
              'no T/V distinction needed. Use third-person neutral. Preserve Arabic '
              'scientific heritage terms (الخوارزمية, الجبر) — they ARE native.',
        'Hindi' =>
          '🎭 CULTURAL REGISTER: use आप (āp, formal) for tutor-student. NEVER use '
              'तू (tū, intimate/disrespectful). तुम (tum) acceptable for peer-style. '
              'Use Devanagari script (देवनागरी) — NOT Roman transliteration (Hinglish). '
              'Use softeners (सोचो, विचार करो, मान लो कि).',
        _ =>
          '🎭 CULTURAL REGISTER: use the academic-friendly register typical of '
              'a $langName-speaking university tutor. Use softening verbs ("could", '
              '"consider", "imagine") rather than bare imperatives. Match formality '
              'to a peer-style learning app, neither overly cold nor too casual.',
      };

  /// 🌍 Language directive — single paragraph written in the TARGET
  /// language itself (rules only, no scenario examples). LLM literature
  /// confirms that instructions written in the target language change
  /// the model's output-language attractor: a pure-EN prompt with
  /// "respond in Italian" tends to leak EN; the same rule written in
  /// Italian reliably anchors the output to Italian.
  ///
  /// Crucially: NO hardcoded scenario/concept examples per language.
  /// Just the abstract rule, translated. This preserves both:
  /// (a) cross-language safety (no IT examples bleeding into ES sessions),
  /// (b) effective language anchoring (rule in target lang).
  static String _nativeLangPin(String langName) => switch (langName) {
        'Italian' =>
          '🌍 RISPONDI ESCLUSIVAMENTE IN ITALIANO. Ogni parola di ogni domanda, '
              'breadcrumb e stem DEVE essere in italiano. Anche i nomi scientifici '
              'e gli scenari classici memorizzati prevalentemente in inglese devono '
              'essere tradotti attivamente in italiano. La prima parola del campo `q` '
              'DEVE essere italiana. Traduci internamente prima di emettere il JSON.',
        'Spanish' =>
          '🌍 RESPONDE EXCLUSIVAMENTE EN ESPAÑOL. Cada palabra de cada pregunta, '
              'breadcrumb y stem DEBE estar en español. Incluso los nombres '
              'científicos y los escenarios clásicos memorizados en inglés deben '
              'traducirse activamente al español. La primera palabra del campo `q` '
              'DEBE estar en español. Traduce internamente antes de emitir el JSON.',
        'French' =>
          '🌍 RÉPONDS EXCLUSIVEMENT EN FRANÇAIS. Chaque mot de chaque question, '
              'breadcrumb et stem DOIT être en français. Même les noms scientifiques '
              'et les scénarios classiques mémorisés en anglais doivent être traduits '
              'activement en français. Le premier mot du champ `q` DOIT être en '
              'français. Traduis intérieurement avant d\'émettre le JSON.',
        'German' =>
          '🌍 ANTWORTE AUSSCHLIESSLICH AUF DEUTSCH. Jedes Wort jeder Frage, '
              'jedes Breadcrumb und jedes Stem MUSS auf Deutsch sein. Auch '
              'wissenschaftliche Namen und klassische Szenarien, die hauptsächlich '
              'auf Englisch gespeichert sind, müssen aktiv ins Deutsche übersetzt '
              'werden. Das erste Wort des `q`-Feldes MUSS auf Deutsch sein. '
              'Übersetze intern, bevor du das JSON ausgibst.',
        'Portuguese' =>
          '🌍 RESPONDA EXCLUSIVAMENTE EM PORTUGUÊS. Cada palavra de cada pergunta, '
              'breadcrumb e stem DEVE estar em português. Mesmo os nomes científicos '
              'e os cenários clássicos memorizados em inglês devem ser traduzidos '
              'ativamente para o português. A primeira palavra do campo `q` DEVE '
              'estar em português. Traduza internamente antes de emitir o JSON.',
        'Japanese' =>
          '🌍 必ず日本語で回答してください。すべての質問、ブレッドクラム、ステムの'
              'すべての単語は日本語でなければなりません。英語で記憶されている科学的'
              '名称や古典的なシナリオも、積極的に日本語に翻訳してください。`q`フィールド'
              'の最初の単語は日本語でなければなりません。JSONを出力する前に内部で翻訳'
              'してください。',
        'Korean' =>
          '🌍 반드시 한국어로만 답변하세요. 모든 질문, 브레드크럼, 스템의 모든 단어는 '
              '한국어여야 합니다. 영어로 기억된 과학 용어와 고전적인 시나리오도 '
              '한국어로 적극 번역하세요. `q` 필드의 첫 단어는 한국어여야 합니다. '
              'JSON을 출력하기 전에 내부적으로 번역하세요.',
        'Chinese' =>
          '🌍 请仅用中文回答。每个问题、面包屑和题干的每个词都必须是中文。即使是主要以英文'
              '记忆的科学名称和经典场景，也必须主动翻译成中文。`q`字段的第一个词必须是中文。'
              '在输出JSON之前请在内部翻译。',
        'Arabic' =>
          '🌍 أجب باللغة العربية حصرياً. كل كلمة في كل سؤال وكل تلميح وكل بداية '
              'يجب أن تكون باللغة العربية. حتى الأسماء العلمية والسيناريوهات '
              'الكلاسيكية المحفوظة بالإنجليزية يجب ترجمتها بنشاط إلى العربية. '
              'الكلمة الأولى من حقل `q` يجب أن تكون بالعربية. ترجم داخلياً قبل '
              'إخراج JSON.',
        _ =>
          // Fallback for other Tier-1 i18n languages (Hindi, Dutch, Swedish,
          // Polish, Turkish, Russian) — EN instruction with explicit target.
          'OUTPUT LANGUAGE = $langName. Every word of every question, '
              'breadcrumb, and stem MUST be in $langName. Translate scientific '
              'names and classic scenarios actively into $langName even when '
              'their English form is more famous. The first word of every `q` '
              'value must be in $langName. Translate internally before emitting '
              'the JSON.',
      };


  /// 🔶 Socratic V2 multi-turn follow-up — system instruction (cached).
  /// CONTRACT: never evaluate the student. Always generate a new question
  /// that extends the dialogue. Two roles: `followUp` (turn 2) and
  /// `aporetic` (turn 3 final).
  static String _socraticFollowUpSystemPrompt(String langName) =>
      '''${_nativeLangPin(langName)}

🎓 You are a Socratic multi-turn tutor. Purpose: provoke continued reflection, NEVER evaluate. Reply in $langName.

HARD RULES (violation = invalid output):
1. NEVER say "exact", "right", "wrong", "correct", "incorrect", or any judgement equivalent in $langName. Translate this rule to the equivalent terms in $langName.
2. NEVER judge whether the student's response is right or wrong.
3. NEVER reveal the correct answer or state what is "true".
4. NEVER use evaluative verbs ("grade", "verify", "check", "correct") — those belong to Exam mode, not Socratic.
5. ALWAYS produce a NEW question that extends the student's thinking.
6. The question must ANCHOR to ONE specific word/concept from the student's sketch — cite it literally in quotes.
7. The question must INVITE reconsideration, not conclusion.
8. Max 2 sentences (≤40 words total).
9. No preamble ("interesting", "good perspective", "I see you wrote…") — go straight to the question.
10. NEVER meta-echo the task ("The prompt asks…", "I was asked to generate…", "Here is the question:", "For cluster X,…"). The `q` field starts DIRECTLY with the question's first word.
11. If the student's sketch is fewer than 2 meaningful words (≥3 chars), or appears to be garbled OCR (isolated tokens like "CA", "OK", "forever" without context), do NOT cite it literally. Instead, anchor to the cluster's THEME and ask a broad depth question on the concept without mentioning the sketch.
12. NATIVE-DISCIPLINE TERMINOLOGY — always use technical terms that $langName-speaking students would find in their discipline's textbooks. Never produce literal translations from English. If you suspect a calque, reformulate with the native canonical term.

TWO FOLLOW-UP MODES:

▶ role="followUp" (turn 2, intermediate):
  Identify ONE word/concept from the sketch. Extend into unexplored territory. Typical: edge case in the same domain, OR connection to a related concept from the original cluster.
  Output shape: {"q": "<question in $langName, anchoring to a quoted token from the sketch>", "isAporetic": false}

▶ role="aporetic" (turn 3, FINAL):
  Expose a PRODUCTIVE CONTRADICTION or edge case the student's mental model does NOT handle. End by inviting the student to "keep it in mind" — do NOT request an answer in the same turn.
  Output shape: {"q": "<question in $langName ending with an invitation to hold the contradiction in mind, not answer it>", "isAporetic": true}

OCR AWARENESS: the student's sketch arrives as OCR of handwriting and may contain artifacts. Infer the real concept, do NOT quote the artifact. Extract meaningful words ≥4 chars.

OUTPUT — strict JSON, nothing else:
{"q": "the next question, in $langName", "isAporetic": false|true}

`isAporetic` must be `true` ONLY when role=aporetic. Never true when role=followUp.''';

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
            // 🌍 Sprint C — propagate `maxOutputTokens` so language-aware
            // budget scaling (`maxOutTokensForLang`) actually takes effect.
            maxOutputTokens: (generationConfig['maxOutputTokens'] as num?)?.toInt(),
            // 🔶 Legge 3 prompt_engineering_cognitive.md — when a typed
            // responseSchema is provided, propagate it to the SDK so the
            // model enforces the JSON structure server-side (vs. our
            // current best-effort schema-in-prompt approach).
            responseSchema: generationConfig['responseSchema'] as Schema?,
          );
    final model = GenerativeModel(
      model: modelName,
      apiKey: _apiKey!,
      generationConfig: genConfig,
      systemInstruction: Content.system(systemInstruction),
    );
    return DirectGeminiClient(model, modelName: modelName);
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
        client: _model!,
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

  /// 🧩 Cluster-level dispatcher (F8). Sends the cluster payload to the
  /// dedicated `_clusterModel` (system prompt already cached) and parses
  /// the response into [ClusterAction]s. The caller passes the executed
  /// actions to `ClusterActionExecutor` from inside a
  /// `LayerController.runAsBatch` so the whole operation lands as a
  /// single undo entry.
  @override
  Future<ClusterAtlasResponse> askAtlasCluster(
    String userPrompt,
    Map<String, dynamic> clusterContext,
  ) async {
    if (!_initialized || _clusterModel == null) {
      throw StateError('Atlas non inizializzato. Chiama initialize() prima.');
    }

    // Payload is built by `CanvasStateExtractor.buildClusterContext`; we
    // forward it verbatim. The system prompt already encodes the schema.
    final payload = jsonEncode(clusterContext);

    try {
      return await _meter<ClusterAtlasResponse>(
        'askAtlasCluster',
        estimate: 600,
        client: _clusterModel!,
        run: () async {
          final response = await _clusterModel!.generateContent(
            [Content.text(payload)],
            featureTag: 'askAtlasCluster',
            estimate: 600,
          );
          ClusterAtlasResponse value = const ClusterAtlasResponse.empty();
          if (response.text != null) {
            final rawText = response.text!
                .replaceAll('```json', '')
                .replaceAll('```', '')
                .trim();
            final json = jsonDecode(rawText) as Map<String, dynamic>;
            final actions = ClusterAction.parseAll(json);
            final explanation = json['spiegazione'] as String?
                ?? json['explanation'] as String?;
            value = ClusterAtlasResponse(
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
      debugPrint('⚠️ askAtlasCluster error: $e');
      return const ClusterAtlasResponse.empty();
    }
  }

  // 🗑️ Sprint A.9 (2026-05-13): the per-stage `_stageModels` map +
  // `streamForStage` replaced the batch monolith path entirely
  // (`_socraticSystemPrompt` + `_socraticModel` + dead schemas deleted).
  // `askSocraticBatch` is retained ONLY as a no-op stub because
  // `AiProvider` is implemented (not extended), so the abstract
  // signature must have a concrete impl here even though the production
  // path no longer calls it. Tests use the `FakeGeminiProvider` override.
  @override
  Future<String> askSocraticBatch(
    String userPrompt, {
    List<String> avoidPrompts = const [],
  }) async {
    debugPrint('⚠️ askSocraticBatch called on GeminiProvider — production '
        'path is V3.4 ω `streamForStage`; this stub returns empty.');
    return '';
  }

  /// 🌊 Socratic V3.4 ω — lazy per-(stage, lang) GenerativeModel builder.
  ///
  /// Each stage has its own dedicated system instruction (small,
  /// lang-native, hand-tuned or AI-bootstrapped). The system instruction
  /// is cached server-side by Gemini after the first call, so subsequent
  /// calls within a session pay only for the per-call payload.
  ///
  /// Output budget is tight (maxOutputTokens=500) because each call
  /// produces ONE question + 3 hints (~250 tokens average) → 100%+ margin
  /// → truncation impossible. Combined with streaming early-stop in
  /// [streamForStage], the truncation problem is structurally eliminated.
  GeminiClient _socraticStageModelFor(String stageName, String langCode) {
    final key = '$stageName::$langCode';
    final cached = _stageModels[key];
    if (cached != null) return cached;

    // Resolve the stage enum from its name; default to anchor on
    // unknown (defensive — controller should always pass valid names).
    final stage = SocraticStage.values.firstWhere(
      (s) => s.name == stageName,
      orElse: () => SocraticStage.anchor,
    );

    final systemPrompt = PedagogyRegistry.stagePedagogyFor(stage, langCode);
    final built = _buildClient(
      modelName: _modelFlash,
      systemInstruction: systemPrompt,
      generationConfig: const {
        'responseMimeType': 'application/json',
        'temperature': 0.4,
        // 🛡️ Sprint E.2 (2026-05-13): bumped 500 → 2000 to match legacy
        // working values (`askSocraticBatch` used 1200-1560). Device
        // repro showed responses truncating at 13-34 chars (~10 tokens)
        // despite the 500 budget — strongly suggests the proxy or
        // model enforces a different cap. 2000 leaves headroom even
        // if the proxy caps below requested values. Per-call output is
        // ~250 tokens (1 q + 3 h), so still tight margin vs 2000.
        'maxOutputTokens': 2000,
      },
    );
    _stageModels[key] = built;
    return built;
  }

  /// 🌊 Socratic V3.4 ω — per-stage generation (single-shot under the hood).
  ///
  /// CONTRACT: yields the full JSON response in ONE chunk. The abstract
  /// API is `Stream<String>` to preserve the controller's per-stage
  /// parallel-stream architecture, but internally we use `generateContent`
  /// (not `generateContentStream`).
  ///
  /// 🛡️ 2026-05-13 device repro: the Edge proxy doesn't reliably stream
  /// JSON-mime responses — the SSE stream closes after the first chunk
  /// (~20-36 chars), truncating the response mid-string. Other streaming
  /// surfaces (`askAtlasStream`, `askChatStream`) work because they DON'T
  /// set `responseMimeType: application/json`. For JSON output we
  /// fall back to single-shot. The controller still fires N parallel
  /// stage calls (failure isolation preserved); perceived latency loses
  /// the streaming win but the wall-clock is the same.
  @override
  Stream<String> streamForStage({
    required String stage,
    required String payload,
    required String langCode,
  }) async* {
    if (!_initialized) {
      throw StateError('Atlas non inizializzato. Chiama initialize() prima.');
    }
    final client = _socraticStageModelFor(stage, langCode);
    // Use the whitelisted `askSocraticBatch` feature tag for proxy
    // compat (Edge proxy maintains a feature-tag whitelist).
    final text = await _meter<String>(
      'askSocraticBatch',
      estimate: 2000,
      client: client,
      run: () async {
        final response = await client.generateContent(
          [Content.text(payload)],
          featureTag: 'askSocraticBatch',
          estimate: 2000,
        );
        // 🔍 Sprint E.1 diagnostic — exact reason the model stopped
        // emitting. Critical to distinguish MAX_TOKENS (proxy/budget
        // cap) vs STOP (model thinks JSON is complete) vs SAFETY
        // (filter triggered).
        debugPrint('🔍 stage=$stage '
            'finishReason=${response.finishReason ?? "null"} '
            'outputTokens=${response.usageMetadata?.candidatesTokenCount ?? "null"} '
            'promptTokens=${response.usageMetadata?.promptTokenCount ?? "null"} '
            'partsCount=${response.partsCount ?? "null"} '
            'textLen=${response.text?.length ?? 0}');
        final body = response.text?.trim() ?? '';
        return (value: body, response: response);
      },
    );
    yield text;
  }

  /// 🧹 OCR cleanup pass — fixes obvious MyScript handwriting errors
  /// (letter confusions like d↔e, joined/split words) without altering
  /// meaning. Used by Socratic + future Atlas Exam OCR pipelines as a
  /// post-processing step. Lives on `_streamModel` (no JSON constraint;
  /// raw text in / raw text out).
  ///
  /// Reuses the existing low-temperature streamModel (cached by Gemini)
  /// so the marginal cost is ~$0.0001 per call. Returns the original
  /// [raw] string on any failure (defensive — no value lost if Gemini
  /// is unavailable).
  ///
  /// [raw] should already be the trimmed MyScript output; multi-line
  /// strokes are joined with spaces by the caller.
  Future<String> cleanOcrItalian(String raw, {String language = 'Italian'}) async {
    if (!_initialized || _streamModel == null) return raw;
    final trimmed = raw.trim();
    // Skip very short text — too short to confidently correct without
    // hallucinating, and "F=ma" / "1ª" should pass through untouched.
    if (trimmed.length < 4) return raw;

    final prompt =
        'Pulisci questa trascrizione OCR di scrittura a mano in $language. '
        'Correggi SOLO errori OCR ovvi:\n'
        '1. Lettere confuse: d/e, m/n, l/i, rn/m, p/t (es. "Riposo" ≠ "Rito"), c/e\n'
        '2. **FUSIONI con particelle/preposizioni — molto comuni in italiano**:\n'
        '   - "LEGGITI NEWTON" → "LEGGI DI NEWTON"\n'
        '   - "ASCAUSA" → "A CAUSA"\n'
        '   - "PRIMOPRINCIPIO" → "PRIMO PRINCIPIO"\n'
        '   - "DELLO/DELLA/DEGLI" attaccato → separa quando sensato\n'
        '3. Parole frammentate: "FISI CA" → "FISICA", "Primalele" → "prima legge"\n'
        '4. Maiuscole rotte: "SECUNDA" → "SECONDA", "TERMODINA MICA" → "TERMODINAMICA"\n'
        '5. Refusi ovvi su parole italiane comuni del lessico scientifico/accademico\n'
        '6. Frammenti OCR che assomigliano vagamente a notazione matematica MA '
        'sono in un contesto di parole italiane → ricostruisci la parola:\n'
        '   - "Corpo a R\' to" → "Corpo a Riposo" (NON "R^{2}", NON "R²")\n'
        '   - "Sper. mento" → "Esperimento" (NON una variabile)\n'
        '   - "f orza" o "f. orza" → "forza" (NON la funzione f)\n\n'
        '**REGOLA CRITICA — anti-LaTeX hallucination:**\n'
        'NON convertire MAI testo italiano ambiguo in formule LaTeX/Unicode '
        '(R^{2}, x_t, β\', etc.) a meno che il contesto circostante sia '
        'CHIARAMENTE matematico (numeri, segni =, operatori, simboli greci '
        'già presenti). In dubbio, ricostruisci la PAROLA italiana o lascia '
        'inalterato — MAI inventare una formula.\n\n'
        'PRESERVA formule SOLO quando già evidenti come tali: F=ma, E=mc², '
        '∫f(x)dx, H₂O, x²+y², pH, ΔG. Una sequenza tipo "R\' to" in mezzo '
        'a "Corpo a … prima legge Newton" NON è una formula, è OCR rotto '
        'di "Riposo".\n\n'
        'NON cambiare il significato. NON aggiungere parole nuove. '
        'NON commentare. NON tradurre. Se il testo è già corretto, '
        'rispondi identico. Output: SOLO il testo pulito.\n\n'
        'Input: $trimmed\nOutput:';

    try {
      return await _meter<String>(
        'cleanOcrItalian',
        estimate: 200,
        client: _streamModel!,
        run: () async {
          final response = await _streamModel!.generateContent(
            [Content.text(prompt)],
            featureTag: 'cleanOcrItalian',
            estimate: 200,
          );
          final out = response.text?.trim() ?? '';
          // Strip any surrounding quotes the model occasionally adds.
          final cleaned = out
              .replaceAll(RegExp(r'^["“«]+|["”»]+$'), '')
              .trim();
          // Sanity check — if the model returned something obviously
          // longer (e.g. it added a commentary), fall back to the raw.
          if (cleaned.isEmpty || cleaned.length > trimmed.length * 2 + 20) {
            debugPrint('🧹 cleanOcrItalian: rejected (empty or too long), '
                'using raw: "${trimmed.substring(0, trimmed.length.clamp(0, 60))}"');
            return (value: raw, response: response);
          }
          if (cleaned != trimmed) {
            debugPrint('🧹 cleanOcrItalian: '
                '"${trimmed.substring(0, trimmed.length.clamp(0, 60))}" → '
                '"${cleaned.substring(0, cleaned.length.clamp(0, 60))}"');
          } else {
            debugPrint('🧹 cleanOcrItalian: passthrough (no changes) for '
                '"${trimmed.substring(0, trimmed.length.clamp(0, 60))}"');
          }
          return (value: cleaned, response: response);
        },
      );
    } on AiQuotaExceededException {
      // Quota exceeded — better to ship the raw OCR than to throw.
      return raw;
    } catch (e) {
      debugPrint('⚠️ cleanOcrItalian error: $e');
      return raw;
    }
  }

  /// 🔶 Socratic V2 multi-turn follow-up.
  ///
  /// Generates the NEXT question in a multi-turn dialogue. NEVER
  /// evaluates the student's response. Returns `(question, isAporetic)`
  /// where `isAporetic == true` means this was the closing turn.
  ///
  /// On any failure (provider not initialized, quota, timeout, parse
  /// error) returns an empty question — caller falls back to the
  /// type-aware template via `SocraticOutputFilter`.
  @override
  Future<({String question, bool isAporetic})> askSocraticFollowUp({
    required String tipo,
    required String tema,
    required String priorQuestion,
    required String sketchOcr,
    required dynamic role,
    String? stage,
  }) async {
    if (!_initialized || _socraticFollowUpModel == null) {
      return (question: '', isAporetic: false);
    }
    final roleName = role is Enum ? role.name : role.toString();
    final isAporeticRole = roleName == 'aporetic';

    // 🎭 S2.A 2026-05-12 — Stage-aware follow-up guidance. When the
    // caller passes the pedagogical stage of the prior question, we
    // tell the model HOW to extend (counterfactual → push to a more
    // extreme edge case; application → vary one scenario parameter;
    // etc.). When stage is null, fall back to the generic prompt.
    final stageGuidance = switch (stage) {
      'counterfactual' =>
        'STAGE FOCUS: counterfactual extension. Presenta un caso limite ANCORA PIÙ estremo del precedente. Es. se la prior chiedeva "F=ma con massa che varia", il follow-up chiede "e in regime relativistico, quando v→c, F=ma resta ancora valida?". Spingi il modello mentale al suo limite operativo.',
      'application' =>
        'STAGE FOCUS: application variation (Bjork variation). CAMBIA UN PARAMETRO dello scenario originale. Es. se la prior chiedeva "astronauta in caduta libera nello spazio", il follow-up chiede "e se l\'astronauta avesse massa doppia, cosa cambia nei tuoi calcoli?". Forza transfer della stessa logica a contesti diversi.',
      'comparative' =>
        'STAGE FOCUS: comparative refinement. Aggiungi UN TERZO concetto vicino agli altri due e chiedi quale dei tre è più simile a quale, secondo quale criterio. Approfondisce la distinzione saliente.',
      'elaboration' =>
        'STAGE FOCUS: elaboration deepening. Chiedi un meccanismo o una conseguenza implicita del modello che lo studente ha appena articolato. NON enunciare il modello — ancorati a una parola del suo schizzo.',
      'anchor' =>
        'STAGE FOCUS: anchor extension (lightweight). Continua il retrieval cued: chiedi un dettaglio aggiuntivo dello stesso concetto, senza alzare la difficoltà.',
      'interleave' =>
        'STAGE FOCUS: interleave bridge. Cita un altro concetto del canvas (se citabile dallo schizzo) e chiedi una connessione strutturale, non semantica superficiale.',
      'metacognitive' =>
        'STAGE FOCUS: metacognitive deepening. Chiedi una self-question prospettica: "Quale aspetto di questo concetto vorrai chiarire la prossima volta?". Non valutativo.',
      _ => null,
    };

    // Per-call prompt: invariant rules live in the cached system
    // instruction; we send only the contextual variables.
    final prompt = '''TIPO DOMANDA: $tipo
TEMA CLUSTER: "$tema"
${stage != null ? 'STAGE: $stage' : ''}

DOMANDA TURNO PRECEDENTE:
"$priorQuestion"

SCHIZZO DELLO STUDENTE (può avere refusi OCR, ignora i token illeggibili):
"$sketchOcr"

role: $roleName
${stageGuidance != null ? '\n$stageGuidance\n' : ''}
Genera SOLO il JSON con la prossima domanda. Cita letteralmente fra virgolette singole una parola dello schizzo come ancora.''';

    try {
      return await _meter<({String question, bool isAporetic})>(
        'socraticFollowUp',
        estimate: 400,
        client: _socraticFollowUpModel!,
        run: () async {
          final response = await _socraticFollowUpModel!.generateContent(
            [Content.text(prompt)],
            featureTag: 'socraticFollowUp',
            estimate: 400,
          );
          final raw = response.text?.trim() ?? '';
          if (raw.isEmpty) {
            return (
              value: (question: '', isAporetic: isAporeticRole),
              response: response,
            );
          }
          try {
            final json = jsonDecode(raw);
            if (json is Map) {
              final q = (json['q'] as String?)?.trim() ?? '';
              final ap = json['isAporetic'] as bool? ?? isAporeticRole;
              return (
                value: (question: q, isAporetic: ap),
                response: response,
              );
            }
          } catch (_) {
            // Fall through — return empty so caller uses fallback.
          }
          return (
            value: (question: '', isAporetic: isAporeticRole),
            response: response,
          );
        },
      );
    } on AiQuotaExceededException {
      return (question: '', isAporetic: isAporeticRole);
    } catch (e) {
      debugPrint('⚠️ askSocraticFollowUp error: $e');
      return (question: '', isAporetic: isAporeticRole);
    }
  }

  /// 🛡️ S3.A 2026-05-12 — G4 chain-of-verification.
  ///
  /// Production implementation uses the same heuristic as the base
  /// abstract class (length + interrogative + topic mention + ?). Future
  /// extension: call a dedicated `_validatorModel` Gemini-Flash-Lite for
  /// LLM-based pedagogical scoring. For now the heuristic is the
  /// cost-free default. Override here only when we want to differentiate
  /// production behavior from the abstract-class default.
  @override
  Future<double> validateSocraticQuestion({
    required String questionText,
    required String clusterTopic,
    String? clusterRawOcr,
    String? stage,
    String? targetLang,
  }) async {
    final text = questionText.trim();
    if (text.isEmpty) return 0.0;
    // 🚨 Language-drift hard reject — uses targetLang when provided.
    if (socraticLanguageDriftsFromSource(
      text,
      clusterRawOcr ?? clusterTopic,
      targetLang: targetLang,
    )) {
      return 0.05;
    }
    int score = 0;
    if (text.length >= 20) score++;
    // Expanded openers (covers ~95% of IT+EN questions). See abstract
    // `AiProvider.validateSocraticQuestion` for the canonical list.
    final hasInterrogative = RegExp(
      r'\b('
      r'cosa|quale|quali|perch[ée]|come|quando|chi|dove|cos[ae]|qual'
      r'|immagina|considera|supponi|pensa|descrivi|spiega|analizza|confronta|se'
      r'|what|why|how|when|which|where|who|whose|whom'
      r'|does|do|did|is|are|was|were|can|could|would|should|will|shall'
      r'|imagine|consider|suppose|think|describe|explain|analyse|analyze|compare'
      r'|if|in what|in which|to what'
      r')\b',
      caseSensitive: false,
    ).hasMatch(text);
    if (hasInterrogative) score++;
    // Concept mention pool: label + raw OCR (2026-05-12 device fix —
    // Atlas labels drift to EN on IT OCR, so label-only matching wrongly
    // rejected good IT questions).
    List<String> wordsFrom(String s) => s
        .toLowerCase()
        .split(RegExp(r'[^a-zàèéìòùA-ZÀ-Ÿ]+'))
        .where((w) => w.length >= 4)
        .toList();
    final topicWords = <String>{
      ...wordsFrom(clusterTopic),
      if (clusterRawOcr != null) ...wordsFrom(clusterRawOcr),
    };
    final lower = text.toLowerCase();
    final mentionsTopic = topicWords.any((w) => lower.contains(w));
    // Cross-language credit (same logic as the abstract default):
    //   (a) source confidently ≠ target, OR
    //   (b) source 'unknown' but question matches target.
    if (mentionsTopic) {
      score++;
    } else if (targetLang != null) {
      final sourceSample = clusterRawOcr ?? clusterTopic;
      final srcLang = detectLanguageSignature(sourceSample);
      final qLang = detectLanguageSignature(text);
      final confidentCrossLang =
          srcLang != 'unknown' && srcLang != targetLang;
      final unknownSourceTargetQ =
          srcLang == 'unknown' && qLang == targetLang;
      if (confidentCrossLang || unknownSourceTargetQ) {
        score++;
      }
    }
    if (text.endsWith('?')) score++;
    return switch (score) {
      4 => 0.75,
      3 => 0.55,
      2 => 0.30,
      _ => 0.10,
    };
  }

  /// 🔶 Free-text prompt — sends raw text, returns raw text.
  /// Used for breadcrumbs and other ad-hoc non-structured prompts.
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
        client: _streamModel!,
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
      client: _streamModel!,
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
    if (!_initialized || _chatModel == null) {
      throw StateError('Atlas not initialized. Call initialize() first.');
    }

    // System prompt (hard-rules + language) is cached in _chatModel's
    // systemInstruction — see _chatSystemPrompt. Per-call payload is just
    // canvas context + conversation history + the new user message.
    final prompt = '''$canvasContext

$conversationHistory

STUDENT: $userMessage

FLUERA AI:''';

    yield* _meterStream(
      'askChatStream',
      estimate: 1500,
      client: _chatModel!,
      start: () => _chatModel!.generateContentStream(
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
  ///
  /// Post-validation (Sprint 3 P1.3 + P3.2): the LLM output is checked for
  /// Bloom-level distribution and question-type distribution. If either is
  /// off-target the call is retried once with a corrective addendum to the
  /// prompt. Two retries max — after that we accept the best batch we have
  /// and emit a `step_11_exam_*_target_missed` telemetry event so the gap
  /// shows up in cohort analytics.
  Future<List<ExamQuestion>> generateExamQuestions(
    Map<String, String> clusterTexts, {
    String language = 'Italian',
    int count = 7,
    String difficulty = 'normale', // 'facile' | 'normale' | 'difficile'
    List<String> avoidPrompts = const [],
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

    // Detect math / formula content in the source notes — drives the
    // type-distribution rule (no formulaRecall expected if no math present).
    final hasFormulaContent = _hasMathContent(validTexts.values);

    // Up to 2 attempts: the first is plain, the second adds a corrective
    // addendum if Bloom or type distribution missed target.
    String correctiveAddendum = '';
    List<ExamQuestion> best = const [];

    for (int attempt = 0; attempt < 2; attempt++) {
      // 🎓 Sprint EX-D: V2 short payload when flag is on (system prompt
      // cached on the model). Legacy monolithic prompt otherwise.
      final prompt = _useExamPedagogyV34
          ? _buildExamPayloadV2(
              count: count,
              difficulty: difficulty,
              clusterSummary: clusterSummary,
              correctiveAddendum: correctiveAddendum,
              avoidPrompts: avoidPrompts,
            )
          : _buildExamPrompt(
              count: count,
              difficulty: difficulty,
              language: language,
              clusterSummary: clusterSummary,
              correctiveAddendum: correctiveAddendum,
              avoidPrompts: avoidPrompts,
            );

      final batch = await _runExamGeneration(prompt, clusterTexts, labelToId);
      if (batch.isEmpty) {
        // Quota / parse failure — bail out, no point retrying.
        return best;
      }

      // Classify Bloom levels in-place + record best-attempt fallback.
      BloomClassifier.classifyAll(batch);
      best = batch;

      final issues = _validateExamBatch(
        batch,
        difficulty: difficulty,
        hasFormulaContent: hasFormulaContent,
      );

      if (issues.isEmpty) break; // good batch — done

      // Last attempt? Accept what we have + log skew.
      if (attempt == 1) {
        for (final reason in issues) {
          _telemetry.logEvent('step_11_exam_target_missed', properties: {
            'reason': reason,
            'difficulty': difficulty,
            'count': count,
          });
        }
        debugPrint(
            '⚠️ generateExamQuestions: retry exhausted, accepting batch with ${issues.length} issue(s): $issues');
        break;
      }

      // Otherwise: build a corrective addendum and retry once.
      correctiveAddendum =
          _buildCorrectiveAddendum(batch, issues, language: language);
      debugPrint('🔁 generateExamQuestions retrying — issues: $issues');
    }

    // Final telemetry: distribution snapshot for cohort analysis.
    final dist = BloomClassifier.distribution(best);
    _telemetry.logEvent('step_11_exam_bloom_distribution', properties: {
      'difficulty': difficulty,
      'count': best.length,
      for (final lvl in BloomLevel.values) lvl.name: dist[lvl] ?? 0,
    });

    return best;
  }

  // ── 🌉 Cross-Domain exam generation (Passo 9) ──────────────────────────────

  /// Generate validation exam questions for accepted cross-zone bridges.
  ///
  /// Unlike [generateExamQuestions] (cluster-scoped, Bloom-balanced) and
  /// unlike Socratic dialogue (open-ended, no judgment), these are
  /// **NON-Socratic, assertive, single-answer** questions designed to
  /// verify whether the student can actually apply the transfer the
  /// bridge implied. One question per bridge. The student gets a
  /// correct / partial / incorrect grade exactly like the regular exam.
  ///
  /// Why NON-Socratic here? See [feedback_socratic_identity_distinct_from_exam]:
  /// Exam validates retention with a closed answer; Socratic explores with
  /// an open question. Mixing the modes would either erode Socratic's
  /// non-judging stance or weaken Exam's transfer-learning measurement.
  ///
  /// [bridges] — pairs of `(sourceLabel, targetLabel, socraticQuestion)`
  /// taken from `CrossZoneBridgeController.recentAcceptedBridges()`.
  /// [clusterTexts] — `clusterId → OCR text` for the bridge endpoints
  /// (used to ground the AI in actual student content, not generic prose).
  /// [language] — output language; defaults to Italian to match the app.
  ///
  /// Returns `ExamQuestion`s with `isCrossDomain: true` so the exam UI can
  /// badge them and the telemetry can bucket their correct-rate separately.
  /// Returns an empty list if the AI is not initialized or no bridges qualify.
  Future<List<ExamQuestion>> generateCrossDomainQuestions({
    required List<({String sourceLabel, String targetLabel, String socraticQuestion, String sourceClusterId, String targetClusterId})>
        bridges,
    required Map<String, String> clusterTexts,
    String language = 'Italian',
  }) async {
    if (!_initialized || _examModel == null) {
      return [];
    }
    if (bridges.isEmpty) return [];

    final bridgeBlocks = <String>[];
    for (int i = 0; i < bridges.length && i < 5; i++) {
      final b = bridges[i];
      final srcText = clusterTexts[b.sourceClusterId]?.trim() ?? '';
      final tgtText = clusterTexts[b.targetClusterId]?.trim() ?? '';
      if (srcText.length < 10 || tgtText.length < 10) continue;
      final srcSnip =
          srcText.length > 200 ? srcText.substring(0, 200) : srcText;
      final tgtSnip =
          tgtText.length > 200 ? tgtText.substring(0, 200) : tgtText;
      bridgeBlocks.add('''
[[Bridge ${i + 1}]]
  source: ${b.sourceLabel}
    text: $srcSnip
  target: ${b.targetLabel}
    text: $tgtSnip
  socratic prompt that was accepted: ${b.socraticQuestion}
''');
    }
    if (bridgeBlocks.isEmpty) return [];

    final prompt = '''
<ROLE>
You are Atlas, an exam author. The student previously accepted N cross-domain
"bridges" (links between concepts from different knowledge areas) framed as
Socratic questions. Your job NOW is the opposite of Socratic — generate
**validation questions** that test whether the student can actually apply
the transfer in a new context.
</ROLE>

<HARD_CONSTRAINTS>
1. NON-SOCRATIC: each question must have a SINGLE correct answer.
   No "what do you think?", no "explore the analogy", no open-ended prompts.
2. ONE QUESTION PER BRIDGE: generate exactly one question per [[Bridge X]]
   block, in the same order.
3. APPLICATION, not recall: the question must require the student to apply
   the bridge concept to a slightly new scenario, not just restate it.
4. LANGUAGE: $language.
5. SHORT: ≤ 25 words per question.
</HARD_CONSTRAINTS>

<BRIDGES>
${bridgeBlocks.join('\n---\n')}
</BRIDGES>

<OUTPUT_FORMAT>
Return ONLY a JSON array. No markdown fences, no commentary.
[
  {
    "question": "your validation question",
    "correctAnswer": "the single correct answer (1-2 sentences)",
    "explanation": "why this is correct + how it uses the bridge",
    "bridgeIndex": 1
  }
]
</OUTPUT_FORMAT>
''';

    final sw = Stopwatch()..start();
    String raw = '';
    try {
      raw = await askFreeText(prompt);
    } catch (e) {
      debugPrint('🌉 [exam-cross-domain] AI error: $e');
      return [];
    } finally {
      sw.stop();
    }

    if (raw.isEmpty) return [];

    // Robust JSON extraction (markdown fence + bracket scan).
    final trimmed = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    final start = trimmed.indexOf('[');
    final end = trimmed.lastIndexOf(']');
    if (start < 0 || end <= start) return [];
    final jsonStr = trimmed.substring(start, end + 1);

    List<dynamic> items;
    try {
      items = jsonDecode(jsonStr) as List<dynamic>;
    } catch (_) {
      return [];
    }

    final out = <ExamQuestion>[];
    for (final item in items) {
      try {
        if (item is! Map<String, dynamic>) continue;
        final q = (item['question'] as String?)?.trim();
        final a = (item['correctAnswer'] as String?)?.trim();
        final exp = (item['explanation'] as String?)?.trim();
        final idx = (item['bridgeIndex'] as num?)?.toInt() ?? 0;
        if (q == null || q.isEmpty || a == null || a.isEmpty) continue;
        if (idx < 1 || idx > bridges.length) continue;
        final bridge = bridges[idx - 1];
        out.add(ExamQuestion(
          id: 'crossdomain_${DateTime.now().millisecondsSinceEpoch}_${idx - 1}',
          questionText: q,
          type: ExamQuestionType.openEnded,
          correctAnswer: a,
          explanation: exp ?? '',
          sourceClusterId: bridge.sourceClusterId,
          sourceText: clusterTexts[bridge.sourceClusterId] ?? '',
          isCrossDomain: true,
        ));
      } catch (e) {
        debugPrint('🌉 [exam-cross-domain] item parse error: $e');
      }
    }

    debugPrint(
        '🌉 [exam-cross-domain] generated ${out.length}/${bridges.length} validation questions in ${sw.elapsedMilliseconds}ms');
    return out;
  }

  // ── Exam generation helpers (Sprint 3) ─────────────────────────────────────

  /// True if any of the source notes look mathematical — the
  /// formulaRecall slot only makes sense when the cluster contains math.
  /// Heuristic: a few common math characters or a digit-equation pattern.
  bool _hasMathContent(Iterable<String> texts) {
    final mathChars = RegExp(r'[=±∫∑√≥≤≠∂Δπθμ°]');
    final equationLike = RegExp(r'[A-Za-z]\s*=\s*[A-Za-z0-9]');
    for (final t in texts) {
      if (mathChars.hasMatch(t) || equationLike.hasMatch(t)) return true;
    }
    return false;
  }

  /// Validate Bloom + type distributions of a generated batch.
  /// Returns a list of issue strings, empty when the batch is good.
  List<String> _validateExamBatch(
    List<ExamQuestion> batch, {
    required String difficulty,
    required bool hasFormulaContent,
  }) {
    final issues = <String>[];
    if (batch.isEmpty) return issues;

    // ── Bloom check ─────────────────────────────────────────────────
    // facile → no constraint (Remember/Understand acceptable).
    // normale → ≥40% Apply or higher.
    // difficile → ≥40% Analyze or higher.
    if (difficulty == 'normale') {
      if (BloomClassifier.deepRatio(batch) < 0.4) {
        issues.add('bloom_apply_below_40_normale');
      }
    } else if (difficulty == 'difficile') {
      if (BloomClassifier.higherOrderRatio(batch) < 0.4) {
        issues.add('bloom_analyze_below_40_difficile');
      }
    }

    // ── Type distribution check ─────────────────────────────────────
    // Skip enforcement on tiny batches (< 4 questions) — there's no
    // meaningful distribution to enforce.
    if (batch.length >= 4) {
      final typeCounts = <ExamQuestionType, int>{};
      for (final q in batch) {
        typeCounts[q.type] = (typeCounts[q.type] ?? 0) + 1;
      }

      // No single type exceeds 60% of the batch.
      for (final entry in typeCounts.entries) {
        if (entry.value / batch.length > 0.60) {
          issues.add('type_${entry.key.name}_dominates');
        }
      }

      // Each non-formula type must appear at least once.
      const requiredTypes = [
        ExamQuestionType.openEnded,
        ExamQuestionType.multipleChoice,
        ExamQuestionType.trueOrFalse,
      ];
      for (final t in requiredTypes) {
        if ((typeCounts[t] ?? 0) == 0) {
          issues.add('type_${t.name}_missing');
        }
      }

      // formulaRecall must appear iff the source has math content.
      final formulaCount = typeCounts[ExamQuestionType.formulaRecall] ?? 0;
      if (hasFormulaContent && formulaCount == 0) {
        issues.add('type_formulaRecall_missing_with_math');
      }
      if (!hasFormulaContent && formulaCount > 0) {
        issues.add('type_formulaRecall_present_without_math');
      }
    }

    return issues;
  }

  /// Build a small corrective fragment to append to the prompt for the
  /// retry. We tell the LLM what went wrong in concrete numbers — it
  /// is much more reliable than abstract instructions.
  String _buildCorrectiveAddendum(
    List<ExamQuestion> previous,
    List<String> issues, {
    required String language,
  }) {
    final dist = BloomClassifier.distribution(previous);
    final typeCounts = <ExamQuestionType, int>{};
    for (final q in previous) {
      typeCounts[q.type] = (typeCounts[q.type] ?? 0) + 1;
    }
    final bloomLine = dist.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key.name}=${e.value}')
        .join(', ');
    final typeLine = typeCounts.entries
        .map((e) => '${e.key.name}=${e.value}')
        .join(', ');
    return '''

<RETRY_CORRECTION>
The previous attempt was unbalanced and you are being asked to regenerate.
- Bloom distribution was: $bloomLine
- Question types were: $typeLine
- Issues detected: ${issues.join(', ')}

Re-distribute the batch:
- Hit the BLOOM target for the requested DIFFICULTY (Apply+ for "normale", Analyze+ for "difficile").
- Honor the QUESTION_MIX section: every non-formula type at least once, no type above 60% of the batch.
- formulaRecall ONLY when the source notes contain math content.
Output language remains $language.
</RETRY_CORRECTION>''';
  }

  /// Run a single Gemini call with the given prompt and parse the JSON.
  /// Pulled out so the retry loop can reuse it with a corrective addendum.
  ///
  /// 🎓 Sprint EX-D: when [_useExamPedagogyV34] is on, routes through the
  /// per-phase cached model with a short payload. When off, uses the
  /// legacy `_examModel` with the full monolithic prompt — same behavior
  /// as before this sprint.
  Future<List<ExamQuestion>> _runExamGeneration(
    String prompt,
    Map<String, String> clusterTexts,
    Map<String, String> labelToId,
  ) async {
    final client = _useExamPedagogyV34
        ? _examPhaseModels[ExamPhase.generation]!
        : _examModel!;
    try {
      return await _meter<List<ExamQuestion>>(
        'generateExamQuestions',
        estimate: 2500,
        client: client,
        run: () async {
          final response = await client.generateContent(
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

  /// Build the exam prompt. Optionally appends a [correctiveAddendum]
  /// after the schema for retries (Sprint 3).
  String _buildExamPrompt({
    required int count,
    required String difficulty,
    required String language,
    required String clusterSummary,
    String correctiveAddendum = '',
    List<String> avoidPrompts = const [],
  }) {
    // Variation seed — forces the model to produce a different angle each
    // call. Without this, identical input + low temperature gave students
    // near-identical re-runs (same questions in slightly different forms).
    // The seed is just a timestamp slice — meaningless, but it perturbs
    // the prompt enough to escape the cache + nudges the sampler.
    final seed = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    // Recent question texts to avoid — populated by the controller from
    // its in-memory ring buffer. Truncated to keep prompt token cost sane.
    final avoidSection = avoidPrompts.isEmpty
        ? ''
        : '''

<AVOID_REPETITION>
The student has recently been asked the following questions on these notes.
Do NOT repeat them. Do NOT paraphrase them. Pick genuinely fresh angles
on the same concepts (different examples, different scenarios, different
distractors, different sub-aspects).
${[
            for (var i = 0; i < avoidPrompts.length && i < 30; i++)
              '${i + 1}. ${avoidPrompts[i].length > 120 ? '${avoidPrompts[i].substring(0, 120)}…' : avoidPrompts[i]}'
          ].join('\n')}
</AVOID_REPETITION>
''';
    return '''
<SYSTEM>
You are an expert educational assessment designer specializing in formative evaluation and Bloom's Taxonomy. You create precise, pedagogically-sound exam questions from student handwritten notes.
</SYSTEM>

<TASK>
Generate exactly $count exam questions from the student notes below.
- Output language for ALL text fields (question, answer, explanation, choices): **$language**
- Think step-by-step: (1) identify key concepts in the notes, (2) determine testable knowledge, (3) craft questions at the appropriate Bloom level, (4) verify each question tests CONTENT not META-structure.
- VARIATION SESSION ID: $seed — for THIS specific session, deliberately
  pick a DIFFERENT angle on each concept than you would by default. Vary:
  numerical examples, scenario contexts, distractor wording, the order
  of multi-step reasoning. Two students with the same notes should get
  different exams; the same student re-running the exam should get
  meaningfully fresh questions, not paraphrases of the previous batch.
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
Map questions to Bloom's Taxonomy. EACH LEVEL HAS A NUMERIC TARGET that you MUST hit — failing the target produces an invalid output.

For "facile" (Remember + Understand): no minimum. Use verbs like *recall, define, list, identify, describe, explain, summarize, match, recognize*.

For "normale" (Apply + Analyze): **AT LEAST 40% of the $count questions MUST be Apply or higher**. That means at least ${(count * 0.4).ceil()} of $count questions must use verbs like *calculate, apply, solve given, predict, demonstrate, classify, compare, contrast, distinguish, categorize, derive, illustrate*. The remaining can be Understand.

For "difficile" (Evaluate + Create): **AT LEAST 40% of the $count questions MUST be Analyze or higher**. That means at least ${(count * 0.4).ceil()} of $count questions must use verbs like *evaluate, critique, justify, argue, assess, design, construct, generate, propose, formulate, synthesize*. The rest can be Apply.

Current target: $difficulty → minimum ${(count * 0.4).ceil()}/$count questions at the deeper-than-Understand level. Count them mentally before returning.
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
</STUDENT_NOTES>$avoidSection

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
</OUTPUT_SCHEMA>$correctiveAddendum''';
  }

  /// 🎓 Sprint EX-D V2 — per-call payload for the cached
  /// `_examPhaseModels[ExamPhase.generation]`. System prompt
  /// (Bloom rubric, anti-patterns, OUTPUT_SCHEMA) lives in
  /// `systemInstruction`, cached server-side. Per-call payload =
  /// vars only → ~80% input-token reduction vs `_buildExamPrompt`.
  String _buildExamPayloadV2({
    required int count,
    required String difficulty,
    required String clusterSummary,
    String correctiveAddendum = '',
    List<String> avoidPrompts = const [],
  }) {
    final seed = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final minAtLevel = (count * 0.4).ceil();
    final avoidSection = avoidPrompts.isEmpty
        ? ''
        : '\n\n<AVOID_REPETITION>\nDo NOT repeat or paraphrase these recent questions:\n${[
            for (var i = 0; i < avoidPrompts.length && i < 30; i++)
              '${i + 1}. ${avoidPrompts[i].length > 120 ? '${avoidPrompts[i].substring(0, 120)}…' : avoidPrompts[i]}'
          ].join('\n')}\n</AVOID_REPETITION>';
    return '''
<EXAM_PARAMS>
count: $count
difficulty: $difficulty
min_at_target_bloom_level: $minAtLevel / $count
seed: $seed
</EXAM_PARAMS>

<STUDENT_NOTES>
$clusterSummary
</STUDENT_NOTES>$avoidSection$correctiveAddendum''';
  }

  /// 🎓 Sprint EX-D V2 — per-call payload for
  /// `_examPhaseModels[ExamPhase.evaluation]`. System prompt
  /// (rubric, anti-patterns, output format) is cached. Payload =
  /// the 3 vars: question, correct answer, student answer.
  String _buildEvalPayloadV2({
    required String question,
    required String correctAnswer,
    required String userAnswer,
  }) {
    return '''
<EVAL_CONTEXT>
Question: $question
Correct Answer: $correctAnswer
Student's Answer: ${userAnswer.isEmpty ? "(no answer provided)" : userAnswer}
</EVAL_CONTEXT>''';
  }

  /// 🎓 Sprint EX-D V2 — per-call payload for
  /// `_examPhaseModels[ExamPhase.hint]`. System prompt (≤12 words,
  /// no preamble, no reveal) is cached. Payload = question + answer.
  String _buildHintPayloadV2({
    required String question,
    required String correctAnswer,
  }) {
    return '''
Question: $question
Correct answer (DO NOT REVEAL): $correctAnswer''';
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

    // 🎓 Sprint EX-D: V2 short payload when flag is on (rubric +
    // anti-patterns + output format are cached in the model's
    // systemInstruction). Legacy monolithic prompt otherwise.
    final prompt = _useExamPedagogyV34
        ? _buildEvalPayloadV2(
            question: question,
            correctAnswer: correctAnswer,
            userAnswer: userAnswer,
          )
        : '''
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

    final evalClient = _useExamPedagogyV34
        ? _examPhaseModels[ExamPhase.evaluation]!
        : _evaluationModel!;

    String fullText = '';
    ExamAnswerResult result = ExamAnswerResult.incorrect;
    int tokens = 800; // fallback estimate
    int? inputTokens;
    int? outputTokens;

    try {
      await _tracker.ensureBalance(estimate: 800, feature: 'evaluateOpenAnswer');
      try {
        final stream = evalClient.generateContentStream(
          [Content.text(prompt)],
          featureTag: 'evaluateOpenAnswer',
          estimate: 800,
        );
        await for (final chunk in stream) {
          final meta = chunk.usageMetadata;
          final m = meta?.totalTokenCount;
          if (m != null && m > 0) tokens = m;
          if (meta?.promptTokenCount != null) inputTokens = meta!.promptTokenCount;
          if (meta?.candidatesTokenCount != null) outputTokens = meta!.candidatesTokenCount;
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
          unawaited(_tracker.recordUsage(
            tokens,
            'evaluateOpenAnswer',
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            model: _evaluationModel!.modelName,
          ));
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

    // Resolve language from parameter or user/device preference.
    final resolvedLanguage = language ?? AiLanguagePreference.displayName();

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

1. **MISSING** ("mancante") — Key concepts the student has not yet placed in their canvas. These reveal where additional fragments will integrate the existing knowledge — not "blind spots", but bridges to build. Each mancante node MUST have a "nodo_correlato" pointing to the most relevant existing cluster.
2. **WEAK** ("debole") — ONLY when the student wrote a fragment used in the wrong context (Knowledge in Pieces / diSessa). A single keyword without details is NOT weak. Use sparingly (0-1 nodes max).
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
      await _tracker.ensureBalance(estimate: 3500, feature: 'generateGhostMap');
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
      final meta = response.usageMetadata;
      final m = meta?.totalTokenCount;
      if (m != null && m > 0) ghostMapTokens = m;
      if (usesProxy) {
        unawaited(_tracker.refresh());
      } else {
        unawaited(_tracker.recordUsage(
          ghostMapTokens,
          'generateGhostMap',
          inputTokens: meta?.promptTokenCount,
          outputTokens: meta?.candidatesTokenCount,
          model: ghostModel.modelName,
        ));
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
    _chatModel = null;
    _clusterModel = null;
    _ghostMapModel = null;
    _examModel = null;
    _evaluationModel = null;
    _socraticFollowUpModel = null;
    // V3.4 ω: per-stage models cache cleared.
    _stageModels.clear();
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

  /// Localized fallback shown when the AI is unavailable or returns empty.
  /// Same string is also baked into the controller's catch-all path so the
  /// student always sees encouraging copy.
  static String _hintFallback(String language) {
    switch (language) {
      case 'Italian':
        return '💡 Pensa ai concetti fondamentali!';
      case 'Spanish':
        return '💡 ¡Piensa en los conceptos fundamentales!';
      case 'French':
        return '💡 Pense aux concepts fondamentaux !';
      case 'German':
        return '💡 Denk an die Grundkonzepte!';
      case 'Portuguese':
        return '💡 Pensa nos conceitos fundamentais!';
      default:
        return '💡 Think about the fundamental concepts!';
    }
  }

  /// Build a hint prompt entirely in the target language. The earlier
  /// English-prompt-with-Italian-output combo caused Gemini to "explain
  /// the instructions" in Italian instead of executing them — surfacing
  /// meta-commentary in the hint bubble. A native-language prompt with
  /// a terminator line ("INDIZIO:") that the model fills in directly
  /// is much more reliable.
  static String _buildHintPrompt({
    required String question,
    required String correctAnswer,
    required String language,
  }) {
    switch (language) {
      case 'Italian':
        return '''Sei un tutor che dà UN SOLO indizio breve a uno studente bloccato.

REGOLE (rispetta TUTTE):
- Rispondi SOLO in italiano.
- Massimo 12 parole.
- NON rivelare la risposta, i termini chiave, né le formule esatte.
- Punta al concetto o principio sottostante, non alla soluzione.
- NIENTE preamboli ("Ecco", "Indizio:", "Suggerimento:") né virgolette.
- NIENTE meta-commento sulle istruzioni.

Risposta corretta (NON RIVELARE): $correctAnswer
Domanda: $question

INDIZIO:''';
      case 'Spanish':
        return '''Eres un tutor que da UNA sola pista breve a un estudiante bloqueado.

REGLAS (todas obligatorias):
- Responde SOLO en español.
- Máximo 12 palabras.
- NO reveles la respuesta, los términos clave ni las fórmulas exactas.
- Apunta al concepto o principio subyacente, no a la solución.
- SIN preámbulos ni comillas.
- SIN meta-comentario sobre las instrucciones.

Respuesta correcta (NO REVELAR): $correctAnswer
Pregunta: $question

PISTA:''';
      case 'French':
        return '''Tu es un tuteur qui donne UN seul indice bref à un étudiant bloqué.

RÈGLES (toutes obligatoires) :
- Réponds UNIQUEMENT en français.
- Maximum 12 mots.
- NE révèle PAS la réponse, les termes clés, ni les formules exactes.
- Pointe vers le concept ou principe sous-jacent, pas la solution.
- AUCUN préambule ni guillemets.
- AUCUN méta-commentaire sur les instructions.

Réponse correcte (NE PAS RÉVÉLER) : $correctAnswer
Question : $question

INDICE :''';
      case 'German':
        return '''Du bist ein Tutor, der EINEN kurzen Hinweis an einen blockierten Studenten gibt.

REGELN (alle einhalten):
- Antworte AUSSCHLIESSLICH auf Deutsch.
- Maximal 12 Wörter.
- KEINE Lösung, Schlüsselbegriffe oder exakten Formeln nennen.
- Verweise auf das zugrundeliegende Konzept, nicht auf die Lösung.
- KEINE Einleitung, keine Anführungszeichen.
- KEIN Meta-Kommentar zu den Anweisungen.

Richtige Antwort (NICHT VERRATEN): $correctAnswer
Frage: $question

HINWEIS:''';
      case 'Portuguese':
        return '''És um tutor que dá UMA só pista breve a um estudante bloqueado.

REGRAS (todas obrigatórias):
- Responde SÓ em português.
- Máximo 12 palavras.
- NÃO reveles a resposta, os termos-chave nem as fórmulas exactas.
- Aponta para o conceito ou princípio subjacente, não para a solução.
- SEM preâmbulos nem aspas.
- SEM meta-comentário sobre as instruções.

Resposta correcta (NÃO REVELAR): $correctAnswer
Pergunta: $question

PISTA:''';
      default:
        return '''You are a tutor giving ONE brief hint to a stuck student.

RULES (all mandatory):
- Answer ONLY in English.
- Maximum 12 words.
- Do NOT reveal the answer, key terms, or exact formulas.
- Point to the underlying concept or principle, not the solution.
- NO preamble ("Here's a hint:") or quotation marks.
- NO meta-commentary about these instructions.

Correct answer (DO NOT REVEAL): $correctAnswer
Question: $question

HINT:''';
    }
  }

  /// Returns one short clue for [question] without revealing [correctAnswer].
  Future<String> generateHint({
    required String question,
    required String correctAnswer,
    String language = 'Italian',
  }) async {
    // 🎓 Sprint EX-D: when flag is on, route through the per-phase
    // cached model. Otherwise use the legacy `_streamModel` with the
    // monolithic `_buildHintPrompt` switch.
    //
    // Legacy: _streamModel (text mode, no JSON wrap, no canvas-action
    // system instruction) — not _model which would JSON-wrap into
    // `{spiegazione, azioni}` and dump meta-commentary instead of hint.
    final hintModel = _useExamPedagogyV34
        ? _examPhaseModels[ExamPhase.hint]
        : (_streamModel ?? _model);
    if (!_initialized || hintModel == null) return _hintFallback(language);
    try {
      // V2: short payload (just question + correctAnswer). Legacy: full
      // 6-lang switch monolith from `_buildHintPrompt`.
      final prompt = _useExamPedagogyV34
          ? _buildHintPayloadV2(
              question: question,
              correctAnswer: correctAnswer,
            )
          : _buildHintPrompt(
              question: question,
              correctAnswer: correctAnswer,
              language: language,
            );
      return await _meter<String>(
        'generateHint',
        estimate: 200,
        client: hintModel,
        run: () async {
          final result = await hintModel.generateContent(
            [Content.text(prompt)],
            featureTag: 'generateHint',
            estimate: 200,
          );
          final raw = result.text?.trim() ?? '';
          if (raw.isEmpty) {
            return (value: _hintFallback(language), response: result);
          }
          // Defensive cleanup: strip "Indizio:" / "Hint:" preambles, smart
          // quotes, surrounding quotes, leading bullet markers, code fences.
          String hintText = raw
              .replaceAll(RegExp(r'^```(?:\w+)?\s*'), '')
              .replaceAll(RegExp(r'\s*```$'), '')
              .replaceAll(
                  RegExp(r'^(?:indizio|hint|suggerimento|tip)\s*[:\-—]\s*',
                      caseSensitive: false),
                  '')
              .replaceAll(RegExp(r'^["“`]+|["”`]+$'), '')
              .replaceAll(RegExp(r'^\s*[-•*]\s+'), '')
              .trim();
          // If the model leaked into JSON despite the text-mode model
          // (rare), fall back to extracting the field. This was the
          // common failure mode with _model and is preserved as a belt-
          // and-suspenders safety net.
          if (hintText.startsWith('{') || hintText.startsWith('[')) {
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map<String, dynamic>) {
                final candidates = [
                  decoded['spiegazione'],
                  decoded['hint'],
                  decoded['testo'],
                  decoded['text'],
                ];
                for (final c in candidates) {
                  if (c is String && c.trim().isNotEmpty) {
                    hintText = c.trim();
                    break;
                  }
                }
              }
            } catch (_) {
              // JSON malformed — keep raw, will be sanitised below.
            }
          }
          // Defensive: if the result still looks like JSON or is wrapped in
          // backticks/quotes, strip the obvious noise so the bubble shows
          // something readable.
          hintText = hintText
              .replaceAll(RegExp(r'^```(?:json)?\s*'), '')
              .replaceAll(RegExp(r'\s*```$'), '')
              .replaceAll(RegExp(r'^["“]+|["”]+$'), '')
              .trim();
          if (hintText.isEmpty || hintText.startsWith('{')) {
            hintText = _hintFallback(language);
          }
          return (value: hintText, response: result);
        },
      );
    } on AiQuotaExceededException {
      rethrow;
    } catch (_) {
      return _hintFallback(language);
    }
  }
}
