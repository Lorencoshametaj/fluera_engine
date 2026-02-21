import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/nodes/tabular_node.dart';
import 'package:nebula_engine/src/core/scene_graph/node_id.dart';
import 'package:nebula_engine/src/core/tabular/cell_address.dart';
import 'package:nebula_engine/src/core/tabular/cell_node.dart';
import 'package:nebula_engine/src/core/tabular/cell_value.dart';
import 'package:nebula_engine/src/history/tabular_format_commands.dart';

void main() {
  late TabularNode node;

  setUp(() {
    node = TabularNode(id: const NodeId('fmt-test'));
    node.evaluator.setCellAndEvaluate(
      const CellAddress(0, 0),
      const NumberValue(42),
    );
    node.evaluator.setCellAndEvaluate(
      const CellAddress(1, 0),
      const TextValue('hello'),
    );
  });

  group('ToggleBoldCommand', () {
    test('toggles bold on', () {
      final cmd = ToggleBoldCommand(
        node: node,
        address: const CellAddress(0, 0),
      );
      cmd.execute();
      expect(node.model.getCell(const CellAddress(0, 0))?.format?.bold, true);
    });

    test('undo restores original', () {
      final cmd = ToggleBoldCommand(
        node: node,
        address: const CellAddress(0, 0),
      );
      cmd.execute();
      cmd.undo();
      expect(
        node.model.getCell(const CellAddress(0, 0))?.format?.bold ?? false,
        false,
      );
    });

    test('toggles bold off when already bold', () {
      // First toggle on.
      ToggleBoldCommand(node: node, address: const CellAddress(0, 0)).execute();
      // Second toggle off.
      final cmd = ToggleBoldCommand(
        node: node,
        address: const CellAddress(0, 0),
      );
      cmd.execute();
      expect(node.model.getCell(const CellAddress(0, 0))?.format?.bold, false);
    });
  });

  group('ToggleItalicCommand', () {
    test('toggles italic on', () {
      final cmd = ToggleItalicCommand(
        node: node,
        address: const CellAddress(0, 0),
      );
      cmd.execute();
      expect(node.model.getCell(const CellAddress(0, 0))?.format?.italic, true);
    });
  });

  group('SetTextColorCommand', () {
    test('sets text color', () {
      final cmd = SetTextColorCommand(
        node: node,
        address: const CellAddress(0, 0),
        newColor: const Color(0xFFFF0000),
      );
      cmd.execute();
      expect(
        node.model.getCell(const CellAddress(0, 0))?.format?.textColor,
        const Color(0xFFFF0000),
      );
    });

    test('merge coalescing for same cell', () {
      final cmd1 = SetTextColorCommand(
        node: node,
        address: const CellAddress(0, 0),
        newColor: const Color(0xFFFF0000),
      );
      final cmd2 = SetTextColorCommand(
        node: node,
        address: const CellAddress(0, 0),
        newColor: const Color(0xFF00FF00),
      );
      expect(cmd1.canMergeWith(cmd2), true);
    });
  });

  group('SetBackgroundColorCommand', () {
    test('sets background color', () {
      final cmd = SetBackgroundColorCommand(
        node: node,
        address: const CellAddress(0, 0),
        newColor: const Color(0xFF00FF00),
      );
      cmd.execute();
      expect(
        node.model.getCell(const CellAddress(0, 0))?.format?.backgroundColor,
        const Color(0xFF00FF00),
      );
    });
  });

  group('SetAlignmentCommand', () {
    test('sets alignment', () {
      final cmd = SetAlignmentCommand(
        node: node,
        address: const CellAddress(0, 0),
        newAlignment: CellAlignment.center,
      );
      cmd.execute();
      expect(
        node.model.getCell(const CellAddress(0, 0))?.format?.horizontalAlign,
        CellAlignment.center,
      );
    });

    test('undo restores alignment', () {
      final cmd = SetAlignmentCommand(
        node: node,
        address: const CellAddress(0, 0),
        newAlignment: CellAlignment.right,
      );
      cmd.execute();
      cmd.undo();
      expect(
        node.model.getCell(const CellAddress(0, 0))?.format?.horizontalAlign,
        isNull,
      );
    });
  });

  group('SetCellFormatCommand', () {
    test('sets complete format', () {
      final fmt = CellFormat(
        bold: true,
        italic: true,
        textColor: const Color(0xFFFF0000),
        fontSize: 16,
      );
      final cmd = SetCellFormatCommand(
        node: node,
        address: const CellAddress(0, 0),
        newFormat: fmt,
      );
      cmd.execute();
      expect(node.model.getCell(const CellAddress(0, 0))?.format, fmt);
    });

    test('undo restores previous format', () {
      final fmt = CellFormat(bold: true);
      final cmd = SetCellFormatCommand(
        node: node,
        address: const CellAddress(0, 0),
        newFormat: fmt,
      );
      cmd.execute();
      cmd.undo();
      expect(node.model.getCell(const CellAddress(0, 0))?.format, isNull);
    });

    test('creates cell with format even on empty cell', () {
      final fmt = CellFormat(bold: true);
      final cmd = SetCellFormatCommand(
        node: node,
        address: const CellAddress(5, 5),
        newFormat: fmt,
      );
      cmd.execute();
      final cell = node.model.getCell(const CellAddress(5, 5));
      expect(cell, isNotNull);
      expect(cell?.format?.bold, true);
    });
  });

  group('SetRangeFormatCommand', () {
    test('applies format to entire range', () {
      node.evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(1),
      );
      node.evaluator.setCellAndEvaluate(
        const CellAddress(1, 1),
        const NumberValue(2),
      );

      final range = CellRange(const CellAddress(0, 0), const CellAddress(1, 1));
      final fmt = CellFormat(bold: true);
      final cmd = SetRangeFormatCommand(
        node: node,
        range: range,
        newFormat: fmt,
      );
      cmd.execute();

      for (final addr in range.addresses) {
        expect(node.model.getCell(addr)?.format?.bold, true);
      }
    });
  });

  group('SetNumberFormatCommand', () {
    test('sets number format on range', () {
      final range = CellRange(const CellAddress(0, 0), const CellAddress(0, 0));
      final cmd = SetNumberFormatCommand(
        node: node,
        range: range,
        newFormat: '#,##0.00',
      );
      cmd.execute();
      expect(
        node.model.getCell(const CellAddress(0, 0))?.format?.numberFormat,
        '#,##0.00',
      );
    });
  });
}
