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
// ============================================================================

import 'package:flutter/foundation.dart';

/// The 12 learning steps in the Fluera mastery methodology.
///
/// Each step has specific rules about which engine subsystems may be active.
/// The controller enforces these rules via capability queries.
enum LearningStep {
  /// Step 1: Handwritten notes during lecture.
  /// AI is DORMANT. Zero distractions. Pure writing flow.
  step1Notes,

  /// Step 2: Active recall without looking at notes.
  /// AI is DORMANT. Hide/reveal mechanics only.
  step2Recall,

  /// Step 3: Socratic dialogue with Atlas AI.
  /// AI is ACTIVE (Socratic only — no auto-suggestions).
  step3Socratic,

  /// Step 4: Knowledge graph elaboration.
  /// AI is ACTIVE (connections, gap analysis).
  step4Elaboration,

  /// Step 5: Spaced repetition review.
  /// AI is ACTIVE (SR scheduling, flashcards).
  step5SpacedRepetition,

  /// Step 6: Teaching / Feynman technique.
  /// AI is ACTIVE (evaluation, feedback).
  step6Teaching,

  /// Step 7: Cross-linking with other subjects.
  /// AI is ACTIVE (inter-subject connections).
  step7CrossLinking,

  /// Step 8: Application and problem solving.
  /// AI is ACTIVE (exercise generation, hints).
  step8Application,

  /// Step 9: Metacognitive reflection.
  /// AI is ACTIVE (calibration analysis).
  step9Metacognition,

  /// Step 10: Collaborative learning.
  /// AI is ACTIVE (peer matching, debate facilitation).
  step10Collaboration,

  /// Step 11: Exam simulation.
  /// AI is ACTIVE (exam generation, grading).
  step11ExamSimulation,

  /// Step 12: Long-term consolidation.
  /// AI is ACTIVE (review scheduling, knowledge pruning).
  step12Consolidation,
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

  /// Create a controller starting at the given step.
  ///
  /// Default is [LearningStep.step1Notes] — the entry point for
  /// every new study session. The step can be changed later via
  /// [setStep] when the user progresses through the methodology.
  LearningStepController({
    LearningStep initialStep = LearningStep.step1Notes,
  }) : _currentStep = initialStep;

  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  /// The current learning step.
  LearningStep get currentStep => _currentStep;

  /// Transition to a new learning step.
  ///
  /// Notifies all listeners (subsystems will re-evaluate their gates).
  void setStep(LearningStep step) {
    if (_currentStep == step) return;
    _currentStep = step;
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
      _currentStep.index >= LearningStep.step4Elaboration.index;

  /// Whether automatic connection suggestions may appear.
  ///
  /// Ghost connections and link suggestions are distracting during
  /// active note-taking. Only allowed from Step 4+.
  bool get isConnectionSuggestionAllowed =>
      _currentStep.index >= LearningStep.step4Elaboration.index;

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

  /// Whether spaced repetition features (flashcards, SR dots) are available.
  bool get isSpacedRepetitionAllowed =>
      _currentStep.index >= LearningStep.step5SpacedRepetition.index;

  /// Human-readable name for the current step (for debugging / UI).
  String get stepName {
    switch (_currentStep) {
      case LearningStep.step1Notes:
        return 'Appunti a Mano';
      case LearningStep.step2Recall:
        return 'Richiamo Attivo';
      case LearningStep.step3Socratic:
        return 'Dialogo Socratico';
      case LearningStep.step4Elaboration:
        return 'Elaborazione';
      case LearningStep.step5SpacedRepetition:
        return 'Ripetizione Spaziata';
      case LearningStep.step6Teaching:
        return 'Tecnica Feynman';
      case LearningStep.step7CrossLinking:
        return 'Collegamenti Incrociati';
      case LearningStep.step8Application:
        return 'Applicazione';
      case LearningStep.step9Metacognition:
        return 'Metacognizione';
      case LearningStep.step10Collaboration:
        return 'Apprendimento Collaborativo';
      case LearningStep.step11ExamSimulation:
        return 'Simulazione Esame';
      case LearningStep.step12Consolidation:
        return 'Consolidamento';
    }
  }

  @override
  String toString() => 'LearningStepController(step: $stepName)';
}
