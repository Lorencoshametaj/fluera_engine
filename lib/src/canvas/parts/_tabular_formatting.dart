part of '../fluera_canvas_screen.dart';

/// 📊 Tabular Formatting — bold, italic, alignment, borders, colors, clear.
extension FlueraCanvasTabularFormatting on _FlueraCanvasScreenState {
  // ── Cell formatting ──────────────────────────────────────────────────

  /// Get the format of the currently selected cell (for toolbar state).
  CellFormat? _getSelectedCellFormat() {
    final node = _tabularTool.selectedTabular;
    final col = _tabularTool.selectedCol;
    final row = _tabularTool.selectedRow;
    if (node == null || col == null || row == null) return null;
    return node.model.getCell(CellAddress(col, row))?.format;
  }

  /// Apply a format transform to all cells in the effective range.
  void _applyFormat(CellFormat Function(CellFormat?) transform) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;

    for (final addr in range.addresses) {
      final cell = node.model.getCell(addr);
      if (cell != null) {
        cell.format = transform(cell.format);
      } else {
        // Create empty cell with format
        node.model.setCell(
          addr,
          CellNode(value: const EmptyValue(), format: transform(null)),
        );
      }
    }

    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Toggle bold on/off for the selected cells.
  void _toggleBold() {
    final current = _getSelectedCellFormat();
    final newBold = !(current?.bold ?? false);
    _applyFormat((f) => (f ?? const CellFormat()).copyWith(bold: newBold));
  }

  /// Toggle italic on/off for the selected cells.
  void _toggleItalic() {
    final current = _getSelectedCellFormat();
    final newItalic = !(current?.italic ?? false);
    _applyFormat((f) => (f ?? const CellFormat()).copyWith(italic: newItalic));
  }

  /// Set horizontal alignment for selected cells.
  void _setAlignment(CellAlignment align) {
    _applyFormat(
      (f) => (f ?? const CellFormat()).copyWith(horizontalAlign: align),
    );
  }

  /// Apply a border preset to the selected cells.
  ///
  /// Presets:
  /// - `all` — all borders on every cell
  /// - `none` — no borders on any cell
  /// - `outline` — borders only on outer edges of the selection
  /// - `inside` — borders only between cells (no outer edges)
  /// - `bottom` — only the bottom border of each cell
  void _setBorderPreset(String preset) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;

    final minC = range.startColumn;
    final maxC = range.endColumn;
    final minR = range.startRow;
    final maxR = range.endRow;

    for (final addr in range.addresses) {
      final c = addr.column;
      final r = addr.row;
      final isTop = r == minR;
      final isBottom = r == maxR;
      final isLeft = c == minC;
      final isRight = c == maxC;

      CellBorders borders;
      switch (preset) {
        case 'all':
          borders = CellBorders.all;
          break;
        case 'none':
          borders = CellBorders.none;
          break;
        case 'outline':
          borders = CellBorders(
            top: isTop,
            bottom: isBottom,
            left: isLeft,
            right: isRight,
          );
          break;
        case 'inside':
          borders = CellBorders(
            top: !isTop,
            bottom: !isBottom,
            left: !isLeft,
            right: !isRight,
          );
          break;
        case 'bottom':
          borders = const CellBorders(
            top: false,
            bottom: true,
            left: false,
            right: false,
          );
          break;
        default:
          borders = CellBorders.all;
      }

      final cell = node.model.getCell(addr);
      if (cell != null) {
        cell.format = (cell.format ?? const CellFormat()).copyWith(
          borders: borders,
        );
      } else {
        node.model.setCell(
          addr,
          CellNode(
            value: const EmptyValue(),
            format: CellFormat(borders: borders),
          ),
        );
      }
    }

    // Clear facing borders on neighbor cells outside the selection.
    _syncNeighborBorders(node, minC, maxC, minR, maxR);

    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Sync neighbor borders to match the selection's edge borders.
  void _syncNeighborBorders(
    dynamic node,
    int minC,
    int maxC,
    int minR,
    int maxR,
  ) {
    CellBorders _getBorders(int c, int r) {
      final cell = node.model.getCell(CellAddress(c, r));
      return cell?.format?.borders ?? CellBorders.all;
    }

    void _patchBorder(CellAddress addr, CellBorders Function(CellBorders) fn) {
      final cell = node.model.getCell(addr);
      final current = cell?.format?.borders ?? CellBorders.all;
      final patched = fn(current);
      if (cell != null) {
        cell.format = (cell.format ?? const CellFormat()).copyWith(
          borders: patched,
        );
      } else {
        node.model.setCell(
          addr,
          CellNode(
            value: const EmptyValue(),
            format: CellFormat(borders: patched),
          ),
        );
      }
    }

    // Top edge → sync with row above.
    if (minR > 0) {
      for (int c = minC; c <= maxC; c++) {
        final edgeTop = _getBorders(c, minR).top;
        _patchBorder(
          CellAddress(c, minR - 1),
          (b) => b.copyWith(bottom: edgeTop),
        );
      }
    }
    // Bottom edge → sync with row below.
    for (int c = minC; c <= maxC; c++) {
      final edgeBottom = _getBorders(c, maxR).bottom;
      _patchBorder(
        CellAddress(c, maxR + 1),
        (b) => b.copyWith(top: edgeBottom),
      );
    }
    // Left edge → sync with column to the left.
    if (minC > 0) {
      for (int r = minR; r <= maxR; r++) {
        final edgeLeft = _getBorders(minC, r).left;
        _patchBorder(
          CellAddress(minC - 1, r),
          (b) => b.copyWith(right: edgeLeft),
        );
      }
    }
    // Right edge → sync with column to the right.
    for (int r = minR; r <= maxR; r++) {
      final edgeRight = _getBorders(maxC, r).right;
      _patchBorder(
        CellAddress(maxC + 1, r),
        (b) => b.copyWith(left: edgeRight),
      );
    }
  }

  /// Set text color for selected cells.
  void _setTextColor(Color color) {
    _applyFormat((f) => (f ?? const CellFormat()).copyWith(textColor: color));
  }

  /// Set background color for selected cells.
  void _setBackgroundColor(Color color) {
    _applyFormat(
      (f) => (f ?? const CellFormat()).copyWith(backgroundColor: color),
    );
  }

  /// Clear all formatting from selected cells.
  void _clearFormatting() {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;

    for (final addr in range.addresses) {
      final cell = node.model.getCell(addr);
      if (cell != null) cell.format = null;
    }

    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    setState(() {});
    _autoSaveCanvas();
  }
}
