import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../base/tool_interface.dart';
import '../base/tool_context.dart';
import '../base/base_tool.dart';
import '../../core/nodes/tabular_node.dart';
import '../../core/tabular/cell_address.dart';
import '../../core/tabular/cell_value.dart';
import '../../core/tabular/cell_node.dart';

/// 📊 Interactive tool state for the tabular engine.
///
/// Tracks selection, editing mode, and active TabularNode.
class TabularToolState extends ChangeNotifier {
  /// The currently targeted TabularNode (null if none selected).
  TabularNode? _activeNode;

  /// Currently selected single cell.
  CellAddress? _selectedCell;

  /// Range selection start (for multi-cell drag selection).
  CellAddress? _selectionStart;

  /// Range selection end.
  CellAddress? _selectionEnd;

  /// Whether the cell is in edit mode (text input active).
  bool _isEditing = false;

  /// Current edit value in the formula bar / inline editor.
  String _editValue = '';

  // -------------------------------------------------------------------------
  // Getters
  // -------------------------------------------------------------------------

  TabularNode? get activeNode => _activeNode;
  CellAddress? get selectedCell => _selectedCell;
  CellAddress? get selectionStart => _selectionStart;
  CellAddress? get selectionEnd => _selectionEnd;
  bool get isEditing => _isEditing;
  String get editValue => _editValue;

  /// Whether a single cell is selected.
  bool get hasCellSelection => _selectedCell != null;

  /// Whether a range is selected.
  bool get hasRangeSelection =>
      _selectionStart != null && _selectionEnd != null;

  /// The display value of the selected cell.
  String get selectedCellDisplayValue {
    if (_activeNode == null || _selectedCell == null) return '';
    final cell = _activeNode!.model.getCell(_selectedCell!);
    if (cell == null) return '';
    if (cell.isFormula) return '=${(cell.value as FormulaValue).expression}';
    return cell.displayValue.displayString;
  }

  // -------------------------------------------------------------------------
  // Mutations
  // -------------------------------------------------------------------------

  void setActiveNode(TabularNode? node) {
    if (_activeNode == node) return;
    _activeNode = node;
    _clearSelection();
    notifyListeners();
  }

  void selectCell(CellAddress addr) {
    _selectedCell = addr;
    _selectionStart = null;
    _selectionEnd = null;
    _isEditing = false;
    _editValue = '';
    notifyListeners();
  }

  void startRangeSelection(CellAddress start) {
    _selectionStart = start;
    _selectionEnd = start;
    _selectedCell = start;
    _isEditing = false;
    notifyListeners();
  }

  void updateRangeSelection(CellAddress end) {
    _selectionEnd = end;
    notifyListeners();
  }

  void enterEditMode() {
    if (_selectedCell == null || _activeNode == null) return;
    _isEditing = true;
    _editValue = selectedCellDisplayValue;
    notifyListeners();
  }

  void updateEditValue(String value) {
    _editValue = value;
    // Don't notify for every keystroke — the text field handles its own state.
  }

  void exitEditMode({bool commit = false}) {
    _isEditing = false;
    if (commit && _selectedCell != null && _activeNode != null) {
      // The caller should handle committing the value via a Command.
    }
    notifyListeners();
  }

  /// Move selection by delta (for Tab/Enter/Arrow keys).
  void moveSelection(int deltaCol, int deltaRow) {
    if (_selectedCell == null) return;
    final newCol = (_selectedCell!.column + deltaCol).clamp(0, 9999);
    final newRow = (_selectedCell!.row + deltaRow).clamp(0, 9999);
    selectCell(CellAddress(newCol, newRow));
  }

  void _clearSelection() {
    _selectedCell = null;
    _selectionStart = null;
    _selectionEnd = null;
    _isEditing = false;
    _editValue = '';
  }

