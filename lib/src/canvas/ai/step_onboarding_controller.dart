// ============================================================================
// 📖 STEP ONBOARDING OVERLAYS — First-time guidance per step (A13.6)
//
// Specifica: A13.6-01 → A13.6-08
//
// When the student enters a learning step for the FIRST TIME, a brief,
// non-blocking overlay appears explaining what to expect. The overlay:
//   - Is dismissable by tap or swipe (A13.6-02)
//   - Shows for max 5 seconds then auto-fades (A13.6-03)
//   - Never appears again for the same step (A13.6-04)
//   - Has a "Don't show again" option (A13.6-05)
//   - Is localized IT/EN (A13.6-06)
//
// ARCHITECTURE:
//   Pure model — no widgets. The canvas reads [pendingOverlay] and renders.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'package:flutter/foundation.dart';

/// 📖 Per-step onboarding overlay content.
class StepOnboardingOverlay {
  /// Learning step number (1–12).
  final int step;

  /// Title line.
  final String title;

  /// Body text (1–2 sentences max).
  final String body;

  /// Emoji icon for the overlay header.
  final String icon;

  /// Duration before auto-dismiss (ms).
  final int autoFadeMs;

  const StepOnboardingOverlay({
    required this.step,
    required this.title,
    required this.body,
    required this.icon,
    this.autoFadeMs = 5000,
  });
}

/// 📖 Step Onboarding Controller (A13.6).
///
/// Tracks which steps have been seen and provides overlay content
/// for first-time encounters.
class StepOnboardingController extends ChangeNotifier {
  /// Steps already seen (persisted).
  final Set<int> _seenSteps;

  /// Whether the user disabled all onboarding overlays.
  bool _globallyDisabled;

  /// Current pending overlay (null if none).
  StepOnboardingOverlay? _pending;

  StepOnboardingController({
    Set<int>? seenSteps,
    bool globallyDisabled = false,
  })  : _seenSteps = seenSteps ?? {},
        _globallyDisabled = globallyDisabled;

  // ── State ─────────────────────────────────────────────────────────────

  /// The overlay to show (null if none pending).
  StepOnboardingOverlay? get pendingOverlay => _pending;

  /// Whether any overlay is pending.
  bool get hasPending => _pending != null;

  /// Whether all overlays are globally disabled.
  bool get isGloballyDisabled => _globallyDisabled;

  // ── Actions ───────────────────────────────────────────────────────────

  /// Called when the student enters a step. Shows overlay if first time.
  void onStepEntered(int step) {
    if (_globallyDisabled || _seenSteps.contains(step)) return;
    if (step < 1 || step > 12) return;

    final content = _overlayContent[step];
    if (content == null) return;

    _pending = content;
    notifyListeners();
  }

  /// Called when the overlay is dismissed (tap, swipe, or auto-fade).
  void dismissOverlay() {
    if (_pending != null) {
      _seenSteps.add(_pending!.step);
      _pending = null;
      notifyListeners();
    }
  }

  /// Globally disable all step onboarding overlays.
  void disableAll() {
    _globallyDisabled = true;
    _pending = null;
    notifyListeners();
  }

  /// Check if a step has been seen.
  bool hasSeenStep(int step) => _seenSteps.contains(step);

  // ── Serialization ─────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'seenSteps': _seenSteps.toList(),
        'globallyDisabled': _globallyDisabled,
      };

  factory StepOnboardingController.fromJson(Map<String, dynamic> json) {
    final steps = (json['seenSteps'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toSet() ??
        {};
    return StepOnboardingController(
      seenSteps: steps,
      globallyDisabled: json['globallyDisabled'] as bool? ?? false,
    );
  }

  // ── Content (IT) ──────────────────────────────────────────────────────

  static const Map<int, StepOnboardingOverlay> _overlayContent = {
    1: StepOnboardingOverlay(
      step: 1,
      title: 'Appunti a Mano',
      body: 'Scrivi liberamente. Nessuna IA, nessuna distrazione.',
      icon: '✍️',
    ),
    2: StepOnboardingOverlay(
      step: 2,
      title: 'Ricorda Senza Guardare',
      body: 'I tuoi appunti verranno nascosti. Prova a riscrivere quello che ricordi.',
      icon: '🧠',
    ),
    3: StepOnboardingOverlay(
      step: 3,
      title: 'Domande Socratiche',
      body: "L'IA si sveglia e ti fa domande — mai risposte.",
      icon: '🤔',
    ),
    4: StepOnboardingOverlay(
      step: 4,
      title: 'Lo Specchio Critico',
      body: 'Confronta i tuoi appunti con la mappa di riferimento.',
      icon: '🗺️',
    ),
    5: StepOnboardingOverlay(
      step: 5,
      title: 'Consolidamento',
      body: 'Lascia sedimentare. Il cervello lavora di notte.',
      icon: '🌙',
    ),
    6: StepOnboardingOverlay(
      step: 6,
      title: 'Il Primo Ritorno',
      body: 'I tuoi appunti sono sfocati. Quanto ricordi?',
      icon: '🔍',
    ),
    7: StepOnboardingOverlay(
      step: 7,
      title: 'Confronto tra Pari',
      body: 'Studia con un compagno. Spiegare è il modo migliore per imparare.',
      icon: '👥',
    ),
    8: StepOnboardingOverlay(
      step: 8,
      title: 'Ripasso a Intervalli',
      body: 'I ritorni si allungano: 1g, 3g, 7g, 14g...',
      icon: '📅',
    ),
    9: StepOnboardingOverlay(
      step: 9,
      title: 'Ponti Cross-Dominio',
      body: 'Collega concetti da materie diverse. Il pensiero sistemico.',
      icon: '🌉',
    ),
    10: StepOnboardingOverlay(
      step: 10,
      title: 'Fog of War',
      body: 'Il canvas è nascosto. Trova tutti i concetti.',
      icon: '🌫️',
    ),
    11: StepOnboardingOverlay(
      step: 11,
      title: 'Passeggiata nel Palazzo',
      body: 'Cammina tra i tuoi appunti. La memoria è spaziale.',
      icon: '🚶',
    ),
    12: StepOnboardingOverlay(
      step: 12,
      title: 'Infrastruttura Permanente',
      body: 'I tuoi appunti vivono e crescono nel tempo.',
      icon: '🏛️',
    ),
  };
}
