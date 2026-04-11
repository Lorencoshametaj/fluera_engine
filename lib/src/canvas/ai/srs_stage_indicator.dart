// ============================================================================
// 🌱 SRS STAGE INDICATOR — 5-stage visual mastery system
//
// Spec: P8-06 → P8-09, A5.7
//
// Maps SRS card state → one of 5 visual stages, each with a distinct
// icon, color, and blur level. The stages provide metacognitive feedback:
// the student sees at a glance which concepts are fragile vs. integrated.
//
// Stage progression:
//   🌱 Fragile   → 🌿 Growing → 🌳 Solid → ⭐ Mastered → 👻 Integrated
//
// A5.7 update: uses STABILITY (not interval) and recent lapse checks:
//   Stage 4: lapses = 0 in last 3 reps
//   Stage 5: lapses = 0 in last 5 reps
//
// No Flutter widget dependencies — pure logic, testable in isolation.
// ============================================================================

import 'dart:ui';

import 'fsrs_scheduler.dart';

/// The 5 mastery stages for SRS-tracked nodes.
///
/// Each stage has distinct visual properties (icon, color, blur)
/// that communicate the student's mastery level at a glance.
enum SrsStage {
  /// 🌱 Stage 1 — Fragile: recently learned, few successful recalls.
  ///
  /// Criteria: reps < 2 AND stability < 3 days.
  fragile,

  /// 🌿 Stage 2 — Growing: starting to stick, moderate stability.
  ///
  /// Criteria: reps ≥ 2 AND stability ∈ [3, 14].
  growing,

  /// 🌳 Stage 3 — Solid: well-established, longer stability.
  ///
  /// Criteria: reps ≥ 4 AND stability ∈ [14, 60].
  solid,

  /// ⭐ Stage 4 — Mastered: high stability, no recent lapses.
  ///
  /// Criteria: reps ≥ 6 AND stability ∈ [60, 180] AND lapses = 0 in last 3 reps.
  mastered,

  /// 👻 Stage 5 — Integrated: part of long-term knowledge, nearly invisible.
  ///
  /// Criteria: reps ≥ 10 AND stability > 180 AND lapses = 0 in last 5 reps.
  integrated;

  /// The emoji icon for this stage.
  String get emoji {
    switch (this) {
      case SrsStage.fragile:
        return '🌱';
      case SrsStage.growing:
        return '🌿';
      case SrsStage.solid:
        return '🌳';
      case SrsStage.mastered:
        return '⭐';
      case SrsStage.integrated:
        return '👻';
    }
  }

  /// The accent color for this stage.
  ///
  /// Used for badge backgrounds, ring overlays, and subtle tinting.
  Color get color {
    switch (this) {
      case SrsStage.fragile:
        return const Color(0xFFF44336); // Red — needs attention
      case SrsStage.growing:
        return const Color(0xFFFF9800); // Orange — progressing
      case SrsStage.solid:
        return const Color(0xFF4CAF50); // Green — well-established
      case SrsStage.mastered:
        return const Color(0xFFFFD700); // Gold — mastered
      case SrsStage.integrated:
        return const Color(0xFF90CAF9); // Light blue — nearly invisible
    }
  }

  /// The blur amount (in logical pixels) for this stage.
  ///
  /// Spec A5.7: inversely proportional to mastery.
  /// Higher stages → more blur during recall (harder test).
  /// Values match spec ranges exactly:
  ///   Stage 1: 5-10px → 8px
  ///   Stage 2: 15-20px → 18px
  ///   Stage 3: 25-30px → 28px
  ///   Stage 4: 35-40px → 38px
  ///   Stage 5: Quasi invisibile → 45px
  double get blurPx {
    switch (this) {
      case SrsStage.fragile:
        return 8.0;
      case SrsStage.growing:
        return 18.0;
      case SrsStage.solid:
        return 28.0;
      case SrsStage.mastered:
        return 38.0;
      case SrsStage.integrated:
        return 45.0; // Almost invisible — test at maximum difficulty
    }
  }

  /// Font size for the emoji badge (in logical pixels, before canvas scaling).
  double get badgeSize => 14.0;

  /// Human-readable label for this stage (Italian, for UI).
  String get label {
    switch (this) {
      case SrsStage.fragile:
        return 'Fragile';
      case SrsStage.growing:
        return 'In crescita';
      case SrsStage.solid:
        return 'Solido';
      case SrsStage.mastered:
        return 'Padroneggiato';
      case SrsStage.integrated:
        return 'Integrato';
    }
  }
}

/// Determines the [SrsStage] for a given [SrsCardData].
///
/// Uses the mapping table from spec A5.7 with STABILITY (not interval):
///   Stage 1: reps < 2 AND stability < 3
///   Stage 2: reps ≥ 2 AND stability ∈ [3, 14]
///   Stage 3: reps ≥ 4 AND stability ∈ [14, 60]
///   Stage 4: reps ≥ 6 AND stability ∈ [60, 180] AND lapses = 0 in last 3 reps
///   Stage 5: reps ≥ 10 AND stability > 180 AND lapses = 0 in last 5 reps
///
/// Evaluation is top-down from Stage 5 → Stage 1 (most restrictive first).
SrsStage stageFromCard(SrsCardData card) {
  // Stage 5: Integrated — highest mastery
  // Requires zero lapses in the last 5 reviews
  if (card.reps >= 10 &&
      card.stability > 180 &&
      card.hasNoRecentLapses(5)) {
    return SrsStage.integrated;
  }

  // Stage 4: Mastered — strong, no recent lapses
  // Requires zero lapses in the last 3 reviews
  if (card.reps >= 6 &&
      card.stability >= 60 &&
      card.stability <= 180 &&
      card.hasNoRecentLapses(3)) {
    return SrsStage.mastered;
  }

  // Stage 3: Solid — well-established
  if (card.reps >= 4 && card.stability >= 14 && card.stability <= 60) {
    return SrsStage.solid;
  }

  // Stage 2: Growing — starting to stick
  if (card.reps >= 2 && card.stability >= 3 && card.stability <= 14) {
    return SrsStage.growing;
  }

  // Stage 1: Fragile — recently learned or struggling
  return SrsStage.fragile;
}
