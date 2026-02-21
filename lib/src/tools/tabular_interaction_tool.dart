import 'package:flutter/material.dart';
import '../core/nodes/tabular_node.dart';
import '../core/scene_graph/scene_graph.dart';
import '../core/nodes/group_node.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/layer_node.dart';
import '../core/tabular/cell_address.dart';

/// 📊 TabularInteractionTool — manages selection, drag, and resize of
/// [TabularNode] instances on the canvas.
///
/// Mirrors the [ImageTool] / [DigitalTextTool] interaction pattern.
class TabularInteractionTool {
  TabularNode? _selected;
  bool _isDragging = false;
  Offset _dragStart = Offset.zero;
  Offset _nodeStartPos = Offset.zero;

  // ── Cell selection ─────────────────────────────────────────────────────
  int? _selectedCol;
  int? _selectedRow;

  // ── Range selection (multi-cell) ───────────────────────────────────────
  int? _rangeEndCol;
  int? _rangeEndRow;

  // ── Selection ──────────────────────────────────────────────────────────

  TabularNode? get selectedTabular => _selected;
  bool get hasSelection => _selected != null;
  bool get isDragging => _isDragging;

  /// Whether a specific cell is selected within the table.
  bool get hasCellSelection => _selectedCol != null && _selectedRow != null;
  int? get selectedCol => _selectedCol;
  int? get selectedRow => _selectedRow;

  /// Whether a multi-cell range is selected (more than one cell).
  bool get hasRangeSelection =>
      _rangeEndCol != null &&
      _rangeEndRow != null &&
      (_rangeEndCol != _selectedCol || _rangeEndRow != _selectedRow);

  /// Get the selected CellRange (normalized). Returns null if no range.
  CellRange? get selectedRange {
    if (_selectedCol == null || _selectedRow == null) return null;
    final ec = _rangeEndCol ?? _selectedCol!;
    final er = _rangeEndRow ?? _selectedRow!;
    return CellRange(
      CellAddress(_selectedCol!, _selectedRow!),
      CellAddress(ec, er),
    );
  }

  /// Cell reference label (e.g. "A1", "B3", or "A1:C5" for ranges).
  String get cellRefLabel {
    if (_selectedCol == null || _selectedRow == null) return '';
    final colLetter = String.fromCharCode(65 + _selectedCol!);
    final base = '$colLetter${_selectedRow! + 1}';
    if (hasRangeSelection) {
      final endLetter = String.fromCharCode(65 + _rangeEndCol!);
      return '$base:$endLetter${_rangeEndRow! + 1}';
    }
    return base;
  }

  void selectTabular(TabularNode node) {
    _selected = node;
  }

  void deselectTabular() {
    _selected = null;
    _isDragging = false;
    _selectedCol = null;
    _selectedRow = null;
    _rangeEndCol = null;
    _rangeEndRow = null;
  }

  /// Select a specific cell within the current table.
  void selectCell(int col, int row) {
    _selectedCol = col;
    _selectedRow = row;
    _rangeEndCol = null;
    _rangeEndRow = null;
  }

  /// Extend the selection to form a range from anchor to (col, row).
  void extendSelection(int col, int row) {
    _rangeEndCol = col;
    _rangeEndRow = row;
  }

  /// Clear cell selection without deselecting the table.
  void deselectCell() {
    _selectedCol = null;
    _selectedRow = null;
    _rangeEndCol = null;
    _rangeEndRow = null;
  }

  /// Move selection down by one row. Wraps within visible rows.
  void moveDown() {
    if (_selected == null || _selectedRow == null) return;
    _selectedRow = (_selectedRow! + 1) % _selected!.visibleRows;
  }

  /// Move selection right by one column. Wraps within visible columns.
  void moveRight() {
    if (_selected == null || _selectedCol == null) return;
    _selectedCol = (_selectedCol! + 1) % _selected!.visibleColumns;
  }

  // ── Hit-test ───────────────────────────────────────────────────────────

