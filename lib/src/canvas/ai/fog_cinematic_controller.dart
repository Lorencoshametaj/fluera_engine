// ============================================================================
// 🌫️ FOG OF WAR CINEMATIC REVEAL — Center-to-edge reveal (P10-21)
//
// Specifica: P10-21 → P10-25
//
// When the student achieves ≥90% correct in Fog of War, a cinematic
// reveal animation plays:
//   - Duration: 3000ms (slow, deliberate)
//   - Pattern: radial wipe from center outward
//   - Sound: "revealSweep" from PedagogicalSoundEngine
//   - Final message: "Sei pronto." (if ≥90%)
//
// INTERMEDIATE REVEAL (student taps a node):
//   - Duration: 800ms
//   - Pattern: circular reveal from tap point
//   - No sound (per-node reveals are quiet)
//
// ARCHITECTURE:
//   Pure model describing the animation phases.
//   The rendering layer uses these parameters to drive the animation.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 🌫️ Type of fog reveal animation.
enum FogRevealType {
  /// Per-node reveal: circle from tap point, 800ms.
  nodeReveal,

  /// Final cinematic: radial wipe center→edge, 3000ms.
  cinematicReveal,
}

/// 🌫️ A fog reveal animation event.
class FogRevealEvent {
  /// Type of reveal.
  final FogRevealType type;

  /// Center point of the reveal (tap position or canvas center).
  final Offset center;

  /// Total animation duration in ms.
  final int durationMs;

  /// Whether to play sound (only for cinematic).
  final bool playSound;

  /// Message to show at the end (only for cinematic ≥90%).
  final String? completionMessage;

  /// Timestamp.
  final DateTime timestamp;

  FogRevealEvent._({
    required this.type,
    required this.center,
    required this.durationMs,
    required this.playSound,
    this.completionMessage,
  }) : timestamp = DateTime.now();

  /// Create a per-node reveal.
  factory FogRevealEvent.nodeReveal(Offset tapPosition) => FogRevealEvent._(
        type: FogRevealType.nodeReveal,
        center: tapPosition,
        durationMs: 800,
        playSound: false,
      );

  /// Create the cinematic reveal (≥90% correct).
  factory FogRevealEvent.cinematic({
    required Offset canvasCenter,
    required int correctCount,
    required int totalCount,
  }) {
    final ratio = totalCount > 0 ? correctCount / totalCount : 0.0;
    return FogRevealEvent._(
      type: FogRevealType.cinematicReveal,
      center: canvasCenter,
      durationMs: 3000,
      playSound: true,
      completionMessage: ratio >= 0.90 ? 'Sei pronto.' : null,
    );
  }
}

/// 🌫️ Cinematic Reveal Controller (P10-21).
///
/// Manages the fog reveal animation lifecycle for the Fog of War tool.
class FogCinematicController extends ChangeNotifier {
  FogRevealEvent? _currentReveal;

  /// The current reveal animation (null if none active).
  FogRevealEvent? get currentReveal => _currentReveal;

  /// Whether a reveal animation is active.
  bool get isRevealing => _currentReveal != null;

  /// Phases for the cinematic reveal animation.
  ///
  /// The rendering layer interpolates between these phases.
  static const List<FogRevealPhase> cinematicPhases = [
    FogRevealPhase(
      name: 'radialExpand',
      startFraction: 0.0,
      endFraction: 0.7,
      description: 'Radial fog wipe from center outward',
    ),
    FogRevealPhase(
      name: 'fullClear',
      startFraction: 0.7,
      endFraction: 0.85,
      description: 'Remaining fog dissolves uniformly',
    ),
    FogRevealPhase(
      name: 'messageAppear',
      startFraction: 0.85,
      endFraction: 1.0,
      description: '"Sei pronto." fades in at the bottom',
    ),
  ];

  /// Trigger a per-node reveal.
  void revealNode(Offset tapPosition) {
    _currentReveal = FogRevealEvent.nodeReveal(tapPosition);
    notifyListeners();
  }

  /// Trigger the cinematic reveal at session end.
  void revealCinematic({
    required Offset canvasCenter,
    required int correctCount,
    required int totalCount,
  }) {
    _currentReveal = FogRevealEvent.cinematic(
      canvasCenter: canvasCenter,
      correctCount: correctCount,
      totalCount: totalCount,
    );
    notifyListeners();
  }

  /// Called when the animation completes.
  void completeReveal() {
    _currentReveal = null;
    notifyListeners();
  }
}

/// 🌫️ A phase within the cinematic reveal animation.
class FogRevealPhase {
  /// Phase identifier.
  final String name;

  /// Start fraction (0.0–1.0) within the total animation.
  final double startFraction;

  /// End fraction (0.0–1.0) within the total animation.
  final double endFraction;

  /// Human-readable description.
  final String description;

  const FogRevealPhase({
    required this.name,
    required this.startFraction,
    required this.endFraction,
    required this.description,
  });
}
