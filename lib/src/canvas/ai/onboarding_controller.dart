// ============================================================================
// 🎓 ONBOARDING ESPERIENZIALE — First-launch seed node (A20.1)
//
// Specifica: A20.1-01 → A20.1-12
//
// When the student opens Fluera for the very first time, the canvas is NOT
// empty. A single pre-placed "seed node" teaches how memory works through
// meta-cognition:
//
//   "Come funziona la memoria?"
//
// This is the ONLY piece of pre-generated content — and it's designed to
// be learned USING the 12-step methodology itself. The student experiences
// Fluera by learning ABOUT Fluera.
//
// RULES (A20.1):
//   01: Seed node placed at canvas center, written in handwriting font
//   02: Content: concise explanation of spaced repetition + active recall
//   03: The node is tagged as `InputMethod.reference` (not generated)
//   04: A subtle prompt appears: "Scrivi sotto con le tue parole"
//   05: When student writes their first stroke, the prompt vanishes
//   06: After 5 minutes of note-taking, P2 becomes available (soft gate)
//   07: The seed node color is distinguishable (muted blue)
//   08: Zero forced tutorial — the seed teaches by example
//   09: Seed node can be deleted freely (no lock)
//   10: First-launch state persisted: seed only shown once per account
//   11: Seed content is localized (IT/EN minimum)
//   12: Zero analytics collected during onboarding
//
// ARCHITECTURE:
//   Pure model + controller — no Flutter widgets.
//   The canvas screen reads the seed data and renders it.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'dart:ui';

// ─────────────────────────────────────────────────────────────────────────────
// ⚠️ INTEGRATION STATUS — not yet wired into FlueraCanvasScreen.
//
// This controller is exported from `fluera_engine.dart` (line 482) but no
// caller instantiates it. To complete the A20.1 experience:
//
//   1. Instantiate OnboardingController in _FlueraCanvasScreenState.initState()
//      (or via a Riverpod provider), loading `isComplete` from storage.
//   2. On first-ever canvas open (all canvases empty), if !isComplete:
//      - Inject a TextNode at the canvas center with OnboardingSeedNode.it.
//      - Render the writePrompt as a BelowCanvas overlay (auto-fades on
//        first stroke via onFirstStroke()).
//   3. Persist isComplete via the storage adapter after the student completes
//      their first recall attempt (Passo 2).
//
// Tracking: roadmap audit_ux.md Appendice B — "Wiring OnboardingController".
// ─────────────────────────────────────────────────────────────────────────────

/// 🎓 Onboarding seed node content (A20.1).
///
/// Contains the pre-written pedagogical content that appears on first launch.
/// The student learns how memory works by reading this — then practices
/// the 12-step methodology on this very content.
class OnboardingSeedNode {
  /// Unique ID for the seed node.
  static const String seedNodeId = 'onboarding_seed_memory';

  /// Position: canvas center (host app adjusts for viewport).
  final Offset position;

  /// The seed content paragraphs (localized).
  final List<String> paragraphs;

  /// The "write below" prompt (vanishes on first stroke).
  final String writePrompt;

  /// Locale code.
  final String locale;

  const OnboardingSeedNode._({
    required this.position,
    required this.paragraphs,
    required this.writePrompt,
    required this.locale,
  });

  /// Italian seed (default).
  ///
  /// Content design (teoria_cognitiva_apprendimento.md, lines 1700-1710):
  /// - The seed is a QUESTION, not a lesson — it invites generation (§3).
  /// - The write prompt triggers Productive Failure (T4): "scrivi tutto
  ///   quello che sai" forces the student to confront how little they know.
  /// - The seed content is deliberately concise — just enough to prime
  ///   curiosity, not enough to satisfy it (Zeigarnik Effect §7).
  static const OnboardingSeedNode it = OnboardingSeedNode._(
    position: Offset.zero,
    locale: 'it',
    paragraphs: [
      'Come funziona la memoria?',
      '',
      'Il cervello dimentica velocemente ciò che non usa.',
      'Dopo 24 ore, senza ripasso, perdi circa il 70%.',
      '',
      'Ma se provi a RICORDARE attivamente — senza guardare — ',
      "il ricordo si rafforza ogni volta. È l'effetto testing.",
      '',
      'Se poi ripassi a intervalli crescenti (1g, 3g, 7g, 14g...),',
      'il ricordo diventa permanente. È la ripetizione spaziata.',
      '',
      'Fluera usa entrambi: scrivi a mano, poi ricorda senza guardare.',
      "L'IA non ti dà risposte — ti fa le domande giuste.",
    ],
    // T4 (Productive Failure) + §3 (Generation Effect):
    // "Scrivi tutto quello che SAI" — not "scrivi con le tue parole"
    // (which implies paraphrasing). The student must generate from
    // their own knowledge, discovering their gaps through failure.
    writePrompt:
        '✍️ Scrivi tutto quello che sai sulla memoria. Non c\u2019\u00e8 una risposta giusta.',
  );

