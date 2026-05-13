import 'atlas_action.dart';
import 'cluster_action.dart';

/// Abstract contract for AI providers (Gemini, Claude, GPT, local models).
///
/// Fluera's canvas communicates with any LLM through this single interface.
/// To swap the underlying AI engine, implement this class and inject it
/// into [EngineScope].
///
/// ```dart
/// // Today: Gemini
/// AiProvider atlas = GeminiProvider();
///
/// // Tomorrow: Claude
/// AiProvider atlas = ClaudeProvider();
/// ```
abstract class AiProvider {
  /// Human-readable name of this provider (e.g. "Gemini Flash", "Claude Sonnet").
  String get name;

  /// Initialize the provider (load API keys, warm up connections).
  Future<void> initialize();

  /// Whether the provider is ready to accept requests.
  bool get isInitialized;

  /// Send a user prompt together with the spatial canvas context
  /// and receive structured [AtlasAction]s to execute on the canvas.
  ///
  /// [userPrompt] — natural language request (voice or text).
  /// [canvasContext] — structured JSON list of nodes in the area of interest
  ///   (selected via Lasso, viewport, or proximity).
  ///
  /// Returns an [AtlasResponse] containing parsed actions and optional
  /// text explanation.
  Future<AtlasResponse> askAtlas(
    String userPrompt,
    List<Map<String, dynamic>> canvasContext,
  );

  /// Streaming variant of [askAtlas] — yields partial text chunks
  /// as they arrive from the AI model.
  ///
  /// Used by "Analizza" to show real-time response rendering.
  /// Default implementation falls back to non-streaming [askAtlas].
  Stream<String> askAtlasStream(
    String userPrompt,
    List<Map<String, dynamic>> canvasContext,
  ) async* {
    final response = await askAtlas(userPrompt, canvasContext);
    if (response.explanation != null) {
      yield response.explanation!;
    }
  }

  /// Multi-turn chat streaming — yields partial text chunks for
  /// conversational Q&A grounded in the user's notes.
  ///
  /// [conversationHistory] — previous messages formatted as role: text pairs.
  /// [userMessage] — the new question from the user.
  /// [canvasContext] — structured note context (OCR, titles, transcripts).
  ///
  /// Default implementation falls back to [askAtlasStream].
  Stream<String> askChatStream(
    String conversationHistory,
    String userMessage,
    String canvasContext,
  ) async* {
    yield* askAtlasStream(
      '$conversationHistory\n\nSTUDENT: $userMessage',
      const [],
    );
  }

  /// Send a free-text prompt and get a plain text response.
  ///
  /// Unlike [askAtlas] which expects structured JSON actions,
  /// this method sends raw text and returns raw text — ideal for
  /// Socratic questions, breadcrumbs, and other non-structured prompts.
  Future<String> askFreeText(String prompt) async {
    final response = await askAtlas(prompt, const []);
    return response.explanation ?? '';
  }

  /// Socratic batch generation — sends only the per-call variable data
  /// (cluster list). The invariant Socratic rules live in the model's
  /// systemInstruction, which Gemini caches across calls to cut input
  /// tokens by ~60%.
  ///
  /// [userPrompt] — plain text with the clusters (OCR, recall, type).
  /// [avoidPrompts] — optional list of recently-asked questions to avoid
  /// regenerating verbatim. The implementation appends them to the
  /// system prompt as a "do not repeat" block.
  ///
  /// Returns raw JSON text: `{"clusters":[{"q":"...","h":["...","...","..."]}, …]}`.
  /// Default implementation falls back to [askFreeText] (unoptimized path).
  Future<String> askSocraticBatch(
    String userPrompt, {
    List<String> avoidPrompts = const [],
  }) =>
      askFreeText(userPrompt);

