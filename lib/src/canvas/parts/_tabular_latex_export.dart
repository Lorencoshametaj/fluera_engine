part of '../nebula_canvas_screen.dart';

/// 📊 Tabular LaTeX Export — LaTeX tables, TikZ charts, LaTeX import, .tex export.
extension NebulaCanvasTabularLatexExport on _NebulaCanvasScreenState {
  // ── Excel-to-LaTeX Integration ────────────────────────────────────────

  /// Generate a LateX table from the selected spreadsheet range.
  void _generateLatexFromSelection() {
    final node = _tabularTool.selectedTabular;
    final range = _tabularTool.selectedRange;
    if (node == null || range == null) return;
    if (!EngineScope.hasScope) return;

    final renderer = LatexReportTemplate(node.evaluator);
    final latexSource = renderer.render(
      '{TABLE(${range.label}, headers=true)}',
    );

    final tableWidth = node.model.totalWidth(node.visibleColumns);
    final insertX = node.localTransform.getTranslation().x + tableWidth + 50;
    final insertY = node.localTransform.getTranslation().y;

    final latexNodeId = generateUid();
    final latexNode = LatexNode(
      id: NodeId(latexNodeId),
      name: 'Generated Table',
      latexSource: latexSource,
      sourceTabularId: node.id.toString(),
      sourceRangeLabel: range.label,
    );

    latexNode.localTransform.setTranslationRaw(insertX, insertY, 0);

    final activeLayer = _layerController.activeLayer;
    if (activeLayer == null) return;
    _commandHistory.execute(
      AddLatexNodeCommand(parent: activeLayer.node, latexNode: latexNode),
    );

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
      _buildAndPlaceChart(node, range, selectedType);
    });
  }

  /// Build chart data and place LaTeX node on canvas.
  Future<void> _buildAndPlaceChart(
    TabularNode node,
    CellRange range,
    TikzChartType selectedType,
  ) async {
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
      opts: TikzChartOptions(title: 'Chart from ${range.label}', headers: true),
    );

    final startCol = range.startColumn;
    final endCol = range.endColumn;
    final dataStartRow = range.startRow + 1;
    final endRow = range.endRow;
    final mm = node.mergeManager;

    final chartLabels = <String>[];
    for (int r = dataStartRow; r <= endRow; r++) {
      final addr = CellAddress(startCol, r);
      if (mm.isHiddenByMerge(addr)) continue;
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
        if (mm.isHiddenByMerge(addr)) continue;
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

      final cols = parsed.columnCount;
      final rows = parsed.totalRows;
      _addTabularNode(columns: cols.clamp(1, 50), rows: rows.clamp(1, 200));

      WidgetsBinding.instance.addPostFrameCallback((_) {
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