  /// Returns the first [TabularNode] whose rendered bounds contain
  /// [canvasPos], or `null` if none.
  TabularNode? hitTest(Offset canvasPos, SceneGraph sceneGraph) {
    // Check layers
    for (final layer in sceneGraph.layers) {
      final result = _hitTestNode(canvasPos, layer);
      if (result != null) return result;
    }
    // Check rootNode children (nodes added directly to root)
    for (final child in sceneGraph.rootNode.children) {
      final result = _hitTestNode(canvasPos, child);
      if (result != null) return result;
    }
    return null;
  }

  TabularNode? _hitTestNode(Offset canvasPos, CanvasNode node) {
    if (node is TabularNode && node.isVisible) {
      final bounds = _getNodeBounds(node);
      if (bounds.contains(canvasPos)) return node;
    } else if (node is GroupNode) {
      // Reverse order: top-most (last child) gets priority
      for (int i = node.children.length - 1; i >= 0; i--) {
        final child = node.children[i];
        if (child.isVisible) {
          final result = _hitTestNode(canvasPos, child);
          if (result != null) return result;
        }
      }
    }
    return null;
  }

  /// Get the axis-aligned bounding rect of a [TabularNode] in canvas coords.
  Rect _getNodeBounds(TabularNode node) {
    final tx = node.localTransform.getTranslation();
    final cols = node.visibleColumns;
    final rows = node.visibleRows;
    final w = node.model.totalWidth(cols) + node.headerWidth;
    final h = node.model.totalHeight(rows) + node.headerHeight;
    return Rect.fromLTWH(tx.x, tx.y, w, h);
  }

  /// Public accessor for selection bounds (used by overlay rendering).
  Rect? get selectionBounds {
    if (_selected == null) return null;
    return _getNodeBounds(_selected!);
  }

  // ── Drag (move) ────────────────────────────────────────────────────────

  void startDrag(Offset canvasPos) {
    if (_selected == null) return;
    _isDragging = true;
    _dragStart = canvasPos;
    final tx = _selected!.localTransform.getTranslation();
    _nodeStartPos = Offset(tx.x, tx.y);
  }

  /// Updates the node position during drag. Returns `true` if moved.
  bool updateDrag(Offset canvasPos) {
    if (!_isDragging || _selected == null) return false;
    final delta = canvasPos - _dragStart;
    final newPos = _nodeStartPos + delta;
    _selected!.localTransform.setTranslationRaw(newPos.dx, newPos.dy, 0);
    return true;
  }

  void endDrag() {
    _isDragging = false;
  }

  // ── Cell hit-test (for editing) ────────────────────────────────────────

  /// Returns the (column, row) of the cell at [canvasPos], or null if
  /// the point is on a header or outside the grid.
  (int col, int row)? hitTestCell(Offset canvasPos) {
    if (_selected == null) return null;
    final tx = _selected!.localTransform.getTranslation();
    final localX = canvasPos.dx - tx.x - _selected!.headerWidth;
    final localY = canvasPos.dy - tx.y - _selected!.headerHeight;
    if (localX < 0 || localY < 0) return null;

    // Find column
    double cumX = 0;
    int col = -1;
    for (int c = 0; c < _selected!.visibleColumns; c++) {
      cumX += _selected!.model.getColumnWidth(c);
      if (localX < cumX) {
        col = c;
        break;
      }
    }
    if (col < 0) return null;

    // Find row
    double cumY = 0;
    int row = -1;
    for (int r = 0; r < _selected!.visibleRows; r++) {
      cumY += _selected!.model.getRowHeight(r);
      if (localY < cumY) {
        row = r;
        break;
      }
    }
    if (row < 0) return null;

    return (col, row);
  }