  /// 🌊 Socratic V3.4 ω — streaming per-stage question generator.
  ///
  /// Replaces the batch-of-3 paradigm with N parallel per-stage streams.
  /// Each call generates ONE question for ONE stage, with a small system
  /// prompt (cached per (stage, langCode)) and a tight output budget
  /// (≤500 tokens). Truncation impossible by design: the caller stops
  /// reading the stream as soon as `{"q":"...","h":[...]}` parses cleanly.
  ///
  /// [stage] — pedagogical stage as `SocraticStage.name` string
  /// (`'anchor'`, `'elaboration'`, `'comparative'`, `'counterfactual'`,
  /// `'application'`, `'interleave'`, `'metacognitive'`).
  /// [payload] — per-call payload built by the controller (cluster
  /// topic, OCR excerpt, discipline hints block, misconception hint
  /// when present, variation seed, avoid-list).
  /// [langCode] — target output language ISO 639-1 (`'it'`, `'en'`, …).
  ///
  /// Yields accumulating chunks; the caller is responsible for
  /// early-stop on valid JSON (truncation is structurally impossible
  /// when caller cuts the read).
  ///
  /// Default implementation is a single-shot fallback (no streaming) —
  /// wraps `askFreeText` and yields the full body. Production providers
  /// (`AtlasAiService`) override with `generateContentStream`.
  Stream<String> streamForStage({
    required String stage,
    required String payload,
    required String langCode,
  }) async* {
    final body = await askFreeText(payload);
    yield body;
  }

  /// 🧹 OCR cleanup — fixes obvious handwriting recognition errors in
  /// the supplied [raw] text without altering meaning. Used by the
  /// cognitive surfaces (Socratic, exam) as a post-processing step
  /// after MyScript returns garbled output.
  ///
  /// Default implementation returns [raw] unchanged so providers that
  /// don't implement it stay backward-compatible.
  Future<String> cleanOcrItalian(String raw, {String language = 'Italian'}) =>
      Future.value(raw);

  /// 🔶 Socratic V2 multi-turn follow-up. Given the student's sketch
  /// (OCR'd text), generate the NEXT question in the dialogue.
  ///
  /// CRITICAL contract: the implementation MUST NEVER evaluate the
  /// student's response as correct/wrong. It must always produce a new
  /// question that extends the dialogue. See
  /// `_socraticFollowUpSystemPrompt` for the full ruleset.
  ///
  /// [tipo] — question category (lacuna|sfida|profondità|transfer).
  /// [tema] — the cluster's clean topic (title or cleanedOcr).
  /// [priorQuestion] — the question the student just sketched on.
  /// [sketchOcr] — OCR'd text from the student's sketch.
  /// [role] — `followUp` (turn 2) or `aporetic` (turn 3 final).
  /// [stage] — 🎭 S2.A 2026-05-12. Pedagogical stage label as `enum.name`
  ///           ('anchor'|'elaboration'|'comparative'|'counterfactual'|
  ///           'application'|'interleave'|'metacognitive'). When provided,
  ///           the follow-up adapts its move to the stage context (e.g.
  ///           counterfactual → present an even more extreme edge case;
  ///           application → vary one parameter of the scenario). Optional
  ///           for backward compat — implementations should default to
  ///           the legacy generic prompt when null/missing.
  ///
  /// Default implementation returns an empty question — caller falls
  /// back to type-aware template via [`SocraticOutputFilter`].
  Future<({String question, bool isAporetic})> askSocraticFollowUp({
    required String tipo,
    required String tema,
    required String priorQuestion,
    required String sketchOcr,
    required dynamic role, // SocraticTurnRole (cross-package, kept as dynamic)
    String? stage,
  }) async {
    return (question: '', isAporetic: false);
  }

