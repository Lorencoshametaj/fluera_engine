import 'package:flutter/material.dart';
import '../core/nodes/tabular_node.dart';
import '../core/nodes/group_node.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/tabular/cell_address.dart';
import '../core/tabular/cell_node.dart';
import '../core/tabular/cell_value.dart';
import '../core/tabular/spreadsheet_model.dart';
import 'command_history.dart';

// ---------------------------------------------------------------------------
// Tabular Node Commands — Undoable operations for spreadsheet nodes
// ---------------------------------------------------------------------------

/// Add a [TabularNode] to a parent group. Undo removes it.
class AddTabularNodeCommand extends Command {
  final GroupNode parent;
  final TabularNode tabularNode;
  final int? index;

  AddTabularNodeCommand({
    required this.parent,
    required this.tabularNode,
    this.index,
  }) : super(label: 'Add spreadsheet "${tabularNode.name}"');

  @override
  void execute() {
    if (index != null) {
      parent.insertAt(index!, tabularNode);
    } else {
      parent.add(tabularNode);
    }
  }

  @override
  void undo() => parent.remove(tabularNode);
}

/// Delete a [TabularNode] from its parent. Undo re-inserts at original index.
class DeleteTabularNodeCommand extends Command {
  final GroupNode parent;
  final TabularNode tabularNode;
  late final int _originalIndex;

  DeleteTabularNodeCommand({required this.parent, required this.tabularNode})
    : super(label: 'Delete spreadsheet "${tabularNode.name}"') {
    _originalIndex = parent.indexOf(tabularNode);
  }

  @override
  void execute() => parent.remove(tabularNode);

  @override
  void undo() =>
      parent.insertAt(_originalIndex.clamp(0, parent.childCount), tabularNode);
}

// ---------------------------------------------------------------------------
// Cell Commands
// ---------------------------------------------------------------------------

/// Set a cell's value. Supports merge coalescing for rapid edits.
class SetCellCommand extends Command {
  final TabularNode node;
  final CellAddress address;
  final CellValue newValue;
  final CellValue _oldValue;
  final CellNode? _oldCell;

  SetCellCommand({
    required this.node,
    required this.address,
    required this.newValue,
  }) : _oldValue = node.model.getCell(address)?.value ?? const EmptyValue(),
       _oldCell = node.model.getCell(address)?.clone(),
       super(label: 'Set ${address.label}');

  @override
  void execute() {
    node.evaluator.setCellAndEvaluate(address, newValue);
  }

  @override
  void undo() {
    final old = _oldCell;
    if (old != null) {
      node.model.setCell(address, old.clone());
      node.evaluator.evaluateAll();
    } else {
      node.evaluator.clearCellAndEvaluate(address);
    }
  }

  @override
  bool canMergeWith(Command other) =>
      other is SetCellCommand &&
      other.node.id == node.id &&
      other.address == address;

  @override
  void mergeWith(Command other) {
    // Keep _oldValue from the first command, take newValue from latest.
    // No need to update — undo still restores the original state.
  }
}

/// Clear a cell. Undo restores the previous value.
class ClearCellCommand extends Command {
  final TabularNode node;
  final CellAddress address;
  final CellNode? _oldCell;

  ClearCellCommand({required this.node, required this.address})
    : _oldCell = node.model.getCell(address)?.clone(),
      super(label: 'Clear ${address.label}');

  @override
  void execute() {
    node.evaluator.clearCellAndEvaluate(address);
  }

  @override
  void undo() {
    final old = _oldCell;
    if (old != null) {
      node.model.setCell(address, old.clone());
      node.evaluator.evaluateAll();
    }
  }
}

// ---------------------------------------------------------------------------
// Row/Column Commands
// ---------------------------------------------------------------------------

/// Insert a row at [rowIndex]. Shifts all rows below down by one.
class InsertRowCommand extends Command {
  final TabularNode node;
  final int rowIndex;

  /// Saved state for undo: cells that were shifted.
  late final Map<CellAddress, CellNode> _savedCells;

  InsertRowCommand({required this.node, required this.rowIndex})
    : super(label: 'Insert row ${rowIndex + 1}');

  @override
  void execute() {
    final model = node.model;
    // Collect cells at or below rowIndex (need to shift them down).
    final toShift = <CellAddress, CellNode>{};
    for (final addr in model.occupiedAddresses.toList()) {
      if (addr.row >= rowIndex) {
        toShift[addr] = model.getCell(addr)!;
      }
    }

    // Remove cells in shift zone.
    for (final addr in toShift.keys) {
      model.clearCell(addr);
    }

    // Re-insert shifted down by 1 row.
    for (final entry in toShift.entries) {
      final newAddr = CellAddress(entry.key.column, entry.key.row + 1);
      model.setCell(newAddr, entry.value);
    }

    // Shift row heights.
    final maxRow = model.maxRow;
    for (int r = maxRow; r >= rowIndex; r--) {
      final h = model.getRowHeight(r);
      model.setRowHeight(r + 1, h);
    }
    model.setRowHeight(rowIndex, model.defaultRowHeight);

    node.evaluator.evaluateAll();
  }

