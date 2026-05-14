/// 🔶 SOCRATIC SPATIAL — Data models for Socratic interrogation bubbles.
///
/// Spec: P3-09 → P3-46 (Passo 3 — L'Interrogazione Socratica)
///
/// These models represent:
/// - Question types (4 categories from spec §3.2)
/// - Bubble visual status (6 states)
/// - Individual question data (anchor, confidence, breadcrumbs)
/// - Full session tracking with ZPD adaptation metrics
library;

import 'dart:ui';
import 'package:flutter/foundation.dart';

import 'socratic_discipline.dart';

export 'socratic_discipline.dart' show Discipline;

// ============================================================================
// QUESTION TYPE (P3-09 → P3-13)
// ============================================================================

/// 🎭 SocraticStage — pedagogical sequence position in a session (2026-05-12).
///
/// Orthogonal to [SocraticQuestionType]: the type is FSRS-recall-driven and
/// determines breadcrumb gating + legacy fallback selection, while the stage
/// drives the **session-level cognitive trajectory** — which evidence-based
/// pedagogical move the AI should perform for this question slot.
///
/// Pedagogical references for each stage:
///   • [anchor]        — psychological safety + cued retrieval (IJSSPA 2024)
///   • [elaboration]   — Elaborative Interrogation (Dunlosky 2013)
///                       + Self-Explanation (Chi et al. 1994)
///   • [comparative]   — Compare-2-with-1-saliente-diff (Rittle-Johnson &
///                       Star 2017)
///   • [counterfactual] — Desirable difficulty (Bjork 2011) +
///                        misconception probe (Hestenes FCI 1992)
///   • [application]   — Bloom apply/create (Anderson & Krathwohl 2001),
///                       case-concrete obligatorio
///   • [interleave]    — Cross-concept retrieval (Bjork's interleaving)
///   • [metacognitive] — Session close, knowledge calibration
enum SocraticStage {
  anchor,
  elaboration,
  comparative,
  counterfactual,
  application,
  interleave,
  metacognitive,
}

/// 🎓 Discipline — inferred from cluster content. Used to tune question
/// stems to the way professors in that field actually interrogate, and
/// to scope the misconception library (e.g. Hestenes FCI for physics,
/// Lamarckian inheritance for biology).
///
/// [generic] is the graceful-degradation fallback when the discipline
/// signal is ambiguous (e.g. interdisciplinary canvas). When generic,
/// the prompt's discipline-specific section is skipped and misconception
/// injection is suppressed.
// Discipline enum moved to socratic_discipline.dart (pure-Dart, no
// flutter/dart:ui import) and re-exported via `export` at the top of
// this file. Callers that use `Discipline` here keep working unchanged.

/// The 4 types of Socratic questions, each activated by a different principle.
enum SocraticQuestionType {
  /// Tipo A — Domanda di Lacuna.
  /// "Vedo che hai scritto sulla termodinamica, ma manca qualcosa..."
  /// Used for: recall 1-2 (missed nodes).
  /// Principle: Active Recall §2, Zeigarnik §7.
  lacuna,

  /// Tipo B — Domanda di Sfida.
  /// "Sei sicuro che A causi B? E se fosse il contrario?"
  /// Used for: nodes with potentially wrong connections.
  /// Principle: Ipercorrezione §4, Desirable Difficulties §5.
  challenge,

  /// Tipo C — Domanda di Profondità.
  /// "Puoi spiegare *perché* questo è vero, non solo *che cosa* è?"
  /// Used for: recall ≥4 (student "knows" but maybe superficially).
  /// Principle: Levels of Processing §6, Elaborazione.
  depth,

  /// Tipo D — Domanda di Transfer.
  /// "Questo principio ti ricorda qualcosa in un'altra materia?"
  /// Used for: mastered nodes — to create cross-domain bridges.
  /// Principle: Transfer T3, Interleaving §10.
  transfer,
}

// ============================================================================
// BUBBLE STATUS (P3-20, P3-21, P3-30)
// ============================================================================

/// Visual state of a Socratic question bubble on the canvas.
enum SocraticBubbleStatus {
  /// 🟠 Domanda aperta — pulsazione ambra.
  active,

  /// ⏳ Waiting for confidence declaration before answer (P3-17).
  awaitingConfidence,

  /// ✍️ Student is writing answer on canvas (P3-18).
  awaitingAnswer,

