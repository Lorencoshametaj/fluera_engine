/// 🧠 INTELLIGENCE ADAPTERS — Wraps existing subsystems into the
/// Conscious Architecture contract.
///
/// These are thin adapters that expose existing engine subsystems as
/// [IntelligenceSubsystem] instances. They delegate all real work to
/// the underlying implementation and only add lifecycle coordination.
///
/// ## L3 — Invisible
/// - [SmartSnapAdapter] — wraps [SmartSnapEngine]
/// - [SmartAnimateAdapter] — wraps [SmartAnimateEngine]
/// - [AccessibilityAdapter] — wraps [CanvasAccessibilityBridge]
///
/// ## L4 — Generative
/// - [DesignLinterAdapter] — wraps [DesignLinter]
library;

import '../core/conscious_architecture.dart';

// =============================================================================
// L3 — INVISIBLE: Smart Snap
// =============================================================================

/// Adapter that exposes [SmartSnapEngine] to the Conscious Architecture.
///
/// SmartSnapEngine is stateless and const-constructible, so this adapter
/// mainly provides lifecycle visibility and context-based threshold tuning.
class SmartSnapAdapter extends IntelligenceSubsystem {
  @override
  IntelligenceLayer get layer => IntelligenceLayer.invisible;

  @override
  String get name => 'SmartSnap';

  bool _active = true;

  @override
  bool get isActive => _active;

  /// Current snap threshold (px). May be tuned based on zoom level.
  double snapThreshold = 8.0;

  @override
  void onContextChanged(EngineContext context) {
    // At high zoom, reduce snap threshold for pixel-perfect alignment.
    // At low zoom, increase threshold for easier snapping.
    if (context.zoom > 3.0) {
      snapThreshold = 4.0;
    } else if (context.zoom < 0.3) {
      snapThreshold = 16.0;
    } else {
      snapThreshold = 8.0;
    }
  }

  @override
  void onIdle(Duration idleDuration) {
    // SmartSnap is synchronous — no idle work needed.
  }

  @override
  void dispose() {
    _active = false;
  }
}

// =============================================================================
// L3 — INVISIBLE: Smart Animate
// =============================================================================

/// Adapter that exposes [SmartAnimateEngine] to the Conscious Architecture.
///
/// SmartAnimateEngine is stateless — this adapter provides lifecycle tracking
/// and could be extended to pre-cache transition plans during idle.
class SmartAnimateAdapter extends IntelligenceSubsystem {
  @override
  IntelligenceLayer get layer => IntelligenceLayer.invisible;

  @override
  String get name => 'SmartAnimate';

  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void onContextChanged(EngineContext context) {
    // Future: pre-compute transition plans when switching to prototype mode.
  }

  @override
  void onIdle(Duration idleDuration) {
    // Future: pre-cache layer snapshots for faster transitions.
  }

  @override
  void dispose() {
    _active = false;
  }
}

// =============================================================================
// L3 — INVISIBLE: Accessibility Bridge
// =============================================================================

/// Adapter that exposes [CanvasAccessibilityBridge] to the Conscious Architecture.
///
/// The bridge already has its own lifecycle (rebuild, dispose). This adapter
/// adds context-aware rebuilding: when the tool changes, the semantics tree
/// may need different interaction hints.
class AccessibilityAdapter extends IntelligenceSubsystem {
  @override
  IntelligenceLayer get layer => IntelligenceLayer.invisible;

  @override
  String get name => 'Accessibility';

  bool _active = true;

  @override
  bool get isActive => _active;

  /// Whether to announce tool changes to screen readers.
  bool announceToolChanges = true;

  /// Last known active tool — used to detect changes.
  String? _lastTool;

  /// Callback to trigger accessibility rebuild (wired at registration).
  void Function()? onNeedsRebuild;

  /// Callback to announce messages (wired at registration).
  void Function(String message)? onAnnounce;

  @override
  void onContextChanged(EngineContext context) {
    // Announce tool changes for screen reader users.
    if (announceToolChanges &&
        context.activeTool != null &&
        context.activeTool != _lastTool) {
      _lastTool = context.activeTool;
      onAnnounce?.call('Tool: ${context.activeTool}');
    }
  }

  @override
  void onIdle(Duration idleDuration) {
    // Rebuild semantics tree after idle (debounced rebuild).
    if (idleDuration.inMilliseconds > 300) {
      onNeedsRebuild?.call();
    }
  }

  @override
  void dispose() {
    _active = false;
    onNeedsRebuild = null;
    onAnnounce = null;
  }
}

// =============================================================================
// L4 — GENERATIVE: Design Linter
// =============================================================================

/// Adapter that exposes [DesignLinter] to the Conscious Architecture.
///
/// Runs design lint rules during idle periods to provide proactive
/// quality feedback without interrupting the user's flow.
class DesignLinterAdapter extends IntelligenceSubsystem {
  @override
  IntelligenceLayer get layer => IntelligenceLayer.generative;

  @override
  String get name => 'DesignLinter';

  bool _active = true;

  @override
  bool get isActive => _active;

  /// Number of violations found in the last lint pass.
  int lastViolationCount = 0;

  /// Whether a lint pass is pending (set on context changes, cleared on idle).
  bool _lintPending = false;

  /// Whether a lint pass is pending.
  bool get lintPending => _lintPending;

  /// Callback to trigger a lint pass (wired at registration).
  /// Returns the number of violations found.
  int Function()? onLintRequested;

  @override
  void onContextChanged(EngineContext context) {
    // Mark lint as pending on any context change.
    // Actual lint runs during idle to avoid blocking interactions.
    _lintPending = true;
  }

  @override
  void onIdle(Duration idleDuration) {
    // Run lint after 1 second of idle — don't interrupt active work.
    if (_lintPending && idleDuration.inMilliseconds > 1000) {
      _lintPending = false;
      if (onLintRequested != null) {
        lastViolationCount = onLintRequested!();
      }
    }
  }

  @override
  void dispose() {
    _active = false;
    onLintRequested = null;
  }
}
