// ============================================================================
// 🚶 PASSEGGIATA CONTROLLER — Contemplative mode for Step 11 (A10)
//
// Specifica: A10-01 → A10-07 (Appendice A10 — Passeggiata nel Palazzo)
//
// The "Passeggiata nel Palazzo" is a pre-exam contemplative walk through
// the entire canvas. Key properties:
//
//   ✅ All content visible — no blur, no fog, no test
//   ✅ Student CAN write (annotations, last-minute notes)
//   ✅ Tracking is OFF — zero SRS data generated
//   ✅ UI atmosphere: vignette 10%, toolbar minimized, slow entry animation
//   ✅ Optional guided path (golden dotted line)
//   ✅ "Torna" button to exit
//
// ❌ ANTI-PATTERNS:
//   A10-03: No blur, no fog, no recall test
//   A10-06: No SRS tracking, no performance metrics
//   A13-18: Ambient animations disabled during writing
//
// ARCHITECTURE:
//   Pure ChangeNotifier — no Flutter widgets, no BuildContext.
//   Consumed by the canvas screen to modify overlay rendering.
// ============================================================================

import 'package:flutter/foundation.dart';

/// 🚶 State of the Passeggiata contemplative mode.
enum PasseggiataState {
  /// Not active — normal canvas mode.
  inactive,

  /// Entry animation in progress (A10-02: 1s).
  entering,

  /// Active — contemplative mode is on.
  active,

  /// Exit animation in progress.
  exiting,
}

/// 🚶 Configuration for the optional guided path (A10-04).
class GuidedPathConfig {
  /// Ordered list of cluster IDs defining the walk path.
  final List<String> clusterIds;

  /// Whether the path has been dismissed by the student.
  bool isDismissed;

  GuidedPathConfig({
    required this.clusterIds,
    this.isDismissed = false,
  });
}

/// 🚶 Controller for the Passeggiata nel Palazzo (Step 11 contemplative mode).
///
/// Manages the full lifecycle:
/// 1. [activate] — triggers entry animation + atmospheric changes
/// 2. Active state — canvas fully visible, writing allowed, no tracking
/// 3. [deactivate] — triggers exit animation, restores normal UI
///
/// The canvas screen observes this controller to:
/// - Apply vignette overlay (10% edge darkening, A10-02)
/// - Minimize toolbar (A10-02)
/// - Disable all recall/blur/fog mechanics (A10-03)
/// - Set `tracking: false` (A10-06)
/// - Optionally render the guided path (A10-04)
///
/// Usage:
/// ```dart
/// passeggiataController.activate(clusterIds: orderedClusters);
/// // ... student walks through canvas ...
/// passeggiataController.deactivate();
/// ```
class PasseggiataController extends ChangeNotifier {

  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  PasseggiataState _state = PasseggiataState.inactive;
  PasseggiataState get state => _state;

  /// Whether the Passeggiata mode is currently active (or transitioning).
  bool get isActive =>
      _state == PasseggiataState.active ||
      _state == PasseggiataState.entering;

  /// Whether the Passeggiata is fully active (not transitioning).
  bool get isFullyActive => _state == PasseggiataState.active;

  /// Whether we're in a transition animation.
  bool get isTransitioning =>
      _state == PasseggiataState.entering ||
      _state == PasseggiataState.exiting;

  // ── Tracking flag (A10-06) ────────────────────────────────────────────

  /// When true, all SRS/review tracking is suppressed.
  ///
  /// The canvas screen checks this flag and sets `tracking: false`
  /// on any session data created during the Passeggiata.
  bool get isTrackingDisabled => isActive;

  // ── Guided path (A10-04) ──────────────────────────────────────────────

  GuidedPathConfig? _guidedPath;

  /// The guided path configuration, if available and not dismissed.
  GuidedPathConfig? get guidedPath =>
      _guidedPath?.isDismissed == true ? null : _guidedPath;

  /// Whether a guided path is available (not dismissed).
  bool get hasGuidedPath =>
      _guidedPath != null && !_guidedPath!.isDismissed;

  // ── Vignette (A10-02) ─────────────────────────────────────────────────

  /// Target vignette opacity (0.0 = none, 0.1 = 10% as per spec).
  ///
  /// During entry: 0.0 → 0.1
  /// During exit:  0.1 → 0.0
  /// Active:       0.1
  double get targetVignetteOpacity {
    return switch (_state) {
      PasseggiataState.inactive => 0.0,
      PasseggiataState.entering => 0.1,
      PasseggiataState.active => 0.1,
      PasseggiataState.exiting => 0.0,
    };
  }

  /// Whether the toolbar should be minimized.
  bool get shouldMinimizeToolbar => isActive;

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVATION (A10-01, A10-02)
  // ─────────────────────────────────────────────────────────────────────────

  /// Activate the Passeggiata contemplative mode.
  ///
  /// [clusterIds] — optional ordered list of cluster IDs for the guided
  /// path (A10-04). If null or empty, no guided path is shown.
  ///
  /// The entry animation takes 1000ms (A10-02). The controller transitions
  /// from [entering] to [active] after the animation completes. The
  /// consumer is responsible for driving the animation and calling
  /// [completeEntry] when done.
  void activate({List<String>? clusterIds}) {
    if (_state != PasseggiataState.inactive) return;

    // Set up guided path if cluster IDs provided.
    if (clusterIds != null && clusterIds.isNotEmpty) {
      _guidedPath = GuidedPathConfig(clusterIds: clusterIds);
    }

    _state = PasseggiataState.entering;
    notifyListeners();
  }

  /// Signal that the entry animation has completed.
  ///
  /// Call this from the animation controller's onComplete callback
  /// after the 1000ms entry animation (A10-02) finishes.
  void completeEntry() {
    if (_state != PasseggiataState.entering) return;
    _state = PasseggiataState.active;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEACTIVATION (A10-07)
  // ─────────────────────────────────────────────────────────────────────────

  /// Deactivate the Passeggiata mode.
  ///
  /// Triggers the exit animation: vignette dissolves, toolbar reappears.
  /// The consumer calls [completeExit] when the animation finishes.
  void deactivate() {
    if (_state == PasseggiataState.inactive ||
        _state == PasseggiataState.exiting) return;

    _state = PasseggiataState.exiting;
    notifyListeners();
  }

  /// Signal that the exit animation has completed.
  void completeExit() {
    if (_state != PasseggiataState.exiting) return;

    _state = PasseggiataState.inactive;
    _guidedPath = null;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GUIDED PATH (A10-04)
  // ─────────────────────────────────────────────────────────────────────────

  /// Dismiss the guided path (student gesture, A10-04: "dismissable").
  void dismissGuidedPath() {
    if (_guidedPath == null) return;
    _guidedPath!.isDismissed = true;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  /// Reset all state. Called when the canvas screen is disposed.
  void reset() {
    _state = PasseggiataState.inactive;
    _guidedPath = null;
    notifyListeners();
  }
}