  /// 🤔 V2 multi-turn: after confidence, awaits "Penso solo" / "Schizzo".
  awaitingTurnMode,

  /// ✏️ V2 multi-turn: scratchpad panel open, student is sketching.
  awaitingSketch,

  /// 🌀 V2 multi-turn: sketch submitted, AI is generating next-turn question.
  generatingFollowUp,

  /// 🧘 V2 multi-turn: aporetic turn emitted, awaiting 3-state reflection.
  awaitingReflection,

  /// 🟢 Risposta corretta — bordo verde.
  correct,

  /// 🟢 Corretta + bassa confidenza — verde chiaro.
  correctLowConf,

  /// 🟡 Errore + bassa confidenza — ambra (lacuna nota).
  wrongLowConf,

  /// 🔴 Errore + ALTA confidenza — SHOCK ipercorrezione (P3-21).
  wrongHighConf,

  /// ⬜ Dismissata senza risposta (P3-15).
  skipped,

  /// ⬛ Fuori dalla ZPD — grigio scuro (P3-27, P3-28).
  belowZPD,
}

// ============================================================================
// MULTI-TURN MODEL (V2 — dialogue mode)
// ============================================================================

/// Role of a turn in a multi-turn Socratic dialogue.
///
/// Each `SocraticQuestion` carries 1-3 turns:
///   • [initial] — the original AI question (turn 0)
///   • [followUp] — AI-generated mid-dialogue question (turn 1) anchored
///     to a concept in the student's sketch. NEVER evaluates correctness.
///   • [aporetic] — AI-generated final question (turn 2). Exposes a
///     contradiction or edge case; closes with "tienila in testa".
///
/// Cap: max one follow-up + one aporetic per question (3 turns total).
enum SocraticTurnRole { initial, followUp, aporetic }

/// 3-state self-evaluation outcome at the end of a multi-turn dialogue.
///
/// Replaces the binary "Ricordo / Non ricordo" of the legacy single-turn
/// path. Each outcome maps to a different FSRS `stability` bump:
///   • [thinking]   → +0.5 (engagement signal, but unresolved)
///   • [uncertain]  → +1.0 (productive struggle = strongest learning)
///   • [satisfied]  → +2.0 (consolidation)
enum SocraticReflectionOutcome {
  /// 💡 "Mi viene da pensare" — il dialogo ha generato nuove domande.
  thinking,

  /// 🤔 "Mi è venuto il dubbio" — aporia raggiunta, modello mentale
  /// destabilizzato (segnale pedagogicamente forte).
  uncertain,

  /// 😌 "Sono soddisfatto" — comprensione consolidata.
  satisfied,
}

/// A single turn within a multi-turn Socratic dialogue. Strokes are
/// ephemeral (scratchpad is isolated and discarded on confirm); only
/// the OCR'd text is preserved in [sketchOcr] for conversational
/// history and the AI follow-up prompt.
@immutable
class SocraticTurn {
  final int index;
  final SocraticTurnRole role;

  /// AI-generated question for this turn.
  final String question;

  /// OCR text from the student's sketch, or `null` if the student
  /// chose "Penso solo" (no sketch path).
  final String? sketchOcr;

  final DateTime timestamp;

  const SocraticTurn({
    required this.index,
    required this.role,
    required this.question,
    this.sketchOcr,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'role': role.name,
        'question': question,
        'sketchOcr': sketchOcr,
        'timestamp': timestamp.toIso8601String(),
      };

  factory SocraticTurn.fromJson(Map<String, dynamic> j) => SocraticTurn(
        index: (j['index'] as num?)?.toInt() ?? 0,
        role: SocraticTurnRole.values.firstWhere(
          (r) => r.name == j['role'],
          orElse: () => SocraticTurnRole.initial,
        ),
        question: j['question'] as String? ?? '',
        sketchOcr: j['sketchOcr'] as String?,
        timestamp:
            DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
      );
}

// ============================================================================
// QUESTION DATA
// ============================================================================

/// Individual Socratic question data.
///
/// A3: Immutable — state transitions use [copyWith].
@immutable
class SocraticQuestion {
  final String id;

  /// Cluster ID this question is anchored to.
  final String clusterId;

  /// Canvas-space position for anchoring (cluster centroid).
  final Offset anchorPosition;

  /// Question type (A/B/C/D).
  final SocraticQuestionType type;

