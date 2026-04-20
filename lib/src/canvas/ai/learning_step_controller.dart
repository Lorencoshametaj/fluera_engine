// ============================================================================
// 🧠 LEARNING STEP CONTROLLER — Cognitive cycle state machine
//
// Manages the 12-step mastery methodology defined in the specifica
// implementativa. Each step gates which engine subsystems are active:
//
//   Step 1 (Notes):     AI dormant, zero-distraction canvas
//   Step 2 (Recall):    AI dormant, hide/reveal mechanics
//   Step 3 (Socratic):  AI active, Socratic prompting
//   Step 4+ :           Progressive AI engagement
//
// This controller lives INSIDE the engine (not the host app) because
// the cognitive cycle is identity-defining for Fluera.
//
// Step names from specifica_implementativa.md:
//   Passo 1  — Appunti a Mano Durante la Lezione
//   Passo 2  — L'Elaborazione Solitaria: Riscrivere Senza Guardare
//   Passo 3  — L'Interrogazione Socratica: L'IA Si Sveglia
//   Passo 4  — Il Confronto Centauro: Lo Specchio Critico
//   Passo 5  — La Notte: Il Consolidamento Offline
//   Passo 6  — Il Primo Ritorno: Active Recall Spaziale con Blur
//   Passo 7  — L'Apprendimento Solidale: Il Confronto tra Pari
//   Passo 8  — I Ritorni SRS: Il Ripasso a Intervalli Crescenti
//   Passo 9  — I Ponti Cross-Dominio: Pensiero Sistemico
//   Passo 10 — La Fog of War: Preparazione all'Esame
//   Passo 11 — L'Esame: Il Canvas nella Testa
//   Passo 12 — Il Canvas Resta e Cresce: Infrastruttura Permanente
// ============================================================================

import 'package:flutter/foundation.dart';

import '../../ai/telemetry_recorder.dart';
import 'passeggiata_controller.dart';
import 'step_transition_choreographer.dart';

/// The 12 learning steps in the Fluera mastery methodology.
///
/// Each step has specific rules about which engine subsystems may be active.
/// The controller enforces these rules via capability queries.
///
/// Enum identifiers match the spec section titles for traceability.
enum LearningStep {
  /// Passo 1: Appunti a Mano Durante la Lezione.
  /// AI is DORMANT. Zero distractions. Pure writing flow.
  step1Notes,

  /// Passo 2: L'Elaborazione Solitaria — Riscrivere Senza Guardare.
  /// AI is DORMANT. Hide/reveal mechanics only.
  step2Recall,

  /// Passo 3: L'Interrogazione Socratica — L'IA Si Sveglia.
  /// AI is ACTIVE (Socratic only — no auto-suggestions).
  step3Socratic,

  /// Passo 4: Il Confronto Centauro — Lo Specchio Critico.
  /// AI is ACTIVE (Ghost Map: structural gap analysis).
  step4GhostMap,

  /// Passo 5: La Notte — Il Consolidamento Offline.
  /// AI is ACTIVE (FSRS overnight computation, sleep consolidation).
  step5Consolidation,

  /// Passo 6: Il Primo Ritorno — Active Recall Spaziale con Blur.
  /// AI is ACTIVE (SRS blur overlay, spaced retrieval practice).
  step6SrsBlur,

  /// Passo 7: L'Apprendimento Solidale — Il Confronto tra Pari.
  /// AI is ACTIVE (collaborative canvas, peer matching).
  step7PeerReview,

  /// Passo 8: I Ritorni SRS — Il Ripasso a Intervalli Crescenti.
  /// AI is ACTIVE (FSRS-driven review scheduling, retrieval practice).
  step8SrsReturns,

  /// Passo 9: I Ponti Cross-Dominio — Pensiero Sistemico.
  /// AI is ACTIVE (inter-domain connections, transfer learning).
  step9CrossDomain,

  /// Passo 10: La Fog of War — Preparazione all'Esame.
  /// AI is ACTIVE (Fog of War memory palace test).
  step10FogOfWar,

