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

    // Add to the active layer's stable node (rootNode is ephemeral).
    final activeTabLayer = _layerController.activeLayer;
    if (activeTabLayer == null) return;
    _commandHistory.execute(
      AddTabularNodeCommand(parent: activeTabLayer.node, tabularNode: node),
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
    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    setState(() {});
    _autoSaveCanvas();
  }

  /// 🔄 Refresh all LatexNodes that are linked to the given TabularNode.
  ///
  /// Walks through all layers to find LatexNodes with a matching
  /// `sourceTabularId`, then regenerates their LaTeX source from the
  /// live evaluator data.
  void _refreshLinkedLatexNodes(TabularNode tabular) {
    if (!EngineScope.hasScope) return;
    final tabularId = tabular.id.toString();

    for (final layer in _layerController.layers) {
      for (final child in layer.node.children) {
        if (child is LatexNode &&
            child.sourceTabularId == tabularId &&
            child.sourceRangeLabel != null) {
          String newSource;

          if (child.chartType != null) {
            // Regenerate TikZ chart source.
            final rangeMatch = RegExp(
              r'([A-Z]+\d+):([A-Z]+\d+)',
            ).firstMatch(child.sourceRangeLabel!);
            if (rangeMatch == null) continue;
            final start = CellAddress.fromLabel(rangeMatch.group(1)!);
            final end = CellAddress.fromLabel(rangeMatch.group(2)!);
            final chartType = TikzChartType.values.firstWhere(
              (t) => t.name == child.chartType,
              orElse: () => TikzChartType.bar,
            );
            final gen = TikzChartGenerator(tabular.evaluator);
            newSource = gen.generate(
              CellRange(start, end),
              chartType,
              opts: TikzChartOptions(
                title: 'Chart from ${child.sourceRangeLabel}',
                headers: true,
              ),
            );

            // Also refresh chart data for visual rendering.
            final range = CellRange(start, end);
            final dataStartRow = range.startRow + 1;
            final newLabels = <String>[];
            for (int r = dataStartRow; r <= range.endRow; r++) {
              final cv = tabular.evaluator.getComputedValue(
                CellAddress(range.startColumn, r),
              );
              if (cv is TextValue) {
                newLabels.add(cv.value);
              } else if (cv is NumberValue) {
                newLabels.add(cv.value.toString());
              } else {
                newLabels.add('R$r');
              }
            }
            final newValues = <List<double>>[];
            for (int c = range.startColumn + 1; c <= range.endColumn; c++) {
              final series = <double>[];
              for (int r = dataStartRow; r <= range.endRow; r++) {
                final cv = tabular.evaluator.getComputedValue(
                  CellAddress(c, r),
                );
                if (cv is NumberValue) {
                  series.add(cv.value.toDouble());
                } else {
                  series.add(0);
                }
              }
              newValues.add(series);
            }
            child.chartLabels = newLabels;
            child.chartValues = newValues;
            // Refresh series names from header row.
            final newSeriesNames = <String>[];
            for (int c = range.startColumn + 1; c <= range.endColumn; c++) {
              final hcv = tabular.evaluator.getComputedValue(
                CellAddress(c, range.startRow),
              );
              if (hcv is TextValue && hcv.value.isNotEmpty) {
                newSeriesNames.add(hcv.value);
              } else {
                newSeriesNames.add('Series ${c - range.startColumn}');
              }
            }
            child.chartSeriesNames = newSeriesNames;
          } else {
            // Regenerate LaTeX table source.
            final renderer = LatexReportTemplate(
              tabular.evaluator,
              mergeManager: tabular.mergeManager,
            );
            newSource = renderer.render(
              '{TABLE(${child.sourceRangeLabel}, headers=true)}',
            );
          }

          if (newSource != child.latexSource) {
            child.latexSource = newSource;
          }
        }
      }
    }
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

  // ── Merge / Unmerge cells ────────────────────────────────────────────

  /// Merge the currently selected cell range into a single merged cell.
  ///
  /// The value of the top-left (master) cell is kept; all other cells
  /// in the range are cleared. Does nothing if less than 2 cells are
  /// selected or the range overlaps an existing merge.
  void _mergeCells() {
    final node = _tabularTool.selectedTabular;
    final range = _tabularTool.selectedRange;
    if (node == null || range == null) return;

    // Need at least 2 cells to merge.
    final colSpan = range.endColumn - range.startColumn + 1;
    final rowSpan = range.endRow - range.startRow + 1;
    if (colSpan <= 1 && rowSpan <= 1) return;

    // Try adding the merge region (will throw if overlapping).
    try {
      node.mergeManager.addRegion(range);
    } on ArgumentError {
      // Overlap — show feedback and bail.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot merge — overlaps existing merged region'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Keep the top-left cell value, clear the rest.
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
    if (removed == null) return; // Not merged — nothing to do.

    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
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

  // ── Fill handle state ─────────────────────────────────────────────────

  /// Known smart sequences for auto-fill.
  static const _smartSequences = <List<String>>[
    // English days (short + full).
    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ],
    // Italian days.
    ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'],
    [
      'Lunedì',
      'Martedì',
      'Mercoledì',
      'Giovedì',
      'Venerdì',
      'Sabato',
      'Domenica',
    ],
    // English months (short + full).
    [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ],
    [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ],
    // Italian months.
    [
      'Gen',
      'Feb',
      'Mar',
      'Apr',
      'Mag',
      'Giu',
      'Lug',
      'Ago',
      'Set',
      'Ott',
      'Nov',
      'Dic',
    ],
    [
      'Gennaio',
      'Febbraio',
      'Marzo',
      'Aprile',
      'Maggio',
      'Giugno',
      'Luglio',
      'Agosto',
      'Settembre',
      'Ottobre',
      'Novembre',
      'Dicembre',
    ],
    // Quarters.
    ['Q1', 'Q2', 'Q3', 'Q4'],
  ];

  /// Tracks the last filled cell addresses for ripple animation.
  static List<CellAddress> _lastFilledAddresses = [];

  /// Timestamp when the last fill operation completed (for ripple animation).
  static DateTime? _lastFillTime;

  /// Simple power for doubles (avoids dart:math import in part file).
  static double _pow(double base, int exp) {
    if (exp == 0) return 1.0;
    double result = 1.0;
    final absExp = exp.abs();
    for (int i = 0; i < absExp; i++) {
      result *= base;
    }
    return exp < 0 ? 1.0 / result : result;
  }

  /// Compute the preview value that would be placed at [targetRow] for [col]
  /// during a fill-down operation. Used by the tooltip overlay.
  String _computeFillPreviewValue(int col, int targetRow) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return '';

    final sourceRowCount = range.endRow - range.startRow + 1;

    final sourceValues = <CellValue>[];
    final sourceCells = <CellNode?>[];
    for (int r = range.startRow; r <= range.endRow; r++) {
      final cell = node.model.getCell(CellAddress(col, r));
      sourceCells.add(cell);
      sourceValues.add(cell?.value ?? const EmptyValue());
    }

    final hasFormulas = sourceCells.any((c) => c != null && c.isFormula);
    final nums = sourceValues.map((v) => v.asNumber).toList();
    final allNumeric =
        nums.every((n) => n != null) && nums.length >= 2 && !hasFormulas;

    double? step;
    double? ratio;
    if (allNumeric && nums.length >= 2) {
      step = nums[1]! - nums[0]!;
      if (nums[0]! != 0) {
        final r0 = nums[1]! / nums[0]!;
        bool isGeometric = r0 != 1.0;
        for (int i = 2; i < nums.length && isGeometric; i++) {
          if (nums[i - 1]! == 0 || (nums[i]! / nums[i - 1]!) != r0) {
            isGeometric = false;
          }
        }
        if (isGeometric) ratio = r0;
      }
    }

    final smartSeq = _detectSmartSequence(sourceValues);
    final sourceIdx = (targetRow - (range.endRow + 1)) % sourceRowCount;
    final sourceRow = range.startRow + sourceIdx;
    final sourceCell = sourceCells[sourceIdx];

    if (hasFormulas && sourceCell != null && sourceCell.isFormula) {
      final rowDelta = targetRow - sourceRow;
      final formula = (sourceCell.value as FormulaValue).expression;
      return '=${_shiftFormulaReferences(formula, 0, rowDelta)}';
    } else if (smartSeq != null) {
      final seq = smartSeq.$1;
      final startIdx = smartSeq.$2;
      final seqIdx =
          (startIdx + sourceRowCount + (targetRow - range.startRow)) %
          seq.length;
      return seq[seqIdx];
    } else if (allNumeric && ratio != null) {
      final lastNum = nums.last!;
      final fillIdx = targetRow - range.endRow;
      final newVal = lastNum * _pow(ratio, fillIdx);
      return NumberValue(newVal).displayString;
    } else if (allNumeric && step != null) {
      final lastNum = nums.last!;
      final fillIdx = targetRow - range.endRow;
      final newVal = lastNum + step * fillIdx;
      return NumberValue(newVal).displayString;
    } else {
      return sourceValues[sourceIdx].displayString;
    }
  }

  /// Dispatch fill result to the appropriate direction handler.
  void _performFill(
    ({FillDirection dir, int targetRow, int targetCol}) result,
  ) {
    final range = _getEffectiveRange();
    if (range == null) return;

    switch (result.dir) {
      case FillDirection.down:
        _performFillDown(range.endRow + 1, result.targetRow);
      case FillDirection.up:
        _performFillUp(result.targetRow, range.startRow - 1);
      case FillDirection.right:
        _performFillRight(range.endColumn + 1, result.targetCol);
      case FillDirection.left:
        _performFillLeft(result.targetCol, range.startColumn - 1);
    }
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

    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Fill from the selected range downward to [fillEndRow] (inclusive).
  ///
  /// Handles:
  /// - **Formulas**: shifts cell references (A1 → A2, B3 → B4, etc.)
  /// - **Numeric sequences**: detects arithmetic step (1,2,3 → 4,5,6)
  /// - **Pattern repetition**: cycles text values
  void _performFillDown(int fillStartRow, int fillEndRow) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;
    if (fillStartRow > fillEndRow) return;

    final sourceRowCount = range.endRow - range.startRow + 1;
    final filledAddrs = <CellAddress>[];

    for (int c = range.startColumn; c <= range.endColumn; c++) {
      final sourceCells = <CellNode?>[];
      final sourceValues = <CellValue>[];
      for (int r = range.startRow; r <= range.endRow; r++) {
        final cell = node.model.getCell(CellAddress(c, r));
        sourceCells.add(cell);
        sourceValues.add(cell?.value ?? const EmptyValue());
      }

      final hasFormulas = sourceCells.any((c) => c != null && c.isFormula);
      final nums = sourceValues.map((v) => v.asNumber).toList();
      final allNumeric =
          nums.every((n) => n != null) && nums.length >= 2 && !hasFormulas;

      // Detect arithmetic vs geometric sequence.
      double? step;
      double? ratio;
      if (allNumeric && nums.length >= 2) {
        step = nums[1]! - nums[0]!;
        // Check geometric: all ratios must be equal and non-zero divisor.
        if (nums[0]! != 0) {
          final r0 = nums[1]! / nums[0]!;
          bool isGeometric = r0 != 1.0;
          for (int i = 2; i < nums.length && isGeometric; i++) {
            if (nums[i - 1]! == 0 || (nums[i]! / nums[i - 1]!) != r0) {
              isGeometric = false;
            }
          }
          if (isGeometric) ratio = r0;
        }
      }

      final smartSeq = _detectSmartSequence(sourceValues);

      for (int targetRow = fillStartRow; targetRow <= fillEndRow; targetRow++) {
        if (targetRow >= node.effectiveRows + 50) break;

        final sourceIdx = (targetRow - fillStartRow) % sourceRowCount;
        final sourceRow = range.startRow + sourceIdx;
        final sourceCell = sourceCells[sourceIdx];
        final addr = CellAddress(c, targetRow);

        // Fill value.
        if (hasFormulas && sourceCell != null && sourceCell.isFormula) {
          final rowDelta = targetRow - sourceRow;
          final formula = (sourceCell.value as FormulaValue).expression;
          final shifted = _shiftFormulaReferences(formula, 0, rowDelta);
          node.evaluator.setCellAndEvaluate(addr, FormulaValue(shifted));
        } else if (smartSeq != null) {
          final seq = smartSeq.$1;
          final startIdx = smartSeq.$2;
          final seqIdx =
              (startIdx + sourceRowCount + (targetRow - range.startRow)) %
              seq.length;
          node.evaluator.setCellAndEvaluate(addr, TextValue(seq[seqIdx]));
        } else if (allNumeric && ratio != null) {
          // Geometric sequence (2, 4, 8, 16...).
          final lastNum = nums.last!;
          final fillIdx = targetRow - range.endRow;
          final newVal = lastNum * _pow(ratio, fillIdx);
          node.evaluator.setCellAndEvaluate(addr, NumberValue(newVal));
        } else if (allNumeric && step != null) {
          final lastNum = nums.last!;
          final fillIdx = targetRow - range.endRow;
          final newVal = lastNum + step * fillIdx;
          node.evaluator.setCellAndEvaluate(addr, NumberValue(newVal));
        } else {
          node.evaluator.setCellAndEvaluate(addr, sourceValues[sourceIdx]);
        }

        // Copy formatting from source cell.
        if (sourceCell?.format != null) {
          final targetCell = node.model.getCell(addr);
          if (targetCell != null) {
            targetCell.format = sourceCell!.format;
          }
        }

        filledAddrs.add(addr);
      }
    }

    _tabularTool.extendSelection(range.endColumn, fillEndRow);
    _lastFilledAddresses = filledAddrs;
    _lastFillTime = DateTime.now();
    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Shift cell references in a formula expression by [deltaCol] columns
  /// and [deltaRow] rows.
  ///
  /// Example: `_shiftFormulaReferences("A1+B2", 0, 1)` → `"A2+B3"`
  static String _shiftFormulaReferences(
    String formula,
    int deltaCol,
    int deltaRow,
  ) {
    // Match cell references like A1, B23, AA5, etc.
    // Supports optional $ for absolute references (skips them).
    final regex = RegExp(r'(\$?)([A-Z]+)(\$?)(\d+)');

    return formula.replaceAllMapped(regex, (match) {
      final colAbsolute = match.group(1) == r'$';
      final colLetters = match.group(2)!;
      final rowAbsolute = match.group(3) == r'$';
      final rowNum = int.parse(match.group(4)!);

      // Compute new column letters.
      String newCol = colLetters;
      if (!colAbsolute && deltaCol != 0) {
        int colIdx = 0;
        for (int i = 0; i < colLetters.length; i++) {
          colIdx = colIdx * 26 + (colLetters.codeUnitAt(i) - 65);
        }
        colIdx = (colIdx + deltaCol).clamp(0, 16383);
        newCol = '';
        int temp = colIdx;
        do {
          newCol = String.fromCharCode(65 + temp % 26) + newCol;
          temp = temp ~/ 26 - 1;
        } while (temp >= 0);
      }

      // Compute new row number.
      int newRow = rowNum;
      if (!rowAbsolute) {
        newRow = (rowNum + deltaRow).clamp(1, 99999);
      }

      return '${colAbsolute ? r"$" : ""}$newCol'
          '${rowAbsolute ? r"$" : ""}$newRow';
    });
  }

  /// Detect if the source values match a known smart sequence.
  /// Returns (sequence, startIndex) or null.
  static (List<String>, int)? _detectSmartSequence(List<CellValue> values) {
    if (values.isEmpty) return null;
    final texts = values.map((v) => v.displayString.trim()).toList();
    if (texts.any((t) => t.isEmpty)) return null;

    for (final seq in _smartSequences) {
      final firstIdx = seq.indexWhere(
        (s) => s.toLowerCase() == texts[0].toLowerCase(),
      );
      if (firstIdx < 0) continue;

      bool match = true;
      for (int i = 1; i < texts.length; i++) {
        final expected = seq[(firstIdx + i) % seq.length].toLowerCase();
        if (texts[i].toLowerCase() != expected) {
          match = false;
          break;
        }
      }
      if (match) return (seq, firstIdx);
    }
    return null;
  }

  /// Fill upward from [fillStartRow] to [fillEndRow] (inclusive).
  void _performFillUp(int fillStartRow, int fillEndRow) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;
    if (fillStartRow > fillEndRow) return;

    final sourceRowCount = range.endRow - range.startRow + 1;

    for (int c = range.startColumn; c <= range.endColumn; c++) {
      final sourceCells = <CellNode?>[];
      final sourceValues = <CellValue>[];
      for (int r = range.startRow; r <= range.endRow; r++) {
        final cell = node.model.getCell(CellAddress(c, r));
        sourceCells.add(cell);
        sourceValues.add(cell?.value ?? const EmptyValue());
      }

      final hasFormulas = sourceCells.any((c) => c != null && c.isFormula);
      final nums = sourceValues.map((v) => v.asNumber).toList();
      final allNumeric =
          nums.every((n) => n != null) && nums.length >= 2 && !hasFormulas;
      double? step;
      if (allNumeric) step = nums[1]! - nums[0]!;
      final smartSeq = _detectSmartSequence(sourceValues);

      for (int targetRow = fillEndRow; targetRow >= fillStartRow; targetRow--) {
        if (targetRow < 0) break;
        final distFromStart = range.startRow - targetRow;
        final sourceIdx =
            ((sourceRowCount - (distFromStart % sourceRowCount)) %
                sourceRowCount);
        final sourceRow = range.startRow + sourceIdx;
        final sourceCell = sourceCells[sourceIdx];
        final addr = CellAddress(c, targetRow);

        if (hasFormulas && sourceCell != null && sourceCell.isFormula) {
          final rowDelta = targetRow - sourceRow;
          final formula = (sourceCell.value as FormulaValue).expression;
          final shifted = _shiftFormulaReferences(formula, 0, rowDelta);
          node.evaluator.setCellAndEvaluate(addr, FormulaValue(shifted));
        } else if (smartSeq != null) {
          final seq = smartSeq.$1;
          final startIdx = smartSeq.$2;
          final seqIdx =
              ((startIdx - distFromStart) % seq.length + seq.length) %
              seq.length;
          node.evaluator.setCellAndEvaluate(addr, TextValue(seq[seqIdx]));
        } else if (allNumeric && step != null) {
          final firstNum = nums.first!;
          final newVal = firstNum - step * distFromStart;
          node.evaluator.setCellAndEvaluate(addr, NumberValue(newVal));
        } else {
          node.evaluator.setCellAndEvaluate(addr, sourceValues[sourceIdx]);
        }
      }
    }

    _tabularTool.extendSelection(range.endColumn, fillStartRow);
    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Fill rightward from [fillStartCol] to [fillEndCol] (inclusive).
  void _performFillRight(int fillStartCol, int fillEndCol) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;
    if (fillStartCol > fillEndCol) return;

    final sourceColCount = range.endColumn - range.startColumn + 1;

    for (int r = range.startRow; r <= range.endRow; r++) {
      final sourceCells = <CellNode?>[];
      final sourceValues = <CellValue>[];
      for (int c = range.startColumn; c <= range.endColumn; c++) {
        final cell = node.model.getCell(CellAddress(c, r));
        sourceCells.add(cell);
        sourceValues.add(cell?.value ?? const EmptyValue());
      }

      final hasFormulas = sourceCells.any((c) => c != null && c.isFormula);
      final nums = sourceValues.map((v) => v.asNumber).toList();
      final allNumeric =
          nums.every((n) => n != null) && nums.length >= 2 && !hasFormulas;
      double? step;
      if (allNumeric) step = nums[1]! - nums[0]!;

      for (int targetCol = fillStartCol; targetCol <= fillEndCol; targetCol++) {
        if (targetCol >= node.effectiveColumns + 50) break;
        final sourceIdx = (targetCol - fillStartCol) % sourceColCount;
        final sourceCol = range.startColumn + sourceIdx;
        final sourceCell = sourceCells[sourceIdx];
        final addr = CellAddress(targetCol, r);

        if (hasFormulas && sourceCell != null && sourceCell.isFormula) {
          final colDelta = targetCol - sourceCol;
          final formula = (sourceCell.value as FormulaValue).expression;
          final shifted = _shiftFormulaReferences(formula, colDelta, 0);
          node.evaluator.setCellAndEvaluate(addr, FormulaValue(shifted));
        } else if (allNumeric && step != null) {
          final lastNum = nums.last!;
          final fillIdx = targetCol - range.endColumn;
          node.evaluator.setCellAndEvaluate(
            addr,
            NumberValue(lastNum + step * fillIdx),
          );
        } else {
          node.evaluator.setCellAndEvaluate(addr, sourceValues[sourceIdx]);
        }
      }
    }

    _tabularTool.extendSelection(fillEndCol, range.endRow);
    _refreshLinkedLatexNodes(node);
    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    HapticFeedback.lightImpact();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Fill leftward from [fillStartCol] to [fillEndCol] (inclusive).
  void _performFillLeft(int fillStartCol, int fillEndCol) {
    final node = _tabularTool.selectedTabular;
    final range = _getEffectiveRange();
    if (node == null || range == null) return;
    if (fillStartCol > fillEndCol) return;

    final sourceColCount = range.endColumn - range.startColumn + 1;

    for (int r = range.startRow; r <= range.endRow; r++) {
      final sourceCells = <CellNode?>[];
      final sourceValues = <CellValue>[];
      for (int c = range.startColumn; c <= range.endColumn; c++) {
        final cell = node.model.getCell(CellAddress(c, r));
        sourceCells.add(cell);
        sourceValues.add(cell?.value ?? const EmptyValue());
      }

      final hasFormulas = sourceCells.any((c) => c != null && c.isFormula);
      final nums = sourceValues.map((v) => v.asNumber).toList();
      final allNumeric =
          nums.every((n) => n != null) && nums.length >= 2 && !hasFormulas;
      double? step;
      if (allNumeric) step = nums[1]! - nums[0]!;

      for (int targetCol = fillEndCol; targetCol >= fillStartCol; targetCol--) {
        if (targetCol < 0) break;
        final distFromStart = range.startColumn - targetCol;
        final sourceIdx =
            ((sourceColCount - (distFromStart % sourceColCount)) %
                sourceColCount);
        final sourceCol = range.startColumn + sourceIdx;
        final sourceCell = sourceCells[sourceIdx];
        final addr = CellAddress(targetCol, r);

        if (hasFormulas && sourceCell != null && sourceCell.isFormula) {
          final colDelta = targetCol - sourceCol;
          final formula = (sourceCell.value as FormulaValue).expression;
          final shifted = _shiftFormulaReferences(formula, colDelta, 0);
          node.evaluator.setCellAndEvaluate(addr, FormulaValue(shifted));
        } else if (allNumeric && step != null) {
          final firstNum = nums.first!;
          node.evaluator.setCellAndEvaluate(
            addr,
            NumberValue(firstNum - step * distFromStart),
          );
        } else {
          node.evaluator.setCellAndEvaluate(addr, sourceValues[sourceIdx]);
        }
      }
    }

    _tabularTool.extendSelection(fillStartCol, range.endRow);
    _refreshLinkedLatexNodes(node);
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
    // This ensures that presets like "inside" (outer=false) and "none"
    // actually remove the line, since the renderer uses OR logic:
    // a line is drawn if EITHER adjacent cell wants it.
    _syncNeighborBorders(node, minC, maxC, minR, maxR);

    _layerController.sceneGraph.bumpVersion();
    DrawingPainter.invalidateAllTiles();
    setState(() {});
    _autoSaveCanvas();
  }

  /// Sync neighbor borders to match the selection's edge borders.
  ///
  /// For each cell on the edge of the selection, reads its outer border
  /// value and copies it to the facing border of the neighbor cell.
  /// This ensures that adjacent cells always agree:
  ///  - "All"     → edge.top=true  → neighbor above gets bottom=true  (restore)
  ///  - "Inside"  → edge.top=false → neighbor above gets bottom=false (clear)
  ///  - "Outline" → edge.top=true  → neighbor above gets bottom=true  (restore)
  ///  - "None"    → edge.top=false → neighbor above gets bottom=false (clear)
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

    final activeTabLayer2 = _layerController.activeLayer;
    if (activeTabLayer2 == null) return;
    _commandHistory.execute(
      AddTabularNodeCommand(parent: activeTabLayer2.node, tabularNode: node),
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

    // Create the LaTeX node with reactive binding to the source tabular
    final latexNodeId = generateUid();
    final latexNode = LatexNode(
      id: NodeId(latexNodeId),
      name: 'Generated Table',
      latexSource: latexSource,
      sourceTabularId: node.id.toString(),
      sourceRangeLabel: range.label,
    );

    latexNode.localTransform.setTranslationRaw(insertX, insertY, 0);

    // Add to the active layer's stable node (not sceneGraph.layers which is ephemeral).
    final activeLayer = _layerController.activeLayer;
    if (activeLayer == null) return;
    _commandHistory.execute(
      AddLatexNodeCommand(parent: activeLayer.node, latexNode: latexNode),
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

  // ── TikZ Chart Generation ──────────────────────────────────────────────

  /// Generate a TikZ/pgfplots chart from the selected spreadsheet range.
  void _generateChartFromSelection() {
    final node = _tabularTool.selectedTabular;
    final range = _tabularTool.selectedRange;
    if (node == null || range == null) return;
    if (!EngineScope.hasScope) return;

    // Show chart type picker dialog
    showDialog<TikzChartType>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text(
            'Select Chart Type',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _chartTypeOption(
                  ctx,
                  TikzChartType.bar,
                  Icons.bar_chart,
                  'Bar Chart',
                  'Compare values by category',
                ),
                const SizedBox(height: 8),
                _chartTypeOption(
                  ctx,
                  TikzChartType.line,
                  Icons.show_chart,
                  'Line Chart',
                  'Show trends over time',
                ),
                const SizedBox(height: 8),
                _chartTypeOption(
                  ctx,
                  TikzChartType.scatter,
                  Icons.scatter_plot,
                  'Scatter Plot',
                  'Show data distribution',
                ),
                const SizedBox(height: 8),
                _chartTypeOption(
                  ctx,
                  TikzChartType.pie,
                  Icons.pie_chart,
                  'Pie Chart',
                  'Show proportions',
                ),
                const SizedBox(height: 8),
                _chartTypeOption(
                  ctx,
                  TikzChartType.area,
                  Icons.area_chart,
                  'Area Chart',
                  'Filled trends over time',
                ),
                const SizedBox(height: 8),
                _chartTypeOption(
                  ctx,
                  TikzChartType.stacked_bar,
                  Icons.stacked_bar_chart,
                  'Stacked Bar',
                  'Compare composition',
                ),
                const SizedBox(height: 8),
                _chartTypeOption(
                  ctx,
                  TikzChartType.hbar,
                  Icons.align_horizontal_left,
                  'Horizontal Bar',
                  'Horizontal value comparison',
                ),
                const SizedBox(height: 8),
                _chartTypeOption(
                  ctx,
                  TikzChartType.radar,
                  Icons.hexagon_outlined,
                  'Radar / Spider',
                  'Multi-dimensional analysis',
                ),
                const SizedBox(height: 8),
                _chartTypeOption(
                  ctx,
                  TikzChartType.waterfall,
                  Icons.waterfall_chart,
                  'Waterfall',
                  'Cumulative positive/negative',
                ),
                const SizedBox(height: 8),
                _chartTypeOption(
                  ctx,
                  TikzChartType.bubble,
                  Icons.bubble_chart,
                  'Bubble Chart',
                  'Variable-size data points',
                ),
              ],
            ),
          ),
        );
      },
    ).then((selectedType) async {
      if (selectedType == null) return;

      // ── Merge detection ───────────────────────────────────────────
      final hasMerges = node.mergeManager.regions.any(
        (mr) =>
            mr.startColumn <= range.endColumn &&
            mr.endColumn >= range.startColumn &&
            mr.startRow <= range.endRow &&
            mr.endRow >= range.startRow,
      );

      if (hasMerges) {
        final proceed = await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E2E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFFFB74D),
                      size: 24,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Merged Cells Detected',
                      style: TextStyle(
                        color: Color(0xFFF0F0FF),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                content: const Text(
                  'The selected range contains merged cells.\n\n'
                  'Merged cells will use the master cell value only — '
                  'slave cells will be skipped to avoid duplicate zeros.',
                  style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 13),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Color(0x80FFFFFF)),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C4DFF),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Continue'),
                  ),
                ],
              ),
        );
        if (proceed != true) return;
      }

      final gen = TikzChartGenerator(node.evaluator);
      final tikzSource = gen.generate(
        range,
        selectedType,
        opts: TikzChartOptions(
          title: 'Chart from ${range.label}',
          headers: true,
        ),
      );

      // Extract raw chart data — skip slave cells from merge regions.
      final startCol = range.startColumn;
      final endCol = range.endColumn;
      final dataStartRow = range.startRow + 1; // skip header row
      final endRow = range.endRow;
      final mm = node.mergeManager;

      final chartLabels = <String>[];
      for (int r = dataStartRow; r <= endRow; r++) {
        final addr = CellAddress(startCol, r);
        if (mm.isHiddenByMerge(addr)) continue; // skip slave
        final cv = node.evaluator.getComputedValue(addr);
        if (cv is TextValue) {
          chartLabels.add(cv.value);
        } else if (cv is NumberValue) {
          chartLabels.add(cv.value.toString());
        } else {
          chartLabels.add('R$r');
        }
      }

      final chartValues = <List<double>>[];
      for (int c = startCol + 1; c <= endCol; c++) {
        final series = <double>[];
        for (int r = dataStartRow; r <= endRow; r++) {
          final addr = CellAddress(c, r);
          if (mm.isHiddenByMerge(addr)) continue; // skip slave
          final cv = node.evaluator.getComputedValue(addr);
          if (cv is NumberValue) {
            series.add(cv.value.toDouble());
          } else if (cv is TextValue) {
            series.add(double.tryParse(cv.value) ?? 0);
          } else {
            series.add(0);
          }
        }
        chartValues.add(series);
      }
      // Extract series names from header row.
      final seriesNames = <String>[];
      for (int c = startCol + 1; c <= endCol; c++) {
        final cv = node.evaluator.getComputedValue(
          CellAddress(c, range.startRow),
        );
        if (cv is TextValue && cv.value.isNotEmpty) {
          seriesNames.add(cv.value);
        } else {
          seriesNames.add('Series ${c - startCol}');
        }
      }

      // Place the LaTeX node to the right of the table
      final tableWidth = node.model.totalWidth(node.visibleColumns);
      final insertX = node.localTransform.getTranslation().x + tableWidth + 50;
      final insertY = node.localTransform.getTranslation().y;

      final latexNodeId = generateUid();
      final typeLabel =
          '${selectedType.name[0].toUpperCase()}${selectedType.name.substring(1)}';
      final latexNode = LatexNode(
        id: NodeId(latexNodeId),
        name: '$typeLabel Chart',
        latexSource: tikzSource,
        sourceTabularId: node.id.toString(),
        sourceRangeLabel: range.label,
        chartType: selectedType.name,
        chartLabels: chartLabels,
        chartValues: chartValues,
        chartSeriesNames: seriesNames,
      );
      latexNode.localTransform.setTranslationRaw(insertX, insertY, 0);

      final activeLayer2 = _layerController.activeLayer;
      if (activeLayer2 == null) return;
      _commandHistory.execute(
        AddLatexNodeCommand(parent: activeLayer2.node, latexNode: latexNode),
      );

      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${selectedType.name.toUpperCase()} Chart Generated'),
          duration: const Duration(seconds: 2),
        ),
      );

      _layerController.sceneGraph.bumpVersion();
      setState(() {});
      _autoSaveCanvas();
    });
  }

  /// Helper widget for chart type picker options.
  Widget _chartTypeOption(
    BuildContext ctx,
    TikzChartType type,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(ctx).pop(type),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A3E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3A3A50)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF7C4DFF), size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF7C4DFF),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── LaTeX → Spreadsheet Import ─────────────────────────────────────────

  /// Import LaTeX table/matrix source into a new TabularNode.
  void _importLatexToSpreadsheet() {
    // Show a dialog for the user to paste LaTeX source
    showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Import LaTeX Table',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 500,
            child: TextField(
              controller: controller,
              maxLines: 12,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: r'Paste \begin{tabular}...\end{tabular} here',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Import'),
            ),
          ],
        );
      },
    ).then((latexSource) {
      if (latexSource == null || latexSource.trim().isEmpty) return;

      final parser = LatexTableParser();
      final parsed = parser.parse(latexSource);
      if (parsed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid LaTeX table found'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // Create a new TabularNode with parsed data
      final cols = parsed.columnCount;
      final rows = parsed.totalRows;
      _addTabularNode(columns: cols.clamp(1, 50), rows: rows.clamp(1, 200));

      // Wait for next frame so the node exists, then populate cells
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Find the most recently added tabular node
        final allNodes =
            _layerController.sceneGraph.nodeIndexIds
                .map((id) => _layerController.findNodeById(id))
                .whereType<TabularNode>()
                .toList();
        if (allNodes.isEmpty) return;

        final targetNode = allNodes.last;
        final allRows = parsed.allRows;
        for (int r = 0; r < allRows.length; r++) {
          for (int c = 0; c < allRows[r].length; c++) {
            final text = allRows[r][c];
            if (text.isEmpty) continue;
            final addr = CellAddress(c, r);
            final numVal = num.tryParse(text);
            if (numVal != null) {
              targetNode.evaluator.setCellAndEvaluate(
                addr,
                NumberValue(numVal),
              );
            } else {
              targetNode.evaluator.setCellAndEvaluate(addr, TextValue(text));
            }
          }
        }
        _layerController.sceneGraph.bumpVersion();
        setState(() {});
      });

      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported ${parsed.environment} → $cols×$rows table'),
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  // ── .tex File Export ────────────────────────────────────────────────────

  /// Export all LaTeX nodes to a .tex file.
  void _exportTexFile() {
    final exporter = LatexFileExporter();
    final texContent = exporter.exportDocument(
      _layerController.sceneGraph,
      options: const TexExportOptions(
        title: 'Nebula Engine — LaTeX Export',
        addComments: true,
      ),
    );

    // Copy to clipboard (cross-platform safe)
    Clipboard.setData(ClipboardData(text: texContent));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('.tex document copied to clipboard'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}
