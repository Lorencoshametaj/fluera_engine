// ============================================================================
// 🧱 RED WALL RESPONSE — Crisis management for >70% forgotten nodes (A20.4.1)
//
// Specifica: A20-47 → A20-54
//
// When the student sees 70%+ red nodes during review (Steps 6, 8, 10),
// the system activates a PROTECTIVE response to prevent abandonment.
//
// The response is:
//   1. Visual softening: red → grey (#888), green nodes get celebration pulse
//   2. Metacognitive message (NEVER motivational or condescending)
//   3. SRS volume reduction: next session proposes max(10, N×0.3) nodes
//   4. Guaranteed success: at least 1 green node (from comfort zone)
//
// ❌ ANTI-PATTERNS (A20-52 → A20-54):
//   - NEVER "You got {N} wrong out of {M}"
//   - NEVER "Don't give up, you can do it!"
//   - NEVER "Maybe you should go back"
//
// THREAD SAFETY: Main isolate only.
// ============================================================================

import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 🧱 Red Wall activation status.
enum RedWallState {
  /// Below threshold — normal display.
  inactive,

  /// Threshold exceeded — protective response active.
  active,
}

/// 🧱 Configuration for the Red Wall protective response.
class RedWallConfig {
  /// Threshold for activation (A20-47: >70%).
  final double threshold;

  /// Maximum nodes to propose in the next session when active (A20-50).
  final int minimumNextSessionNodes;

  /// Multiplier for next session volume reduction (A20-50: N×0.3).
  final double volumeReductionFactor;

  const RedWallConfig({
    this.threshold = 0.70,
    this.minimumNextSessionNodes = 10,
    this.volumeReductionFactor = 0.30,
  });

  static const RedWallConfig defaultConfig = RedWallConfig();
}

/// 🧱 Result of a Red Wall evaluation on a review session.
class RedWallEvaluation {
  /// Whether the Red Wall response is active.
  final RedWallState state;

  /// Number of forgotten nodes (red).
  final int forgottenCount;

  /// Total nodes in the session.
  final int totalCount;

  /// The exact ratio (forgotten / total).
  final double ratio;

  /// Suggested maximum nodes for the next session (A20-50).
  final int suggestedNextSessionSize;

  const RedWallEvaluation({
    required this.state,
    required this.forgottenCount,
    required this.totalCount,
    required this.ratio,
    required this.suggestedNextSessionSize,
  });

  /// Whether the protective response is active.
  bool get isActive => state == RedWallState.active;
}

/// 🧱 Red Wall Response Controller (A20.4.1).
///
/// Evaluates review sessions for crisis conditions and provides
/// the appropriate protective response configuration.
///
/// Usage:
/// ```dart
/// final eval = RedWallController.evaluate(
///   forgottenCount: 15,
///   totalCount: 20,
/// );
/// if (eval.isActive) {
///   // Apply grey overlay instead of red
///   // Show metacognitive message
///   // Reduce next session volume
/// }
/// ```
class RedWallController {
  RedWallController._();

  // ── Colors (A20-48) ───────────────────────────────────────────────────

  /// Normal red color for forgotten nodes.
  static const Color normalForgottenColor = Color(0xFFFF3B30);

  /// Softened grey color when Red Wall is active (A20-48).
  static const Color protectedForgottenColor = Color(0xFF888888);

  /// Resolve the forgotten node color based on Red Wall state.
  static Color forgottenNodeColor(RedWallState state) {
    return state == RedWallState.active
        ? protectedForgottenColor
        : normalForgottenColor;
  }

  // ── Evaluation ────────────────────────────────────────────────────────

  /// Evaluate a review session for Red Wall activation (A20-47).
  ///
  /// [forgottenCount] — nodes with recall level ≤ 2.
  /// [totalCount] — total nodes in the review session.
  /// [config] — optional configuration overrides.
  static RedWallEvaluation evaluate({
    required int forgottenCount,
    required int totalCount,
    RedWallConfig config = const RedWallConfig(),
  }) {
    if (totalCount <= 0) {
      return const RedWallEvaluation(
        state: RedWallState.inactive,
        forgottenCount: 0,
        totalCount: 0,
        ratio: 0.0,
        suggestedNextSessionSize: 10,
      );
    }

    final ratio = forgottenCount / totalCount;
    final isTriggered = ratio > config.threshold;

    // A20-50: reduce volume for next session.
    final suggestedSize = isTriggered
        ? (totalCount * config.volumeReductionFactor)
            .ceil()
            .clamp(config.minimumNextSessionNodes, totalCount)
        : totalCount;

    return RedWallEvaluation(
      state: isTriggered ? RedWallState.active : RedWallState.inactive,
      forgottenCount: forgottenCount,
      totalCount: totalCount,
      ratio: ratio,
      suggestedNextSessionSize: suggestedSize,
    );
  }

  // ── Messages (A20-49) ─────────────────────────────────────────────────

  /// Generate the metacognitive summary message (A20-49).
  ///
  /// NEVER uses words: "failure", "error", "wrong", "bad".
  /// ALWAYS frames forgetting as diagnostic information.
  ///
  /// Returns a localized message key and fallback Italian text.
  static String protectiveMessage(int forgottenCount) {
    return 'Hai identificato esattamente $forgottenCount zone da rafforzare. '
        'Ora sai dove lavorare — la maggior parte degli studenti non lo sa.';
  }

  /// Micro-message for the summary overlay (shorter variant).
  static String shortProtectiveMessage(int forgottenCount) {
    return '$forgottenCount zone identificate per il ripasso mirato.';
  }

  // ── Next session calibration (A20-50, A20-51) ────────────────────────

  /// Calculate the node selection for the next session when Red Wall is active.
  ///
  /// Returns a list of node IDs, ordered by accessibility (ZPD-near first).
  /// Guarantees at least 1 comfort-zone node (A20-51).
  ///
  /// [allNodeIds] — all available node IDs.
  /// [recallLevels] — nodeId → last recall level (1-5).
  /// [maxNodes] — maximum nodes from [RedWallEvaluation.suggestedNextSessionSize].
  static List<String> calibrateNextSession({
    required List<String> allNodeIds,
    required Map<String, int> recallLevels,
    required int maxNodes,
  }) {
    if (allNodeIds.isEmpty) return const [];

    // Sort by recall level descending (easiest first = ZPD-near).
    final sorted = List<String>.from(allNodeIds);
    sorted.sort((a, b) {
      final la = recallLevels[a] ?? 1;
      final lb = recallLevels[b] ?? 1;
      return lb.compareTo(la); // Higher recall = easier = first
    });

    // Take up to maxNodes.
    final selected = sorted.take(maxNodes).toList();

    // A20-51: Guarantee at least 1 comfort-zone node (recall ≥ 4).
    final hasComfortNode = selected.any((id) => (recallLevels[id] ?? 1) >= 4);
    if (!hasComfortNode) {
      // Find a comfort node to add.
      final comfortNode = sorted.firstWhere(
        (id) => (recallLevels[id] ?? 1) >= 4,
        orElse: () => '', // None available — rare but possible.
      );
      if (comfortNode.isNotEmpty && !selected.contains(comfortNode)) {
        selected.add(comfortNode);
      }
    }

    return selected;
  }
}
