part of '../fluera_canvas_screen.dart';

/// 📊 Tabular Clipboard — copy/cut/paste, sorting, row/col ops, merge,
/// keyboard navigation, and cell clearing.
extension FlueraCanvasTabularClipboard on _FlueraCanvasScreenState {
  // ── Row / Column management ──────────────────────────────────────────

  /// Insert a row after the currently selected row (or at end).
  void _insertRow() {
    final node = _tabularTool.selectedTabular;
    if (node == null) return;

    final insertAt = (_tabularTool.selectedRow ?? node.visibleRows - 1) + 1;
    _commandHistory.execute(InsertRowCommand(node: node, rowIndex: insertAt));
    node.visibleRows++;
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Delete the currently selected row.
  void _deleteRow() {
    final node = _tabularTool.selectedTabular;
    final row = _tabularTool.selectedRow;
    if (node == null || row == null) return;
    if (node.visibleRows <= 1) return; // Keep at least 1 row

    _commandHistory.execute(DeleteRowCommand(node: node, rowIndex: row));
    node.visibleRows--;
    _tabularTool.deselectCell();
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Insert a column after the currently selected column (or at end).
  void _insertColumn() {
    final node = _tabularTool.selectedTabular;
    if (node == null) return;

    final insertAt = (_tabularTool.selectedCol ?? node.visibleColumns - 1) + 1;
    _commandHistory.execute(
      InsertColumnCommand(node: node, columnIndex: insertAt),
    );
    node.visibleColumns++;
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Delete the currently selected column.
  void _deleteColumn() {
    final node = _tabularTool.selectedTabular;
    final col = _tabularTool.selectedCol;
    if (node == null || col == null) return;
    if (node.visibleColumns <= 1) return; // Keep at least 1 column

    _commandHistory.execute(DeleteColumnCommand(node: node, columnIndex: col));
    node.visibleColumns--;
    _tabularTool.deselectCell();
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    setState(() {});
    _autoSaveCanvas();
  }

  // ── Merge / Unmerge cells ────────────────────────────────────────────

  /// Merge the currently selected cell range into a single merged cell.
  void _mergeCells() {
    final node = _tabularTool.selectedTabular;
    final range = _tabularTool.selectedRange;
    if (node == null || range == null) return;

    final colSpan = range.endColumn - range.startColumn + 1;
    final rowSpan = range.endRow - range.startRow + 1;
    if (colSpan <= 1 && rowSpan <= 1) return;

    try {
      node.mergeManager.addRegion(range);
    } on ArgumentError {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot merge — overlaps existing merged region'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final masterAddr = CellAddress(range.startColumn, range.startRow);
    for (final addr in range.addresses) {
      if (addr != masterAddr) {
        node.evaluator.clearCellAndEvaluate(addr);
      }
    }

    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.mediumImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Unmerge the merge region containing the currently selected cell.
  void _unmergeCells() {
    final node = _tabularTool.selectedTabular;
    final col = _tabularTool.selectedCol;
    final row = _tabularTool.selectedRow;
    if (node == null || col == null || row == null) return;

    final addr = CellAddress(col, row);
    final removed = node.mergeManager.removeRegionAt(addr);
    if (removed == null) return;

    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  // ── Clipboard operations ─────────────────────────────────────────────

  /// Copy selected cells to system clipboard.
  Future<void> _copySelection() async {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;

    await TabularClipboard.copy(node.model, range);
    HapticFeedback.lightImpact();
  }

  /// Cut selected cells (copy + clear).
  Future<void> _cutSelection() async {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;

    await TabularClipboard.cut(node.model, range);
    node.evaluator.evaluateAll();
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.mediumImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Paste from system clipboard at the selected cell position.
  Future<void> _pasteAtSelection() async {
    final node = _tabularTool.selectedTabular;
    final col = _tabularTool.selectedCol;
    final row = _tabularTool.selectedRow;
    if (node == null || col == null || row == null) return;

    final data = await TabularClipboard.paste();
    if (data == null || data.isEmpty) return;

    _commandHistory.execute(
      PasteRangeCommand(
        node: node,
        startAddress: CellAddress(col, row),
        values: data,
      ),
    );
    node.evaluator.evaluateAll();
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  // ── Sorting ──────────────────────────────────────────────────────────

  /// Sort data rows by a column in ascending or descending order.
  void _sortByColumn({required int column, required bool ascending}) {
    final node = _tabularTool.selectedTabular;
    if (node == null) return;

    final firstDataRow = 0;
    final lastRow = node.visibleRows - 1;
    if (lastRow <= firstDataRow) return;

    final rowData = <int, Map<int, CellValue>>{};
    for (int r = firstDataRow; r <= lastRow; r++) {
      final cells = <int, CellValue>{};
      for (int c = 0; c < node.visibleColumns; c++) {
        final cell = node.model.getCell(CellAddress(c, r));
        if (cell != null) cells[c] = cell.value;
      }
      rowData[r] = cells;
    }

    final sortedRows =
        rowData.keys.toList()..sort((a, b) {
          final va = rowData[a]?[column];
          final vb = rowData[b]?[column];
          final na = va?.asNumber;
          final nb = vb?.asNumber;

          int result;
          if (na != null && nb != null) {
            result = na.compareTo(nb);
          } else {
            result = (va?.displayString ?? '').compareTo(
              vb?.displayString ?? '',
            );
          }
          return ascending ? result : -result;
        });

    for (int i = 0; i < sortedRows.length; i++) {
      final targetRow = firstDataRow + i;
      final sourceData = rowData[sortedRows[i]]!;
      for (int c = 0; c < node.visibleColumns; c++) {
        final addr = CellAddress(c, targetRow);
        final val = sourceData[c];
        if (val != null) {
          node.model.setCell(addr, CellNode(value: val));
        } else {
          node.model.clearCell(addr);
        }
      }
    }

    node.evaluator.evaluateAll();
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  // ── Clear content ────────────────────────────────────────────────────

  /// Clear content of selected cells (Del key).
  void _clearSelectedCells() {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;

    for (final addr in range.addresses) {
      node.model.clearCell(addr);
    }

    node.evaluator.evaluateAll();
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  // ── Keyboard navigation ──────────────────────────────────────────────

  /// Move selection up by one row.
  void _moveUp() {
    if (_tabularTool.selectedRow == null || _tabularTool.selectedRow! <= 0) {
      return;
    }
    _tabularTool.selectCell(
      _tabularTool.selectedCol!,
      _tabularTool.selectedRow! - 1,
    );
    setState(() {});
  }

  /// Move selection down (alias for _onFormulaBarSubmit without saving).
  void _moveDownNav() {
    _tabularTool.moveDown();
    setState(() {});
  }

  /// Move selection left.
  void _moveLeft() {
    if (_tabularTool.selectedCol == null || _tabularTool.selectedCol! <= 0) {
      return;
    }
    _tabularTool.selectCell(
      _tabularTool.selectedCol! - 1,
      _tabularTool.selectedRow!,
    );
    setState(() {});
  }

  /// Move selection right (alias).
  void _moveRightNav() {
    _tabularTool.moveRight();
    setState(() {});
  }
}
