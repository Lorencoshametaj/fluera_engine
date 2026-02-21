import '../core/nodes/tabular_node.dart';
import '../core/tabular/cell_address.dart';
import '../core/tabular/cell_node.dart';
import '../core/tabular/cell_value.dart';
import '../core/tabular/merge_region_manager.dart';
import 'command_history.dart';

// ---------------------------------------------------------------------------
// Merge Commands — Undoable cell merge/unmerge operations
// ---------------------------------------------------------------------------

/// Merge a range of cells into one. The top-left cell retains its value;
/// all other cells in the range are cleared. Undo restores the cleared cells.
class MergeCellsCommand extends Command {
  final TabularNode node;
  final CellRange range;

  /// Saved cells that will be cleared on merge (everything except top-left).
  late final Map<CellAddress, CellNode> _clearedCells;

  MergeCellsCommand({required this.node, required this.range})
    : super(label: 'Merge ${range.label}');

  @override
  void execute() {
    _clearedCells = {};

    // Clear all cells except the master (top-left).
    final master = CellAddress(range.startColumn, range.startRow);
    for (final addr in range.addresses) {
      if (addr == master) continue;
      final cell = node.model.getCell(addr);
      if (cell != null) {
        _clearedCells[addr] = cell.clone();
        node.model.clearCell(addr);
      }
    }

    // Register the merge region.
    node.mergeManager.addRegion(range);
  }

  @override
  void undo() {
    // Remove the merge region.
    node.mergeManager.removeRegion(range);

    // Restore cleared cells.
    for (final entry in _clearedCells.entries) {
      node.model.setCell(entry.key, entry.value.clone());
    }

    node.evaluator.evaluateAll();
  }
}

/// Unmerge a previously merged range. Undo re-merges (clearing subordinate
/// cells again).
class UnmergeCellsCommand extends Command {
  final TabularNode node;
  final CellRange range;

  UnmergeCellsCommand({required this.node, required this.range})
    : super(label: 'Unmerge ${range.label}');

  @override
  void execute() {
    node.mergeManager.removeRegion(range);
  }

  @override
  void undo() {
    // Re-merge: clear subordinate cells and register region.
    final master = CellAddress(range.startColumn, range.startRow);
    for (final addr in range.addresses) {
      if (addr == master) continue;
      node.model.clearCell(addr);
    }
    node.mergeManager.addRegion(range);
  }
}