  /// 🛡️ S3.A 2026-05-12 — G4 chain-of-verification.
  ///
  /// Validates a Socratic question's pedagogical quality AFTER it has
  /// passed the G2 regex filter + B4 specificity check. Returns a score
  /// in [0.0, 1.0]:
  ///   • ≥ 0.6 → accept
  ///   • < 0.6 → caller should retry (with strengthened prompt) or fall
  ///     back to `SocraticOutputFilter.fallbackForStage`
  ///
  /// Default implementation is a pure heuristic (no network call):
  ///   • length ≥ 20 chars
  ///   • contains ≥ 1 interrogative word (cosa/quale/perché/come/quando/...)
  ///   • mentions ≥ 1 word (≥4 chars) from [clusterTopic] OR [clusterRawOcr]
  ///   • ends with `?`
  /// All four → 0.75. Three → 0.55. Two or fewer → 0.30.
  ///
  /// 🛡️ 2026-05-12 device fix: the topic pool now includes both the
  /// AI-generated label AND the raw OCR text. Atlas titles drift to
  /// English on Italian OCR, so label-only matching wrongly rejected
  /// otherwise excellent IT questions ("Cosa intendi… prima legge di
  /// Newton…" vs label "Newton's Laws"). Raw OCR closes the gap.
  ///
  /// Implementations that want LLM-based validation can override this
  /// (and pay the Gemini call); the heuristic is the safe offline default.
  Future<double> validateSocraticQuestion({
    required String questionText,
    required String clusterTopic,
    String? clusterRawOcr,
    String? stage,
    String? targetLang,
  }) async {
    final text = questionText.trim();
    if (text.isEmpty) return 0.0;

    // 🚨 LANGUAGE-DRIFT HARD REJECT (Phase 2.3).
    // When `targetLang` is provided, drift = question_lang != targetLang
    // (correct for cross-language source content, e.g. IT notes + EN
    // device locale). When null, fallback to source-comparison.
    if (socraticLanguageDriftsFromSource(
      text,
      clusterRawOcr ?? clusterTopic,
      targetLang: targetLang,
    )) {
      return 0.05;
    }

    int score = 0;
    if (text.length >= 20) score++;
    // Interrogative opener (IT + EN tokens, deliberate-loose).
    // Expanded openers: covers ~95% of real questions in IT+EN.
    // Includes: standard wh-words, auxiliary verbs ("does", "do"),
    // softener openers ("imagine", "consider", "suppose"), conditional
    // ("if"), elaboration verbs ("describe", "explain", "compare"),
    // plus IT equivalents ("immagina", "considera", "spiega", "se").
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
    // Concept mention pool — label + OCR raw, ≥4 char words.
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
    // Cross-language credit: lexical topic overlap is 0 by design when
    // source language differs from target. Two cases credit specificity
    // semantically:
    //   (a) source detected ≠ target (confident cross-lang)
    //   (b) source 'unknown' (short technical topic) but question is
    //       confidently in target language
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

  /// 🧩 Cluster-level Atlas dispatcher (F8).
  ///
  /// Sibling to [askAtlas] but operates on semantic clusters instead of
  /// individual scene-graph nodes. Used for high-level reshape commands
  /// (organize, align, distribute, color, connect) where node-level
  /// granularity would scatter handwriting into individual letters.
  ///
  /// [clusterContext] is the JSON shape produced by
  /// `CanvasStateExtractor.buildClusterContext`. Implementations that
  /// don't support cluster mode fall through to an empty response — the
  /// caller surfaces a "feature not available" hint at the UI layer.
  Future<ClusterAtlasResponse> askAtlasCluster(
    String userPrompt,
    Map<String, dynamic> clusterContext,
  ) async =>
      const ClusterAtlasResponse.empty();

  /// Release resources held by this provider.
  void dispose();
}

/// 🧩 Structured response for cluster-level Atlas commands.
///
/// Sibling to [AtlasResponse] but carries [ClusterAction]s. The actions
/// are applied by `ClusterActionExecutor` rather than the node-level
/// `AtlasActionExecutor`. See `_clusterSystemPrompt` for the schema.
class ClusterAtlasResponse {
  final List<ClusterAction> actions;
  final String? explanation;
  final Map<String, dynamic>? rawJson;

  const ClusterAtlasResponse({
    required this.actions,
    this.explanation,
    this.rawJson,
  });

  const ClusterAtlasResponse.empty()
      : actions = const [],
        explanation = null,
        rawJson = null;

  @override
  String toString() =>
      'ClusterAtlasResponse(actions: ${actions.length}, '
      'explanation: ${explanation != null ? "yes" : "no"})';
}

/// Structured response from Atlas AI.
class AtlasResponse {
  /// Parsed actions to execute on the canvas (create nodes, connect, etc.).
  final List<AtlasAction> actions;

  /// Optional text explanation from the AI (shown in a toast or overlay).
  final String? explanation;

  /// Raw JSON response (for debugging).
  final Map<String, dynamic>? rawJson;

  const AtlasResponse({
    required this.actions,
    this.explanation,
    this.rawJson,
  });

  /// Empty response (no actions).
  const AtlasResponse.empty()
      : actions = const [],
        explanation = null,
        rawJson = null;

