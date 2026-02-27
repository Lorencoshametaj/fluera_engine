part of '../fluera_canvas_screen.dart';

/// 📦 Canvas Operations (Undo/Redo/Clear) — extracted from _FlueraCanvasScreenState
extension on _FlueraCanvasScreenState {
  void _undo() {
    // ⏪ Command-based undo (variable ops, node ops, etc.)
    if (_commandHistory.canUndo) {
      _commandHistory.undo();
      setState(() {});
      _autoSaveCanvas();
      HapticFeedback.lightImpact();
      return;
    }

    // Altrimenti undo sul layer corrente
    _layerController.undoLastElement();
    // 🚀 Invalidate tile cache (l'undo potrebbe rimuovere strokes)
    DrawingPainter.invalidateAllTiles();
    // 💾 AUTO-SAVE after undo
    _autoSaveCanvas();
  }

  void _redo() {
    // ⏪ Command-based redo (variable ops, node ops, etc.)
    if (_commandHistory.canRedo) {
      _commandHistory.redo();
      setState(() {});
      _autoSaveCanvas();
      HapticFeedback.lightImpact();
      return;
    }

    // Altrimenti redo sul layer corrente
    if (_undoStack.isEmpty) return;
    final restored = _undoStack.removeLast();
    _layerController.addStroke(restored);
    // 🚀 Invalidate tile cache for the nuovo stroke
    DrawingPainter.invalidateTilesForStroke(restored);
    // 💾 AUTO-SAVE after redo
    _autoSaveCanvas();
  }

  void _clear() {
    _layerController.clearActiveLayer();
    _undoStack.clear();
    _commandHistory.clear();
    _currentStrokeNotifier.clear();
    // 🚀 Invalidate the entire tile cache
    DrawingPainter.invalidateAllTiles();
    // 💾 AUTO-SAVE after clear
    _autoSaveCanvas();
  }

  /// 📄 Show paper type / canvas settings dialog (Looponia-style MD3).
  void _showPaperTypePicker() {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    CanvasSettingsDialog.show(
      context,
      isDark: isDark,
      currentBackgroundColor: _canvasBackgroundColor,
      currentPaperType: _paperType,
      currentSurface: _activeSurface,
      onBackgroundColorChanged: (color) {
        setState(() => _canvasBackgroundColor = color);
        BackgroundPainter.clearCache();
        DrawingPainter.invalidateAllTiles();
        _autoSaveCanvas();
      },
      onPaperTypeChanged: _changePaperType,
      onSurfaceChanged: _changeSurface,
    );
  }

  /// 📄 Change the canvas paper/background type.
  void _changePaperType(String newType) {
    if (_paperType == newType) return;
    setState(() {
      _paperType = newType;
    });
    // Update the tool controller
    _toolController.setPaperType(newType);
    // Clear cached background so it redraws with new paper type
    BackgroundPainter.clearCache();
    // Invalidate drawing tiles (paper pattern is baked into export tiles)
    DrawingPainter.invalidateAllTiles();
    // Auto-save with new paper type
    _autoSaveCanvas();
  }

  /// 🧬 Change the active surface material.
  void _changeSurface(SurfaceMaterial? surface) {
    if (_activeSurface == surface) return;
    setState(() {
      _activeSurface = surface;
    });
    // 🧬 Sync static fallback so ALL renderers (tile cache, scene graph, etc.)
    // use the correct surface without explicit parameter passing.
    BrushEngine.activeSurface = surface;
    // Invalidate tile cache — surface affects stroke rendering
    DrawingPainter.invalidateAllTiles();
    _autoSaveCanvas();
  }
}
