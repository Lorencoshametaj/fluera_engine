part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Alignment & Distribution (delegates to SelectionManager)
// =============================================================================

extension LassoAlignment on LassoTool {
  // ===========================================================================
  // Alignment
  // ===========================================================================

  void _alignLeft() {
    if (!hasSelection) return;
    selectionManager.alignLeft();
    _calculateSelectionBounds();
  }

  void _alignRight() {
    if (!hasSelection) return;
    selectionManager.alignRight();
    _calculateSelectionBounds();
  }

  void _alignCenterH() {
    if (!hasSelection) return;
    selectionManager.alignCenterH();
    _calculateSelectionBounds();
  }

  void _alignTop() {
    if (!hasSelection) return;
    selectionManager.alignTop();
    _calculateSelectionBounds();
  }

  void _alignBottom() {
    if (!hasSelection) return;
    selectionManager.alignBottom();
    _calculateSelectionBounds();
  }

  void _alignCenterV() {
    if (!hasSelection) return;
    selectionManager.alignCenterV();
    _calculateSelectionBounds();
  }

  // ===========================================================================
  // Distribution
  // ===========================================================================

  void _distributeHorizontal() {
    if (selectionCount < 3) return;
    selectionManager.distributeHorizontally();
    _calculateSelectionBounds();
  }

  void _distributeVertical() {
    if (selectionCount < 3) return;
    selectionManager.distributeVertically();
    _calculateSelectionBounds();
  }
}
