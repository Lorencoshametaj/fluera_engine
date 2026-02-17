part of '../../nebula_canvas_screen.dart';

/// 📦 Build UI — orchestrator that delegates to:
///   • [_ui_toolbar.dart]      → _buildToolbar()
///   • [_ui_canvas_layer.dart] → _buildCanvasArea()
///   • [_ui_eraser.dart]       → _buildEraserOverlays()
///   • [_ui_overlays.dart]     → _buildRemoteOverlays(), _buildStandardOverlays(), _buildToolOverlays()
///   • [_ui_menus.dart]        → _buildMenus()
extension on _NebulaCanvasScreenState {
  // ============================================================================
  // BUILD — Main entry point
  // ============================================================================

  Widget _buildImpl(BuildContext context) {
    // 🎨 Eagerly load brush presets (async, no-op if already loaded)
    if (!_presetsLoaded) {
      _brushPresetManager.load().then((_) {
        if (mounted) {
          _presetsLoaded = true;
          setState(() {});
        }
      });
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // ✒️ Delegate key events to pen tool when active
        if (_toolController.isPenToolMode) {
          final consumed = _penTool.handleKeyEvent(event, _penToolContext);
          if (consumed) {
            setState(() {});
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              // Main content: toolbar + canvas
              Column(
                children: [
                  // 🛠️ Professional Toolbar
                  _buildToolbar(context),

                  // 🎨 Infinite Canvas with Zoom & Pan
                  _buildCanvasArea(context),
                ],
              ),

              // 🎯 Context Menus & Panels (above everything)
              ..._buildMenus(context),
            ],
          ),
        ),
      ),
    ); // Focus + Scaffold
  }
}
