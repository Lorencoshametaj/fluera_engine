part of '../nebula_canvas_screen.dart';

/// 📦 Canvas Operations (Undo/Redo/Clear) — extracted from _NebulaCanvasScreenState
extension on _NebulaCanvasScreenState {
  void _undo() {
    // In mode editing immagine, undo sugli strokes of the image
    if (_imageInEditMode != null) {
      if (_imageEditingStrokes.isEmpty) return;

      setState(() {
        final removed = _imageEditingStrokes.removeLast();
        _imageEditingUndoStack.add(removed);
      });

      HapticFeedback.lightImpact();
      return;
    }

    // Altrimenti undo sul layer corrente
    _layerController.undoLastElement();
    // 🚀 Invalidate tile cache (l'undo potrebbe rimuovere strokes)
    DrawingPainter.invalidateAllTiles();
    // 💾 AUTO-SAVE dopo undo
    _autoSaveCanvas();
  }

  void _redo() {
    // In mode editing immagine, redo sugli strokes of the image
    if (_imageInEditMode != null) {
      if (_imageEditingUndoStack.isEmpty) return;

      setState(() {
        final restored = _imageEditingUndoStack.removeLast();
        _imageEditingStrokes.add(restored);
      });

      HapticFeedback.lightImpact();
      return;
    }

    // Altrimenti redo sul layer corrente
    if (_undoStack.isEmpty) return;
    final restored = _undoStack.removeLast();
    _layerController.addStroke(restored);
    // 🚀 Invalidate tile cache for the nuovo stroke
    DrawingPainter.invalidateTilesForStroke(restored);
    // 💾 AUTO-SAVE dopo redo
    _autoSaveCanvas();
  }

  void _clear() {
    _layerController.clearActiveLayer();
    _undoStack.clear();
    _currentStrokeNotifier.clear();
    // 🚀 Invalidate tutta la tile cache
    DrawingPainter.invalidateAllTiles();
    // 💾 AUTO-SAVE dopo clear
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
      onBackgroundColorChanged: (color) {
        setState(() => _canvasBackgroundColor = color);
        BackgroundPainter.clearCache();
        DrawingPainter.invalidateAllTiles();
        _autoSaveCanvas();
      },
      onPaperTypeChanged: _changePaperType,
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
    // Invalidatete drawing tiles (paper pattern is baked into export tiles)
    DrawingPainter.invalidateAllTiles();
    // Auto-save with new paper type
    _autoSaveCanvas();
  }
}
