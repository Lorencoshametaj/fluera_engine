// ============================================================================
// 🎭 STEP TRANSITION CHOREOGRAPHY — Animated step transitions (A13.2)
//
// Specifica: A13.1 → A13.2 + A13-T01 → A13-T06
//
// Each step transition is a "pedagogical moment" — not just a screen change.
// The student must FEEL the progression through the 12-step journey.
//
// This controller:
//   1. Defines the emotional identity of each step (A13.1)
//   2. Schedules animation + haptic + sound for each transition (A13.2)
//   3. Coordinates the three channels (visual, haptic, audio)
//   4. Respects FlowGuard: zero animations during writing (A13-20)
//
// ARCHITECTURE:
//   Pure model + controller — no Flutter widgets.
//   The canvas screen listens for TransitionEvent and drives the
//   actual AnimationController / HapticFeedback / Sound calls.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 🎭 Emotional identity of each learning step (A13.1).
class StepIdentity {
  /// Step number (1-12).
  final int step;

  /// Dominant emotion.
  final String emotion;

  /// Ambient color as ARGB value.
  final int ambientColor;

  /// UI intensity (0.0 = minimal, 1.0 = maximum).
  final double uiIntensity;

  /// Poetic metaphor for the step.
  final String metaphor;

  const StepIdentity({
    required this.step,
    required this.emotion,
    required this.ambientColor,
    required this.uiIntensity,
    required this.metaphor,
  });
}

/// 🎭 Registry of all 12 step identities.
class StepIdentityRegistry {
  StepIdentityRegistry._();

  static const List<StepIdentity> _identities = [
    StepIdentity(
      step: 1,
      emotion: 'Concentrazione serena',
      ambientColor: 0x00000000, // No ambient color — pure canvas
      uiIntensity: 0.1,
      metaphor: 'Stanza vuota, luce naturale',
    ),
    StepIdentity(
      step: 2,
      emotion: 'Tensione costruttiva',
      ambientColor: 0x0DF5E6D3, // Beige 5%
      uiIntensity: 0.2,
      metaphor: 'Stanza con le luci abbassate',
    ),
    StepIdentity(
      step: 3,
      emotion: 'Curiosità dialogica',
      ambientColor: 0x1A5C6BC0, // Indigo soft 10%
      uiIntensity: 0.5,
      metaphor: 'Conversazione con un mentore',
    ),
    StepIdentity(
      step: 4,
      emotion: 'Scoperta e confronto',
      ambientColor: 0x1A4CAF50, // Multi-color glow
      uiIntensity: 0.8,
      metaphor: 'Mappa del tesoro sovrapposta alla propria',
    ),
    StepIdentity(
      step: 5,
      emotion: 'Riposo',
      ambientColor: 0x00000000, // No UI
      uiIntensity: 0.0,
      metaphor: 'Il Palazzo dorme',
    ),
    StepIdentity(
      step: 6,
      emotion: 'Attesa e rivelazione',
      ambientColor: 0x1A607D8B, // Blue-grey desaturated
      uiIntensity: 0.5,
      metaphor: 'Nebbia mattutina nel Palazzo',
    ),
    StepIdentity(
      step: 7,
      emotion: 'Eccitazione sociale',
      ambientColor: 0x1A26A69A, // Teal
      uiIntensity: 0.8,
      metaphor: 'Due esploratori nella stessa mappa',
    ),
    StepIdentity(
      step: 8,
      emotion: 'Routine rituale',
      ambientColor: 0x26607D8B, // Blue-grey more saturated
      uiIntensity: 0.5,
      metaphor: 'Passeggiata serale nel Palazzo',
    ),
    StepIdentity(
      step: 9,
      emotion: 'Illuminazione',
      ambientColor: 0x1AFFD700, // Gold
      uiIntensity: 0.7,
      metaphor: "Vista dall'alto, strade che si illuminano",
    ),
    StepIdentity(
      step: 10,
      emotion: 'Sfida e verità',
      ambientColor: 0x33212121, // Dark
      uiIntensity: 0.8,
      metaphor: 'Esplorazione notturna con torcia',
    ),
    StepIdentity(
      step: 11,
      emotion: 'Fiducia silenziosa',
      ambientColor: 0x0DFFF3E0, // Warm minimal
      uiIntensity: 0.1,
      metaphor: 'Il Palazzo vive nella testa',
    ),
    StepIdentity(
      step: 12,
      emotion: 'Orgoglio e appartenenza',
      ambientColor: 0x1AFFD700, // Gold for timeline
      uiIntensity: 0.8,
      metaphor: 'Il Palazzo completato',
    ),
  ];

