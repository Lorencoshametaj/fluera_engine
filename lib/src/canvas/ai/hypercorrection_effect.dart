// ============================================================================
// ⚡ HYPERCORRECTION VISUAL EFFECT — Shock animation for P3-21
//
// Specifica: P3-21 → P3-25
//
// When the student answers a Socratic question with HIGH CONFIDENCE but
// is WRONG, a brief "shock" visual effect fires to leverage the
// hypercorrection effect (Butterfield & Metcalfe, 2001):
//
//   "The more confident you are in your wrong answer,
//    the more likely you are to remember the correct one."
//
// The visual effect:
//   - 600ms total duration
//   - Phase 1 (0–200ms): node border flashes bright orange
//   - Phase 2 (200–600ms): "⚡" icon pulses once, border fades
//   - Haptic: single strong intensity
//   - Sound: none (budget reserved for pedagogy)
//
// ANTI-PATTERNS:
//   - No shame, no "wrong!" text (this is a LEARNING opportunity)
//   - The message is always positive: "Il tuo cervello ricorderà meglio"
//   - No sound — visual + haptic only
//
// ARCHITECTURE:
//   Pure model — consumed by the rendering layer.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'dart:ui';

import 'package:flutter/foundation.dart';

/// ⚡ Hypercorrection effect event.
class HypercorrectionEvent {
  /// The node/question that triggered the effect.
  final String questionId;

  /// Student's reported confidence (1–5 scale).
  final int confidence;

  /// Where to anchor the visual effect (screen coordinates).
  final Offset anchorPosition;

  /// Timestamp when the effect was triggered.
  final DateTime timestamp;

  /// Total duration: 600ms.
  static const int durationMs = 600;

  /// Phase 1 duration: border flash (0–200ms).
  static const int flashPhaseMs = 200;

  /// Positive reinforcement (debug/logging only — UI uses L10n).
  static const String debugMessage = '⚡ Il tuo cervello ricorderà meglio';

  /// Border flash color.
  static const Color flashColor = Color(0xFFFF9800); // Bright orange

  /// Haptic pattern.
  static const HypercorrectionHaptic haptic = HypercorrectionHaptic.strongSingle;

  HypercorrectionEvent({
    required this.questionId,
    required this.confidence,
    required this.anchorPosition,
  }) : timestamp = DateTime.now();

  /// Whether this is a "strong" hypercorrection (confidence ≥ 4).
  ///
  /// Strong hypercorrections have a more pronounced visual effect
  /// and higher SRS urgency boost (A5.6: ×1.3).
  bool get isStrong => confidence >= 4;
}

/// ⚡ Haptic pattern for hypercorrection.
enum HypercorrectionHaptic {
  /// Single strong vibration (default).
  strongSingle,
}

/// ⚡ Hypercorrection Visual Controller (P3-21).
///
/// Emits [HypercorrectionEvent]s when a high-confidence wrong answer
/// is detected. The canvas rendering layer observes [pendingEffect]
/// and renders the flash + icon animation.
///
/// Integration: called by `SocraticController` when
/// `question.isHypercorrection` is set to true during evaluation.
class HypercorrectionController extends ChangeNotifier {
  HypercorrectionEvent? _pending;

  /// Current pending hypercorrection effect (null if none).
  HypercorrectionEvent? get pendingEffect => _pending;

  /// Whether an effect is waiting to be rendered.
  bool get hasPending => _pending != null;

  /// Trigger a hypercorrection effect.
  ///
  /// Only fires when confidence is ≥ 3 (the threshold for
  /// meaningful hypercorrection, per Butterfield & Metcalfe).
  void trigger({
    required String questionId,
    required int confidence,
    required Offset anchorPosition,
  }) {
    if (confidence < 3) return; // Below threshold, no effect

    _pending = HypercorrectionEvent(
      questionId: questionId,
      confidence: confidence,
      anchorPosition: anchorPosition,
    );
    notifyListeners();
  }

  /// Called after the rendering layer has animated the effect.
  void consumeEffect() {
    _pending = null;
  }
}
