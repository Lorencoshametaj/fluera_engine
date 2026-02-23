import 'package:flutter/material.dart';

import 'tabular_tool.dart';
import '../../core/nodes/tabular_node.dart';
import '../../core/tabular/cell_address.dart';

/// 📊 Overlay widget for the tabular tool.
///
/// Renders:
/// 1. **Selection highlight** — blue border around selected cell(s)
/// 2. **Formula bar** — text field at the top showing cell address + value
/// 3. **Inline cell editor** — text field positioned over the active cell
///
/// This widget observes [TabularToolState] and rebuilds on state changes.
class TabularSelectionOverlay extends StatefulWidget {
  final TabularToolState toolState;

  /// Callback when a cell value is committed (via Enter or Tab).
  final void Function(CellAddress addr, String value)? onCellCommit;

  /// Callback when a cell is cleared (Delete/Backspace pressed).
  final void Function(CellAddress addr)? onCellClear;

  const TabularSelectionOverlay({
    super.key,
    required this.toolState,
    this.onCellCommit,
    this.onCellClear,
  });

  @override
  State<TabularSelectionOverlay> createState() =>
      _TabularSelectionOverlayState();
}

class _TabularSelectionOverlayState extends State<TabularSelectionOverlay> {
  final TextEditingController _formulaController = TextEditingController();
  final FocusNode _formulaFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.toolState.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(TabularSelectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toolState != widget.toolState) {
      oldWidget.toolState.removeListener(_onStateChanged);
      widget.toolState.addListener(_onStateChanged);
    }
  }

  @override
  void dispose() {
    widget.toolState.removeListener(_onStateChanged);
    _formulaController.dispose();
    _formulaFocus.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    setState(() {
      if (widget.toolState.isEditing) {
        _formulaController.text = widget.toolState.editValue;
        _formulaFocus.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.toolState;
    if (state.activeNode == null) return const SizedBox.shrink();

    return Stack(
      children: [
        // Formula bar.
        if (state.hasCellSelection) _buildFormulaBar(state),
      ],
    );
  }

  Widget _buildFormulaBar(TabularToolState state) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          border: Border(
            bottom: BorderSide(color: const Color(0xFF3A3A3A), width: 1),
          ),
        ),
        child: Row(
          children: [
            // Cell address badge.
            Container(
              width: 60,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Color(0xFF3A3A3A))),
              ),
              child: Text(
                _selectionLabel(state),
                style: const TextStyle(
                  color: Color(0xFF90CAF9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // fx label.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'fx',
                style: TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            // Value / formula field.
            Expanded(
              child: TextField(
                controller: _formulaController,
                focusNode: _formulaFocus,
                style: const TextStyle(
                  color: Color(0xFFE0E0E0),
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                  isDense: true,
                ),
                onSubmitted: (value) {
                  if (state.selectedCell != null) {
                    widget.onCellCommit?.call(state.selectedCell!, value);
                    state.exitEditMode(commit: true);
                    state.moveSelection(0, 1); // Move to next row.
                  }
                },
                onChanged: (value) {
                  state.updateEditValue(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Descriptive label for the current selection.
  String _selectionLabel(TabularToolState state) {
    if (state.hasFullRowSelection) {
      return 'Row ${state.selectedRow! + 1}';
    }
    if (state.hasFullColumnSelection) {
      return CellAddress(state.selectedColumn!, 0).columnLabel;
    }
    return state.selectedCell?.label ?? '';
  }
}

/// Custom painter for rendering cell selection highlights.
///
/// Used as a [CustomPaint] layer over the canvas to draw:
/// - Single cell selection (blue border)
/// - Range selection (semi-transparent blue fill)
class TabularSelectionPainter extends CustomPainter {
  final TabularToolState toolState;
  final Matrix4 canvasTransform;

  TabularSelectionPainter({
    required this.toolState,
    required this.canvasTransform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final node = toolState.activeNode;
    if (node == null) return;

    canvas.save();

    // Apply canvas transform.
    canvas.transform(canvasTransform.storage);

    // Single cell highlight.
    if (toolState.selectedCell != null) {
      final rect = _cellRect(node, toolState.selectedCell!);
      if (rect != null) {
        final paint =
            Paint()
              ..color = const Color(0xFF4A90D9)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;
        canvas.drawRect(rect, paint);
      }
    }

    // Range selection highlight.
    if (toolState.hasRangeSelection) {
      final start = toolState.selectionStart!;
      final end = toolState.selectionEnd!;
      final range = CellRange(start, end);

      final topLeft = _cellTopLeft(
        node,
        CellAddress(range.startColumn, range.startRow),
      );
      final bottomRight = _cellBottomRight(
        node,
        CellAddress(range.endColumn, range.endRow),
      );

      if (topLeft != null && bottomRight != null) {
        final rangeRect = Rect.fromPoints(topLeft, bottomRight);
        final fillPaint =
            Paint()
              ..color = const Color(0x334A90D9)
              ..style = PaintingStyle.fill;
        canvas.drawRect(rangeRect, fillPaint);

        final borderPaint =
            Paint()
              ..color = const Color(0xFF4A90D9)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5;
        canvas.drawRect(rangeRect, borderPaint);
      }
    }

    canvas.restore();
  }

  Rect? _cellRect(TabularNode node, CellAddress addr) {
    final topLeft = _cellTopLeft(node, addr);
    if (topLeft == null) return null;

    // Check if this cell is the master of a merge region.
    final mergeRegion = node.mergeManager.getRegion(addr);
    if (mergeRegion != null && node.mergeManager.isMasterCell(addr)) {
      // Sum widths across merged columns.
      double w = 0;
      for (int c = mergeRegion.startColumn; c <= mergeRegion.endColumn; c++) {
        w += node.model.getColumnWidth(c);
      }
      // Sum heights across merged rows.
      double h = 0;
      for (int r = mergeRegion.startRow; r <= mergeRegion.endRow; r++) {
        h += node.model.getRowHeight(r);
      }
      return Rect.fromLTWH(topLeft.dx, topLeft.dy, w, h);
    }

    final w = node.model.getColumnWidth(addr.column);
    final h = node.model.getRowHeight(addr.row);
    return Rect.fromLTWH(topLeft.dx, topLeft.dy, w, h);
  }

  Offset? _cellTopLeft(TabularNode node, CellAddress addr) {
    final xOffset = node.showRowHeaders ? node.headerWidth : 0.0;
    final yOffset = node.showColumnHeaders ? node.headerHeight : 0.0;

    double x = xOffset;
    for (int c = 0; c < addr.column; c++) {
      x += node.model.getColumnWidth(c);
    }

    double y = yOffset;
    for (int r = 0; r < addr.row; r++) {
      y += node.model.getRowHeight(r);
    }

    return Offset(x, y);
  }

  Offset? _cellBottomRight(TabularNode node, CellAddress addr) {
    final topLeft = _cellTopLeft(node, addr);
    if (topLeft == null) return null;
    return Offset(
      topLeft.dx + node.model.getColumnWidth(addr.column),
      topLeft.dy + node.model.getRowHeight(addr.row),
    );
  }

  @override
  bool shouldRepaint(covariant TabularSelectionPainter oldDelegate) => true;
}
