// ============================================================================
// 🚦 STEP GATE CONTROLLER — Prerequisite state machine for 12-step workflow
//
// Implements Appendix A15 of the specifica implementativa:
// - Soft gates: informative message + "Procedi comunque" (1× per session)
// - Hard gates: step not activatable, clear explanation
// - Per-zone step history with completion tracking
// - Suggested next step algorithm
//
// Philosophy (A15.1): Fluera NEVER blocks the student. Soft gates advise,
// the student decides (Autonomy T2).
//
// This controller is pure logic — no UI, no BuildContext, no KeyValueStore.
// Persistence is handled by the consumer (canvas screen).
// ============================================================================

import 'learning_step_controller.dart';

/// Result of evaluating a step prerequisite gate.
class StepGateResult {
  /// The type of gate encountered.
  final StepGateType type;

  /// Informative message for the student (Italian).
  /// Null for [StepGateType.open] and [StepGateType.automatic].
  final String? message;

  /// Label for the bypass button (soft gates only).
  /// Null for non-soft gates.
  final String? proceedLabel;

  /// Whether the student can proceed to this step.
  /// `false` only for [StepGateType.hard].
  bool get canProceed => type != StepGateType.hard;

  const StepGateResult._({
    required this.type,
    this.message,
    this.proceedLabel,
  });

  /// No gate — step is available without any message.
  const StepGateResult.open()
      : type = StepGateType.open,
        message = null,
        proceedLabel = null;

  /// Soft gate — show message once per session, student can bypass.
  const StepGateResult.soft({
    required String message,
    String proceedLabel = 'Procedi comunque',
  }) : this._(
          type: StepGateType.soft,
          message: message,
          proceedLabel: proceedLabel,
        );

  /// Hard gate — step not available, explain why.
  const StepGateResult.hard({required String message})
      : this._(type: StepGateType.hard, message: message);

  /// Automatic step — no user action needed.
  const StepGateResult.automatic()
      : type = StepGateType.automatic,
        message = null,
        proceedLabel = null;
}

/// Type of gate for a learning step.
enum StepGateType {
  /// 🟢 Always available — no message, no gate.
  open,

  /// 🟡 Soft (recommended) — informative message + "Procedi comunque".
  soft,

  /// 🔴 Hard (blocking) — step not activatable.
  hard,

  /// ⚪ Automatic — system manages in background.
  automatic,
}

/// Completion record for a single step in a zone.
class StepRecord {
  /// How many times this step was completed in this zone.
  final int completedCount;

  /// When the step was last completed (null if never).
  final DateTime? lastCompleted;

  const StepRecord({
    this.completedCount = 0,
    this.lastCompleted,
  });

  /// Create a record with one more completion.
  StepRecord increment() => StepRecord(
        completedCount: completedCount + 1,
        lastCompleted: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'completedCount': completedCount,
        if (lastCompleted != null)
          'lastCompleted': lastCompleted!.millisecondsSinceEpoch,
      };

  factory StepRecord.fromJson(Map<String, dynamic> json) => StepRecord(
        completedCount: (json['completedCount'] as num?)?.toInt() ?? 0,
        lastCompleted: json['lastCompleted'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (json['lastCompleted'] as num).toInt())
            : null,
      );
}

/// Context data needed to evaluate step prerequisites.
///
/// The canvas screen populates this from its current state before
/// calling [StepGateController.evaluateGate].
class ZoneContext {
  /// Number of content nodes in the zone (for Step 2 gate: ≥5 required).
  final int nodeCount;

  /// Number of Socratic questions answered (for Step 4 gate: ≥3 required).
  final int socraticQuestionsAnswered;

  /// When the student last did Step 1 or 2 (for Step 6 gate: ≥24h ago).
  final DateTime? lastStep1Or2;

  /// Whether the device has internet (for Step 7 hard gate).
  final bool hasInternet;

  /// Number of SRS nodes due today (for Step 8 hard gate: ≥1 required).
  final int dueNodeCount;

  /// Next scheduled review date (for Step 8 message).
  final DateTime? nextReviewDate;

  /// Number of zones with ≥10 nodes (for Step 9 gate: ≥2 required).
  final int zonesWithEnoughNodes;

  /// Ratio of nodes at Stage ≥2 (for Step 10 gate: ≥0.5 required).
  final double stageGte2Ratio;

  const ZoneContext({
    this.nodeCount = 0,
    this.socraticQuestionsAnswered = 0,
    this.lastStep1Or2,
    this.hasInternet = true,
    this.dueNodeCount = 0,
    this.nextReviewDate,
    this.zonesWithEnoughNodes = 0,
    this.stageGte2Ratio = 0.0,
  });
}