  void clear() {
    _activeNode = null;
    _clearSelection();
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// TabularTool
// ---------------------------------------------------------------------------

/// 📊 Interactive tabular tool for cell selection and editing.
///
/// Handles:
/// - Click: select cell
/// - Double-click: enter edit mode
/// - Drag: range selection
/// - Tab: move right, Enter: move down
/// - Escape: exit edit mode
class TabularTool extends BaseTool {
  @override
  String get toolId => 'tabular';

  @override
  IconData get icon => Icons.grid_on;

  @override
  String get label => 'Spreadsheet';

  @override
  String get description => 'Interact with spreadsheet cells';

  @override
  bool get hasOverlay => true;

  /// Shared tool state (referenced by the overlay and toolbar).
  final TabularToolState toolState = TabularToolState();

  /// Time of last pointer down (for double-click detection).
  DateTime? _lastPointerDown;

  /// Position of last pointer down.
  Offset? _lastPointerDownPos;

  @override
  void onActivate(ToolContext context) {
    super.onActivate(context);
  }

  @override
  void onDeactivate(ToolContext context) {
    toolState.clear();
    super.onDeactivate(context);
  }

  @override
  void onPointerDown(ToolContext context, PointerDownEvent event) {
    final canvasPos = context.screenToCanvas(event.position);

    // Detect double-click (within 300ms and 10px).
    final now = DateTime.now();
    final isDoubleClick =
        _lastPointerDown != null &&
        _lastPointerDownPos != null &&
        now.difference(_lastPointerDown!).inMilliseconds < 300 &&
        (canvasPos - _lastPointerDownPos!).distance < 10;
    _lastPointerDown = now;
    _lastPointerDownPos = canvasPos;

    if (toolState.activeNode == null) return;

    final addr = _hitTestCell(canvasPos);
    if (addr == null) return;

    if (isDoubleClick) {
      // Double-click: enter edit mode.
      toolState.selectCell(addr);
      toolState.enterEditMode();
    } else {
      // Single click: select cell and start potential range drag.
      toolState.startRangeSelection(addr);
    }

    beginOperation(context, event.position);
  }

  @override
  void onPointerMove(ToolContext context, PointerMoveEvent event) {
    if (state == ToolOperationState.idle) return;
    if (toolState.isEditing) return;

    final canvasPos = context.screenToCanvas(event.position);
    final addr = _hitTestCell(canvasPos);
    if (addr != null) {
      toolState.updateRangeSelection(addr);
    }

    continueOperation(context, event.position);
  }

  @override
  void onPointerUp(ToolContext context, PointerUpEvent event) {
    if (toolState.selectionStart == toolState.selectionEnd) {
      // No drag — just select the single cell.
      if (toolState.selectionStart != null) {
        toolState.selectCell(toolState.selectionStart!);
      }
    }
    completeOperation(context);
  }

  @override
  Widget? buildOverlay(ToolContext context) {
    // The overlay is built externally via tabular_selection_overlay.dart.
    return null;
  }

  /// Handle keyboard events (Tab, Enter, Escape, Arrow keys).
  void handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.tab:
        if (toolState.isEditing) {
          toolState.exitEditMode(commit: true);
        }
        toolState.moveSelection(1, 0); // Tab → right
      case LogicalKeyboardKey.enter:
        if (toolState.isEditing) {
          toolState.exitEditMode(commit: true);
          toolState.moveSelection(0, 1); // Enter → down
        } else {
          toolState.enterEditMode();
        }
      case LogicalKeyboardKey.escape:
        if (toolState.isEditing) {
          toolState.exitEditMode(commit: false);
        } else {
          toolState.clear();
        }
      case LogicalKeyboardKey.arrowUp:
        if (!toolState.isEditing) toolState.moveSelection(0, -1);
      case LogicalKeyboardKey.arrowDown:
        if (!toolState.isEditing) toolState.moveSelection(0, 1);
      case LogicalKeyboardKey.arrowLeft:
        if (!toolState.isEditing) toolState.moveSelection(-1, 0);
      case LogicalKeyboardKey.arrowRight:
        if (!toolState.isEditing) toolState.moveSelection(1, 0);
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        if (!toolState.isEditing && toolState.selectedCell != null) {
          // Delete cell contents — the caller handles the command.
        }
      default:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Hit testing
  // -------------------------------------------------------------------------

  /// Convert a canvas position to a cell address within the active node.
  CellAddress? _hitTestCell(Offset canvasPos) {
    final node = toolState.activeNode;
    if (node == null) return null;

    // Transform canvas position to node-local coordinates.
    // For simplicity, assume the node's transform is applied upstream.
    final localPos = canvasPos;

    final xOffset = node.showRowHeaders ? node.headerWidth : 0.0;
    final yOffset = node.showColumnHeaders ? node.headerHeight : 0.0;

    final x = localPos.dx - xOffset;
    final y = localPos.dy - yOffset;

    if (x < 0 || y < 0) return null;

    // Find column.
    int col = -1;
    double cx = 0;
    final cols = node.effectiveColumns;
    for (int c = 0; c < cols; c++) {
      final w = node.model.getColumnWidth(c);
      if (cx + w > x) {
        col = c;
        break;
      }
      cx += w;
    }

    // Find row.
    int row = -1;
    double ry = 0;
    final rows = node.effectiveRows;
    for (int r = 0; r < rows; r++) {
      final h = node.model.getRowHeight(r);
      if (ry + h > y) {
        row = r;
        break;
      }
      ry += h;
    }

    if (col < 0 || row < 0) return null;
    return CellAddress(col, row);
  }
}
