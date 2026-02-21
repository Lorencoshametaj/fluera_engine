import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/tabular/cell_address.dart';
import 'package:nebula_engine/src/core/tabular/cell_value.dart';
import 'package:nebula_engine/src/core/tabular/tabular_csv.dart';

void main() {
  // ===========================================================================
  // Import
  // ===========================================================================

  group('TabularCsv.import', () {
    test('imports simple CSV', () {
      final model = TabularCsv.import('Name,Age\nAlice,30\nBob,25');
      expect(model.cellCount, 6); // 3 rows × 2 cols
    });

    test('auto-detects numbers', () {
      final model = TabularCsv.import('42,3.14,-7');
      expect(
        model.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(42),
      );
      expect(
        model.getCell(const CellAddress(1, 0))?.value,
        const NumberValue(3.14),
      );
      expect(
        model.getCell(const CellAddress(2, 0))?.value,
        const NumberValue(-7),
      );
    });

    test('auto-detects text', () {
      final model = TabularCsv.import('hello,world');
      expect(
        model.getCell(const CellAddress(0, 0))?.value,
        const TextValue('hello'),
      );
    });

    test('auto-detects booleans', () {
      final model = TabularCsv.import('TRUE,FALSE,true');
      expect(
        model.getCell(const CellAddress(0, 0))?.value,
        const BoolValue(true),
      );
      expect(
        model.getCell(const CellAddress(1, 0))?.value,
        const BoolValue(false),
      );
      expect(
        model.getCell(const CellAddress(2, 0))?.value,
        const BoolValue(true),
      );
    });

    test('auto-detects formulas', () {
      final model = TabularCsv.import('=SUM(A1:A10)');
      expect(
        model.getCell(const CellAddress(0, 0))?.value,
        const FormulaValue('SUM(A1:A10)'),
      );
    });

    test('handles quoted fields with commas', () {
      final model = TabularCsv.import('"hello, world",42');
      expect(
        model.getCell(const CellAddress(0, 0))?.value,
        const TextValue('hello, world'),
      );
      expect(
        model.getCell(const CellAddress(1, 0))?.value,
        const NumberValue(42),
      );
    });

    test('handles escaped quotes', () {
      final model = TabularCsv.import('"He said ""hello""",done');
      expect(
        model.getCell(const CellAddress(0, 0))?.value,
        const TextValue('He said "hello"'),
      );
    });

    test('handles empty cells', () {
      final model = TabularCsv.import('a,,c');
      expect(
        model.getCell(const CellAddress(0, 0))?.value,
        const TextValue('a'),
      );
      expect(model.getCell(const CellAddress(1, 0)), isNull); // empty
      expect(
        model.getCell(const CellAddress(2, 0))?.value,
        const TextValue('c'),
      );
    });

    test('handles custom delimiter', () {
      final model = TabularCsv.import('a;b;c', delimiter: ';');
      expect(model.cellCount, 3);
    });

    test('handles CRLF line endings', () {
      final model = TabularCsv.import('a,b\r\nc,d');
      expect(model.cellCount, 4);
      expect(
        model.getCell(const CellAddress(0, 1))?.value,
        const TextValue('c'),
      );
    });

    test('empty string produces empty model', () {
      final model = TabularCsv.import('');
      expect(model.cellCount, 0);
    });
  });

  // ===========================================================================
  // Export
  // ===========================================================================

  group('TabularCsv.export', () {
    test('exports simple model', () {
      final model = TabularCsv.import('Name,Age\nAlice,30');
      final csv = TabularCsv.export(model);
      expect(csv, 'Name,Age\nAlice,30');
    });

    test('quotes fields with commas', () {
      final model = TabularCsv.import('"hello, world",42');
      final csv = TabularCsv.export(model);
      expect(csv.contains('"hello, world"'), true);
    });

    test('roundtrip preserves data', () {
      const input = 'Name,Score,Pass\nAlice,95,TRUE\nBob,87,FALSE';
      final model = TabularCsv.import(input);
      final output = TabularCsv.export(model);
      expect(output, input);
    });

    test('empty model exports empty string', () {
      final model = TabularCsv.import('');
      expect(TabularCsv.export(model), '');
    });

    test('custom delimiter export', () {
      final model = TabularCsv.import('a;b', delimiter: ';');
      final csv = TabularCsv.export(model, delimiter: ';');
      expect(csv, 'a;b');
    });
  });

  // ===========================================================================
  // Roundtrip
  // ===========================================================================

  group('TabularCsv roundtrip', () {
    test('numeric roundtrip', () {
      const input = '1,2,3\n4,5,6';
      final model = TabularCsv.import(input);
      expect(TabularCsv.export(model), input);
    });

    test('mixed types roundtrip', () {
      const input = 'hello,42,TRUE';
      final model = TabularCsv.import(input);
      expect(TabularCsv.export(model), input);
    });
  });
}