  /// English seed.
  static const OnboardingSeedNode en = OnboardingSeedNode._(
    position: Offset.zero,
    locale: 'en',
    paragraphs: [
      'How does memory work?',
      '',
      'Your brain quickly forgets what it doesn\'t use.',
      'After 24 hours without review, you lose about 70%.',
      '',
      'But if you try to RECALL actively — without looking —',
      'the memory strengthens each time. This is the testing effect.',
      '',
      'If you then review at growing intervals (1d, 3d, 7d, 14d...),',
      'the memory becomes permanent. This is spaced repetition.',
      '',
      'Fluera uses both: write by hand, then recall without looking.',
      'The AI never gives answers — it asks the right questions.',
    ],
    writePrompt:
        '✍️ Write everything you know about memory. There\u2019s no right answer.',
  );

  /// Get seed for a locale (falls back to Italian).
  static OnboardingSeedNode forLocale(String locale) {
    if (locale.startsWith('en')) return en;
    return it; // Default: Italian
  }

  /// Full text content (for rendering).
  String get fullText => paragraphs.join('\n');
}

// =============================================================================
// ONBOARDING STATE CONTROLLER
// =============================================================================

/// 🎓 Onboarding state machine (A20.1).
///
/// Tracks whether the student has completed the first-launch experience.
/// Once the seed is shown and the student writes their first stroke,
/// onboarding is complete and never shown again.
///
/// Persistence: the host app stores [isComplete] in shared preferences
/// or the user profile. The controller reads it on init.
class OnboardingController {
  /// Whether the onboarding seed has been shown and dismissed.
  bool _isComplete;

  /// Whether the write prompt is currently visible.
  bool _isPromptVisible;

  /// The seed node to display (null if onboarding is complete).
  OnboardingSeedNode? _seedNode;

  OnboardingController({
    bool isComplete = false,
    String locale = 'it',
  })  : _isComplete = isComplete,
        _isPromptVisible = !isComplete,
        _seedNode = isComplete ? null : OnboardingSeedNode.forLocale(locale);

  // ── Getters ───────────────────────────────────────────────────────────

  /// Whether onboarding is complete (seed was shown, student wrote).
  bool get isComplete => _isComplete;

  /// Whether the "scrivi sotto" prompt should be shown.
  bool get isPromptVisible => _isPromptVisible && !_isComplete;

  /// The seed node to render (null if onboarding is complete).
  OnboardingSeedNode? get seedNode => _seedNode;

  /// Whether a seed node should be rendered on the canvas.
  bool get shouldShowSeed => !_isComplete && _seedNode != null;

  // ── Actions ───────────────────────────────────────────────────────────

  /// Called when the student draws their first stroke (A20.1-05).
  ///
  /// Hides the write prompt. Does NOT mark onboarding complete yet —
  /// that happens after the first successful recall (Step 2).
  void onFirstStroke() {
    _isPromptVisible = false;
  }

  /// Called when the student has completed at least one recall attempt.
  ///
  /// Marks onboarding as complete. The seed node can still exist on
  /// the canvas but won't be re-created on next launch.
  void markComplete() {
    _isComplete = true;
    _isPromptVisible = false;
    _seedNode = null;
  }

  /// Called when the student deletes the seed node (A20.1-09).
  ///
  /// The seed is freely deletable — no lock, no confirmation.
  void onSeedDeleted() {
    markComplete();
  }

  /// Serialize onboarding state for persistence.
  Map<String, dynamic> toJson() => {
        'isComplete': _isComplete,
      };

  /// Restore from persisted state.
  factory OnboardingController.fromJson(
    Map<String, dynamic> json, {
    String locale = 'it',
  }) {
    return OnboardingController(
      isComplete: json['isComplete'] as bool? ?? false,
      locale: locale,
    );
  }
}
