import 'dart:async';
import 'package:flutter/foundation.dart';
import 'socratic_model.dart';
import 'socratic_output_filter.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/telemetry_recorder.dart';
import '../../../reflow/content_cluster.dart';

/// 🔶 SOCRATIC SPATIAL — Controller for Socratic interrogation sessions.
///
/// State machine managing the full lifecycle:
///
/// ```
/// inactive → generating → active → complete → inactive
/// ```
///
/// Each question goes through:
/// ```
/// active → awaitingConfidence → awaitingAnswer → [correct|wrong|skipped|belowZPD]
/// ```
///
/// Spec: P3-01 → P3-46
///
/// ❌ ANTI-PATTERNS:
///   P3-06: No automatic activation
///   P3-07: No loading animations
///   P3-29: AI NEVER provides the complete answer
///   P3-36: No correct answer shown after error
///   P3-37: No multiple choice / true-false
///   P3-38: No timer / countdown
///   P3-40: No visible question list count
class SocraticController extends ChangeNotifier {
  SocraticController({TelemetryRecorder? telemetry})
      : _telemetry = telemetry ?? TelemetryRecorder.noop;

  final TelemetryRecorder _telemetry;
  DateTime? _sessionStartedAt;

  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  SocraticSession? _session;
  SocraticSession? get session => _session;

  bool _isActive = false;
  bool get isActive => _isActive;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  /// Whether the last session used fallback questions (AI call failed).
  bool _usedFallback = false;
  bool get usedFallback => _usedFallback;

  /// Version notifier for painter/widget repaints.
  final ValueNotifier<int> version = ValueNotifier(0);

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVATION (P3-01)
  // ─────────────────────────────────────────────────────────────────────────

