part of '../fluera_canvas_screen.dart';

// ============================================================================
// 🚧 PENDING FEATURES — Stub methods for not-yet-implemented features
// ============================================================================

extension PendingFeatures on _FlueraCanvasScreenState {
  /// 🤝 Jump viewport to followed user's cursor position.
  void _jumpToFollowedUser(String userId) {
    // Collaboration: implement follow-user viewport jump
  }

  /// 🖥️ Launch the advanced split view system.
  ///
  /// Uses a 2-phase transition to avoid raster spike:
  /// - Frame 1: Set transitioning flag → renders lightweight blank surface
  ///            (disposes old canvas DrawingPainter, Vulkan, overlays)
  /// - Frame 2: Activate multiview → creates orchestrator on clean slate
  ///
  /// 🚀 Uses _multiviewVersionNotifier instead of setState to rebuild ONLY
  /// the canvas area, not the entire 2500+ line screen widget tree.
  void _launchAdvancedSplitView() {
    // Phase 1: Transition out — disposes old canvas tree, shows blank surface
    _isMultiviewTransitioning = true;
    _multiviewVersionNotifier.value++;

    // Phase 2: Create multiview — scheduled for next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _isMultiviewTransitioning = false;
      _isMultiviewActive = true;
      _multiviewLayout = AdvancedSplitLayout(
        type: SplitLayoutType.split2,
        primaryOrientation: SplitOrientation.horizontal,
        secondaryOrientation: SplitOrientation.vertical,
        panelContents: {
          0: SplitPanelContent.canvas(),
          1: SplitPanelContent.canvas(),
        },
        proportions: const {'panel_0': 0.5, 'panel_1': 0.5},
      );
      _multiviewVersionNotifier.value++;
    });
  }
}