  /// Get the screen-space rect of a specific cell (for overlay positioning).
  Rect? getCellRect(int col, int row, Offset canvasOffset, double scale) {
    if (_selected == null) return null;
    final tx = _selected!.localTransform.getTranslation();

    // Cell position in canvas coords
    final cellX =
        tx.x + _selected!.headerWidth + _selected!.model.columnOffset(col);
    final cellY =
        tx.y + _selected!.headerHeight + _selected!.model.rowOffset(row);
    final cellW = _selected!.model.getColumnWidth(col);
    final cellH = _selected!.model.getRowHeight(row);

    // Convert to screen coords
    return Rect.fromLTWH(
      cellX * scale + canvasOffset.dx,
      cellY * scale + canvasOffset.dy,
      cellW * scale,
      cellH * scale,
    );
  }

  // ── Resize (column/row border drag) ────────────────────────────────────

  /// Resize border type detected by [hitTestBorder].
  bool _isResizing = false;
  bool _isResizingColumn = false; // true = column, false = row
  int _resizeIndex = -1;
  double _resizeStartPos = 0;
  double _resizeOriginalSize = 0;

  bool get isResizing => _isResizing;

  /// Tolerance in canvas pixels for detecting a border (scales with zoom).
  static const double _borderTolerance = 8.0;
  static const double _minSize = 20.0;

  /// Test if [canvasPos] is near a column or row border of the selected table.
  /// Returns a record with (isColumn, borderIndex) or null.
  ({bool isColumn, int index})? hitTestBorder(Offset canvasPos) {
    if (_selected == null) return null;
    final node = _selected!;
    final tx = node.localTransform.getTranslation();
    final localX = canvasPos.dx - tx.x - node.headerWidth;
    final localY = canvasPos.dy - tx.y - node.headerHeight;

    // Must be within the grid area (allowing some tolerance outside)
    final gridW = node.model.totalWidth(node.visibleColumns);
    final gridH = node.model.totalHeight(node.visibleRows);
    if (localX < -_borderTolerance || localX > gridW + _borderTolerance) {
      return null;
    }
    if (localY < -_borderTolerance || localY > gridH + _borderTolerance) {
      return null;
    }

    // Check column borders (right edge of each column)
    double cumX = 0;
    for (int c = 0; c < node.visibleColumns; c++) {
      cumX += node.model.getColumnWidth(c);
      if ((localX - cumX).abs() < _borderTolerance) {
        return (isColumn: true, index: c);
      }
    }

    // Check row borders (bottom edge of each row)
    double cumY = 0;
    for (int r = 0; r < node.visibleRows; r++) {
      cumY += node.model.getRowHeight(r);
      if ((localY - cumY).abs() < _borderTolerance) {
        return (isColumn: false, index: r);
      }
    }

    return null;
  }

  /// Start a resize drag on a column or row border.
  void startResize(bool isColumn, int index, Offset canvasPos) {
    if (_selected == null) return;
    _isResizing = true;
    _isResizingColumn = isColumn;
    _resizeIndex = index;
    _resizeStartPos = isColumn ? canvasPos.dx : canvasPos.dy;
    _resizeOriginalSize =
        isColumn
            ? _selected!.model.getColumnWidth(index)
            : _selected!.model.getRowHeight(index);
  }

  /// Update the resize during drag. Returns the new size if changed.
  double? updateResize(Offset canvasPos) {
    if (!_isResizing || _selected == null) return null;
    final currentPos = _isResizingColumn ? canvasPos.dx : canvasPos.dy;
    final delta = currentPos - _resizeStartPos;
    final newSize = (_resizeOriginalSize + delta).clamp(_minSize, 500.0);

    if (_isResizingColumn) {
      _selected!.model.setColumnWidth(_resizeIndex, newSize);
    } else {
      _selected!.model.setRowHeight(_resizeIndex, newSize);
    }
    return newSize;
  }

  /// End the resize drag. Returns info needed for the undo command.
  ({bool isColumn, int index, double newSize})? endResize() {
    if (!_isResizing) return null;
    final result = (
      isColumn: _isResizingColumn,
      index: _resizeIndex,
      newSize:
          _isResizingColumn
              ? _selected!.model.getColumnWidth(_resizeIndex)
              : _selected!.model.getRowHeight(_resizeIndex),
    );
    _isResizing = false;
    _resizeIndex = -1;
    return result;
  }
}
