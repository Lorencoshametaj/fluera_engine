part of '../fluera_canvas_screen.dart';

/// ⭐ GOLDEN SHIMMER — Ambient shimmer on mastered nodes (SRS Stage 4+)
///
/// Spec: A13.9 (Stella dorata), A13-18 → A13-21
///
/// Mastered concept clusters display a slow golden shimmer to create
/// visual anchoring — mastered concepts "glow" subtly in the panorama,
/// reinforcing the student's sense of progress.
///
/// Integration points:
///   - Uses `_reviewSchedule` + `_clusterCache` to find mastered clusters
///   - Respects `_flowGuard.isFlowProtected` — pauses during active writing
///   - Animation runs independently at 6s period (0.167 Hz)
///   - Disableable via `_goldenShimmerEnabled` flag
extension GoldenShimmerExtension on _FlueraCanvasScreenState {

  // ── PUBLIC API ────────────────────────────────────────────────────────────

  /// Starts the golden shimmer effect on mastered nodes.
  ///
  /// Called after SRS data is loaded and clusters are detected.
  void startGoldenShimmer() {
    if (!_goldenShimmerEnabled) return;
    if (_goldenShimmerAnimController != null) return; // Already running

    final bounds = _findMasteredNodeBounds();
    if (bounds.isEmpty) return;

    _goldenShimmerNodeBounds = bounds;

    // Create a repeating animation controller (period = 6s).
    //
    // 🎨 RASTER FIX: no setState() listener on the controller — see the same
    // comment in [ZeigarnikEffectExtension.startZeigarnikEffect]. The shimmer
    // painter binds to the controller via AnimatedBuilder in
    // [buildGoldenShimmerOverlay], so only that painter repaints per tick,
    // isolated in a RepaintBoundary.
    _goldenShimmerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _goldenShimmerAnimController!.repeat();

    debugPrint('⭐ Golden Shimmer: shimmering ${bounds.length} mastered nodes');
  }

  /// Stops the golden shimmer effect.
  void stopGoldenShimmer() {
    _goldenShimmerAnimController?.stop();
    _goldenShimmerAnimController?.dispose();
    _goldenShimmerAnimController = null;
    _goldenShimmerNodeBounds = const [];
    if (mounted) setState(() {});
  }

  /// Refreshes the list of mastered nodes (e.g., after a review session).
  void refreshGoldenShimmerNodes() {
    if (!_goldenShimmerEnabled) return;
    _goldenShimmerNodeBounds = _findMasteredNodeBounds();
  }

  // ── OVERLAY BUILDER ──────────────────────────────────────────────────────

  /// Builds the golden shimmer overlay widget.
  ///
  /// Called from the UI overlay layer in `_ui_canvas_layer_painters.dart`.
  Widget? buildGoldenShimmerOverlay() {
    if (!_goldenShimmerEnabled) return null;
    if (_goldenShimmerNodeBounds.isEmpty) return null;
    final controller = _goldenShimmerAnimController;
    if (controller == null) return null;

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return CustomPaint(
              size: Size.infinite,
              painter: GoldenShimmerPainter(
                masteredNodeBounds: _goldenShimmerNodeBounds,
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

  /// Finds clusters that have mastered SRS status (Stage 4 or 5).
  ///
  /// A cluster is considered "mastered" if its recognized text matches a
  /// concept in `_reviewSchedule` with `stageFromCard` ≥ `SrsStage.mastered`.
  List<Rect> _findMasteredNodeBounds() {
    final bounds = <Rect>[];

    for (final cluster in _clusterCache) {
      final text = _clusterTextCache[cluster.id] ?? '';
      if (text.isEmpty) continue;

      // Check if any concept in the review schedule is mastered
      for (final entry in _reviewSchedule.entries) {
        if (text.toLowerCase().contains(entry.key.toLowerCase())) {
          final stage = stageFromCard(entry.value);
          if (stage.index >= SrsStage.mastered.index) {
            bounds.add(cluster.bounds);
            break; // One match is enough per cluster
          }
        }
      }
    }

    return bounds;
  }
}
