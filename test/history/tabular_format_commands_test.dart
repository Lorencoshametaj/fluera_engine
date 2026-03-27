import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/history/tabular_format_commands.dart';
import 'package:fluera_engine/src/history/command_history.dart';
import 'package:fluera_engine/src/core/nodes/tabular_node.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_node.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/scene_graph/node_id.dart';

void main() {
  late TabularNode node;
  late CommandHistory history;

  setUp(() {
    node = TabularNode(id: NodeId('test-table'));
    // Populate a few cells so format commands have something to operate on
    node.model.setCell(
      CellAddress(0, 0),
      CellNode(value: const NumberValue(42)),
    );
    node.model.setCell(
      CellAddress(1, 1),
      CellNode(value: const TextValue('hello')),
    );
    history = CommandHistory();
  });

  // ===========================================================================
  // SetCellFormatCommand
  // ===========================================================================

  group('SetCellFormatCommand', () {
    test('execute applies format', () {
      final addr = CellAddress(0, 0);
      final format = CellFormat(bold: true);

      final cmd = SetCellFormatCommand(
        node: node,
        address: addr,
        newFormat: format,
      );

      history.execute(cmd);

      final cell = node.model.getCell(addr);
      expect(cell?.format?.bold, true);
    });

    test('undo restores previous format', () {
      final addr = CellAddress(0, 0);
      final oldFormat = node.model.getCell(addr)?.format;

      final cmd = SetCellFormatCommand(
        node: node,
        address: addr,
        newFormat: CellFormat(bold: true),
      );

      history.execute(cmd);
      history.undo();

      final cell = node.model.getCell(addr);
      expect(cell?.format, oldFormat);
    });

    test('canMergeWith same cell returns true', () {
      final addr = CellAddress(0, 0);
      final cmd1 = SetCellFormatCommand(
        node: node,
        address: addr,
        newFormat: CellFormat(bold: true),
      );
      final cmd2 = SetCellFormatCommand(
        node: node,
        address: addr,
        newFormat: CellFormat(italic: true),
      );

      expect(cmd1.canMergeWith(cmd2), true);
    });
  });

  // ===========================================================================
  // ToggleBoldCommand
  // ===========================================================================

  group('ToggleBoldCommand', () {
    test('toggles bold on', () {
      final addr = CellAddress(0, 0);

      history.execute(ToggleBoldCommand(node: node, address: addr));

      expect(node.model.getCell(addr)?.format?.bold, true);
    });

    test('undo toggles bold off', () {
      final addr = CellAddress(0, 0);

      history.execute(ToggleBoldCommand(node: node, address: addr));
      history.undo();

      // Should be back to original (no bold)
      final format = node.model.getCell(addr)?.format;
      expect(format?.bold ?? false, false);
    });
  });

  // ===========================================================================
  // ToggleItalicCommand
  // ===========================================================================

  group('ToggleItalicCommand', () {
    test('toggles italic on', () {
      final addr = CellAddress(0, 0);

      history.execute(ToggleItalicCommand(node: node, address: addr));

      expect(node.model.getCell(addr)?.format?.italic, true);
    });
  });

  // ===========================================================================
  // SetTextColorCommand
  // ===========================================================================

  group('SetTextColorCommand', () {
    test('sets text color', () {
      final addr = CellAddress(1, 1);

      history.execute(
        SetTextColorCommand(node: node, address: addr, newColor: Colors.red),
      );

      expect(node.model.getCell(addr)?.format?.textColor, Colors.red);
    });

    test('undo restores previous color', () {
      final addr = CellAddress(0, 0);

      // Pre-set a color via cell format
      node.model.getCell(addr)!.format = CellFormat(textColor: Colors.red);

      // Change to blue
      history.execute(
        SetTextColorCommand(node: node, address: addr, newColor: Colors.blue),
      );

      // Undo should restore to red
      history.undo();

      expect(node.model.getCell(addr)?.format?.textColor, Colors.red);
    });

    test('canMergeWith returns true for same cell', () {
      final addr = CellAddress(0, 0);
      final cmd1 = SetTextColorCommand(
        node: node,
        address: addr,
        newColor: Colors.red,
      );
      final cmd2 = SetTextColorCommand(
        node: node,
        address: addr,
        newColor: Colors.blue,
      );
      expect(cmd1.canMergeWith(cmd2), true);
    });
  });

  // ===========================================================================
  // SetBackgroundColorCommand
  // ===========================================================================

  group('SetBackgroundColorCommand', () {
    test('sets background color', () {
      final addr = CellAddress(0, 0);

      history.execute(
        SetBackgroundColorCommand(
          node: node,
          address: addr,
          newColor: Colors.yellow,
        ),
      );

      expect(node.model.getCell(addr)?.format?.backgroundColor, Colors.yellow);
    });
  });
}
