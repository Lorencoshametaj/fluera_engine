part of '../fluera_canvas_screen.dart';

/// 📊 Tabular CSV — import/export and frozen header toggle.
extension FlueraCanvasTabularCsv on _FlueraCanvasScreenState {
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
}
