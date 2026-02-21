import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/tabular/cell_address.dart';
import 'package:nebula_engine/src/core/tabular/cell_node.dart';
import 'package:nebula_engine/src/core/tabular/cell_value.dart';
import 'package:nebula_engine/src/core/tabular/spreadsheet_model.dart';

void main() {
  // ===========================================================================
  // CellAddress
  // ===========================================================================

  group('CellAddress', () {
    test('basic construction and equality', () {
      const a = CellAddress(0, 0);
      const b = CellAddress(0, 0);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('column labels A-Z', () {
      expect(const CellAddress(0, 0).columnLabel, 'A');
      expect(const CellAddress(25, 0).columnLabel, 'Z');
    });

    test('column labels AA, AB, AZ, BA', () {
      expect(const CellAddress(26, 0).columnLabel, 'AA');
      expect(const CellAddress(27, 0).columnLabel, 'AB');
      expect(const CellAddress(51, 0).columnLabel, 'AZ');
      expect(const CellAddress(52, 0).columnLabel, 'BA');
    });

    test('label string', () {
      expect(const CellAddress(0, 0).label, 'A1');
      expect(const CellAddress(2, 4).label, 'C5');
      expect(const CellAddress(26, 99).label, 'AA100');
    });

    test('fromLabel parses correctly', () {
      expect(CellAddress.fromLabel('A1'), const CellAddress(0, 0));
      expect(CellAddress.fromLabel('C5'), const CellAddress(2, 4));
      expect(CellAddress.fromLabel('AA100'), const CellAddress(26, 99));
    });

    test('fromLabel strips dollar signs', () {
      expect(CellAddress.fromLabel('\$A\$1'), const CellAddress(0, 0));
      expect(CellAddress.fromLabel('B\$3'), const CellAddress(1, 2));
    });

    test('roundtrip label → fromLabel → label', () {
      final addresses = [
        const CellAddress(0, 0),
        const CellAddress(5, 10),
        const CellAddress(26, 0),
        const CellAddress(100, 50),
      ];
      for (final addr in addresses) {
        expect(CellAddress.fromLabel(addr.label), addr);
      }
    });

    test('JSON serialization roundtrip', () {
      const addr = CellAddress(5, 10);
      final json = addr.toJson();
      final restored = CellAddress.fromJson(json);
      expect(restored, addr);
    });

    test('compareTo sorts by row then column', () {
      const a = CellAddress(2, 1);
      const b = CellAddress(0, 2);
      const c = CellAddress(1, 2);
      expect(a.compareTo(b), lessThan(0)); // row 1 < row 2
      expect(b.compareTo(c), lessThan(0)); // same row, col 0 < col 1
    });
  });

  // ===========================================================================
  // CellRange
  // ===========================================================================

  group('CellRange', () {
    test('contains', () {
      final range = CellRange(const CellAddress(0, 0), const CellAddress(2, 4));
      expect(range.contains(const CellAddress(1, 2)), true);
      expect(range.contains(const CellAddress(0, 0)), true);
      expect(range.contains(const CellAddress(2, 4)), true);
      expect(range.contains(const CellAddress(3, 0)), false);
      expect(range.contains(const CellAddress(0, 5)), false);
    });

    test('addresses yields row-major order', () {
      final range = CellRange(const CellAddress(0, 0), const CellAddress(1, 1));
      final addrs = range.addresses.toList();
      expect(addrs.length, 4);
      expect(addrs[0], const CellAddress(0, 0));
      expect(addrs[1], const CellAddress(1, 0));
      expect(addrs[2], const CellAddress(0, 1));
      expect(addrs[3], const CellAddress(1, 1));
    });

    test('dimensions', () {
      final range = CellRange(const CellAddress(1, 2), const CellAddress(3, 5));
      expect(range.columnCount, 3);
      expect(range.rowCount, 4);
    });

    test('fromLabel parses A1:C5', () {
      final range = CellRange.fromLabel('A1:C5');
      expect(range.start, const CellAddress(0, 0));
      expect(range.end, const CellAddress(2, 4));
    });

    test('JSON serialization roundtrip', () {
      final range = CellRange(
        const CellAddress(0, 0),
        const CellAddress(5, 10),
      );
      final json = range.toJson();
      final restored = CellRange.fromJson(json);
      expect(restored, range);
    });
  });

  // ===========================================================================
  // CellValue
  // ===========================================================================

  group('CellValue', () {
    test('EmptyValue', () {
      const v = EmptyValue();
      expect(v.displayString, '');
      expect(v.asNumber, isNull);
      expect(v, equals(const EmptyValue()));
    });

    test('NumberValue', () {
      const v = NumberValue(42);
      expect(v.displayString, '42');
      expect(v.asNumber, 42.0);
    });

    test('NumberValue float display', () {
      const v = NumberValue(3.14);
      expect(v.displayString, '3.14');
    });

    test('TextValue', () {
      const v = TextValue('hello');
      expect(v.displayString, 'hello');
      expect(v.asNumber, isNull);
    });

    test('BoolValue', () {
      const t = BoolValue(true);
      const f = BoolValue(false);
      expect(t.displayString, 'TRUE');
      expect(f.displayString, 'FALSE');
      expect(t.asNumber, 1.0);
      expect(f.asNumber, 0.0);
    });

    test('FormulaValue', () {
      const v = FormulaValue('SUM(A1:A10)');
      expect(v.displayString, '=SUM(A1:A10)');
    });

    test('ErrorValue display strings', () {
      expect(
        const ErrorValue(CellError.divisionByZero).displayString,
        '#DIV/0!',
      );
      expect(const ErrorValue(CellError.circularRef).displayString, '#CIRC!');
      expect(const ErrorValue(CellError.nameError).displayString, '#NAME?');
    });

    test('ComplexValue', () {
      const v = ComplexValue({'label': 'Budget', 'amount': 1000});
      expect(v.displayString, 'Budget');
    });

    test('JSON serialization roundtrip for all types', () {
      final values = <CellValue>[
        const EmptyValue(),
        const NumberValue(42),
        const TextValue('hello'),
        const BoolValue(true),
        const FormulaValue('A1+B1'),
        const ErrorValue(CellError.divisionByZero),
        const ComplexValue({'key': 'val'}),
      ];
      for (final v in values) {
        final json = v.toJson();
        final restored = CellValue.fromJson(json);
        expect(restored, v, reason: 'Failed for type: ${v.typeTag}');
      }
    });
  });

  // ===========================================================================
  // SpreadsheetModel
  // ===========================================================================

  group('SpreadsheetModel', () {
    test('empty model has no cells', () {
      final model = SpreadsheetModel();
      expect(model.cellCount, 0);
      expect(model.maxColumn, -1);
      expect(model.maxRow, -1);
    });

    test('setCell and getCell', () {
      final model = SpreadsheetModel();
      final cell = CellNode(value: const NumberValue(42));
      model.setCell(const CellAddress(0, 0), cell);
      expect(
        model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(42),
      );
      expect(model.cellCount, 1);
    });

    test('clearCell removes cell', () {
      final model = SpreadsheetModel();
      model.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(1)),
      );
      model.clearCell(const CellAddress(0, 0));
      expect(model.getCell(const CellAddress(0, 0)), isNull);
      expect(model.cellCount, 0);
    });

    test('sparse storage — only occupied cells use memory', () {
      final model = SpreadsheetModel();
      model.setCell(
        const CellAddress(100, 200),
        CellNode(value: const NumberValue(1)),
      );
      expect(model.cellCount, 1); // Only 1 cell, not 20,000+
      expect(model.maxColumn, 100);
      expect(model.maxRow, 200);
    });

    test('getCellsInRange', () {
      final model = SpreadsheetModel();
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
        const CellAddress(5, 5),
        CellNode(value: const NumberValue(99)),
      ); // outside range

      final range = CellRange(const CellAddress(0, 0), const CellAddress(1, 1));
      final cells = model.getCellsInRange(range);
      expect(cells.length, 3);
      expect(cells.containsKey(const CellAddress(5, 5)), false);
    });

    test('column width and row height', () {
      final model = SpreadsheetModel();
      expect(model.getColumnWidth(0), 100.0);
      model.setColumnWidth(0, 200.0);
      expect(model.getColumnWidth(0), 200.0);
      expect(model.getColumnWidth(1), 100.0); // default

      expect(model.getRowHeight(0), 28.0);
      model.setRowHeight(0, 40.0);
      expect(model.getRowHeight(0), 40.0);
    });

    test('JSON serialization roundtrip', () {
      final model = SpreadsheetModel(defaultColumnWidth: 120);
      model.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(42)),
      );
      model.setCell(
        const CellAddress(1, 0),
        CellNode(value: const TextValue('hello')),
      );
      model.setColumnWidth(0, 200.0);
      model.frozenColumns = 1;

      final json = model.toJson();
      final restored = SpreadsheetModel.fromJson(json);

      expect(restored.cellCount, 2);
      expect(
        restored.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(42),
      );
      expect(
        restored.getCell(const CellAddress(1, 0))?.value,
        const TextValue('hello'),
      );
      expect(restored.getColumnWidth(0), 200.0);
      expect(restored.defaultColumnWidth, 120.0);
      expect(restored.frozenColumns, 1);
    });

    test('clone produces independent copy', () {
      final model = SpreadsheetModel();
      model.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(1)),
      );
      final copy = model.clone();
      copy.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(99)),
      );
      expect(
        model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(1),
      );
      expect(
        copy.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(99),
      );
    });
  });
}