  @override
  void undo() {
    final model = node.model;
    // Shift cells back up by removing inserted row.
    final toShift = <CellAddress, CellNode>{};
    for (final addr in model.occupiedAddresses.toList()) {
      if (addr.row > rowIndex) {
        toShift[addr] = model.getCell(addr)!;
      }
    }

    // Clear the inserted row and shifted cells.
    for (final addr in model.occupiedAddresses.toList()) {
      if (addr.row >= rowIndex) {
        model.clearCell(addr);
      }
    }

    // Re-insert shifted back up.
    for (final entry in toShift.entries) {
      final newAddr = CellAddress(entry.key.column, entry.key.row - 1);
      model.setCell(newAddr, entry.value);
    }

    node.evaluator.evaluateAll();
  }
}

/// Delete a row at [rowIndex]. Shifts all rows below up by one.
class DeleteRowCommand extends Command {
  final TabularNode node;
  final int rowIndex;

  /// Saved row data for undo.
  late final Map<CellAddress, CellNode> _deletedCells;
  late final double _deletedHeight;

  DeleteRowCommand({required this.node, required this.rowIndex})
    : super(label: 'Delete row ${rowIndex + 1}');

  @override
  void execute() {
    final model = node.model;

    // Save deleted row cells.
    _deletedCells = {};
    for (final addr in model.occupiedAddresses.toList()) {
      if (addr.row == rowIndex) {
        _deletedCells[addr] = model.getCell(addr)!.clone();
        model.clearCell(addr);
      }
    }
    _deletedHeight = model.getRowHeight(rowIndex);

    // Shift cells below up by 1.
    final toShift = <CellAddress, CellNode>{};
    for (final addr in model.occupiedAddresses.toList()) {
      if (addr.row > rowIndex) {
        toShift[addr] = model.getCell(addr)!;
        model.clearCell(addr);
      }
    }
    for (final entry in toShift.entries) {
      final newAddr = CellAddress(entry.key.column, entry.key.row - 1);
      model.setCell(newAddr, entry.value);
    }

    node.evaluator.evaluateAll();
  }

  @override
  void undo() {
    final model = node.model;

    // Shift cells back down.
    final toShift = <CellAddress, CellNode>{};
    for (final addr in model.occupiedAddresses.toList()) {
      if (addr.row >= rowIndex) {
        toShift[addr] = model.getCell(addr)!;
        model.clearCell(addr);
      }
    }
    for (final entry in toShift.entries) {
      final newAddr = CellAddress(entry.key.column, entry.key.row + 1);
      model.setCell(newAddr, entry.value);
    }

    // Restore deleted cells.
    for (final entry in _deletedCells.entries) {
      model.setCell(entry.key, entry.value.clone());
    }
    model.setRowHeight(rowIndex, _deletedHeight);

    node.evaluator.evaluateAll();
  }
}

/// Insert a column at [columnIndex]. Shifts all columns right by one.
class InsertColumnCommand extends Command {
  final TabularNode node;
  final int columnIndex;

  InsertColumnCommand({required this.node, required this.columnIndex})
    : super(label: 'Insert column ${CellAddress(columnIndex, 0).columnLabel}');

  @override
  void execute() {
    final model = node.model;

    final toShift = <CellAddress, CellNode>{};
    for (final addr in model.occupiedAddresses.toList()) {
      if (addr.column >= columnIndex) {
        toShift[addr] = model.getCell(addr)!;
        model.clearCell(addr);
      }
    }
    for (final entry in toShift.entries) {
      final newAddr = CellAddress(entry.key.column + 1, entry.key.row);
      model.setCell(newAddr, entry.value);
    }

    model.setColumnWidth(columnIndex, model.defaultColumnWidth);
    node.evaluator.evaluateAll();
  }

  @override
  void undo() {
    final model = node.model;

    // Remove inserted column cells and shift back.
    final toShift = <CellAddress, CellNode>{};
    for (final addr in model.occupiedAddresses.toList()) {
      if (addr.column > columnIndex) {
        toShift[addr] = model.getCell(addr)!;
        model.clearCell(addr);
      } else if (addr.column == columnIndex) {
        model.clearCell(addr);
      }
    }
    for (final entry in toShift.entries) {
      final newAddr = CellAddress(entry.key.column - 1, entry.key.row);
      model.setCell(newAddr, entry.value);
    }

    node.evaluator.evaluateAll();
  }
}

/// Delete a column at [columnIndex]. Shifts all columns left by one.
class DeleteColumnCommand extends Command {
  final TabularNode node;
  final int columnIndex;

  late final Map<CellAddress, CellNode> _deletedCells;
  late final double _deletedWidth;