  /// Question text from Atlas AI.
  final String text;

  /// Current visual status.
  final SocraticBubbleStatus status;

  /// Confidence level declared by student (1-5) before answering (P3-17).
  /// Null until declared.
  final int? confidence;

  /// Number of breadcrumbs used (0-3) (P3-24 → P3-26).
  final int breadcrumbsUsed;

  /// Breadcrumb hints from AI, unlocked progressively (P3-25).
  /// Index 0 = L'Eco Lontano, 1 = Il Sentiero, 2 = La Soglia.
  final List<String> breadcrumbs;

  /// Timestamp when answered.
  final DateTime? answeredAt;

  /// Whether this was a hypercorrection event (P3-21, P3-23).
  /// True if: confidence ≥ 4 AND answer was wrong.
  final bool isHypercorrection;

  /// Recall level from Recall Mode (1-5), if available.
  final int? recallLevel;

  /// V2 multi-turn dialogue: ordered list of turns. `turns[0]` is always
  /// the initial question (mirrors [text]). Follow-up + aporetic turns
  /// are appended as the student engages with the sketch path.
  ///
  /// Legacy "Penso solo" path → [turns] stays at length 1.
  /// Full multi-turn path     → length 3 (initial + followUp + aporetic).
  final List<SocraticTurn> turns;

  /// V2 multi-turn: the 3-state reflection chosen at end of dialogue.
  /// `null` until the student picks one. When non-null, the legacy
  /// `status`-based [wasCorrect]/[wasWrong] do NOT apply — FSRS scoring
  /// uses [finalReflection] instead (see `_persistSocraticToFSRS`).
  final SocraticReflectionOutcome? finalReflection;

  /// V2 multi-turn: true once the aporetic turn (final) has been emitted
  /// for this question. The UI uses this to hide the "Schizzo" button
  /// and show only the reflection picker.
  final bool isAporeticClosed;

  /// 🎭 Pedagogical stage this question was emitted at (2026-05-12).
  /// `null` for legacy / pre-redesign questions deserialized from disk.
  final SocraticStage? stage;

  /// 🎓 Discipline inferred for the BATCH this question belongs to.
  /// `null` for legacy / pre-redesign. All questions in one batch share
  /// the same discipline (computed once per session).
  final Discipline? discipline;

  /// 🧠 ID of the misconception injected for this slot (if any).
  /// Non-null only for counterfactual-stage questions that received a
  /// hint from [pickMisconceptionFor]. Used for telemetry + dedup
  /// across sessions.
  final String? misconceptionId;

  const SocraticQuestion({
    required this.id,
    required this.clusterId,
    required this.anchorPosition,
    required this.type,
    required this.text,
    this.status = SocraticBubbleStatus.active,
    this.confidence,
    this.breadcrumbsUsed = 0,
    this.breadcrumbs = const [],
    this.answeredAt,
    this.isHypercorrection = false,
    this.recallLevel,
    this.turns = const [],
    this.finalReflection,
    this.isAporeticClosed = false,
    this.stage,
    this.discipline,
    this.misconceptionId,
  });

  /// Create a copy with modified fields (A3: immutable state transitions).
  SocraticQuestion copyWith({
    SocraticBubbleStatus? status,
    int? confidence,
    int? breadcrumbsUsed,
    List<String>? breadcrumbs,
    DateTime? answeredAt,
    bool? isHypercorrection,
    SocraticQuestionType? type,
    String? text,
    List<SocraticTurn>? turns,
    SocraticReflectionOutcome? finalReflection,
    bool? isAporeticClosed,
    SocraticStage? stage,
    Discipline? discipline,
    String? misconceptionId,
  }) => SocraticQuestion(
    id: id,
    clusterId: clusterId,
    anchorPosition: anchorPosition,
    type: type ?? this.type,
    text: text ?? this.text,
    status: status ?? this.status,
    confidence: confidence ?? this.confidence,
    breadcrumbsUsed: breadcrumbsUsed ?? this.breadcrumbsUsed,
    breadcrumbs: breadcrumbs ?? this.breadcrumbs,
    answeredAt: answeredAt ?? this.answeredAt,
    isHypercorrection: isHypercorrection ?? this.isHypercorrection,
    recallLevel: recallLevel,
    turns: turns ?? this.turns,
    finalReflection: finalReflection ?? this.finalReflection,
    isAporeticClosed: isAporeticClosed ?? this.isAporeticClosed,
    stage: stage ?? this.stage,
    discipline: discipline ?? this.discipline,
    misconceptionId: misconceptionId ?? this.misconceptionId,
  );

