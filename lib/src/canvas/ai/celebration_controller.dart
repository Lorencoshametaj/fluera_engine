// ============================================================================
// 🎉 PEDAGOGICAL CELEBRATIONS — Discrete positive feedback (A13.8)
//
// Specifica: A13.8-01 → A13.8-09
//
// Celebrations in Fluera are DISCRETE, INFORMATIVE, and SHORT-LIVED.
// They are NOT gamification — no stars, no streaks, no XP, no leaderboards.
//
// The student receives a small, warm signal when they demonstrate mastery.
// The signal fades quickly (<2s) and never interrupts the cognitive flow.
//
// CELEBRATION TYPES:
//   1. RecallPerfect  — All nodes recalled in a session (≥5 nodes)
//   2. StabilityGain  — A node reaches 🌳 or ⭐ stage
//   3. BridgeFormed   — Cross-domain connection confirmed
//   4. FogCleared     — Fog of War completed with ≥90% green
//   5. FirstRecall    — Very first successful recall ever (onboarding)
//
// ANTI-PATTERNS (A13.8):
//   - No sound (celebrations are visual-only, sound budget is for pedagogy)
//   - No counter ("you've done X reviews!") — this is not Duolingo
//   - No animation longer than 2 seconds
//   - No blocking overlay — celebrations are inline, dismissable by touch
//   - No negative-adjacent celebrations ("you only forgot 2!")
//
// ARCHITECTURE:
//   Pure model + controller — no Flutter widgets.
//   The canvas screen observes [pendingCelebration] and renders it.
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 🎉 Type of pedagogical celebration.
enum CelebrationType {
  /// All nodes recalled in a session (≥5 nodes reviewed).
  ///
  /// Visual: green pulse on canvas edges, 1.5s.
  /// Message: "Solido." (Italian) / "Solid." (English)
  recallPerfect,

  /// A node reaches 🌳 (mature) or ⭐ (mastered) stage.
  ///
  /// Visual: subtle gold glow around the node, 1.2s.
  /// Message: "🌳 Radicato" / "⭐ Padroneggiato"
  stabilityGain,

  /// Cross-domain connection confirmed by the student.
  ///
  /// Visual: golden bridge line pulses once, 1.0s.
  /// Message: "🌉 Ponte creato"
  bridgeFormed,

  /// Fog of War completed with ≥90% correct.
  ///
  /// Visual: soft white flash from center, 2.0s.
  /// Message: "Sei pronto."
  fogCleared,

  /// Very first successful recall ever (onboarding milestone).
  ///
  /// Visual: warm amber pulse, 2.0s.
  /// Message: "Il primo ricordo è il più importante."
  firstRecall,
}

/// 🎉 A celebration event to render.
class CelebrationEvent {
  /// What type of celebration this is.
  final CelebrationType type;

  /// Duration in milliseconds (always ≤ 2000ms per A13.8-03).
  final int durationMs;

  /// Primary color for the celebration visual.
  final Color color;

  /// Message to display (localized).
  final String message;

  /// Whether the celebration has a spatial anchor (node/bridge).
  /// If null, the celebration is canvas-wide.
  final Offset? anchorPosition;

  /// Timestamp when the celebration was triggered.
  final DateTime timestamp;

  CelebrationEvent._({
    required this.type,
    required this.durationMs,
    required this.color,
    required this.message,
    this.anchorPosition,
  }) : timestamp = DateTime.now();
}

/// 🎉 Pedagogical Celebration Controller (A13.8).
///
/// Generates discrete, informative celebration events when the student
/// demonstrates mastery. Celebrations are visual-only, < 2s, and never
/// interrupt cognitive flow.
///
/// Usage:
/// ```dart
/// final celebrations = CelebrationController();
/// celebrations.addListener(() {
///   final event = celebrations.pendingCelebration;
///   if (event != null) _showCelebration(event);
/// });
/// celebrations.onRecallSessionComplete(remembered: 10, total: 10);
/// ```
class CelebrationController extends ChangeNotifier {