  /// Activate Socratic mode.
  ///
  /// [clusters] — the detected content clusters on the canvas.
  /// [recallData] — optional recall levels from Recall Mode (clusterId → recall 1-5).
  /// [fsrsData] — optional FSRS schedule (concept → next review date).
  /// [provider] — Atlas AI provider for question generation.
  Future<void> activate({
    required List<ContentCluster> clusters,
    required Map<String, int> recallData,
    AiProvider? provider,
    Map<String, String> clusterTexts = const {},
  }) async {
    if (_isActive) return;
    if (clusters.isEmpty) return;

    _isGenerating = true;
    _isActive = true;
    _usedFallback = false;
    notifyListeners();

    // Generate questions for the clusters.
    final questions = await _generateQuestions(
      clusters: clusters,
      recallData: recallData,
      provider: provider,
      clusterTexts: clusterTexts,
    );

    if (questions.isEmpty) {
      _isActive = false;
      _isGenerating = false;
      notifyListeners();
      return;
    }

    _session = SocraticSession(
      sessionId: 'socratic_${DateTime.now().millisecondsSinceEpoch}',
      queue: questions,
      maxQuestions: questions.length.clamp(5, 12),
    );

    debugPrint('🔶 Socratic session created:'
        ' ${questions.length} questions in queue,'
        ' maxQuestions=${_session!.maxQuestions},'
        ' types=${questions.map((q) => q.type.name).join(', ')}');

    _sessionStartedAt = DateTime.now();
    _telemetry.logEvent('step_3_socratic_started', properties: {
      'cluster_count': clusters.length,
      'question_count': questions.length,
      'max_questions': _session!.maxQuestions,
      'used_fallback': _usedFallback,
    });

    _isGenerating = false;
    _bump();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QUESTION GENERATION (P3-09 → P3-14)
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<SocraticQuestion>> _generateQuestions({
    required List<ContentCluster> clusters,
    required Map<String, int> recallData,
    AiProvider? provider,
    Map<String, String> clusterTexts = const {},
  }) async {
    final questions = <SocraticQuestion>[];

    // Sort clusters by recall level (ascending) for priority (P3-12).
    final sorted = List<ContentCluster>.from(clusters);
    sorted.sort((a, b) {
      final ra = recallData[a.id] ?? 3;
      final rb = recallData[b.id] ?? 3;
      return ra.compareTo(rb);
    });

    // Limit to first 8 clusters max
    final toProcess = sorted.take(8).toList();

    // ─── BATCH AI GENERATION (single call) ──────────────────────────────
    if (provider != null) {
      try {
        final batchResult = await _generateBatchViaAI(
          provider: provider,
          clusters: toProcess,
          recallData: recallData,
          clusterTexts: clusterTexts,
        );

        for (int i = 0; i < toProcess.length && i < batchResult.length; i++) {
          final cluster = toProcess[i];
          final recall = recallData[cluster.id] ?? 3;
          final type = _questionTypeForRecall(recall);
          final entry = batchResult[i];

          final clusterTopic = clusterTexts[cluster.id] ?? '';
          final rawQuestion = entry['question'];
          final String questionText;
          if (rawQuestion != null) {
            questionText = _applyG2Filter(_stripLatex(rawQuestion), clusterTopic);
            if (questionText != _stripLatex(rawQuestion)) {
              debugPrint('🛡️ G2 replaced question for "$clusterTopic": '
                  '"${rawQuestion.substring(0, rawQuestion.length.clamp(0, 50))}..."');
            }
          } else {
            questionText = _fallbackQuestion(type, clusterTopic);
            debugPrint('⚠️ Socratic: null question for "$clusterTopic", using fallback');
          }
          questions.add(SocraticQuestion(
            id: 'sq_${cluster.id}_${DateTime.now().microsecondsSinceEpoch}',
            clusterId: cluster.id,
            anchorPosition: cluster.centroid,
            type: type,
            text: questionText,
            breadcrumbs: List<String>.from(entry['breadcrumbs'] ?? []),
            recallLevel: recall,
          ));
        }

        if (questions.isNotEmpty) return questions;
      } catch (e) {
        debugPrint('⚠️ Socratic batch generation failed: $e');
      }
    }

    // ─── FALLBACK: no AI ─────────────────────────────────────────────────
    _usedFallback = true;
    for (final cluster in toProcess) {
      final recall = recallData[cluster.id] ?? 3;
      final type = _questionTypeForRecall(recall);
      final clusterTopic = clusterTexts[cluster.id] ?? '';
      questions.add(SocraticQuestion(
        id: 'sq_${cluster.id}_${DateTime.now().microsecondsSinceEpoch}',
        clusterId: cluster.id,
        anchorPosition: cluster.centroid,
        type: type,
        text: _fallbackQuestion(type, clusterTopic),
        breadcrumbs: const [],
        recallLevel: recall,
      ));
    }

    return questions;
  }

  /// 🔶 BATCH generation — single API call for all questions + breadcrumbs.
  Future<List<Map<String, dynamic>>> _generateBatchViaAI({
    required AiProvider provider,
    required List<ContentCluster> clusters,
    required Map<String, int> recallData,
    required Map<String, String> clusterTexts,
  }) async {
    if (!provider.isInitialized) await provider.initialize();

    // Build cluster descriptions
    final clusterDescriptions = StringBuffer();
    for (int i = 0; i < clusters.length; i++) {
      final c = clusters[i];
      final text = clusterTexts[c.id] ?? '(vuoto)';
      final recall = recallData[c.id] ?? 3;
      final type = _questionTypeForRecall(recall);
      final typeLabel = switch (type) {
        SocraticQuestionType.lacuna => 'lacuna',
        SocraticQuestionType.challenge => 'sfida',
        SocraticQuestionType.depth => 'profondità',
        SocraticQuestionType.transfer => 'transfer',
      };
      clusterDescriptions.writeln(
        '${i + 1}. OCR: "$text" | recall: $recall/5 | tipo: $typeLabel',
      );
    }

    final prompt = '''Sei un tutor socratico esperto che opera nel contesto di Fluera, un motore cognitivo per studenti universitari.
Il tuo obiettivo è attivare il RETRIEVAL PRACTICE: lo studente deve PRODURRE la risposta dalla memoria, non riconoscerla.

═══ STEP 1 — RICOSTRUZIONE OCR ═══
Il testo proviene da OCR su scrittura a mano. Correggi e ricostruisci il significato reale:
${clusterDescriptions.toString().trim()}

═══ STEP 2 — IDENTIFICA MATERIA E LIVELLO ═══
Dai testi ricostruiti:
- Identifica la DISCIPLINA specifica (es: "fisica meccanica", "biologia molecolare", "letteratura italiana del '900")
- Identifica il LIVELLO (universitario base, avanzato, specialistico)
- TUTTE le domande devono restare DENTRO questa disciplina

═══ STEP 3 — GENERA DOMANDE ═══
Per OGNI cluster, genera UNA domanda socratica. Segui ESATTAMENTE il tipo indicato:

TIPO "lacuna" (recall 1-2 → lo studente ha DIMENTICATO):
Principio: Zeigarnik Effect + Active Recall. Crea un "vuoto cognitivo" che lo studente sente il bisogno di colmare.
- Chiedi cosa COLLEGA due concetti, cosa MANCA nella catena causale
- Usa verbi generativi: "spiega", "descrivi", "che relazione c'è tra..."
✅ BUONO: "Quale passaggio collega la forza applicata al cambiamento di velocità nel caso di Newton?"
❌ CATTIVO: "Cosa sai di Newton?" (troppo vago, non attiva retrieval specifico)

TIPO "sfida" (recall 3 → lo studente crede di sapere):
Principio: Desirable Difficulties (Bjork) + Ipercorrezione. Metti in crisi una certezza per provocare rielaborazione profonda.
- Presenta un controesempio o un'eccezione
- Forza lo studente a DIFENDERE o RIVEDERE la sua comprensione
✅ BUONO: "Se F=ma vale sempre, come spieghi il moto di un corpo a velocità vicine a c?"
❌ CATTIVO: "Sei sicuro che questa cosa sia corretta?" (troppo generico, nessun ancoraggio)

TIPO "profondità" (recall 4 → sa il COSA ma non il PERCHÉ):
Principio: Levels of Processing (Craik & Lockhart). Sposta dall'encoding superficiale a quello profondo.
- Chiedi il MECCANISMO, la CAUSA, il PRINCIPIO sottostante
- Forza la spiegazione causale, non la descrizione
✅ BUONO: "Quale meccanismo molecolare permette al gene di essere trascritto solo quando necessario?"
❌ CATTIVO: "Puoi spiegare il perché?" (non specifica COSA spiegare)

TIPO "transfer" (recall 5 → padronanza):
Principio: Transfer Learning + Interleaving. Crea ponti tra domini diversi.
- Chiedi analogie con ALTRE materie o applicazioni in contesti NUOVI
✅ BUONO: "Il meccanismo di feedback negativo nell'omeostasi ti ricorda qualche sistema in ingegneria o economia?"
❌ CATTIVO: "Questo concetto ti ricorda qualcosa?" (troppo aperto)

═══ BREADCRUMBS (3 per domanda) ═══
Funzionano come scaffolding progressivo (Vygotsky ZPD):
1. L'Eco Lontano — direzione vaga, attiva il priming semantico (max 12 parole)
2. Il Sentiero — circoscrive il dominio, riduce lo spazio di ricerca (max 15 parole)
3. La Soglia — ultimo scaffolding, la risposta è a un passo MA NON VIENE DATA (max 20 parole)

═══ SPECIFICITÀ (regola d'oro) ═══
- Ogni domanda DEVE menzionare almeno UN concetto specifico presente negli appunti dello studente
- Se gli appunti dicono "Newton" e "gene", la domanda su Newton deve menzionare "Newton" o "forza" o "massa", NON essere generica
- Se ci sono 3+ cluster, l'ULTIMO cluster dovrebbe avere una domanda PONTE che collega 2 cluster (interleaving)
  Esempio: se i cluster sono "forza" e "accelerazione", chiedi "che relazione quantitativa lega forza e accelerazione?"

═══ ANTI-PATTERN (vietato) ═══
❌ Domande sì/no o a risposta chiusa
❌ Domande tipo "cosa sai di X?" (non attivano retrieval specifico)
❌ Meta-descrizioni ("sto generando una domanda...")
❌ Domande sulla STORIA di uno scienziato se la materia è la SUA DISCIPLINA
❌ Domande troppo vaghe che permettono qualsiasi risposta
❌ Fornire la risposta, nemmeno parzialmente, nemmeno nei breadcrumbs
❌ Opzioni multiple o vero/falso
❌ Domande che non citano NESSUN concetto dagli appunti
❌ LaTeX o markdown (scrivi F=ma, NON \$F=ma\$)

═══ FORMATO OUTPUT ═══
---CLUSTER 1---
DOMANDA: [la domanda, max 2 frasi, stessa lingua degli appunti]
INDIZIO1: [eco lontano]
INDIZIO2: [sentiero]
INDIZIO3: [soglia]
---CLUSTER 2---
DOMANDA: [la domanda]
INDIZIO1: [eco lontano]
INDIZIO2: [sentiero]
INDIZIO3: [soglia]
...per tutti i ${clusters.length} cluster. SOLO questo formato, nient'altro.''';

    final text = await provider.askFreeText(prompt).timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        debugPrint('⚠️ Socratic AI call timed out after 8s → fallback');
        return '';
      },
    );
    debugPrint('🔶 Socratic batch response (${text.length} chars)');

