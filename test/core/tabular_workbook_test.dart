import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_workbook.dart';

void main() {
  late SpreadsheetWorkbook wb;

  setUp(() {
    wb = SpreadsheetWorkbook();
  });

  tearDown(() => wb.dispose());

  group('Sheet management', () {
    test('add and list sheets', () {
      wb.addSheet('Sheet1');
      wb.addSheet('Sheet2');
      expect(wb.sheetNames, ['Sheet1', 'Sheet2']);
      expect(wb.sheetCount, 2);
      expect(wb.hasSheet('Sheet1'), isTrue);
    });

    test('first sheet becomes active', () {
      wb.addSheet('Revenue');
      expect(wb.activeSheet, 'Revenue');
    });

    test('duplicate sheet throws', () {
      wb.addSheet('S1');
      expect(() => wb.addSheet('S1'), throwsArgumentError);
    });

    test('remove sheet', () {
      wb.addSheet('S1');
      wb.addSheet('S2');
      expect(wb.removeSheet('S1'), isTrue);
      expect(wb.sheetNames, ['S2']);
      expect(wb.activeSheet, 'S2');
    });

    test('rename sheet', () {
      wb.addSheet('Old');
      expect(wb.renameSheet('Old', 'New'), isTrue);
      expect(wb.sheetNames, ['New']);
      expect(wb.hasSheet('Old'), isFalse);
      expect(wb.hasSheet('New'), isTrue);
    });

    test('reorder sheets', () {
      wb.addSheet('A');
      wb.addSheet('B');
      wb.addSheet('C');
      wb.reorderSheet(2, 0);
      expect(wb.sheetNames, ['C', 'A', 'B']);
    });
  });

  group('Cross-sheet references', () {
    test('Sheet2!A1 resolves cross-sheet value', () {
      wb.addSheet('Data');
      wb.addSheet('Summary');

      // Set a value in Data sheet.
      wb
          .getEvaluator('Data')!
          .setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(42));

      // Reference it from Summary sheet using Sheet!A1 syntax.
      wb
          .getEvaluator('Summary')!
          .setCellAndEvaluate(
            const CellAddress(0, 0),
            const FormulaValue('Data!A1 * 2'),
          );

      expect(
        wb.getEvaluator('Summary')!.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(84),
      );
    });

    test('cross-sheet into formula', () {
      wb.addSheet('Prices');
      wb.addSheet('Report');

      wb
          .getEvaluator('Prices')!
          .setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(10));
      wb
          .getEvaluator('Prices')!
          .setCellAndEvaluate(const CellAddress(0, 1), const NumberValue(20));

      wb
          .getEvaluator('Report')!
          .setCellAndEvaluate(
            const CellAddress(0, 0),
            const FormulaValue('Prices!A1 + Prices!A2'),
          );

      expect(
        wb.getEvaluator('Report')!.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(30),
      );
    });

    test('unknown sheet returns #REF! error', () {
      wb.addSheet('S1');
      wb
          .getEvaluator('S1')!
          .setCellAndEvaluate(
            const CellAddress(0, 0),
            const FormulaValue('Unknown!A1'),
          );
      final val = wb
          .getEvaluator('S1')!
          .getComputedValue(const CellAddress(0, 0));
      expect(val, isA<ErrorValue>());
    });
  });

  group('Serialization', () {
    test('toJson/fromJson round-trip', () {
      wb.addSheet('S1');
      wb.addSheet('S2');
      wb
          .getEvaluator('S1')!
          .setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(100));
      wb.activeSheet = 'S2';

      final json = wb.toJson();
      final restored = SpreadsheetWorkbook.fromJson(json);

      expect(restored.sheetNames, ['S1', 'S2']);
      expect(restored.activeSheet, 'S2');
      expect(
        restored.getEvaluator('S1')!.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(100),
      );
      restored.dispose();
    });

    test('clone preserves data', () {
      wb.addSheet('Test');
      wb
          .getEvaluator('Test')!
          .setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(99));

      final cloned = wb.clone();
      expect(cloned.sheetNames, ['Test']);
      expect(
        cloned.getEvaluator('Test')!.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(99),
      );
      cloned.dispose();
    });
  });
}
