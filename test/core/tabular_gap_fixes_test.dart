import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_evaluator.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_model.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_workbook.dart';

void main() {
  late SpreadsheetModel model;
  late SpreadsheetEvaluator eval;

  setUp(() {
    model = SpreadsheetModel();
    eval = SpreadsheetEvaluator(model);
  });

  tearDown(() => eval.dispose());

  group('IFERROR', () {
    test('returns value when no error', () {
      eval.setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(42));
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('IFERROR(A1, 0)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(42),
      );
    });

    test('returns fallback on error', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('1/0'),
      );
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('IFERROR(A1, -1)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(-1),
      );
    });
  });

  group('MEDIAN', () {
    test('odd count', () {
      for (int i = 0; i < 5; i++) {
        eval.setCellAndEvaluate(
          CellAddress(0, i),
          NumberValue([1, 3, 5, 7, 9][i]),
        );
      }
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('MEDIAN(A1:A5)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(5),
      );
    });

    test('even count', () {
      for (int i = 0; i < 4; i++) {
        eval.setCellAndEvaluate(
          CellAddress(0, i),
          NumberValue([2, 4, 6, 8][i]),
        );
      }
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('MEDIAN(A1:A4)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(5),
      );
    });
  });

  group('STDEV', () {
    test('sample standard deviation', () {
      for (int i = 0; i < 5; i++) {
        eval.setCellAndEvaluate(
          CellAddress(0, i),
          NumberValue([2, 4, 4, 4, 5][i]),
        );
      }
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('STDEV(A1:A5)'),
      );
      final result = eval.getComputedValue(const CellAddress(1, 0));
      expect(result, isA<NumberValue>());
      expect((result as NumberValue).value, closeTo(1.095, 0.01));
    });
  });

  group('LARGE and SMALL', () {
    test('LARGE returns kth largest', () {
      for (int i = 0; i < 5; i++) {
        eval.setCellAndEvaluate(
          CellAddress(0, i),
          NumberValue([10, 30, 50, 20, 40][i]),
        );
      }
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('LARGE(A1:A5, 2)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(40),
      );
    });

    test('SMALL returns kth smallest', () {
      for (int i = 0; i < 5; i++) {
        eval.setCellAndEvaluate(
          CellAddress(0, i),
          NumberValue([10, 30, 50, 20, 40][i]),
        );
      }
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('SMALL(A1:A5, 2)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(20),
      );
    });
  });

  group('CHOOSE', () {
    test('picks nth value', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('CHOOSE(2, 10, 20, 30)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(20),
      );
    });
  });

  group('ROUNDDOWN and ROUNDUP', () {
    test('ROUNDDOWN truncates toward zero', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('ROUNDDOWN(3.567, 2)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(3.56),
      );
    });

    test('ROUNDUP rounds away from zero', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('ROUNDUP(3.561, 2)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(3.57),
      );
    });
  });

  group('RANK', () {
    test('descending rank (default)', () {
      for (int i = 0; i < 5; i++) {
        eval.setCellAndEvaluate(
          CellAddress(0, i),
          NumberValue([10, 30, 50, 20, 40][i]),
        );
      }
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('RANK(30, A1:A5)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(3), // 50, 40, 30 → rank 3
      );
    });

    test('ascending rank', () {
      for (int i = 0; i < 5; i++) {
        eval.setCellAndEvaluate(
          CellAddress(0, i),
          NumberValue([10, 30, 50, 20, 40][i]),
        );
      }
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('RANK(30, A1:A5, 1)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(3), // 10, 20, 30 → rank 3
      );
    });
  });

  group('Cross-sheet ranges', () {
    test('SUM(Sheet!A1:A3) sums cross-sheet range', () {
      final wb = SpreadsheetWorkbook();
      wb.addSheet('Data');
      wb.addSheet('Summary');

      // Set values in Data sheet.
      wb
          .getEvaluator('Data')!
          .setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(10));
      wb
          .getEvaluator('Data')!
          .setCellAndEvaluate(const CellAddress(0, 1), const NumberValue(20));
      wb
          .getEvaluator('Data')!
          .setCellAndEvaluate(const CellAddress(0, 2), const NumberValue(30));

      // Sum the cross-sheet range.
      wb
          .getEvaluator('Summary')!
          .setCellAndEvaluate(
            const CellAddress(0, 0),
            const FormulaValue('SUM(Data!A1:A3)'),
          );

      expect(
        wb.getEvaluator('Summary')!.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(60),
      );
      wb.dispose();
    });
  });
}
