part of '../nebula_canvas_screen.dart';

/// 📊 Tabular Handler — core node creation, cell editing, formula bar,
/// value detection, and linked LaTeX refresh.
///
/// Related extensions:
///  • [NebulaCanvasTabularFillHandle]  — _tabular_fill_handle.dart
///  • [NebulaCanvasTabularClipboard]   — _tabular_clipboard.dart
///  • [NebulaCanvasTabularFormatting]  — _tabular_formatting.dart
///  • [NebulaCanvasTabularCsv]         — _tabular_csv_import.dart
///  • [NebulaCanvasTabularLatexExport] — _tabular_latex_export.dart
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
  String? _getSelectedCellDisplayValue() {
    final node = _tabularTool.selectedTabular;
    final col = _tabularTool.selectedCol;
    final row = _tabularTool.selectedRow;
    if (node == null || col == null || row == null) return null;

    final addr = CellAddress(col, row);
    final cell = node.model.getCell(addr);
    if (cell == null) return '';

    if (cell.value is FormulaValue) {
      return '=${(cell.value as FormulaValue).expression}';
    }
    return cell.value.displayString;
  }

  /// Called when the formula bar TextField submits (Enter key).
  void _onFormulaBarSubmit(String value) {
    final col = _tabularTool.selectedCol;
    final row = _tabularTool.selectedRow;
    if (col == null || row == null) return;

    _setCellValue(col, row, value);
    _tabularTool.moveDown();
    setState(() {});
  }

  /// Called when Tab is pressed in the formula bar.
  void _onFormulaBarTab(String value) {
    final col = _tabularTool.selectedCol;
    final row = _tabularTool.selectedRow;
    if (col == null || row == null) return;

    _setCellValue(col, row, value);
    _tabularTool.moveRight();
    setState(() {});
  }

  // ── Effective range helper ───────────────────────────────────────────

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
}