  /// Whether this question has been resolved (answered, skipped, or below ZPD).
  bool get isResolved =>
      status != SocraticBubbleStatus.active &&
      status != SocraticBubbleStatus.awaitingConfidence &&
      status != SocraticBubbleStatus.awaitingAnswer &&
      status != SocraticBubbleStatus.awaitingTurnMode &&
      status != SocraticBubbleStatus.awaitingSketch &&
      status != SocraticBubbleStatus.generatingFollowUp &&
      status != SocraticBubbleStatus.awaitingReflection;

  /// Whether the answer was correct.
  bool get wasCorrect =>
      status == SocraticBubbleStatus.correct ||
      status == SocraticBubbleStatus.correctLowConf;

  /// Whether the answer was wrong.
  bool get wasWrong =>
      status == SocraticBubbleStatus.wrongHighConf ||
      status == SocraticBubbleStatus.wrongLowConf;

  /// Label for the question type (debug/JSON only — UI uses L10n).
  String get typeLabel => type.name;

  Map<String, dynamic> toJson() => {
    'id': id,
    'clusterId': clusterId,
    'anchorX': anchorPosition.dx,
    'anchorY': anchorPosition.dy,
    'type': type.name,
    'text': text,
    'status': status.name,
    'confidence': confidence,
    'breadcrumbsUsed': breadcrumbsUsed,
    'breadcrumbs': breadcrumbs,
    'answeredAt': answeredAt?.toIso8601String(),
    'isHypercorrection': isHypercorrection,
    'recallLevel': recallLevel,
    'turns': turns.map((t) => t.toJson()).toList(),
    'finalReflection': finalReflection?.name,
    'isAporeticClosed': isAporeticClosed,
    'stage': stage?.name,
    'discipline': discipline?.name,
    'misconceptionId': misconceptionId,
  };

  factory SocraticQuestion.fromJson(Map<String, dynamic> j) {
    SocraticQuestionType parseType() {
      final raw = j['type'] as String?;
      return SocraticQuestionType.values.firstWhere(
        (t) => t.name == raw,
        orElse: () => SocraticQuestionType.lacuna,
      );
    }

    SocraticBubbleStatus parseStatus() {
      final raw = j['status'] as String?;
      return SocraticBubbleStatus.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => SocraticBubbleStatus.active,
      );
    }

    final answeredAtRaw = j['answeredAt'] as String?;
    final breadcrumbsRaw = j['breadcrumbs'];
    final breadcrumbs = breadcrumbsRaw is List
        ? breadcrumbsRaw.whereType<String>().toList()
        : const <String>[];
    final turnsRaw = j['turns'];
    final turns = turnsRaw is List
        ? turnsRaw
            .whereType<Map>()
            .map((m) => SocraticTurn.fromJson(m.cast<String, dynamic>()))
            .toList()
        : const <SocraticTurn>[];
    SocraticReflectionOutcome? parseReflection() {
      final raw = j['finalReflection'] as String?;
      if (raw == null) return null;
      for (final r in SocraticReflectionOutcome.values) {
        if (r.name == raw) return r;
      }
      return null;
    }

    SocraticStage? parseStage() {
      final raw = j['stage'] as String?;
      if (raw == null) return null;
      for (final s in SocraticStage.values) {
        if (s.name == raw) return s;
      }
      return null;
    }

    Discipline? parseDiscipline() {
      final raw = j['discipline'] as String?;
      if (raw == null) return null;
      for (final d in Discipline.values) {
        if (d.name == raw) return d;
      }
      return null;
    }

    return SocraticQuestion(
      id: j['id'] as String,
      clusterId: j['clusterId'] as String? ?? '',
      anchorPosition: Offset(
        (j['anchorX'] as num?)?.toDouble() ?? 0.0,
        (j['anchorY'] as num?)?.toDouble() ?? 0.0,
      ),
      type: parseType(),
      text: j['text'] as String? ?? '',
      status: parseStatus(),
      confidence: (j['confidence'] as num?)?.toInt(),
      breadcrumbsUsed: (j['breadcrumbsUsed'] as num?)?.toInt() ?? 0,
      breadcrumbs: breadcrumbs,
      answeredAt: answeredAtRaw != null ? DateTime.parse(answeredAtRaw) : null,
      isHypercorrection: j['isHypercorrection'] as bool? ?? false,
      recallLevel: (j['recallLevel'] as num?)?.toInt(),
      turns: turns,
      finalReflection: parseReflection(),
      isAporeticClosed: j['isAporeticClosed'] as bool? ?? false,
      stage: parseStage(),
      discipline: parseDiscipline(),
      misconceptionId: j['misconceptionId'] as String?,
    );
  }
}