    // Parse the response
    return _parseBatchResponse(text, clusters.length);
  }

  // Cached regex for batch parsing (O2 optimization).
  // Accepts: ---CLUSTER 1---, ---CLUSTER 1 (NEWTON)---, ---CLUSTER 1: NEWTON---
  static final _clusterSplitRegex = RegExp(r'---CLUSTER\s*\d+.*?---', caseSensitive: false);

  /// Parse the batch response into structured data
  List<Map<String, dynamic>> _parseBatchResponse(String text, int expected) {
    final results = <Map<String, dynamic>>[];
    
    // Split by cluster markers
    final sections = text.split(_clusterSplitRegex);
    
    for (final section in sections) {
      if (section.trim().isEmpty) continue;
      
      String? question;
      final breadcrumbs = <String>[];
      
      for (final line in section.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('DOMANDA:')) {
          question = trimmed.substring('DOMANDA:'.length).trim();
        } else if (trimmed.startsWith('INDIZIO1:')) {
          breadcrumbs.add(trimmed.substring('INDIZIO1:'.length).trim());
        } else if (trimmed.startsWith('INDIZIO2:')) {
          breadcrumbs.add(trimmed.substring('INDIZIO2:'.length).trim());
        } else if (trimmed.startsWith('INDIZIO3:')) {
          breadcrumbs.add(trimmed.substring('INDIZIO3:'.length).trim());
        }
      }
      
      if (question != null && question.isNotEmpty) {
        // Ensure 3 breadcrumbs
        while (breadcrumbs.length < 3) {
          breadcrumbs.add('Ripensa a questo concetto da un\'angolazione diversa.');
        }

        // G2 guardrail is applied later in the question creation loop
        // where cluster context is available for contextual fallbacks.
        results.add({
          'question': _stripLatex(question),
          'breadcrumbs': breadcrumbs.take(3).map(_stripLatex).toList(),
        });
      }
    }
    
    return results;
  }

  /// 🛡️ Apply G2 guardrail filter to a question (A2-04 → A2-06).
  ///
  /// If the question contains prohibited patterns (declarations,
  /// explanations, definitions, direct answers), it is replaced
  /// with a safe fallback. Minor issues (missing "?") are auto-corrected.
  String _applyG2Filter(String question, [String clusterTopic = '']) {
    final result = SocraticOutputFilter.scanQuestion(question);

    if (result.passed) return question;

    // Try auto-correction first (e.g. missing "?").
    final corrected = SocraticOutputFilter.tryAutoCorrect(result);
    if (corrected != null) return corrected;

    // Violation too severe — use contextual fallback (A2-05).
    debugPrint('🛡️ G2: replacing violated question with fallback');
    return SocraticOutputFilter.fallbackForCluster(clusterTopic);
  }

  // Cached regex for LaTeX stripping (O9 optimization).
  static final _latexDelimiters = RegExp(r'\$\$|\$|\\[()\[\]]');

  /// Strip LaTeX delimiters from text for plain-text display.
  /// Converts "$F=ma$" → "F=ma", "$$E=mc^2$$" → "E=mc^2"
  String _stripLatex(String text) => text.replaceAll(_latexDelimiters, '').trim();

  /// Map recall level to question type (P3-13).
  SocraticQuestionType _questionTypeForRecall(int recall) {
    if (recall <= 2) return SocraticQuestionType.lacuna;  // O4: merged branches
    if (recall == 3) return SocraticQuestionType.challenge;
    if (recall == 4) return SocraticQuestionType.depth;
    return SocraticQuestionType.transfer; // recall 5
  }

  /// Fallback questions when AI is unavailable (O3: unified, removed duplicate).
  /// [topic] provides cluster context to make the question specific.
  String _fallbackQuestion(SocraticQuestionType type, [String topic = '']) {
    final t = topic.isNotEmpty ? '"$topic"' : 'questo argomento';
    return switch (type) {
      SocraticQuestionType.lacuna =>
        'Cosa manca nella tua comprensione di $t? Riesci a collegare i concetti?',
      SocraticQuestionType.challenge =>
        'Sei sicuro di aver compreso correttamente $t? Cosa accadrebbe se la tua assunzione fosse sbagliata?',
      SocraticQuestionType.depth =>
        'Riguardo a $t, puoi spiegare il *perché* e non solo il *cosa*?',
      SocraticQuestionType.transfer =>
        '$t ti ricorda qualcosa che hai studiato in un altro ambito?',
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONFIDENCE (P3-17)
  // ─────────────────────────────────────────────────────────────────────────

  /// Set the confidence level (1-5) for the active question.
  void setConfidence(int level) {
    final q = _session?.activeQuestion;
    if (q == null) return;
    if (q.status != SocraticBubbleStatus.active &&
        q.status != SocraticBubbleStatus.awaitingConfidence) return;

    // A3: immutable update via copyWith.
    _session!.replaceActive(q.copyWith(
      confidence: level.clamp(1, 5),
      status: SocraticBubbleStatus.awaitingAnswer,
    ));
    _bump();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ANSWER EVALUATION (P3-17 → P3-23)
  // ─────────────────────────────────────────────────────────────────────────

  /// Record the student's self-evaluation result.
  ///
  /// [recalled] — true if the student believes they answered correctly.
  void recordResult({required bool recalled}) {
    final q = _session?.activeQuestion;
    if (q == null) return;

    final confidence = q.confidence ?? 3;
    final now = DateTime.now();

    SocraticBubbleStatus newStatus;
    bool hyper = false;

    if (recalled) {
      // Correct answer.
      newStatus = confidence >= 4
          ? SocraticBubbleStatus.correct
          : SocraticBubbleStatus.correctLowConf;
      _session!.consecutiveCorrect++;
      _session!.consecutiveWrong = 0;
    } else {
      // Wrong answer.
      if (confidence >= 4) {
        // 🔴 HYPERCORRECTION EVENT (P3-21, P3-23).
        newStatus = SocraticBubbleStatus.wrongHighConf;
        hyper = true;
      } else {
        newStatus = SocraticBubbleStatus.wrongLowConf;
      }
      _session!.consecutiveWrong++;
      _session!.consecutiveCorrect = 0;
    }

    // A3: immutable update via copyWith.
    _session!.replaceActive(q.copyWith(
      status: newStatus,
      isHypercorrection: hyper,
      answeredAt: now,
    ));

    // O1: Update session counters.
    _session!.recordOutcome(newStatus, isHypercorrection: hyper);

    // ZPD adaptation (P3-14): adjust next question type based on sliding window.
    _adaptZPD();

    debugPrint('🔶 Socratic recordResult: activeIndex=${_session!.activeIndex}'
        ' queue.length=${_session!.queue.length}'
        ' totalAnswered=${_session!.totalAnswered}'
        ' maxQuestions=${_session!.maxQuestions}'
        ' isComplete=${_session!.isComplete}');

    _bump();
  }

  /// Mark the active question as "below ZPD" (P3-27, P3-28).
  void markBelowZPD() {
    final q = _session?.activeQuestion;
    if (q == null) return;
    // A3: immutable update via copyWith.
    _session!.replaceActive(q.copyWith(
      status: SocraticBubbleStatus.belowZPD,
      answeredAt: DateTime.now(),
    ));
    _session!.recordOutcome(SocraticBubbleStatus.belowZPD);
    _bump();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BREADCRUMBS (P3-24 → P3-29)
  // ─────────────────────────────────────────────────────────────────────────

  /// Request the next breadcrumb for the active question.
  ///
  /// Returns the breadcrumb text, or null if all 3 have been used.
  String? requestBreadcrumb() {
    final q = _session?.activeQuestion;
    if (q == null) return null;
    if (q.breadcrumbsUsed >= 3) return null;
    if (q.breadcrumbs.isEmpty) return null;

    final idx = q.breadcrumbsUsed;
    if (idx >= q.breadcrumbs.length) return null;

    // A3: immutable update via copyWith.
    _session!.replaceActive(q.copyWith(
      breadcrumbsUsed: q.breadcrumbsUsed + 1,
    ));
    _bump();
    return q.breadcrumbs[idx];
  }

  /// Whether more breadcrumbs are available for the active question.
  bool get canRequestBreadcrumb {
    final q = _session?.activeQuestion;
    if (q == null) return false;
    return q.breadcrumbsUsed < 3 && q.breadcrumbs.isNotEmpty;
  }



  // ─────────────────────────────────────────────────────────────────────────
  // NAVIGATION (P3-11, P3-15)
  // ─────────────────────────────────────────────────────────────────────────

  /// Move to the next question (P3-11: one at a time).
  void next() {
    if (_session == null) return;
    _session!.activeIndex++;

    // Skip resolved questions.
    while (_session!.activeIndex < _session!.queue.length &&
           _session!.queue[_session!.activeIndex].isResolved) {
      _session!.activeIndex++;
    }

    if (_session!.isComplete) {
      // Session complete — no more questions.
    }

    _bump();
  }

  /// Skip the current question (P3-15).
  void skip() {
    final q = _session?.activeQuestion;
    if (q == null) return;
    // A3: immutable update via copyWith.
    _session!.replaceActive(q.copyWith(
      status: SocraticBubbleStatus.skipped,
      answeredAt: DateTime.now(),
    ));
    _session!.recordOutcome(SocraticBubbleStatus.skipped);
    next();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ZPD ADAPTATION (P3-14)
  // ─────────────────────────────────────────────────────────────────────────

  void _adaptZPD() {
    final s = _session;
    if (s == null) return;

    // If 3 consecutive correct → try to upgrade next question type.
    if (s.consecutiveCorrect >= 3) {
      final nextIdx = s.activeIndex + 1;
      if (nextIdx < s.queue.length) {
        final nextQ = s.queue[nextIdx];
        final upgraded = _upgradeType(nextQ.type);
        if (upgraded != nextQ.type) {
          // O12 + A3: Preserve AI text, only change type metadata.
          s.replaceQuestion(nextIdx, nextQ.copyWith(type: upgraded));
        }
      }
    }

    // If 2 consecutive wrong → try to downgrade next question type.
    if (s.consecutiveWrong >= 2) {
      final nextIdx = s.activeIndex + 1;
      if (nextIdx < s.queue.length) {
        final nextQ = s.queue[nextIdx];
        final downgraded = _downgradeType(nextQ.type);
        if (downgraded != nextQ.type) {
          // O12 + A3: Preserve AI text, only change type metadata.
          s.replaceQuestion(nextIdx, nextQ.copyWith(type: downgraded));
        }
      }
    }
  }

  SocraticQuestionType _upgradeType(SocraticQuestionType type) {
    return switch (type) {
      SocraticQuestionType.lacuna    => SocraticQuestionType.challenge,
      SocraticQuestionType.challenge => SocraticQuestionType.depth,
      SocraticQuestionType.depth     => SocraticQuestionType.transfer,
      SocraticQuestionType.transfer  => SocraticQuestionType.transfer,
    };
  }

  SocraticQuestionType _downgradeType(SocraticQuestionType type) {
    return switch (type) {
      SocraticQuestionType.transfer  => SocraticQuestionType.depth,
      SocraticQuestionType.depth     => SocraticQuestionType.challenge,
      SocraticQuestionType.challenge => SocraticQuestionType.lacuna,
      SocraticQuestionType.lacuna    => SocraticQuestionType.lacuna,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SESSION LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether the session is complete.
  bool get isComplete => _session?.isComplete ?? false;

  /// Summary text for display.
  /// Summary text for display (debug only — UI should use L10n).
  String get summaryText {
    final s = _session;
    if (s == null) return '';
    final parts = <String>[];
    if (s.totalCorrect > 0) parts.add('✅ ${s.totalCorrect}');
    if (s.totalWrong > 0) parts.add('❌ ${s.totalWrong}');
    if (s.totalHypercorrections > 0) parts.add('⚡ ${s.totalHypercorrections}');
    if (s.totalSkipped > 0) parts.add('⏭️ ${s.totalSkipped}');
    return parts.join(' · ');
  }

  /// All questions in the current session (for overlay rendering).
  List<SocraticQuestion> get allQuestions => _session?.queue ?? const [];

  /// End the session early.
  void endSession() {
    // Skip all remaining unanswered questions (A3: immutable update).
    if (_session != null) {
      for (int i = 0; i < _session!.queue.length; i++) {
        final q = _session!.queue[i];
        if (!q.isResolved) {
          _session!.replaceQuestion(i, q.copyWith(
            status: SocraticBubbleStatus.skipped,
          ));
        }
      }
    }
    _bump();
  }

  /// Dismiss and deactivate.
  void dismiss() {
    // 📊 Emit completion before clearing session state.
    final session = _session;
    final startedAt = _sessionStartedAt;
    if (session != null && startedAt != null) {
      _telemetry.logEvent('step_3_socratic_completed', properties: {
        'questions_answered': session.totalAnswered,
        'questions_correct': session.totalCorrect,
        'questions_wrong': session.totalWrong,
        'duration_sec':
            DateTime.now().difference(startedAt).inSeconds,
      });
    }

    _session = null;
    _sessionStartedAt = null;
    _isActive = false;
    _isGenerating = false;
    SocraticOutputFilter.clearLog(); // O8: prevent memory leak
    _bump();
  }

  /// Get list of cluster IDs with hypercorrection marks (P3-23).
  Set<String> get hypercorrectionClusterIds {
    if (_session == null) return const {};
    return _session!.queue
        .where((q) => q.isHypercorrection)
        .map((q) => q.clusterId)
        .toSet();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNALS
  // ─────────────────────────────────────────────────────────────────────────

  void _bump() {
    version.value++;
    notifyListeners();
  }
}
