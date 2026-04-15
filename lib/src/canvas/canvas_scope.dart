import 'package:flutter/widgets.dart';

import '../reflow/content_cluster.dart';
import '../layers/layer_controller.dart';
import '../tools/unified_tool_controller.dart';
import '../l10n/fluera_localizations.dart';
import './infinite_canvas_controller.dart';
import './ai/socratic/socratic_controller.dart';
import './ai/recall/recall_mode_controller.dart';
import './ai/fog_of_war/fog_of_war_controller.dart';
import './ai/ghost_map_controller.dart';
import './ai/tier_gate_controller.dart';
import './ai/learning_step_controller.dart';

// ============================================================================
// 🏗️ CANVAS SCOPE — Shared state for standalone widgets (Phase 0)
//
// Replaces `part of` coupling by publishing key controllers and caches
// into the widget tree via InheritedWidget.
//
// Usage:  CanvasScope.of(context).layerController
//
// Added: God Object Decomposition — Phase 0
// ============================================================================

/// Provides shared canvas state to descendant widgets without requiring
/// `part of fluera_canvas_screen.dart`.
///
/// This is the first step in decomposing the 57K-LOC God Object:
/// instead of sharing state via private field access on the same class,
/// extracted widgets read state from the nearest [CanvasScope] ancestor.
class CanvasScope extends InheritedWidget {
  // ── Core controllers ──────────────────────────────────────────────────
  final InfiniteCanvasController canvasController;
  final LayerController layerController;
  final UnifiedToolController toolController;
  final LearningStepController learningStepController;

  // ── AI controllers ────────────────────────────────────────────────────
  final SocraticController socraticController;
  final RecallModeController recallModeController;
  final FogOfWarController fogOfWarController;
  final GhostMapController ghostMapController;
  final TierGateController tierGateController;

  // ── Caches ────────────────────────────────────────────────────────────
  final List<ContentCluster> clusterCache;

  // ── Localization ──────────────────────────────────────────────────────
  final FlueraLocalizations l10n;

  // ── Canvas identity ───────────────────────────────────────────────────
  final String canvasId;

  const CanvasScope({
    super.key,
    required this.canvasController,
    required this.layerController,
    required this.toolController,
    required this.learningStepController,
    required this.socraticController,
    required this.recallModeController,
    required this.fogOfWarController,
    required this.ghostMapController,
    required this.tierGateController,
    required this.clusterCache,
    required this.l10n,
    required this.canvasId,
    required super.child,
  });

  /// Retrieves the nearest [CanvasScope] from the widget tree.
  ///
  /// Throws if no scope is found — callers must ensure they are
  /// descendants of a [CanvasScope].
  static CanvasScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CanvasScope>();
    assert(scope != null, 'No CanvasScope found in context');
    return scope!;
  }

  /// Like [of], but returns null if no scope is found.
  /// Useful during widget testing or when scope is optional.
  static CanvasScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CanvasScope>();
  }

  @override
  bool updateShouldNotify(CanvasScope oldWidget) {
    // Controller references are stable (late final), so we only
    // need to check the cache identity which changes on cluster re-detect.
    return clusterCache != oldWidget.clusterCache ||
        l10n != oldWidget.l10n;
  }
}
