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

    // Create a repeating animation controller (period = 4s)
    _zeigarnikAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _zeigarnikAnimController!.addListener(() {
      // Convert controller value [0..1] → phase [0..2π]
      _zeigarnikAnimPhase = _zeigarnikAnimController!.value * 2 * 3.14159;
      if (mounted) setState(() {});
    });
    _zeigarnikAnimController!.repeat();

    debugPrint('💛 Zeigarnik: pulsing ${bounds.length} incomplete nodes');
  }

  /// Stops the Zeigarnik pulsing effect.
  void stopZeigarnikEffect() {
    _zeigarnikAnimController?.stop();
    _zeigarnikAnimController?.dispose();
    _zeigarnikAnimController = null;
    _zeigarnikIncompleteNodeBounds = const [];
    _zeigarnikAnimPhase = 0.0;
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
    if (_zeigarnikAnimController == null) return null;

    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: ZeigarnikPulsePainter(
          incompleteNodeBounds: _zeigarnikIncompleteNodeBounds,
          animPhase: _zeigarnikAnimPhase,
          canvasScale: _canvasController.scale,
          isSuppressed: _flowGuard.isFlowProtected,
          isDarkMode: Theme.of(context).brightness == Brightness.dark,
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