  /// Passo 11: L'Esame — Il Canvas nella Testa.
  /// AI is ACTIVE (exam simulation, grading).
  step11ExamSimulation,

  /// Passo 12: Il Canvas Resta e Cresce — Infrastruttura Permanente.
  /// AI is ACTIVE (long-term review scheduling, knowledge pruning).
  step12Permanence,
}

/// 🧠 Controller for the cognitive learning cycle.
///
/// Provides capability queries that subsystems use to self-gate.
/// The controller does NOT tell subsystems what to do — it answers
/// questions like "may I run proactive analysis right now?"
///
/// **Thread safety**: All state is on the main isolate (Flutter UI).
/// No synchronization needed.
class LearningStepController extends ChangeNotifier {
  LearningStep _currentStep;

  /// Transition choreographer for animated step changes (A13.2).
  final StepTransitionChoreographer choreographer = StepTransitionChoreographer();

  /// Passeggiata controller for Step 11 contemplative mode (A10).
  final PasseggiataController passeggiata = PasseggiataController();

  /// Create a controller starting at the given step.
  ///
  /// Default is [LearningStep.step1Notes] — the entry point for
  /// every new study session. The step can be changed later via
  /// [setStep] when the user progresses through the methodology.
  LearningStepController({
    LearningStep initialStep = LearningStep.step1Notes,
    TelemetryRecorder? telemetry,
  })  : _currentStep = initialStep,
        _telemetry = telemetry ?? TelemetryRecorder.noop;

  final TelemetryRecorder _telemetry;

  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  /// The current learning step.
  LearningStep get currentStep => _currentStep;

  /// The step number (1-indexed) for the choreographer.
  int get stepNumber => _currentStep.index + 1;

  /// Transition to a new learning step.
  ///
  /// Notifies all listeners (subsystems will re-evaluate their gates).
  /// Fires a choreographed transition event (A13.2) if the step changes.
  void setStep(LearningStep step) {
    if (_currentStep == step) return;
    final fromStep = stepNumber;
    _currentStep = step;

    // Fire choreographed transition (A13.2).
    choreographer.transitionTo(
      fromStep: fromStep,
      toStep: stepNumber,
    );

    // Auto-activate passeggiata for Step 11 (A10-01).
    if (step == LearningStep.step11ExamSimulation) {
      if (!passeggiata.isActive) {
        passeggiata.activate();
      }
    } else if (passeggiata.isActive) {
      passeggiata.deactivate();
    }

    // 📊 Telemetry: emit for beta-validated step entries only (1, 2).
    // Other steps are tracked at their domain-specific entry points
    // (step_3_socratic_started, step_4_ghost_map_started, etc.).
    final eventName = switch (step) {
      LearningStep.step1Notes => 'step_1_entered',
      LearningStep.step2Recall => 'step_2_entered',
      _ => null,
    };
    if (eventName != null) {
      _telemetry.logEvent(eventName, properties: {
        'from_step': fromStep,
        'to_step': stepNumber,
      });
    }

    notifyListeners();
  }

