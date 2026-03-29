import 'dart:convert';
import 'dart:ui' as ui;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'ai_provider.dart';
import 'atlas_action.dart';
import '../canvas/ai/exam_session_model.dart';

/// Google Gemini implementation of [AiProvider].
///
/// Uses the `google_generative_ai` package to communicate with Gemini.
/// Configured with a system prompt that instructs Gemini to act as "Atlas",
/// the spatial AI assistant, and to respond exclusively in structured JSON.
///
/// The API key is passed directly instead of using dotenv, making this
/// work cleanly in both package and app contexts.
class GeminiProvider implements AiProvider {
  GenerativeModel? _model;
  GenerativeModel? _streamModel; // For streaming (no JSON constraint)
  bool _initialized = false;

  /// The API key to use for Gemini.
  /// Set via [initialize] or constructor.
  final String? _apiKey;

  /// Create a GeminiProvider.
  ///
  /// If [apiKey] is provided, it will be used directly.
  /// Otherwise, pass it via [initialize].
  GeminiProvider({String? apiKey}) : _apiKey = apiKey;

  @override
  String get name => 'Gemini Flash';

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    final key = _apiKey;
    if (key == null || key.isEmpty) {
      throw Exception(
        'Atlas Error: API Key non fornita. '
        'Passa la chiave API al costruttore di GeminiProvider.',
      );
    }

    _model = GenerativeModel(
      model: 'gemini-3.1-flash-lite-preview',
      apiKey: key,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
      systemInstruction: Content.system(_systemPrompt),
    );

    // Streaming model — no JSON constraint, for real-time text output
    final langCode = ui.PlatformDispatcher.instance.locale.languageCode;
    const langMap = {'it': 'Italian', 'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German', 'pt': 'Portuguese', 'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese', 'ar': 'Arabic', 'ru': 'Russian'};
    final langName = langMap[langCode] ?? 'English';

    _streamModel = GenerativeModel(
      model: 'gemini-3.1-flash-lite-preview',
      apiKey: key,
      systemInstruction: Content.system(
        'You are ATLAS, an advanced spatial intelligence AI. '
        'Respond directly with the analysis text. No JSON wrapping. '
        'You MUST always respond in $langName.',
      ),
    );

    _initialized = true;

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

      final response = await _model!.generateContent([Content.text(payload)]);

      if (response.text != null) {
        final rawText = response.text!
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        final json = jsonDecode(rawText) as Map<String, dynamic>;
        final actions = AtlasAction.parseAll(json);
        final explanation = json['spiegazione'] as String?
            ?? json['explanation'] as String?;

        return AtlasResponse(
          actions: actions,
          explanation: explanation,
          rawJson: json,
        );
      }
    } catch (e) {

    }

    return const AtlasResponse.empty();
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

    try {
      final responses = _streamModel!.generateContentStream(
        [Content.text(payload)],
      );
      await for (final response in responses) {
        if (response.text != null && response.text!.isNotEmpty) {
          yield response.text!;
        }
      }
    } catch (e) {

      rethrow;
    }
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

    try {
      final responses = _streamModel!.generateContentStream(
        [Content.text(prompt)],
      );
      await for (final response in responses) {
        if (response.text != null && response.text!.isNotEmpty) {
          yield response.text!;
        }
      }
    } catch (e) {
      rethrow;
    }
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
    if (!_initialized || _model == null) {
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

      final response = await _model!.generateContent([Content.text(prompt)]);
      if (response.text == null) return [];

      final raw = response.text!
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final json = jsonDecode(raw) as Map<String, dynamic>;
      final domande = json['domande'] as List<dynamic>? ?? [];

      return domande
          .whereType<Map<String, dynamic>>()
          .map((d) => _parseExamQuestion(d, clusterTexts, labelToId))
          .where((q) => q != null)
          .cast<ExamQuestion>()
          .toList();
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
    if (!_initialized || _streamModel == null) {
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

    try {
      final stream = _streamModel!.generateContentStream([Content.text(prompt)]);
      await for (final chunk in stream) {
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
    } catch (e) {

      onTextChunk('\n⚠️ Errore nella valutazione. La risposta corretta è: $correctAnswer');
    }

    return result;
  }

  @override
  void dispose() {
    _model = null;
    _streamModel = null;
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
      final result = await _model!.generateContent([Content.text(prompt)]);
      return result.text?.trim() ?? '💡 Pensa ai concetti fondamentali!';
    } catch (_) {
      return '💡 Pensa ai concetti fondamentali!';
    }
  }
}