  @override
  String toString() =>
      'AtlasResponse(actions: ${actions.length}, explanation: ${explanation != null ? "yes" : "no"})';
}

/// 🌍 Language signature detector — identifies the dominant Latin-script
/// language of [text] via function-word signatures + diacritic markers.
///
/// Returns one of 'it', 'es', 'fr', 'de', 'pt', 'en', or 'unknown'.
/// Language-agnostic: works on any source/question pair without
/// hardcoding which language is "the wrong one". Word-boundary
/// tokenization (no substring false positives like "rest**are**" ←
/// matching "are" in EN).
///
/// Heuristic: for each language, count tokens that match its function-
/// word set + diacritic marks. The language with the highest score
/// wins, provided it has ≥ 2 matches OR a unique diacritic. Otherwise
/// returns 'unknown' — caller should treat as "no signal, accept".
///
/// Detection covers Tier 1 i18n target languages (IT/ES/FR/DE/PT/EN);
/// any other locale returns 'unknown' and drift detection is skipped
/// (conservative — accept by default rather than reject IT-only check).
String detectLanguageSignature(String text) {
  if (text.trim().length < 4) return 'unknown';
  final lower = text.toLowerCase();
  // Tokenize on any non-letter (latin + extended). Cyrillic / CJK
  // would also tokenize, but those locales return 'unknown' since
  // their function words aren't in our dictionaries.
  final tokens = lower
      .split(RegExp(r'[^a-zàâäéèêëîïôöùûüÿñçãõẽíóúüäöüß¿¡]+'))
      .where((t) => t.isNotEmpty)
      .toSet();

  // Function-word signatures. Picked from top-frequency words that are
  // highly distinctive across the Tier-1 i18n set. Expanded set so a
  // typical sentence reaches the ≥2 threshold even when most content
  // words are scientific jargon shared across languages (mitocondri,
  // ATP, Newton). Cross-language overlap is minimised by preferring
  // articles + prepositions specific to each language.
  const itMarkers = {
    'di', 'la', 'il', 'lo', 'le', 'gli', 'che', 'con', 'per', 'del',
    'della', 'sono', 'come', 'una', 'uno', 'alla', 'dello', 'degli',
    'nel', 'nello', 'nella', 'sul', 'sulla', 'questo', 'questa',
    'i', 'attraverso', 'tra', 'fra', 'anche', 'ancora', 'sempre',
    'sotto', 'sopra', 'dopo', 'prima', 'ogni', 'qualche', 'molto',
    'però', 'allo', 'agli', 'dai', 'dei', 'dalle', 'sui', 'negli',
    'affermare', 'essere', 'avere', 'fare', 'dire', 'quindi',
  };
  const esMarkers = {
    'el', 'los', 'las', 'que', 'con', 'por', 'del', 'una', 'unos',
    'unas', 'está', 'son', 'pero', 'como', 'esto', 'esta', 'eso',
    'esa', 'pues', 'cuando', 'donde', 'muy', 'también',
    'ya', 'sin', 'sobre', 'este', 'según', 'cada', 'todo', 'todos',
    'toda', 'todas', 'cómo', 'qué', 'cuál', 'porque',
    'mientras', 'durante', 'entonces', 'aunque',
  };
  const frMarkers = {
    'le', 'les', 'des', 'qui', 'que', 'avec', 'pour', 'dans', 'est',
    'sont', 'une', 'aux', 'sur', 'leur', 'leurs', 'cette', 'ces',
    'comme', 'pourquoi', 'plus', 'où', 'mais', 'aussi', 'donc',
    'sans', 'sous', 'dont', 'tout', 'toute', 'tous', 'toutes',
    'ainsi', 'alors', 'celui', 'celle', 'ceux', 'celles', 'puisque',
    'corps', 'repos', 'reste', 'stipule', 'première', 'deuxième',
  };
  const deMarkers = {
    'der', 'die', 'das', 'den', 'dem', 'mit', 'für', 'ist', 'sind',
    'und', 'eine', 'einen', 'einem', 'einer', 'auf', 'aus', 'von',
    'zum', 'zur', 'nicht', 'auch', 'schon', 'noch', 'immer', 'mehr',
    'wenig', 'sehr', 'kein', 'viel', 'durch', 'gegen', 'ohne', 'um',
    'während', 'weil', 'wenn', 'aber', 'oder', 'sondern',
    'körper', 'gesetz', 'erste',
  };
  const ptMarkers = {
    'os', 'as', 'que', 'com', 'para', 'do', 'da', 'dos', 'das', 'uma',
    'são', 'está', 'pelo', 'pela', 'pelos', 'pelas', 'isso', 'isto',
    'aquele', 'aquela', 'quando', 'também', 'ainda', 'sempre',
    'todos', 'toda', 'todo', 'todas', 'cada', 'sob', 'sobre',
    'entre', 'porque', 'enquanto', 'durante', 'então', 'embora',
    'mas', 'ou', 'corpo', 'repouso', 'permanece', 'afirma',
  };
  // EN markers: avoid short single-letter or 2-letter forms (a, an, in,
  // on, it) that overlap with IT/ES/FR/PT articles/prepositions. Use
  // longer function words instead.
  const enMarkers = {
    'the', 'and', 'with', 'from', 'this', 'these', 'those', 'would',
    'should', 'could', 'were', 'was', 'have', 'has', 'been', 'what',
    'which', 'who', 'whom', 'whose', 'when', 'where', 'while', 'why',
    'how', 'about', 'because', 'although', 'though', 'whether',
    'that', 'than', 'then', 'them', 'they', 'their', 'there', 'here',
    'must', 'might', 'will', 'shall', 'into', 'over', 'under',
    'between', 'through', 'during', 'before', 'after',
    'by', 'until', 'unless', 'either', 'neither', 'however',
    'therefore', 'thus', 'hence', 'onto', 'upon', 'wherein',
    'within', 'without',
  };

  int countMatches(Set<String> dict) =>
      tokens.intersection(dict).length;

  final scores = <String, int>{
    'it': countMatches(itMarkers),
    'es': countMatches(esMarkers),
    'fr': countMatches(frMarkers),
    'de': countMatches(deMarkers),
    'pt': countMatches(ptMarkers),
    'en': countMatches(enMarkers),
  };

  // Diacritic boosts — distinctive marks add 2 points (≈ one extra
  // function word) but tie-break ambiguous short texts. ñ/¿/¡ → ES;
  // ã/õ/ç → PT (also FR uses ç so weaker signal); ä/ö/ü/ß → DE;
  // accented vowels appear in IT/ES/FR/PT so we keep them general.
  if (RegExp(r'[ñ¿¡]').hasMatch(lower)) scores['es'] = scores['es']! + 2;
  if (RegExp(r'[ãõ]').hasMatch(lower)) scores['pt'] = scores['pt']! + 2;
  if (RegExp(r'[äöüß]').hasMatch(lower)) scores['de'] = scores['de']! + 2;
  // Italian uses àèéìòù; Spanish/Portuguese also use accents, but the
  // function-word set already covers them. We add a small IT-specific
  // boost when grave-è is present (very rare in ES/PT vs common in IT).
  if (RegExp(r'è').hasMatch(lower)) scores['it'] = scores['it']! + 1;

  // Pick winner. Require ≥ 1 score AND clear lead over runner-up.
  // Threshold was 2 originally; lowered to 1 (2026-05-12 PM device fix)
  // because short technical topics like "leve di Archimede" (1 marker:
  // 'di') were being classified 'unknown' → B4 lexical check broke for
  // cross-language scenarios. With ≥1 markers + lead, short multi-word
  // topics with at least one function word get correctly classified.
  // Genuine ambiguity (0 markers everywhere or tie) still returns
  // 'unknown' — safe default.
  final sorted = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = sorted[0];
  final runnerUp = sorted.length > 1 ? sorted[1].value : 0;
  if (top.value >= 1 && top.value > runnerUp) return top.key;
  return 'unknown';
}

/// 🚨 Language-drift detector for G4 chain-of-verification.
///
/// Preferred call shape (2026-05-12 device fix): provide [targetLang]
/// (ISO 639-1) — drift = `question_language != targetLang`. This is the
/// correct comparison when the system has an authoritative target
/// (device locale OR user-selected preferredLanguage). It allows
/// legitimate target-lang questions on cross-language source content
/// (e.g. EN question on IT student notes when device locale is EN).
///
/// Backward-compat fallback: when [targetLang] is null, compare against
/// the source-detected language. Used for legacy callers and for cases
/// where there's no clear target signal.
///
/// Both detected languages must be ≠ 'unknown' for a positive drift
/// decision; otherwise returns `false` (accept by default).
bool socraticLanguageDriftsFromSource(
  String question,
  String source, {
  String? targetLang,
}) {
  final qLang = detectLanguageSignature(question);
  if (qLang == 'unknown') return false;
  if (targetLang != null && targetLang.isNotEmpty) {
    return qLang != targetLang;
  }
  final srcLang = detectLanguageSignature(source);
  if (srcLang == 'unknown') return false;
  return srcLang != qLang;
}