  DeleteColumnCommand({required this.node, required this.columnIndex})
    : super(label: 'Delete column ${CellAddress(columnIndex, 0).columnLabel}');

  @override
  void execute() {
    final model = node.model;

    _deletedCells = {};
    _deletedWidth = model.getColumnWidth(columnIndex);

    for (final addr in model.occupiedAddresses.toList()) {
      if (addr.column == columnIndex) {
        _deletedCells[addr] = model.getCell(addr)!.clone();
        model.clearCell(addr);
      }
    }

    final toShift = <CellAddress, CellNode>{};
    for (final addr in model.occupiedAddresses.toList()) {
      if (addr.column > columnIndex) {
        toShift[addr] = model.getCell(addr)!;
        model.clearCell(addr);
      }
    }
    for (final entry in toShift.entries) {
      final newAddr = CellAddress(entry.key.column - 1, entry.key.row);
      model.setCell(newAddr, entry.value);
    }

    node.evaluator.evaluateAll();
  }

  @override
  void undo() {
    final model = node.model;

    final toShift = <CellAddress, CellNode>{};
    for (final addr in model.occupiedAddresses.toList()) {
      if (addr.column >= columnIndex) {
        toShift[addr] = model.getCell(addr)!;
        model.clearCell(addr);
      }
    }
    for (final entry in toShift.entries) {
      final newAddr = CellAddress(entry.key.column + 1, entry.key.row);
      model.setCell(newAddr, entry.value);
    }

    for (final entry in _deletedCells.entries) {
      model.setCell(entry.key, entry.value.clone());
    }
    model.setColumnWidth(columnIndex, _deletedWidth);

    node.evaluator.evaluateAll();
  }
}

// ---------------------------------------------------------------------------
// Sizing Commands
// ---------------------------------------------------------------------------

/// Set column width. Supports merge coalescing for drag-resize.
class SetColumnWidthCommand extends Command {
  final TabularNode node;
  final int column;
  final double newWidth;
  final double _oldWidth;

  SetColumnWidthCommand({
    required this.node,
    required this.column,
    required this.newWidth,
  }) : _oldWidth = node.model.getColumnWidth(column),
       super(label: 'Resize column ${CellAddress(column, 0).columnLabel}');

  @override
  void execute() => node.model.setColumnWidth(column, newWidth);

  @override
  void undo() => node.model.setColumnWidth(column, _oldWidth);

  @override
  bool canMergeWith(Command other) =>
      other is SetColumnWidthCommand &&
      other.node.id == node.id &&
      other.column == column;

  @override
  void mergeWith(Command other) {
    // Keep _oldWidth from first, latest newWidth applied on execute.
  }
}

/// Set row height. Supports merge coalescing for drag-resize.
class SetRowHeightCommand extends Command {
  final TabularNode node;
  final int row;
  final double newHeight;
  final double _oldHeight;

  SetRowHeightCommand({
    required this.node,
    required this.row,
    required this.newHeight,
  }) : _oldHeight = node.model.getRowHeight(row),
       super(label: 'Resize row ${row + 1}');

  @override
  void execute() => node.model.setRowHeight(row, newHeight);

  @override
  void undo() => node.model.setRowHeight(row, _oldHeight);

  @override
  bool canMergeWith(Command other) =>
      other is SetRowHeightCommand &&
      other.node.id == node.id &&
      other.row == row;

  @override
  void mergeWith(Command other) {}
}

// ---------------------------------------------------------------------------
// Bulk Commands
// ---------------------------------------------------------------------------

/// Paste a range of cell values. Stores old values for undo.
class PasteRangeCommand extends Command {
  final TabularNode node;
  final CellAddress startAddress;
  final List<List<CellValue>> values;

  /// Old cells for undo (saved on first execute).
  late final Map<CellAddress, CellNode?> _oldCells;
  bool _executed = false;

  PasteRangeCommand({
    required this.node,
    required this.startAddress,
    required this.values,
  }) : super(label: 'Paste range at ${startAddress.label}');

  @override
  void execute() {
    if (!_executed) {
      _oldCells = {};
      for (int r = 0; r < values.length; r++) {
        for (int c = 0; c < values[r].length; c++) {
          final addr = CellAddress(
            startAddress.column + c,
            startAddress.row + r,
          );
          _oldCells[addr] = node.model.getCell(addr)?.clone();
        }
      }
      _executed = true;
    }

    for (int r = 0; r < values.length; r++) {
      for (int c = 0; c < values[r].length; c++) {
        final addr = CellAddress(startAddress.column + c, startAddress.row + r);
        node.evaluator.setCellAndEvaluate(addr, values[r][c]);
      }
    }
  }

  @override
  void undo() {
    for (final entry in _oldCells.entries) {
      if (entry.value != null) {
        node.model.setCell(entry.key, entry.value!.clone());
      } else {
        node.model.clearCell(entry.key);
      }
    }
    node.evaluator.evaluateAll();
  }
}