// ============================================================================
// SESSION (P3-14, P3-16)
// ============================================================================

/// Full Socratic interrogation session.
class SocraticSession {
  final String sessionId;
  final DateTime startedAt;

  /// The question queue (P3-12: ordered by recall ascending).
  final List<SocraticQuestion> queue;

  /// Index of the currently active question (P3-11: one at a time).
  int activeIndex;

  /// Sliding window for ZPD adaptation (P3-14).
  /// Consecutive correct → increase difficulty.
  int consecutiveCorrect;

  /// Consecutive wrong → decrease difficulty.
  int consecutiveWrong;

  /// Max questions per session (P3-16: default 8-12).
  final int maxQuestions;

  // ── O(1) incremental counters (O1 optimization) ─────────────────────
  int _totalCorrect = 0;
  int _totalWrong = 0;
  int _totalSkipped = 0;
  int _totalHypercorrections = 0;
  int _totalBelowZPD = 0;

  SocraticSession({
    required this.sessionId,
    required this.queue,
    this.activeIndex = 0,
    this.consecutiveCorrect = 0,
    this.consecutiveWrong = 0,
    this.maxQuestions = 10,
  }) : startedAt = DateTime.now();

  /// Internal — used by [fromCheckpoint] to re-attach the original
  /// `startedAt`. Public ctor always uses `DateTime.now()`.
  SocraticSession._restored({
    required this.sessionId,
    required this.queue,
    required DateTime startedAt,
    this.activeIndex = 0,
    this.consecutiveCorrect = 0,
    this.consecutiveWrong = 0,
    this.maxQuestions = 10,
  }) : startedAt = startedAt;

  /// Restore a session from a checkpoint JSON map. Replays each
  /// question's resolved status to rebuild the O(1) counters
  /// (`_totalCorrect`, etc.) — saves us from also persisting them
  /// (single source of truth = the queue).
  factory SocraticSession.fromCheckpoint(Map<String, dynamic> j) {
    final rawQueue = j['queue'];
    final queue = rawQueue is List
        ? [
            for (final item in rawQueue)
              if (item is Map)
                SocraticQuestion.fromJson(Map<String, dynamic>.from(item)),
          ]
        : <SocraticQuestion>[];

    final startedAtStr = j['startedAt'] as String?;
    final session = SocraticSession._restored(
      sessionId: j['sessionId'] as String,
      queue: queue,
      startedAt: startedAtStr != null
          ? DateTime.parse(startedAtStr)
          : DateTime.now(),
      activeIndex: (j['activeIndex'] as num?)?.toInt() ?? 0,
      consecutiveCorrect: (j['consecutiveCorrect'] as num?)?.toInt() ?? 0,
      consecutiveWrong: (j['consecutiveWrong'] as num?)?.toInt() ?? 0,
      maxQuestions: (j['maxQuestions'] as num?)?.toInt() ?? queue.length,
    );

    // Replay queue statuses to rebuild O(1) counters.
    for (final q in queue) {
      if (!q.isResolved) continue;
      session.recordOutcome(q.status, isHypercorrection: q.isHypercorrection);
    }
    return session;
  }

  /// The currently active question, or null if session is complete.
  SocraticQuestion? get activeQuestion =>
      activeIndex < queue.length ? queue[activeIndex] : null;

  /// A3: Replace a question at [index] with an updated copy.
  void replaceQuestion(int index, SocraticQuestion updated) {
    assert(index >= 0 && index < queue.length);
    assert(queue[index].id == updated.id, 'ID mismatch in replaceQuestion');
    queue[index] = updated;
  }

  /// A3: Replace the active question with an updated copy.
  void replaceActive(SocraticQuestion updated) {
    if (activeIndex < queue.length) replaceQuestion(activeIndex, updated);
  }

