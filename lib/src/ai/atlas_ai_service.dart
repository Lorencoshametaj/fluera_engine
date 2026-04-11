import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'ai_provider.dart';
import 'atlas_action.dart';
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
  GenerativeModel? _model;
  GenerativeModel? _streamModel; // For streaming (no JSON constraint)
  GenerativeModel? _ghostMapModel; // 🗺️ Ghost Map — low temperature for accuracy
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

    // 🗺️ Ghost Map model — low temperature (0.3) for factual accuracy (A3-02).
    // The reference concept map MUST be correct — creativity is harmful here.
    _ghostMapModel = GenerativeModel(
      model: 'gemini-3.1-flash-lite-preview',
      apiKey: key,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.3,
      ),
      systemInstruction: Content.system(
        'You are Atlas, an AI tutor embedded in Fluera — a cognitive learning engine. '
        'Your role is to analyze student handwritten notes and identify knowledge gaps. '
        'You must be factually accurate, domain-specific, and pedagogically constructive. '
        'Always respond in Italian. Never invent facts. Keep concepts and explanations concise.',
      ),
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

  /// 🔶 Free-text prompt — sends raw text, returns raw text.
  /// Used for Socratic questions, breadcrumbs, and other non-structured prompts.
  /// Uses _streamModel (no JSON constraint, no canvas system prompt).
  @override
  Future<String> askFreeText(String prompt) async {
    if (!_initialized || _streamModel == null) {
      throw StateError('Atlas non inizializzato. Chiama initialize() prima.');
    }

    try {
      final response = await _streamModel!.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';
      debugPrint('🔶 askFreeText response: $text');
      return text;
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
    String language = 'Italian',
  }) async {
    if (!_initialized || _model == null) {
      throw StateError('Atlas non inizializzato. Chiama initialize() prima.');
    }

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
    final areaWidth = (maxX - minX).isFinite ? (maxX - minX).clamp(200, 5000) : 800;
    final areaHeight = (maxY - minY).isFinite ? (maxY - minY).clamp(200, 3000) : 600;
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
- "rFu+1v+A'" → (garbled, skip this fragment)

Strategy: Focus on RECOGNIZABLE KEYWORDS. If you can identify ≥1 meaningful word in a cluster, use it. Skip fragments that are 100% unintelligible.
</CRITICAL_FIRST_STEP>

<TASK>
Analyze the student's reconstructed notes and generate a Ghost Map:

1. **MISSING** ("mancante") — Key concepts the student SHOULD know for this topic but did NOT write. These are the most valuable: they reveal blind spots.
2. **WEAK** ("debole") — Concepts the student mentioned but incompletely or incorrectly.
3. **CORRECT** ("corretto") — Concepts the student got right. Include 2-3 of the most important ones to provide positive reinforcement.

Think step-by-step:
(a) Reconstruct the OCR text into the student's actual intended words
(b) Identify the subject/topic and academic level
(c) List the 5-10 key concepts a complete understanding requires
(d) Compare against what the student wrote
(e) Output the top 2-5 gaps as ghost nodes + 2-3 correct confirmations
</TASK>

<CONSTRAINTS>
1. LANGUAGE: Detect the language from the notes content. All output fields MUST be in that same language. Do NOT default to English.
2. CONCISENESS: "concetto" ≤ 8 words. "spiegazione" ≤ 15 words. These appear in small UI bubbles.
3. SPECIFICITY: Missing concepts must be specific to the student's topic. "Newton" + "scienziato" → suggest "Tre leggi del moto", NOT "la scienza è importante".
4. POSITIONING: Place ghost nodes BELOW or BESIDE existing nodes, NEVER above them (the top area is covered by the toolbar). Canvas area: x ${(centerX - areaWidth ~/ 2)}..${(centerX + areaWidth ~/ 2)}, y ${(centerY)}..${(centerY + areaHeight)}. Offset ≥ 150px from existing nodes. Prefer y values LARGER than existing nodes' y values.
5. COUNT: 2-5 "mancante" nodes, 0-2 "debole" nodes, 2-3 "corretto" nodes. Never more than 10 total.
6. CROSS-DOMAIN (P4-34/35/36): If the student's notes connect multiple disciplines (e.g., physics+math, biology+chemistry), include 1-2 missing connections labeled "cross_dominio": true that bridge different knowledge domains. These encourage Transfer (far transfer between fields).
</CONSTRAINTS>

<STUDENT_NOTES>
$notesSummary
</STUDENT_NOTES>

<EXISTING_CONNECTIONS>
$connSummary
</EXISTING_CONNECTIONS>
$socraticSection

<FEW_SHOT_EXAMPLE>
Input notes: "[[Nodo 1: Fisica]] NEWTON É UN- SCIGNZ' ATO" + "[[Nodo 2]] Ii GENE"

Good output:
{
  "ricostruzione": "Lo studente ha scritto: (1) 'Newton è uno scienziato' (2) 'Il genio'. Argomento: Isaac Newton, livello universitario.",
  "valutazione": "Lo studente sa chi è Newton ma non ha scritto nulla sulle sue scoperte o leggi.",
  "nodi": [
    {"id": "ghost_1", "stato": "mancante", "concetto": "Tre leggi del moto", "spiegazione": "Fondamento della meccanica classica newtoniana", "nodo_correlato": "nodo_1", "x": 600, "y": 250},
    {"id": "ghost_2", "stato": "mancante", "concetto": "Legge di gravitazione universale", "spiegazione": "F = Gm₁m₂/r², scoperta chiave di Newton", "nodo_correlato": "nodo_1", "x": 400, "y": 450},
    {"id": "ghost_3", "stato": "mancante", "concetto": "Calcolo infinitesimale", "spiegazione": "Newton co-inventò il calcolo con Leibniz", "nodo_correlato": "nodo_1", "x": 800, "y": 350},
    {"id": "ghost_4", "stato": "debole", "concetto": "Identità di Newton", "spiegazione": "Solo 'scienziato' è troppo generico, manca il contesto storico", "nodo_correlato": "nodo_1", "x": 500, "y": 150}
  ],
  "connessioni_mancanti": [
    {"id": "gconn_1", "sorgente": "ghost_1", "destinazione": "ghost_2", "etichetta": "derivano da", "spiegazione": "Le leggi del moto sono il fondamento della gravitazione"}
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
      "nodo_correlato": "nodo_N or null",
      "x": 500,
      "y": 300
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

    try {
      // 🗺️ Use dedicated ghost map model (temperature 0.3) with 12s timeout (A3-03)
      final ghostModel = _ghostMapModel ?? _model!;
      final response = await ghostModel
          .generateContent([Content.text(prompt)])
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw TimeoutException(
              'Ghost Map generation exceeded 12s timeout',
            ),
          );
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
        final relatedLabel = n['nodo_correlato'] as String?;
        final relatedClusterId = relatedLabel != null
            ? labelToId[relatedLabel]
            : null;

        // 🔒 SEC-02: Clamp AI-suggested positions to prevent extreme coordinates
        double nodeX = ((n['x'] as num?)?.toDouble() ??
            (relatedClusterId != null
                ? (clusterPositions[relatedClusterId]?['x'] ?? centerX.toDouble()) + 180
                : centerX.toDouble()))
            .clamp(-50000.0, 50000.0);
        double nodeY = ((n['y'] as num?)?.toDouble() ??
            (relatedClusterId != null
                ? (clusterPositions[relatedClusterId]?['y'] ?? centerY.toDouble()) + 100
                : centerY.toDouble()))
            .clamp(-50000.0, 50000.0);

        // 🗺️ Force missing nodes BELOW existing clusters so they don't
        // hide behind the toolbar at the top of the screen.
        if (status == GhostNodeStatus.missing) {
          double refY = centerY.toDouble();
          double refH = 80;
          if (relatedClusterId != null) {
            refY = clusterPositions[relatedClusterId]?['y'] ?? refY;
            refH = clusterSizes[relatedClusterId]?['h'] ?? refH;
          }
          final clampMinY = refY + refH + 30;
          if (nodeY < clampMinY) nodeY = clampMinY;
        }

        // For weak/correct nodes, snap position to the related cluster
        if (status != GhostNodeStatus.missing && relatedClusterId != null) {
          final relPos = clusterPositions[relatedClusterId];
          if (relPos != null) {
            nodeX = relPos['x'] ?? nodeX;
            nodeY = relPos['y'] ?? nodeY;
          }
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