  /// Advance to a specific step (forward-only).
  ///
  /// Only transitions if [step] is ahead of the current step.
  /// This prevents accidental regression in the methodology.
  void advanceTo(LearningStep step) {
    if (step.index > _currentStep.index) {
      setStep(step);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CAPABILITY QUERIES — subsystems call these to self-gate
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether AI subsystems may run (proactive analysis, semantic titles,
  /// connection suggestions, Atlas prompts, etc.).
  ///
  /// Returns `false` for Steps 1-2 (AI dormant).
  bool get isAiAllowed => _currentStep.index >= LearningStep.step3Socratic.index;

  /// Whether proactive knowledge gap analysis may run.
  ///
  /// Proactive analysis uses OCR + Atlas to identify knowledge gaps
  /// and show glowing cyan dots. This is only allowed from Step 4+.
  bool get isProactiveAnalysisAllowed =>
      _currentStep.index >= LearningStep.step4GhostMap.index;

  /// Whether automatic connection suggestions may appear.
  ///
  /// Ghost connections and link suggestions are distracting during
  /// active note-taking. Only allowed from Step 4+.
  bool get isConnectionSuggestionAllowed =>
      _currentStep.index >= LearningStep.step4GhostMap.index;

  /// Whether semantic title generation (AI-powered) may run.
  ///
  /// Semantic titles use Atlas to generate concise labels for clusters
  /// during dezoom. This is only allowed from Step 3+.
  bool get isSemanticTitleAllowed =>
      _currentStep.index >= LearningStep.step3Socratic.index;

  /// Whether shape recognition (auto-detect shapes from freehand) is allowed.
  ///
  /// During Step 1, shape recognition must be opt-in via toolbar toggle.
  /// Even when enabled, the toast "Did you mean a circle?" must not appear
  /// during active writing (see FlowGuard).
  ///
  /// Returns `false` for Step 1 — shapes can still be drawn via shape tool,
  /// but auto-recognition from freehand strokes is suppressed.
  bool get isShapeRecognitionAllowed =>
      _currentStep.index >= LearningStep.step2Recall.index;

  /// Whether automatic snap-to-grid / smart guides may activate.
  ///
  /// During Step 1, no snapping — pure spatial freedom.
  bool get isSmartSnapAllowed =>
      _currentStep.index >= LearningStep.step2Recall.index;

  /// Whether Recall Mode (Step 2) features are available.
  ///
  /// Recall Mode allows the student to reconstruct content from memory.
  /// Available from Step 2 onwards.
  bool get isRecallModeAllowed =>
      _currentStep.index >= LearningStep.step2Recall.index;

  /// Whether the Socratic dialogue mode is available.
  bool get isSocraticAllowed =>
      _currentStep.index >= LearningStep.step3Socratic.index;

  /// Whether the Ghost Map (Step 4) is available.
  ///
  /// Ghost Map is the knowledge gap overlay that compares the student's
  /// canvas against an AI-generated reference. It requires the student
  /// to have completed at least the Socratic phase (Step 3).
  /// Allowed from Step 4+ without restrictions.
  bool get isGhostMapAllowed =>
      _currentStep.index >= LearningStep.step4GhostMap.index;

  /// Whether spaced repetition features (flashcards, SR dots) are available.
  bool get isSpacedRepetitionAllowed =>
      _currentStep.index >= LearningStep.step5Consolidation.index;

  /// Human-readable name for the current step (for debugging / UI).
  ///
  /// These labels match the official step titles from specifica_implementativa.md.
  String get stepName {
    switch (_currentStep) {
      case LearningStep.step1Notes:
        return 'Appunti a Mano';
      case LearningStep.step2Recall:
        return 'Richiamo Attivo';
      case LearningStep.step3Socratic:
        return 'Interrogazione Socratica';
      case LearningStep.step4GhostMap:
        return 'Confronto Centauro';
      case LearningStep.step5Consolidation:
        return 'Consolidamento Notturno';
      case LearningStep.step6SrsBlur:
        return 'Primo Ritorno SRS';
      case LearningStep.step7PeerReview:
        return 'Confronto tra Pari';
      case LearningStep.step8SrsReturns:
        return 'Ritorni SRS';
      case LearningStep.step9CrossDomain:
        return 'Ponti Cross-Dominio';
      case LearningStep.step10FogOfWar:
        return 'Fog of War';
      case LearningStep.step11ExamSimulation:
        return 'Simulazione Esame';
      case LearningStep.step12Permanence:
        return 'Infrastruttura Permanente';
    }
  }

  /// Whether the Passeggiata contemplative mode is active (Step 11, A10).
  bool get isPasseggiataActive => passeggiata.isActive;

  /// Whether SRS tracking is suppressed (A10-06: during Passeggiata).
  bool get isTrackingDisabled => passeggiata.isTrackingDisabled;

  @override
  void dispose() {
    choreographer.dispose();
    passeggiata.dispose();
    super.dispose();
  }

  @override
  String toString() => 'LearningStepController(step: $stepName)';
}