  /// Whether the session is complete (all answered/skipped or max reached).
  bool get isComplete =>
      activeIndex >= queue.length ||
      totalAnswered >= maxQuestions;

  // ── O(1) metrics (O1 optimization) ───────────────────────────────────

  int get totalAnswered => _totalCorrect + _totalWrong;
  int get totalCorrect => _totalCorrect;
  int get totalWrong => _totalWrong;
  int get totalSkipped => _totalSkipped;
  int get totalHypercorrections => _totalHypercorrections;
  int get totalBelowZPD => _totalBelowZPD;

  /// Record an outcome — updates incremental counters once.
  /// Called by `SocraticController.recordResult` / `skip` / `markBelowZPD`.
  void recordOutcome(SocraticBubbleStatus status, {bool isHypercorrection = false}) {
    switch (status) {
      case SocraticBubbleStatus.correct:
      case SocraticBubbleStatus.correctLowConf:
        _totalCorrect++;
      case SocraticBubbleStatus.wrongHighConf:
      case SocraticBubbleStatus.wrongLowConf:
        _totalWrong++;
      case SocraticBubbleStatus.skipped:
        _totalSkipped++;
      case SocraticBubbleStatus.belowZPD:
        _totalBelowZPD++;
      default:
        break;
    }
    if (isHypercorrection) _totalHypercorrections++;
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'startedAt': startedAt.toIso8601String(),
    'queue': queue.map((q) => q.toJson()).toList(),
    'activeIndex': activeIndex,
    'consecutiveCorrect': consecutiveCorrect,
    'consecutiveWrong': consecutiveWrong,
    'maxQuestions': maxQuestions,
    // Aggregated counters serialised for telemetry / debug — re-derived
    // from queue statuses on `fromCheckpoint`, not used at restore.
    'totalAnswered': totalAnswered,
    'totalCorrect': totalCorrect,
    'totalHypercorrections': totalHypercorrections,
  };
}

// ============================================================================
// HISTORY (V1.5 maturity sprint — parity with ExamHistoryRecord)
// ============================================================================

/// Per-question snapshot stored inside a history record. Captured at
/// session completion so the dashboard / future review screen can show
/// the question text, the type, the student's outcome, and how many
/// breadcrumbs were spent — without needing to keep the live
/// `SocraticQuestion` (which carries `Offset` and other heavy fields).
@immutable
class SocraticHistoryQuestion {
  final String id;
  final String clusterId;
  final String text;

  /// Question type as `enum.name` ('lacuna' | 'challenge' | 'depth' | 'transfer').
  final String typeName;

  /// Self-declared confidence (1-5) before answering. Null when the
  /// student dismissed the question without setting confidence.
  final int? confidence;

  /// True when the student tapped "ricordo" (correct).
  final bool recalled;

  /// Number of breadcrumbs spent on this question (0-3).
  final int breadcrumbsUsed;

  /// True when this was a hypercorrection event (high conf + wrong).
  final bool isHypercorrection;

  /// Final status as `enum.name`. Useful to distinguish skipped /
  /// belowZPD / wrongHighConf without re-deriving from booleans.
  final String statusName;

  const SocraticHistoryQuestion({
    required this.id,
    required this.clusterId,
    required this.text,
    required this.typeName,
    required this.statusName,
    this.confidence,
    this.recalled = false,
    this.breadcrumbsUsed = 0,
    this.isHypercorrection = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'clusterId': clusterId,
        'text': text,
        'typeName': typeName,
        'statusName': statusName,
        if (confidence != null) 'confidence': confidence,
        if (recalled) 'recalled': true,
        if (breadcrumbsUsed > 0) 'breadcrumbsUsed': breadcrumbsUsed,
        if (isHypercorrection) 'isHypercorrection': true,
      };

  factory SocraticHistoryQuestion.fromJson(Map<String, dynamic> j) {
    return SocraticHistoryQuestion(
      id: j['id'] as String,
      clusterId: j['clusterId'] as String? ?? '',
      text: j['text'] as String? ?? '',
      typeName: j['typeName'] as String? ?? 'lacuna',
      statusName: j['statusName'] as String? ?? 'skipped',
      confidence: (j['confidence'] as num?)?.toInt(),
      recalled: j['recalled'] as bool? ?? false,
      breadcrumbsUsed: (j['breadcrumbsUsed'] as num?)?.toInt() ?? 0,
      isHypercorrection: j['isHypercorrection'] as bool? ?? false,
    );
  }
}

/// Persisted summary of a completed Socratic session. Mirrors the role of
/// `ExamHistoryRecord` — capped list (50) on disk, drives the dashboard
/// "Sessioni Socratic recenti" tile, and unlocks future analytics
/// (hypercorrection trends, breadcrumb usage curves, ZPD progression).
@immutable
class SocraticHistoryRecord {
  final String sessionId;
  final DateTime startedAt;
  final DateTime completedAt;

