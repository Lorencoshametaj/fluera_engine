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
  void _launchAdvancedSplitView() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => MultiviewOrchestrator(
              config: _config,
              canvasId: _canvasId,
              title: _noteTitle,
              initialLayout: AdvancedSplitLayout(
                type: SplitLayoutType.split2,
                primaryOrientation: SplitOrientation.horizontal,
                secondaryOrientation: SplitOrientation.vertical,
                panelContents: {
                  0: SplitPanelContent.canvas(),
                  1: SplitPanelContent.canvas(),
                },
                proportions: const {'panel_0': 0.5, 'panel_1': 0.5},
              ),
              onExitMultiview: () => Navigator.of(context).pop(),
            ),
      ),
    );
  }
}
