part of 'lasso_tool.dart';

// =============================================================================
// LassoTool — Clipboard Operations (copy, paste, duplicate)
// =============================================================================

extension LassoClipboard on LassoTool {
  /// Internal clipboard — stores cloned nodes.
  static List<CanvasNode> _clipboardNodes = [];

  /// Copy selected elements to the internal clipboard (as cloned CanvasNodes).
  void _copySelected() {
    if (!hasSelection) return;
    _clipboardNodes =
        selectionManager.selectedNodes.map((n) => n.clone()).toList();
  }

  /// Paste clipboard contents into the active layer with a slight offset.
  ///
  /// Each pasted element gets a new unique ID (via clone).
  /// Returns the number of elements pasted.
  int _pasteFromClipboard({Offset offset = const Offset(20, 20)}) {
    if (_clipboardNodes.isEmpty) return 0;

    final layerNode = _getActiveLayerNode();
    final pastedNodes = <CanvasNode>[];

    for (final original in _clipboardNodes) {
      final pasted = original.clone();
      pasted.translate(offset.dx, offset.dy);
      layerNode.add(pasted);
      pastedNodes.add(pasted);
    }

    // Auto-select the pasted elements
    selectionManager.selectAll(pastedNodes);
    _calculateSelectionBounds();

    return pastedNodes.length;
  }

  /// Duplicate selected elements in-place with a slight offset.
  ///
  /// Combines copy + paste — the duplicated elements become the new selection.
  int _duplicateSelected({Offset offset = const Offset(20, 20)}) {
    _copySelected();
    return _pasteFromClipboard(offset: offset);
  }
}
