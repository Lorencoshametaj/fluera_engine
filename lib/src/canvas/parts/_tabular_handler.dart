part of '../nebula_canvas_screen.dart';

/// 📊 Tabular Handler — creates a TabularNode and adds it to the scene graph.
extension NebulaCanvasTabularHandler on _NebulaCanvasScreenState {
  /// Create a new [TabularNode] at the current viewport center and add it
  /// to the scene graph via the command history (undo/redo support).
  ///
  /// [columns] and [rows] set the visible grid dimensions.
  void _addTabularNode({int columns = 10, int rows = 20}) {
    // Compute viewport center in canvas coordinates.
    final viewportSize = MediaQuery.of(context).size;
    final viewportCenterX =
        (-_canvasController.offset.dx + viewportSize.width / 2) /
        _canvasController.scale;
    final viewportCenterY =
        (-_canvasController.offset.dy + viewportSize.height / 2) /
        _canvasController.scale;

    final node = TabularNode(
      id: NodeId(generateUid()),
      name: 'Spreadsheet',
      visibleColumns: columns,
      visibleRows: rows,
    );

    // Calculate table pixel dimensions to center it properly.
    final tableWidth = node.model.totalWidth(columns) + 40; // +row header
    final tableHeight = node.model.totalHeight(rows) + 24; // +col header

    // Place so the TABLE CENTER is at viewport center.
    node.localTransform.setTranslationRaw(
      viewportCenterX - tableWidth / 2,
      viewportCenterY - tableHeight / 2,
      0,
    );

    // Add to scene graph root via undo-able command.
    final rootGroup = _layerController.sceneGraph.rootNode;
    _commandHistory.execute(
      AddTabularNodeCommand(parent: rootGroup, tabularNode: node),
    );

    // Bump version + persist.
    _layerController.sceneGraph.bumpVersion();
    setState(() {});
    _autoSaveCanvas();
  }