  /// Get the identity for a specific step (1-indexed).
  static StepIdentity forStep(int step) {
    final idx = (step - 1).clamp(0, _identities.length - 1);
    return _identities[idx];
  }

  /// Get the ambient color for a step.
  static Color ambientColorForStep(int step) {
    return Color(forStep(step).ambientColor);
  }
}

// =============================================================================
// TRANSITION EVENTS
// =============================================================================

/// 🎭 Haptic pattern for a transition (A13.3).
enum TransitionHaptic {
  /// No haptic.
  none,

  /// Single medium vibration — "stacco" (P1→P2).
  singleMedium,

  /// Double light tap — "someone knocks" (P2→P3).
  doubleTap,

  /// Crescendo vibration — scanning wave (P3→P4).
  crescendo,

  /// Slow deep pulse — "awakening" (P6 return).
  slowDeepPulse,

  /// Dramatic crescendo — fog reveal (P10 finale).
  dramaticCrescendo,
}

/// 🎭 Sound cue for a transition (A13.4, matched to PedagogicalSoundEngine).
enum TransitionSound {
  /// No sound.
  none,

  /// Low soft tone, 200Hz 300ms — "curtain descending" (P1→P2).
  lowCurtain,

  /// Two ascending notes DO-MI — "the mentor arrives" (P2→P3).
  mentorKnock,

  /// Ascending sweep 200→800Hz + pings — "scanning" (P3→P4).
  scanSweep,

  /// Low rising note 100→400Hz — "palace awakens" (P6 return).
  palaceAwaken,

  /// Minor→major chord — "from doubt to revelation" (P10 reveal).
  revelation,
}

/// 🎭 A complete transition event to be executed by the canvas screen.
///
/// The controller emits this; the canvas screen drives the actual
/// AnimationController, HapticFeedback, and PedagogicalSoundEngine calls.
class StepTransitionEvent {
  /// Which step we're transitioning FROM.
  final int fromStep;

  /// Which step we're transitioning TO.
  final int toStep;

  /// Total animation duration in milliseconds.
  final int durationMs;

  /// Haptic pattern to trigger.
  final TransitionHaptic haptic;

  /// Sound cue to play.
  final TransitionSound sound;

  /// Animation phases (for multi-phase transitions).
  final List<TransitionPhase> phases;

  /// Ambient color to transition TO.
  final int targetAmbientColor;

  const StepTransitionEvent({
    required this.fromStep,
    required this.toStep,
    required this.durationMs,
    required this.haptic,
    required this.sound,
    required this.phases,
    required this.targetAmbientColor,
  });
}

/// 🎭 A single phase within a multi-phase transition.
class TransitionPhase {
  /// Phase start time (0.0 → 1.0 of total duration).
  final double startT;

  /// Phase end time (0.0 → 1.0 of total duration).
  final double endT;

  /// Human-readable description.
  final String description;

  /// Visual effect type for this phase.
  final TransitionVisualEffect effect;

  const TransitionPhase({
    required this.startT,
    required this.endT,
    required this.description,
    required this.effect,
  });
}

/// 🎭 Visual effects available during transitions.
enum TransitionVisualEffect {
  /// Blur increase/decrease.
  blur,

  /// Background tint change.
  tint,

  /// Toolbar reorganization.
  toolbarMorph,

  /// Radial wave from center.
  radialWave,

  /// Staggered element fade-in.
  staggeredFadeIn,

  /// Panel slide from edge.
  panelSlide,

  /// Full-canvas blur dissolve.
  blurDissolve,

  /// Fog dissolve (center → edges).
  fogDissolve,

  /// Heatmap fade-in.
  heatmapReveal,
}

// =============================================================================
// CHOREOGRAPHY CONTROLLER
// =============================================================================

/// 🎭 Step Transition Choreography Controller (A13.2).
///
/// Generates the appropriate [StepTransitionEvent] for any step change.
/// The canvas screen observes [currentTransition] and drives animations.
///
/// Usage:
/// ```dart
/// final choreographer = StepTransitionChoreographer();
/// choreographer.addListener(() {
///   final event = choreographer.currentTransition;
///   if (event != null) _runTransitionAnimation(event);
/// });
/// choreographer.transitionTo(fromStep: 1, toStep: 2);
/// ```
class StepTransitionChoreographer extends ChangeNotifier {

  StepTransitionEvent? _currentTransition;
  StepTransitionEvent? get currentTransition => _currentTransition;

  /// Whether a transition is currently in progress.
  bool _isTransitioning = false;
  bool get isTransitioning => _isTransitioning;

