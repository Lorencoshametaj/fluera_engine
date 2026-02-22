part of '../nebula_canvas_screen.dart';

// ============================================================================
// 🛠️ DEV HANDOFF — Wire inspect engine, redline calculator, code generator
// ============================================================================

extension DevHandoffFeatures on _NebulaCanvasScreenState {
  /// Toggle inspect mode.
  /// Wires: inspect_engine
  void _toggleInspectMode() {
    setState(() {
      _isInspectModeActive = !_isInspectModeActive;
    });
    if (_isInspectModeActive) {
      _activeInspectEngine = const InspectEngine();
      debugPrint('[Design] Inspect mode ON');
    } else {
      _activeInspectEngine = null;
      debugPrint('[Design] Inspect mode OFF');
    }
  }

  /// Toggle redline overlay.
  /// Wires: redline_overlay (RedlineCalculator)
  void _toggleRedlineOverlay() {
    setState(() {
      _isRedlineActive = !_isRedlineActive;
    });
    debugPrint('[Design] Redline overlay ${_isRedlineActive ? "ON" : "OFF"}');
  }

  /// Show code generator panel.
  /// Wires: code_generator, asset_manifest, token_resolver
  void _showCodeGenerator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const DevHandoffPanel(),
    );
    debugPrint('[Design] Code generator opened');
  }
}
