part of '../fluera_canvas_screen.dart';

/// 🚶 PASSEGGIATA NEL PALAZZO — Pre-exam contemplative mode (Step 11)
///
/// Spec: P11-05 → P11-07, A10-01 → A10-07
///
/// A dedicated "walk through your Palace" mode that:
/// - Shows the full canvas without blur, fog, or test mechanics
/// - Adds a subtle vignette (10% edge darkening) for contemplative atmosphere
/// - Minimizes toolbar to reduce visual noise
/// - Generates ZERO SRS data (tracking disabled)
/// - Optionally shows a guided path through zones via cluster centroids
///
/// Writing IS permitted (P11-05: this is not a read-only mode).
///
/// Integration points:
///   - Triggered from toolbar menu (🚶 icon)
///   - Uses `_clusterCache` centroids for guided path generation
///   - Disables SRS tracking via `_isPasseggiataSrsDisabled` flag
///   - Available from Step 6+ (first SRS return)
extension PasseggiataModeExtension on _FlueraCanvasScreenState {

  // ── PUBLIC API ────────────────────────────────────────────────────────────

  /// Activates Passeggiata nel Palazzo mode.
  ///
  /// Suppresses SRS tracking, minimizes toolbar, applies vignette overlay,
  /// and optionally calculates a guided path through cluster centroids.
  void enterPasseggiatMode() {
    if (_isPasseggiataActive) return;

    _isPasseggiataActive = true;
    _isPasseggiataSrsDisabled = true;

    // Calculate guided path from cluster centroids (spatial ordering)
    _passeggiataGuidedPath = _calculateGuidedPath();
    _passeggiataPathProgress = 0.0;

    // Start the vignette + path animation
    _passeggiataAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30), // slow contemplative path
    );
    _passeggiataAnimController!.addListener(() {
      _passeggiataPathProgress = _passeggiataAnimController!.value;
      if (mounted) setState(() {});
    });

    // Haptic feedback: gentle confirmation
    HapticFeedback.lightImpact();

    if (mounted) setState(() {});

    debugPrint('🚶 Passeggiata: entered (${_passeggiataGuidedPath.length} waypoints)');
  }

  /// Starts the guided path animation (student taps "Inizia passeggiata").
  void startPasseggiataGuidedPath() {
    _passeggiataAnimController?.forward();
    if (mounted) setState(() {});
  }

  /// Exits Passeggiata nel Palazzo mode.
  ///
  /// Restores toolbar, removes vignette, re-enables SRS tracking.
  void exitPasseggiatMode() {
    if (!_isPasseggiataActive) return;

    _isPasseggiataActive = false;
    _isPasseggiataSrsDisabled = false;
    _passeggiataGuidedPath = const [];
    _passeggiataPathProgress = 0.0;

    _passeggiataAnimController?.stop();
    _passeggiataAnimController?.dispose();
    _passeggiataAnimController = null;

    HapticFeedback.lightImpact();
    if (mounted) setState(() {});

    debugPrint('🚶 Passeggiata: exited');
  }

  /// Whether the student can enter Passeggiata mode.
  ///
  /// Available from Step 6 onwards (after the first SRS return).
  /// 🚀 v1 DEFER: Gated by V1FeatureGate.passeggiata
  bool get canEnterPasseggiata =>
      V1FeatureGate.passeggiata &&
      _learningStepController.currentStep.index >=
      LearningStep.step5Consolidation.index;

  // ── OVERLAY BUILDER ──────────────────────────────────────────────────────

  /// Builds the Passeggiata overlay widget (vignette + guided path).
  ///
  /// Called from the UI overlay layer in `_ui_overlays.dart`.
  Widget? buildPasseggiataOverlay() {
    if (!_isPasseggiataActive) return null;

    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: PasseggiataOverlayPainter(
          pathProgress: _passeggiataPathProgress,
          guidedPathPoints: _passeggiataGuidedPath,
          canvasScale: _canvasController.scale,
          showGuidedPath: _passeggiataGuidedPath.length >= 2,
        ),
      ),
    );
  }

  // ── PRIVATE HELPERS ──────────────────────────────────────────────────────

  /// Calculates a guided path through cluster centroids.
  ///
  /// Uses nearest-neighbor heuristic for spatial ordering (greedy TSP).
  /// This produces a natural "walk through the palace" path.
  List<Offset> _calculateGuidedPath() {
    if (_clusterCache.isEmpty) return const [];

    // Extract centroids
    final centroids = _clusterCache
        .map((c) => c.centroid)
        .toList();

    if (centroids.length <= 1) return centroids;

    // Nearest-neighbor path (greedy spatial ordering)
    final path = <Offset>[];
    final remaining = List<Offset>.from(centroids);

    // Start from the top-left-most centroid
    remaining.sort((a, b) {
      final da = a.dx + a.dy;
      final db = b.dx + b.dy;
      return da.compareTo(db);
    });

    var current = remaining.removeAt(0);
    path.add(current);

    while (remaining.isNotEmpty) {
      // Find nearest unvisited centroid
      double minDist = double.infinity;
      int nearestIdx = 0;

      for (int i = 0; i < remaining.length; i++) {
        final dx = remaining[i].dx - current.dx;
        final dy = remaining[i].dy - current.dy;
        final dist = dx * dx + dy * dy; // squared distance (no sqrt needed)
        if (dist < minDist) {
          minDist = dist;
          nearestIdx = i;
        }
      }

      current = remaining.removeAt(nearestIdx);
      path.add(current);
    }

    return path;
  }
}