/// 🚦 Controller for step prerequisite gates (A15).
///
/// Evaluates whether a learning step can be activated in a zone,
/// tracks per-zone step completion history, and computes the
/// suggested next step.
///
/// **Usage:**
/// ```dart
/// final gate = _stepGateController.evaluateGate(
///   LearningStep.step4GhostMap,
///   context: zoneContext,
/// );
/// if (gate.type == StepGateType.soft && !_stepGateController.wasGateShownThisSession(step)) {
///   showSnackBar(gate.message!, action: gate.proceedLabel!);
///   _stepGateController.markGateShown(step);
/// }
/// ```
class StepGateController {
  /// Per-zone step history keyed by step name.
  final Map<String, StepRecord> _stepHistory;

  /// Set of step names whose soft gate was already shown this session.
  /// Cleared on new session (controller recreation).
  final Set<String> _gatesShownThisSession = {};

  /// Create a gate controller with optional pre-loaded history.
  StepGateController({
    Map<String, StepRecord>? stepHistory,
  }) : _stepHistory = stepHistory ?? {};

  // ─────────────────────────────────────────────────────────────────────────
  // GATE EVALUATION (A15.2)
  // ─────────────────────────────────────────────────────────────────────────

  /// Evaluate the prerequisite gate for [step] given the current [context].
  ///
  /// Returns a [StepGateResult] indicating whether the step is open,
  /// requires a soft warning, is hard-blocked, or is automatic.
  StepGateResult evaluateGate(
    LearningStep step, {
    required ZoneContext context,
  }) {
    switch (step) {
      // ── Step 1: Always open ──────────────────────────────────────────
      case LearningStep.step1Notes:
        return const StepGateResult.open();

      // ── Step 2: Zone must have ≥5 nodes ─────────────────────────────
      case LearningStep.step2Recall:
        if (context.nodeCount < 5) {
          return const StepGateResult.soft(
            message:
                'Questa zona ha pochi appunti. Vuoi prima scrivere di più?',
          );
        }
        return const StepGateResult.open();

      // ── Step 3: Step 2 completed ≥1 time in zone ────────────────────
      case LearningStep.step3Socratic:
        final step2 = _stepHistory[LearningStep.step2Recall.name];
        if (step2 == null || step2.completedCount < 1) {
          return const StepGateResult.soft(
            message:
                'Ti consiglio prima di provare a ricostruire dalla memoria '
                '(Passo 2). Vuoi procedere comunque?',
          );
        }
        return const StepGateResult.open();

      // ── Step 4: ≥3 Socratic questions answered ──────────────────────
      case LearningStep.step4GhostMap:
        if (context.socraticQuestionsAnswered < 3) {
          return const StepGateResult.soft(
            message:
                'L\'IA non ti ha ancora interrogato su questa zona. '
                'Il confronto sarà più utile dopo l\'interrogazione. Procedere?',
          );
        }
        return const StepGateResult.open();

      // ── Step 5: Automatic (time passes) ─────────────────────────────
      case LearningStep.step5Consolidation:
        return const StepGateResult.automatic();

      // ── Step 6: ≥24h since last Step 1/2 ────────────────────────────
      case LearningStep.step6SrsBlur:
        if (context.lastStep1Or2 != null) {
          final hoursSince =
              DateTime.now().difference(context.lastStep1Or2!).inHours;
          if (hoursSince < 24) {
            return StepGateResult.soft(
              message:
                  'Sono passate solo ${hoursSince}h. Il ripasso è più efficace '
                  'dopo almeno 24h di pausa. Vuoi procedere comunque?',
            );
          }
        }
        return const StepGateResult.open();

      // ── Step 7: ≥1 Step 2 completed + internet ──────────────────────
      case LearningStep.step7PeerReview:
        if (!context.hasInternet) {
          return const StepGateResult.hard(
            message: 'Connessione internet necessaria per la collaborazione.',
          );
        }
        final step2 = _stepHistory[LearningStep.step2Recall.name];
        if (step2 == null || step2.completedCount < 1) {
          return const StepGateResult.soft(
            message:
                'La collaborazione richiede che tu abbia già fatto almeno '
                'un ripasso. Vuoi procedere comunque?',
          );
        }
        return const StepGateResult.open();

      // ── Step 8: ≥1 SRS node due today ───────────────────────────────
      case LearningStep.step8SrsReturns:
        if (context.dueNodeCount < 1) {
          final nextDate = context.nextReviewDate;
          final dateStr = nextDate != null
              ? '${nextDate.day}/${nextDate.month}/${nextDate.year}'
              : 'non determinata';
          return StepGateResult.hard(
            message:
                'Non ci sono nodi da ripassare oggi. '
                'Il prossimo ripasso è previsto per $dateStr.',
          );
        }
        return const StepGateResult.open();

      // ── Step 9: ≥2 zones with ≥10 nodes (cross-domain) ─────────────
      // Deferred: always open until cross-canvas metadata is available.
      case LearningStep.step9CrossDomain:
        if (context.zonesWithEnoughNodes < 2) {
          return const StepGateResult.soft(
            message:
                'I ponti richiedono almeno 2 materie con contenuto '
                'sufficiente. Vuoi procedere comunque?',
          );
        }
        return const StepGateResult.open();

      // ── Step 10: ≥50% nodes at Stage ≥2 ────────────────────────────
      case LearningStep.step10FogOfWar:
        if (context.stageGte2Ratio < 0.5) {
          return const StepGateResult.soft(
            message:
                'Troppi nodi sono ancora fragili. Continua con i ripassi '
                'SRS prima della Fog of War. Vuoi procedere comunque?',
          );
        }
        return const StepGateResult.open();

      // ── Step 11: Always open ────────────────────────────────────────
      case LearningStep.step11ExamSimulation:
        return const StepGateResult.open();

      // ── Step 12: Always open ────────────────────────────────────────
      case LearningStep.step12Permanence:
        return const StepGateResult.open();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ONE-SHOT PER SESSION (A15-02)
  // ─────────────────────────────────────────────────────────────────────────

  /// Check if the soft gate message for [step] was already shown this session.
  bool wasGateShownThisSession(LearningStep step) =>
      _gatesShownThisSession.contains(step.name);

  /// Mark the soft gate for [step] as shown for this session.
  void markGateShown(LearningStep step) =>
      _gatesShownThisSession.add(step.name);

  // ─────────────────────────────────────────────────────────────────────────
  // STEP COMPLETION TRACKING (A15.4)
  // ─────────────────────────────────────────────────────────────────────────

  /// Record that [step] was completed in this zone.
  void recordStepCompletion(LearningStep step) {
    final existing = _stepHistory[step.name] ?? const StepRecord();
    _stepHistory[step.name] = existing.increment();
  }

  /// How many times [step] was completed in this zone.
  int completionCount(LearningStep step) =>
      _stepHistory[step.name]?.completedCount ?? 0;

  /// When [step] was last completed (null if never).
  DateTime? lastCompleted(LearningStep step) =>
      _stepHistory[step.name]?.lastCompleted;

  /// The full step history map (for persistence).
  Map<String, StepRecord> get stepHistory =>
      Map.unmodifiable(_stepHistory);

  // ─────────────────────────────────────────────────────────────────────────
  // SUGGESTED NEXT STEP (A15-04)
  // ─────────────────────────────────────────────────────────────────────────

  /// Calculate the suggested next step in the 1→12 progression.
  ///
  /// Returns the lowest-numbered step that hasn't been completed yet,
  /// skipping automatic steps (5) and hard-blocked steps.
  /// If all steps have been completed at least once, returns the step
  /// with the oldest `lastCompleted` (needs refresh).
  LearningStep suggestedNextStep({required ZoneContext context}) {
    // Priority 1: First uncompleted step in order.
    for (final step in LearningStep.values) {
      // Skip automatic steps (Step 5 = consolidation, managed by system).
      if (step == LearningStep.step5Consolidation) continue;

      final record = _stepHistory[step.name];
      if (record == null || record.completedCount == 0) {
        // Check if it's hard-blocked — don't suggest hard-blocked steps.
        final gate = evaluateGate(step, context: context);
        if (gate.type != StepGateType.hard) {
          return step;
        }
      }
    }

    // Priority 2: All completed — suggest the one with oldest lastCompleted.
    LearningStep? oldestStep;
    DateTime? oldestDate;

    for (final step in LearningStep.values) {
      if (step == LearningStep.step5Consolidation) continue;

      final record = _stepHistory[step.name];
      if (record == null) continue;

      final gate = evaluateGate(step, context: context);
      if (gate.type == StepGateType.hard) continue;

      if (oldestDate == null ||
          (record.lastCompleted != null &&
              record.lastCompleted!.isBefore(oldestDate))) {
        oldestStep = step;
        oldestDate = record.lastCompleted;
      }
    }

    return oldestStep ?? LearningStep.step1Notes;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP AVAILABILITY STATUS (A15-03, for toolbar icons)
  // ─────────────────────────────────────────────────────────────────────────

  /// Get the availability status of [step] for toolbar icon rendering.
  ///
  /// Returns one of:
  /// - [StepGateType.open]: full icon (available)
  /// - [StepGateType.soft]: faded icon (soft gate)
  /// - [StepGateType.hard]: grey icon with lock (hard gate)
  /// - [StepGateType.automatic]: hidden (system-managed)
  StepGateType stepAvailability(
    LearningStep step, {
    required ZoneContext context,
  }) =>
      evaluateGate(step, context: context).type;

  // ─────────────────────────────────────────────────────────────────────────
  // SERIALIZATION (for KeyValueStore persistence)
  // ─────────────────────────────────────────────────────────────────────────

  /// Serialize step history to JSON (for persistence).
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    for (final entry in _stepHistory.entries) {
      map[entry.key] = entry.value.toJson();
    }
    return map;
  }

  /// Create a gate controller from persisted JSON.
  factory StepGateController.fromJson(Map<String, dynamic> json) {
    final history = <String, StepRecord>{};
    for (final entry in json.entries) {
      if (entry.value is Map<String, dynamic>) {
        history[entry.key] =
            StepRecord.fromJson(entry.value as Map<String, dynamic>);
      }
    }
    return StepGateController(stepHistory: history);
  }
}
