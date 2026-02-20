part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Transforms (delegates to SelectionManager)
// =============================================================================

extension LassoTransforms on LassoTool {
  /// Rotate selected elements 90° clockwise.
  void _rotateSelected90() {
    if (!hasSelection) return;
    selectionManager.rotateAll(pi / 2);
    _calculateSelectionBounds();
  }

  /// Rotate selected elements by an arbitrary angle in radians.
  void _rotateSelectedByAngle(double radians, {Offset? center}) {
    if (!hasSelection) return;
    selectionManager.rotateAll(radians);
    _calculateSelectionBounds();
  }

  /// Scale selected elements by a uniform factor.
  void _scaleSelected(double factor, {Offset? center}) {
    if (!hasSelection) return;
    selectionManager.scaleAll(factor, factor);
    _calculateSelectionBounds();
  }

  /// Flip selected elements horizontally around the selection center.
  void _flipHorizontal() {
    if (!hasSelection) return;
    selectionManager.flipHorizontal();
    _calculateSelectionBounds();
  }

  /// Flip selected elements vertically around the selection center.
  void _flipVertical() {
    if (!hasSelection) return;
    selectionManager.flipVertical();
    _calculateSelectionBounds();
  }
}
