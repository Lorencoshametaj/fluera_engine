import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_node.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_model.dart';
import 'package:fluera_engine/src/core/tabular/tabular_clipboard.dart';

void main() {
  group('TabularClipboard', () {
    late SpreadsheetModel model;

    setUp(() {
      model = SpreadsheetModel();
      model.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(1)),
      );
      model.setCell(
        const CellAddress(1, 0),
        CellNode(value: const NumberValue(2)),
      );
      model.setCell(
        const CellAddress(0, 1),
        CellNode(value: const NumberValue(3)),
      );
      model.setCell(
        const CellAddress(1, 1),
        CellNode(value: const NumberValue(4)),
      );
    });

    test('parseTsv parses tab-separated values', () {
      final result = TabularClipboard.parseTsv('1\t2\n3\t4');
      expect(result.length, 2);
      expect(result[0].length, 2);
      expect(result[0][0], const NumberValue(1));
      expect(result[0][1], const NumberValue(2));
      expect(result[1][0], const NumberValue(3));
      expect(result[1][1], const NumberValue(4));
    });

    test('parseTsv detects types', () {
      final result = TabularClipboard.parseTsv('hello\t42\tTRUE\t=SUM(A1:A5)');
      expect(result[0][0], const TextValue('hello'));
      expect(result[0][1], const NumberValue(42));
      expect(result[0][2], const BoolValue(true));
      expect(result[0][3], const FormulaValue('SUM(A1:A5)'));
    });

    test('parseTsv handles empty fields', () {
      final result = TabularClipboard.parseTsv('a\t\tc');
      expect(result[0][0], const TextValue('a'));
      expect(result[0][1], const EmptyValue());
      expect(result[0][2], const TextValue('c'));
    });

    test('parseTsv handles empty string', () {
      final result = TabularClipboard.parseTsv('');
      expect(result, isEmpty);
    });
  });
}