  /// Request a transition from one step to another.
  ///
  /// Emits a [StepTransitionEvent] via [notifyListeners].
  /// The canvas screen is responsible for driving the animation.
  void transitionTo({required int fromStep, required int toStep}) {
    if (_isTransitioning) return;

    _currentTransition = _buildEvent(fromStep, toStep);
    _isTransitioning = true;
    notifyListeners();
  }

  /// Signal that the transition animation has completed.
  void completeTransition() {
    _isTransitioning = false;
    _currentTransition = null;
    notifyListeners();
  }

  /// Get the ambient color for the current step (for static rendering).
  Color ambientColorForStep(int step) =>
      StepIdentityRegistry.ambientColorForStep(step);

  // ── Event builders ────────────────────────────────────────────────────

  StepTransitionEvent _buildEvent(int from, int to) {
    final target = StepIdentityRegistry.forStep(to);

    // Special choreographies for specific transitions.
    return switch ((from, to)) {
      (1, 2) => _transition1to2(target),
      (2, 3) => _transition2to3(target),
      (3, 4) => _transition3to4(target),
      _ => _genericTransition(from, to, target),
    };
  }

  /// P1→P2: Concentrazione → Recall (A13-T01).
  StepTransitionEvent _transition1to2(StepIdentity target) {
    return StepTransitionEvent(
      fromStep: 1,
      toStep: 2,
      durationMs: 800,
      haptic: TransitionHaptic.singleMedium,
      sound: TransitionSound.lowCurtain,
      targetAmbientColor: target.ambientColor,
      phases: const [
        TransitionPhase(
          startT: 0.0,
          endT: 0.6,
          description: 'Nodes blur 0→25px',
          effect: TransitionVisualEffect.blur,
        ),
        TransitionPhase(
          startT: 0.2,
          endT: 0.8,
          description: 'Background warms to beige 5%',
          effect: TransitionVisualEffect.tint,
        ),
        TransitionPhase(
          startT: 0.5,
          endT: 1.0,
          description: 'Toolbar morphs: hide AI, show "non ricordo"',
          effect: TransitionVisualEffect.toolbarMorph,
        ),
      ],
    );
  }

  /// P2→P3: Recall → Socratic Dialogue (A13-T02).
  StepTransitionEvent _transition2to3(StepIdentity target) {
    return StepTransitionEvent(
      fromStep: 2,
      toStep: 3,
      durationMs: 600,
      haptic: TransitionHaptic.doubleTap,
      sound: TransitionSound.mentorKnock,
      targetAmbientColor: target.ambientColor,
      phases: const [
        TransitionPhase(
          startT: 0.0,
          endT: 0.5,
          description: 'Luminous line from right edge → panel',
          effect: TransitionVisualEffect.panelSlide,
        ),
        TransitionPhase(
          startT: 0.3,
          endT: 0.8,
          description: 'Canvas compresses 5% left',
          effect: TransitionVisualEffect.tint,
        ),
      ],
    );
  }

  /// P3→P4: Socratic → Ghost Map (A13-T03).
  StepTransitionEvent _transition3to4(StepIdentity target) {
    return StepTransitionEvent(
      fromStep: 3,
      toStep: 4,
      durationMs: 1200,
      haptic: TransitionHaptic.crescendo,
      sound: TransitionSound.scanSweep,
      targetAmbientColor: target.ambientColor,
      phases: const [
        TransitionPhase(
          startT: 0.0,
          endT: 0.33,
          description: 'Socratic panel dissolves',
          effect: TransitionVisualEffect.panelSlide,
        ),
        TransitionPhase(
          startT: 0.33,
          endT: 0.67,
          description: 'Radial scanning wave from center',
          effect: TransitionVisualEffect.radialWave,
        ),
        TransitionPhase(
          startT: 0.67,
          endT: 1.0,
          description: 'Ghost Map elements staggered fade-in (50ms each)',
          effect: TransitionVisualEffect.staggeredFadeIn,
        ),
      ],
    );
  }

  /// Generic transition for step pairs without specific choreography.
  StepTransitionEvent _genericTransition(
      int from, int to, StepIdentity target) {
    return StepTransitionEvent(
      fromStep: from,
      toStep: to,
      durationMs: 500,
      haptic: TransitionHaptic.singleMedium,
      sound: TransitionSound.none,
      targetAmbientColor: target.ambientColor,
      phases: [
        TransitionPhase(
          startT: 0.0,
          endT: 1.0,
          description: 'Ambient color cross-fade',
          effect: TransitionVisualEffect.tint,
        ),
      ],
    );
  }
}