  /// 🗑️ Delete the currently selected TabularNode.
  void _deleteSelectedTabular() {
    final node = _tabularTool.selectedTabular;
    if (node == null) return;

    // Find parent group
    final rootGroup = _layerController.sceneGraph.rootNode;
    _tabularTool.deselectTabular();

    _commandHistory.execute(
      DeleteTabularNodeCommand(parent: rootGroup, tabularNode: node),
    );

    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.mediumImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// ✏️ Show a cell editor dialog for the first cell (0,0) by default,
  /// or for a tapped cell if called from double-tap.
  void _showCellEditorForCenter() {
    _showCellEditor(0, 0);
  }

  /// ✏️ Show cell editor dialog for a specific cell.
  void _showCellEditor(int col, int row) {
    final node = _tabularTool.selectedTabular;
    if (node == null) return;

    final addr = CellAddress(col, row);
    final cell = node.model.getCell(addr);
    final currentValue = cell?.displayValue.toString() ?? '';
    final controller = TextEditingController(text: currentValue);

    // Column letter (A, B, C, ...)
    final colLabel = String.fromCharCode(65 + col);
    final cellRef = '$colLabel${row + 1}';

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          icon: Icon(Icons.edit_rounded, color: cs.primary, size: 24),
          title: Text('Cell $cellRef'),
          content: SizedBox(
            width: 280,
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter value or formula',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.functions_rounded, size: 20),
              ),
              onSubmitted: (_) {
                Navigator.of(ctx).pop();
                _setCellValue(col, row, controller.text);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _setCellValue(col, row, controller.text);
              },
              child: const Text('Set'),
            ),
          ],
        );
      },
    );
  }

  /// Apply a cell value and refresh the table.
  /// Auto-detects: formulas (=…), numbers, booleans, text.
  void _setCellValue(int col, int row, String value) {
    final node = _tabularTool.selectedTabular;
    if (node == null) return;

    final addr = CellAddress(col, row);
    final cellValue = _detectCellValue(value);
    node.evaluator.setCellAndEvaluate(addr, cellValue);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Auto-detect cell value type from user input string.
  CellValue _detectCellValue(String raw) {
    if (raw.isEmpty) return const TextValue('');

    // Formula: starts with =
    if (raw.startsWith('=')) {
      return FormulaValue(raw.substring(1));
    }

    // Boolean
    final upper = raw.toUpperCase();
    if (upper == 'TRUE') return const BoolValue(true);
    if (upper == 'FALSE') return const BoolValue(false);

    // Number
    final num? n = num.tryParse(raw);
    if (n != null) return NumberValue(n);

    // Text
    return TextValue(raw);
  }

  // ── Formula Bar helpers ──────────────────────────────────────────────

  /// Returns the display value of the currently selected cell.
  /// For formula cells, shows the raw formula expression with = prefix.
  String? _getSelectedCellDisplayValue() {
    final node = _tabularTool.selectedTabular;
    final col = _tabularTool.selectedCol;
    final row = _tabularTool.selectedRow;
    if (node == null || col == null || row == null) return null;

    final addr = CellAddress(col, row);
    final cell = node.model.getCell(addr);
    if (cell == null) return '';

    // Show raw formula with = prefix for editing
    if (cell.value is FormulaValue) {
      return '=${(cell.value as FormulaValue).expression}';
    }
    return cell.value.displayString;
  }

  /// Called when the formula bar TextField submits (Enter key).
  /// Saves the value to the selected cell, moves selection down.
  void _onFormulaBarSubmit(String value) {
    final col = _tabularTool.selectedCol;
    final row = _tabularTool.selectedRow;
    if (col == null || row == null) return;

    _setCellValue(col, row, value);
    _tabularTool.moveDown(); // Navigate to next row
    setState(() {}); // Rebuild → formula bar shows new cell
  }

  /// Called when Tab is pressed in the formula bar.
  /// Saves the value to the selected cell, moves selection right.
  void _onFormulaBarTab(String value) {
    final col = _tabularTool.selectedCol;
    final row = _tabularTool.selectedRow;
    if (col == null || row == null) return;

    _setCellValue(col, row, value);
    _tabularTool.moveRight(); // Navigate to next column
    setState(() {});
  }

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

  // ── Clipboard operations ─────────────────────────────────────────────

  /// Get the effective range: the multi-cell range if selected,
  /// or a single-cell range from the active cell.
  CellRange? _getEffectiveRange() {
    final range = _tabularTool.selectedRange;
    if (range != null) return range;
    final col = _tabularTool.selectedCol;
    final row = _tabularTool.selectedRow;
    if (col == null || row == null) return null;
    return CellRange(CellAddress(col, row), CellAddress(col, row));
  }

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
  /// Header row (row 0) is left in place if [skipHeader] is true.
  void _sortByColumn({required int column, required bool ascending}) {
    final node = _tabularTool.selectedTabular;
    if (node == null) return;

    final firstDataRow = 0; // Can skip headers if needed
    final lastRow = node.visibleRows - 1;
    if (lastRow <= firstDataRow) return;

    // Collect all row data
    final rowData = <int, Map<int, CellValue>>{};
    for (int r = firstDataRow; r <= lastRow; r++) {
      final cells = <int, CellValue>{};
      for (int c = 0; c < node.visibleColumns; c++) {
        final cell = node.model.getCell(CellAddress(c, r));
        if (cell != null) cells[c] = cell.value;
      }
      rowData[r] = cells;
    }

    // Sort row indices by the values in the target column
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

    // Write sorted data back
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

  // ── Auto-fill ────────────────────────────────────────────────────────

  /// Auto-fill from the selected cell/range downward by [count] rows.
  /// Detects numeric sequences and repeats text patterns.
  void _autoFillDown({int count = 5}) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;

    // For each column in the range, detect pattern and fill
    for (int c = range.startColumn; c <= range.endColumn; c++) {
      final sourceValues = <CellValue>[];
      for (int r = range.startRow; r <= range.endRow; r++) {
        final cell = node.model.getCell(CellAddress(c, r));
        sourceValues.add(cell?.value ?? const EmptyValue());
      }

      // Detect numeric sequence
      final nums = sourceValues.map((v) => v.asNumber).toList();
      final allNumeric = nums.every((n) => n != null) && nums.length >= 2;
      double? step;
      if (allNumeric && nums.length >= 2) {
        step = nums[1]! - nums[0]!;
      }

      // Fill below the range
      for (int i = 0; i < count; i++) {
        final targetRow = range.endRow + 1 + i;
        if (targetRow >= node.visibleRows) break;

        final addr = CellAddress(c, targetRow);
        if (allNumeric && step != null) {
          // Arithmetic sequence
          final lastNum = nums.last!;
          final newVal = lastNum + step * (i + 1);
          node.evaluator.setCellAndEvaluate(addr, NumberValue(newVal));
        } else {
          // Repeat pattern
          final patternIdx = i % sourceValues.length;
          node.evaluator.setCellAndEvaluate(addr, sourceValues[patternIdx]);
        }
      }
    }

    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

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

  // ── CSV import ───────────────────────────────────────────────────────

  /// Show file picker and import CSV into a new table.
  void _importCsv(String csvText) {
    if (csvText.isEmpty) return;

    final model = TabularCsv.import(csvText);
    final maxCol = model.maxColumn + 1;
    final maxRow = model.maxRow + 1;

    final viewportSize = MediaQuery.of(context).size;
    final cx =
        (-_canvasController.offset.dx + viewportSize.width / 2) /
        _canvasController.scale;
    final cy =
        (-_canvasController.offset.dy + viewportSize.height / 2) /
        _canvasController.scale;

    final node = TabularNode(
      id: NodeId(generateUid()),
      name: 'Imported CSV',
      visibleColumns: maxCol.clamp(1, 26),
      visibleRows: maxRow.clamp(1, 100),
    );

    // Copy all cells from parsed model
    for (final addr in model.occupiedAddresses) {
      final cell = model.getCell(addr);
      if (cell != null) node.model.setCell(addr, cell.clone());
    }

    final tableWidth = node.model.totalWidth(node.visibleColumns) + 50;
    final tableHeight = node.model.totalHeight(node.visibleRows) + 28;
    node.localTransform.setTranslationRaw(
      cx - tableWidth / 2,
      cy - tableHeight / 2,
      0,
    );

    final rootGroup = _layerController.sceneGraph.rootNode;
    _commandHistory.execute(
      AddTabularNodeCommand(parent: rootGroup, tabularNode: node),
    );

    node.evaluator.evaluateAll();
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Export the selected table to CSV string.
  String _exportCsv() {
    final node = _tabularTool.selectedTabular;
    if (node == null) return '';
    return TabularCsv.export(node.model);
  }

  // ── Frozen header ────────────────────────────────────────────────────

  /// Whether the selected table has a frozen header row.
  bool _hasFrozenRow() {
    return (_tabularTool.selectedTabular?.model.frozenRows ?? 0) > 0;
  }

  /// Toggle frozen header row on/off.
  void _toggleFreezeRow() {
    final node = _tabularTool.selectedTabular;
    if (node == null) return;

    node.model.frozenRows = node.model.frozenRows > 0 ? 0 : 1;
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  // ── Excel-to-LaTeX Integration ────────────────────────────────────────

  /// Generate a LateX table from the selected spreadsheet range.
  void _generateLatexFromSelection() {
    final node = _tabularTool.selectedTabular;
    final range = _tabularTool.selectedRange;
    if (node == null || range == null) return;

    if (!EngineScope.hasScope) return;

    // Use LatexReportTemplate directly on the active cell evaluator
    final renderer = LatexReportTemplate(node.evaluator);

    // Generate LaTeX source code from the spreadsheet range dynamically via a TABLE directive
    final latexSource = renderer.render(
      '{TABLE(${range.label}, headers=true)}',
    );

    // Calculate the insertion point (slightly to the right of the table)
    final tableWidth = node.model.totalWidth(node.visibleColumns);
    final insertX = node.localTransform.getTranslation().x + tableWidth + 50;
    final insertY = node.localTransform.getTranslation().y;

    // Create the LaTeX node
    final latexNodeId = generateUid();
    final latexNode = LatexNode(
      id: NodeId(latexNodeId),
      name: 'Generated Table',
      latexSource: latexSource,
    );

    latexNode.localTransform.setTranslationRaw(insertX, insertY, 0);

    // Add to scene graph root via undo-able command
    final rootGroup = _layerController.sceneGraph.rootNode;
    _commandHistory.execute(
      AddLatexNodeCommand(parent: rootGroup, latexNode: latexNode),
    );

    // Provide haptic feedback and visual confirmation
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('LaTeX Table Generated'),
        duration: Duration(seconds: 2),
      ),
    );

    _layerController.sceneGraph.bumpVersion();
    setState(() {});
    _autoSaveCanvas();
  }
}
