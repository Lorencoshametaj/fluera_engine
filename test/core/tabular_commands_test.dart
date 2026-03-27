import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/nodes/tabular_node.dart';
import 'package:fluera_engine/src/core/nodes/group_node.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/history/tabular_commands.dart';

void main() {
  late TabularNode node;
  late GroupNode parent;

  setUp(() {
    node = TabularNode(id: const NodeId('cmd-test'));
    parent = GroupNode(id: const NodeId('parent'));
    parent.add(node);
  });

  // ===========================================================================
  // SetCellCommand
  // ===========================================================================

  group('SetCellCommand', () {
    test('execute sets cell value', () {
      final cmd = SetCellCommand(
        node: node,
        address: const CellAddress(0, 0),
        newValue: const NumberValue(42),
      );
      cmd.execute();
      expect(
        node.evaluator.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(42),
      );
    });

    test('undo restores previous value', () {
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );

      final cmd = SetCellCommand(
        node: node,
        address: const CellAddress(0, 0),
        newValue: const NumberValue(99),
      );
      cmd.execute();
      expect(
        node.evaluator.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(99),
      );

      cmd.undo();
      expect(
        node.evaluator.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(10),
      );
    });

    test('undo on previously empty cell clears it', () {
      final cmd = SetCellCommand(
        node: node,
        address: const CellAddress(0, 0),
        newValue: const NumberValue(42),
      );
      cmd.execute();
      cmd.undo();
      expect(
        node.evaluator.getComputedValue(const CellAddress(0, 0)),
        const EmptyValue(),
      );
    });

    test('canMergeWith identifies same cell on same node', () {
      final cmd1 = SetCellCommand(
        node: node,
        address: const CellAddress(0, 0),
        newValue: const NumberValue(1),
      );
      final cmd2 = SetCellCommand(
        node: node,
        address: const CellAddress(0, 0),
        newValue: const NumberValue(2),
      );
      final cmd3 = SetCellCommand(
        node: node,
        address: const CellAddress(1, 0), // different cell
        newValue: const NumberValue(3),
      );
      expect(cmd1.canMergeWith(cmd2), true);
      expect(cmd1.canMergeWith(cmd3), false);
    });
  });

  // ===========================================================================
  // ClearCellCommand
  // ===========================================================================

  group('ClearCellCommand', () {
    test('execute clears cell', () {
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(42),
      );

      final cmd = ClearCellCommand(
        node: node,
        address: const CellAddress(0, 0),
      );
      cmd.execute();
      expect(node.model.getCell(const CellAddress(0, 0)), isNull);
    });

    test('undo restores cleared cell', () {
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(42),
      );

      final cmd = ClearCellCommand(
        node: node,
        address: const CellAddress(0, 0),
      );
      cmd.execute();
      cmd.undo();
      expect(
        node.model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(42),
      );
    });
  });

  // ===========================================================================
  // InsertRowCommand
  // ===========================================================================

  group('InsertRowCommand', () {
    test('inserts row and shifts cells down', () {
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(2),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 2),
        const NumberValue(3),
      );

      // Insert row at index 1.
      final cmd = InsertRowCommand(node: node, rowIndex: 1);
      cmd.execute();

      // Row 0 stays. Row 1 is empty. Rows 2/3 have old values from 1/2.
      expect(
        node.model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(1),
      );
      expect(node.model.getCell(const CellAddress(0, 1)), isNull);
      expect(
        node.model.getCell(const CellAddress(0, 2))?.value,
        const NumberValue(2),
      );
      expect(
        node.model.getCell(const CellAddress(0, 3))?.value,
        const NumberValue(3),
      );
    });

    test('undo removes inserted row', () {
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(2),
      );

      final cmd = InsertRowCommand(node: node, rowIndex: 1);
      cmd.execute();
      cmd.undo();

      expect(
        node.model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(1),
      );
      expect(
        node.model.getCell(const CellAddress(0, 1))?.value,
        const NumberValue(2),
      );
    });
  });

  // ===========================================================================
  // DeleteRowCommand
  // ===========================================================================

  group('DeleteRowCommand', () {
    test('deletes row and shifts cells up', () {
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(2),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 2),
        const NumberValue(3),
      );

      final cmd = DeleteRowCommand(node: node, rowIndex: 1);
      cmd.execute();

      expect(
        node.model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(1),
      );
      expect(
        node.model.getCell(const CellAddress(0, 1))?.value,
        const NumberValue(3),
      ); // Was row 2, now row 1.
    });

    test('undo restores deleted row', () {
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(2),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 2),
        const NumberValue(3),
      );

      final cmd = DeleteRowCommand(node: node, rowIndex: 1);
      cmd.execute();
      cmd.undo();

      expect(
        node.model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(1),
      );
      expect(
        node.model.getCell(const CellAddress(0, 1))?.value,
        const NumberValue(2),
      );
      expect(
        node.model.getCell(const CellAddress(0, 2))?.value,
        const NumberValue(3),
      );
    });
  });

  // ===========================================================================
  // InsertColumnCommand
  // ===========================================================================

  group('InsertColumnCommand', () {
    test('inserts column and shifts cells right', () {
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const NumberValue(2),
      );

      final cmd = InsertColumnCommand(node: node, columnIndex: 1);
      cmd.execute();

      expect(
        node.model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(1),
      );
      expect(node.model.getCell(const CellAddress(1, 0)), isNull);
      expect(
        node.model.getCell(const CellAddress(2, 0))?.value,
        const NumberValue(2),
      );
    });
  });

  // ===========================================================================
  // DeleteColumnCommand
  // ===========================================================================

  group('DeleteColumnCommand', () {
    test('deletes column and shifts cells left', () {
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const NumberValue(2),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(2, 0),
        const NumberValue(3),
      );

      final cmd = DeleteColumnCommand(node: node, columnIndex: 1);
      cmd.execute();

      expect(
        node.model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(1),
      );
      expect(
        node.model.getCell(const CellAddress(1, 0))?.value,
        const NumberValue(3),
      );
    });
  });

  // ===========================================================================
  // SetColumnWidthCommand & SetRowHeightCommand
  // ===========================================================================

  group('SetColumnWidthCommand', () {
    test('execute/undo column width', () {
      final cmd = SetColumnWidthCommand(node: node, column: 0, newWidth: 200);
      cmd.execute();
      expect(node.model.getColumnWidth(0), 200);
      cmd.undo();
      expect(node.model.getColumnWidth(0), 100); // default
    });

    test('merge coalescing for same column', () {
      final cmd1 = SetColumnWidthCommand(node: node, column: 0, newWidth: 150);
      final cmd2 = SetColumnWidthCommand(node: node, column: 0, newWidth: 200);
      expect(cmd1.canMergeWith(cmd2), true);
    });
  });

  group('SetRowHeightCommand', () {
    test('execute/undo row height', () {
      final cmd = SetRowHeightCommand(node: node, row: 0, newHeight: 50);
      cmd.execute();
      expect(node.model.getRowHeight(0), 50);
      cmd.undo();
      expect(node.model.getRowHeight(0), 28); // default
    });
  });

  // ===========================================================================
  // PasteRangeCommand
  // ===========================================================================

  group('PasteRangeCommand', () {
    test('pastes 2D range', () {
      final cmd = PasteRangeCommand(
        node: node,
        startAddress: const CellAddress(0, 0),
        values: [
          [const NumberValue(1), const NumberValue(2)],
          [const NumberValue(3), const NumberValue(4)],
        ],
      );
      cmd.execute();

      expect(
        node.evaluator.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(1),
      );
      expect(
        node.evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(2),
      );
      expect(
        node.evaluator.getComputedValue(const CellAddress(0, 1)),
        const NumberValue(3),
      );
      expect(
        node.evaluator.getComputedValue(const CellAddress(1, 1)),
        const NumberValue(4),
      );
    });

    test('undo restores previous values', () {
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(99),
      );

      final cmd = PasteRangeCommand(
        node: node,
        startAddress: const CellAddress(0, 0),
        values: [
          [const NumberValue(1)],
        ],
      );
      cmd.execute();
      expect(
        node.evaluator.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(1),
      );

      cmd.undo();
      expect(
        node.model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(99),
      );
    });
  });

  // ===========================================================================
  // AddTabularNodeCommand / DeleteTabularNodeCommand
  // ===========================================================================

  group('AddTabularNodeCommand', () {
    test('add and undo', () {
      final newNode = TabularNode(id: const NodeId('new-tab'));
      parent.remove(node); // Clear parent.

      final cmd = AddTabularNodeCommand(parent: parent, tabularNode: newNode);
      cmd.execute();
      expect(parent.childCount, 1);

      cmd.undo();
      expect(parent.childCount, 0);
    });
  });

  group('DeleteTabularNodeCommand', () {
    test('delete and undo', () {
      final cmd = DeleteTabularNodeCommand(parent: parent, tabularNode: node);
      cmd.execute();
      expect(parent.childCount, 0);

      cmd.undo();
      expect(parent.childCount, 1);
    });
  });
}
