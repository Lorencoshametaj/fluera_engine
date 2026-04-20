part of '../fluera_canvas_screen.dart';

/// 💛 ZEIGARNIK EFFECT — Ambient pulsing on incomplete nodes
///
/// Spec: P8-13, A13-18 → A13-21, CA-133
///
/// Leverages the Zeigarnik Effect: incomplete tasks stay salient in working
/// memory. Nodes marked as incomplete pulse with a slow amber glow to
/// subtly draw the student's attention without interrupting flow.
///
/// Integration points:
///   - Uses `_clusterCache` to find clusters with incomplete content
///   - Respects `_flowGuard.isFlowProtected` — pauses during active writing
///   - Animation runs independently at 4s period (0.25 Hz)
///   - Disableable via `_zeigarnikEnabled` flag
extension ZeigarnikEffectExtension on _FlueraCanvasScreenState {

  // ── PUBLIC API ────────────────────────────────────────────────────────────

  /// Starts the Zeigarnik pulsing effect.
  ///
  /// Called after cluster detection completes. Only activates if there
  /// are clusters tagged as incomplete (containing "?" nodes or few strokes).
  void startZeigarnikEffect() {
    if (!_zeigarnikEnabled) return;
    if (_zeigarnikAnimController != null) return; // Already running

    final bounds = _findIncompleteNodeBounds();
    if (bounds.isEmpty) return;

    _zeigarnikIncompleteNodeBounds = bounds;

    // Create a repeating animation controller (period = 4s).
    //
    // 🎨 RASTER FIX: we do NOT wire a setState() listener on the controller.
    // That pattern triggers a full rebuild of _FlueraCanvasScreenState every
    // frame at 60–120Hz, which invalidates the whole widget tree including
    // canvas, toolbar and overlays — the root cause of the viewport-wide
    // Repaint Rainbow flicker. Instead, [buildZeigarnikOverlay] binds an
    // AnimatedBuilder directly to the controller, so only the pulse painter
    // rebuilds per tick, inside its own RepaintBoundary.
    _zeigarnikAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _zeigarnikAnimController!.repeat();

    debugPrint('💛 Zeigarnik: pulsing ${bounds.length} incomplete nodes');
  }

  /// Stops the Zeigarnik pulsing effect.
  void stopZeigarnikEffect() {
    _zeigarnikAnimController?.stop();
    _zeigarnikAnimController?.dispose();
    _zeigarnikAnimController = null;
    _zeigarnikIncompleteNodeBounds = const [];
    if (mounted) setState(() {});
  }

  /// Refreshes the list of incomplete nodes (e.g., after new strokes).
  void refreshZeigarnikNodes() {
    if (!_zeigarnikEnabled) return;
    _zeigarnikIncompleteNodeBounds = _findIncompleteNodeBounds();
  }

  // ── OVERLAY BUILDER ──────────────────────────────────────────────────────

  /// Builds the Zeigarnik pulsing overlay widget.
  ///
  /// Called from the UI overlay layer in `_ui_canvas_layer_painters.dart`.
  Widget? buildZeigarnikOverlay() {
    if (!_zeigarnikEnabled) return null;
    if (_zeigarnikIncompleteNodeBounds.isEmpty) return null;
    final controller = _zeigarnikAnimController;
    if (controller == null) return null;

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return CustomPaint(
              size: Size.infinite,
              painter: ZeigarnikPulsePainter(
                incompleteNodeBounds: _zeigarnikIncompleteNodeBounds,
                animPhase: controller.value * 2 * 3.14159,
                canvasScale: _canvasController.scale,
                isSuppressed: _flowGuard.isFlowProtected,
                isDarkMode: isDarkMode,
              ),
            );
          },
        ),
      ),
    );
  }

  // ── PRIVATE HELPERS ──────────────────────────────────────────────────────

  /// Finds clusters that appear incomplete based on heuristics:
  ///   1. Very few strokes (< 3) relative to bounds area
  ///   2. Cluster text contains "?" character
  ///   3. SRS stage is "fragile" with high lapse count
  List<Rect> _findIncompleteNodeBounds() {
    final bounds = <Rect>[];

    for (final cluster in _clusterCache) {
      // Heuristic 1: sparse cluster (few strokes for the area)
      final strokeCount = cluster.strokeIds.length;
      final areaRatio = strokeCount / (cluster.bounds.width * cluster.bounds.height / 10000);
      final isSparse = strokeCount < 3 || areaRatio < 0.05;

      // Heuristic 2: text contains "?"
      final text = _clusterTextCache[cluster.id] ?? '';
      final hasQuestion = text.contains('?');

      // Heuristic 3: fragile SRS card with lapses
      bool isFragileWithLapses = false;
      for (final entry in _reviewSchedule.entries) {
        if (text.toLowerCase().contains(entry.key.toLowerCase())) {
          if (entry.value.lapses >= 2 && entry.value.reps < 2) {
            isFragileWithLapses = true;
            break;
          }
        }
      }

      if (isSparse || hasQuestion || isFragileWithLapses) {
        bounds.add(cluster.bounds);
      }
    }

    return bounds;
  }
}