  final int totalQuestions;
  final int correctCount;
  final int wrongCount;
  final int skippedCount;
  final int hypercorrectionCount;

  /// Cluster IDs probed during the session (deduplicated). Useful when
  /// the future review screen wants to highlight which canvas regions
  /// were exercised.
  final List<String> clusterIds;

  /// Subset of [clusterIds] that triggered a hypercorrection event.
  /// Drives the "ripeti questi concetti" CTA.
  final List<String> hypercorrectionClusterIds;

  /// Total breadcrumbs spent across all questions. A high count vs a
  /// low session score is a useful signal of "not yet ready for
  /// independent recall".
  final int breadcrumbsUsed;

  /// Average confidence across answered questions (1.0-5.0). 0.0 when
  /// no question was answered.
  final double avgConfidence;

  /// Per-question snapshots. Empty when the session was dismissed
  /// before any question was even displayed.
  final List<SocraticHistoryQuestion> questions;

  const SocraticHistoryRecord({
    required this.sessionId,
    required this.startedAt,
    required this.completedAt,
    required this.totalQuestions,
    required this.correctCount,
    required this.wrongCount,
    required this.skippedCount,
    required this.hypercorrectionCount,
    required this.clusterIds,
    required this.hypercorrectionClusterIds,
    required this.breadcrumbsUsed,
    required this.avgConfidence,
    required this.questions,
  });

  /// Score in [0..1] — correct / answered. Mirrors the way the exam
  /// dashboard computes its score-coded color tile.
  double get score {
    final answered = correctCount + wrongCount;
    if (answered == 0) return 0.0;
    return correctCount / answered;
  }

  /// Wall-clock duration of the session.
  Duration get duration => completedAt.difference(startedAt);

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt.toIso8601String(),
        'totalQuestions': totalQuestions,
        'correctCount': correctCount,
        'wrongCount': wrongCount,
        'skippedCount': skippedCount,
        'hypercorrectionCount': hypercorrectionCount,
        'clusterIds': clusterIds,
        'hypercorrectionClusterIds': hypercorrectionClusterIds,
        'breadcrumbsUsed': breadcrumbsUsed,
        'avgConfidence': avgConfidence,
        'questions': questions.map((q) => q.toJson()).toList(),
        'schemaVersion': 1,
      };

  factory SocraticHistoryRecord.fromJson(Map<String, dynamic> j) {
    List<SocraticHistoryQuestion> parseQuestions() {
      final raw = j['questions'];
      if (raw is! List) return const [];
      final out = <SocraticHistoryQuestion>[];
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          out.add(SocraticHistoryQuestion.fromJson(
              Map<String, dynamic>.from(item)));
        } catch (_) {/* skip malformed */}
      }
      return out;
    }

    List<String> parseStringList(dynamic raw) {
      if (raw is! List) return const [];
      return raw.whereType<String>().toList();
    }

    return SocraticHistoryRecord(
      sessionId: j['sessionId'] as String,
      startedAt: DateTime.parse(j['startedAt'] as String),
      completedAt: DateTime.parse(j['completedAt'] as String),
      totalQuestions: (j['totalQuestions'] as num).toInt(),
      correctCount: (j['correctCount'] as num).toInt(),
      wrongCount: (j['wrongCount'] as num).toInt(),
      skippedCount: (j['skippedCount'] as num).toInt(),
      hypercorrectionCount: (j['hypercorrectionCount'] as num?)?.toInt() ?? 0,
      clusterIds: parseStringList(j['clusterIds']),
      hypercorrectionClusterIds:
          parseStringList(j['hypercorrectionClusterIds']),
      breadcrumbsUsed: (j['breadcrumbsUsed'] as num?)?.toInt() ?? 0,
      avgConfidence: (j['avgConfidence'] as num?)?.toDouble() ?? 0.0,
      questions: parseQuestions(),
    );
  }
}