  CelebrationEvent? _pending;

  /// The current pending celebration (null if none).
  /// Once the UI has rendered it, call [consumeCelebration].
  CelebrationEvent? get pendingCelebration => _pending;

  /// Whether there's a celebration waiting to be shown.
  bool get hasPending => _pending != null;

  /// Whether this is the student's very first recall ever.
  bool _hasEverRecalled = false;

  /// Set initial state from persisted data.
  void setHasEverRecalled(bool value) {
    _hasEverRecalled = value;
  }

  // ── Triggers ────────────────────────────────────────────────────────────

  /// Trigger after a recall session completes.
  ///
  /// Fires [CelebrationType.recallPerfect] when all ≥5 nodes were recalled.
  /// Fires [CelebrationType.firstRecall] on the very first successful recall.
  ///
  /// [solidMessage] and [firstRecallMessage] allow the caller to provide
  /// localized strings via FlueraLocalizations (the controller has no context).
  void onRecallSessionComplete({
    required int remembered,
    required int total,
    String? solidMessage,
    String? firstRecallMessage,
  }) {
    if (!_hasEverRecalled && remembered > 0) {
      _hasEverRecalled = true;
      _emit(CelebrationEvent._(
        type: CelebrationType.firstRecall,
        durationMs: 2000,
        color: const Color(0xFFFFA726), // Warm amber
        message: firstRecallMessage ?? 'Il primo ricordo è il più importante.',
      ));
      return;
    }

    if (total >= 5 && remembered == total) {
      _emit(CelebrationEvent._(
        type: CelebrationType.recallPerfect,
        durationMs: 1500,
        color: const Color(0xFF66BB6A), // Soft green
        message: solidMessage ?? 'Solido.',
      ));
    }
  }

  /// Trigger when a node reaches a new SRS stage.
  ///
  /// Only fires for 🌳 (mature, stage 4) and ⭐ (mastered, stage 5).
  void onStabilityMilestone({
    required int newStage,
    Offset? nodePosition,
  }) {
    if (newStage == 4) {
      _emit(CelebrationEvent._(
        type: CelebrationType.stabilityGain,
        durationMs: 1200,
        color: const Color(0xFFFFD700), // Gold
        message: '🌳 Radicato',
        anchorPosition: nodePosition,
      ));
    } else if (newStage >= 5) {
      _emit(CelebrationEvent._(
        type: CelebrationType.stabilityGain,
        durationMs: 1200,
        color: const Color(0xFFFFD700), // Gold
        message: '⭐ Padroneggiato',
        anchorPosition: nodePosition,
      ));
    }
  }

  /// Trigger when a cross-domain bridge is confirmed.
  void onBridgeFormed({Offset? bridgeMidpoint}) {
    _emit(CelebrationEvent._(
      type: CelebrationType.bridgeFormed,
      durationMs: 1000,
      color: const Color(0xFFFFD700), // Gold
      message: '🌉 Ponte creato',
      anchorPosition: bridgeMidpoint,
    ));
  }

  /// Trigger when Fog of War is completed with ≥90% correct.
  void onFogCleared({
    required int correctCount,
    required int totalCount,
  }) {
    if (totalCount == 0) return;
    final ratio = correctCount / totalCount;
    if (ratio >= 0.90) {
      _emit(CelebrationEvent._(
        type: CelebrationType.fogCleared,
        durationMs: 2000,
        color: const Color(0xFFFFFFFF), // White
        message: 'Sei pronto.',
      ));
    }
  }

  // ── Consumption ────────────────────────────────────────────────────────

  /// Called by the UI after it has rendered the celebration.
  void consumeCelebration() {
    _pending = null;
  }

  // ── Internal ──────────────────────────────────────────────────────────

  void _emit(CelebrationEvent event) {
    _pending = event;
    notifyListeners();
  }
}
