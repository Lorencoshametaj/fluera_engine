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

// ============================================================================
// QUESTION TYPE (P3-09 → P3-13)
// ============================================================================

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
  );

  /// Whether this question has been resolved (answered, skipped, or below ZPD).
  bool get isResolved =>
      status != SocraticBubbleStatus.active &&
      status != SocraticBubbleStatus.awaitingConfidence &&
      status != SocraticBubbleStatus.awaitingAnswer;

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
  };
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
    'totalAnswered': totalAnswered,
    'totalCorrect': totalCorrect,
    'totalHypercorrections': totalHypercorrections,
  };
}
