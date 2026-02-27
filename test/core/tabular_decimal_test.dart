import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/decimal_value.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_evaluator.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_model.dart';

void main() {
  // ===========================================================================
  // Core arithmetic precision
  // ===========================================================================

  group('DecimalHelper - core arithmetic', () {
    test('0.1 + 0.2 = 0.3 exactly', () {
      expect(DecimalHelper.add(0.1, 0.2), equals(0.3));
    });

    test('0.3 - 0.1 = 0.2 exactly', () {
      expect(DecimalHelper.subtract(0.3, 0.1), equals(0.2));
    });

    test('1.1 * 1.1 = 1.21 exactly', () {
      expect(DecimalHelper.multiply(1.1, 1.1), equals(1.21));
    });

    test('0.3 / 0.1 = 3 exactly', () {
      expect(DecimalHelper.divide(0.3, 0.1), equals(3));
    });

    test('addition with integers', () {
      expect(DecimalHelper.add(10, 20), equals(30));
    });

    test('subtraction with integers', () {
      expect(DecimalHelper.subtract(50, 30), equals(20));
    });

    test('negative numbers', () {
      expect(DecimalHelper.add(-0.1, -0.2), equals(-0.3));
    });

    test('mixed int and double', () {
      expect(DecimalHelper.add(1, 0.5), equals(1.5));
    });

    test('division by zero returns infinity', () {
      expect(DecimalHelper.divide(1, 0), double.infinity);
    });

    test('modulo precision', () {
      expect(DecimalHelper.modulo(10, 3), equals(1));
      expect(DecimalHelper.modulo(0.3, 0.1), equals(0));
    });

    test('negate', () {
      expect(DecimalHelper.negate(5), equals(-5));
      expect(DecimalHelper.negate(-3.14), equals(3.14));
    });

    test('percent', () {
      expect(DecimalHelper.percent(85), equals(0.85));
      expect(DecimalHelper.percent(100), equals(1));
    });
  });

  // ===========================================================================
  // Rounding
  // ===========================================================================

  group('DecimalHelper - Banker\'s rounding', () {
    test('round 2.5 to 0 places = 2 (even)', () {
      expect(DecimalHelper.round(2.5, 0), equals(2));
    });

    test('round 3.5 to 0 places = 4 (even)', () {
      expect(DecimalHelper.round(3.5, 0), equals(4));
    });

    test('round 2.455 to 2 places = 2.46', () {
      expect(DecimalHelper.round(2.455, 2), equals(2.46));
    });

    test('round 1.235 to 2 places = 1.24 (even)', () {
      expect(DecimalHelper.round(1.235, 2), equals(1.24));
    });

    test('round negative numbers', () {
      expect(DecimalHelper.round(-2.5, 0), equals(-2));
      expect(DecimalHelper.round(-3.5, 0), equals(-4));
    });

    test('round with no decimal trimming needed', () {
      expect(DecimalHelper.round(3.14, 2), equals(3.14));
    });

    test('round integer stays integer', () {
      expect(DecimalHelper.round(42, 2), equals(42));
    });
  });

  // ===========================================================================
  // Floor / Ceil
  // ===========================================================================

  group('DecimalHelper - floor/ceil', () {
    test('floor positive', () {
      expect(DecimalHelper.floor(3.7), equals(3));
    });

    test('floor negative', () {
      expect(DecimalHelper.floor(-3.2), equals(-4));
    });

    test('ceil positive', () {
      expect(DecimalHelper.ceil(3.2), equals(4));
    });

    test('ceil negative', () {
      expect(DecimalHelper.ceil(-3.7), equals(-3));
    });
  });

  // ===========================================================================
  // Comparison
  // ===========================================================================

  group('DecimalHelper - comparison', () {
    test('0.1 + 0.2 equals 0.3', () {
      final result = DecimalHelper.add(0.1, 0.2);
      expect(DecimalHelper.equals(result, 0.3), isTrue);
    });

    test('compare ordering', () {
      expect(DecimalHelper.compare(0.1, 0.2), lessThan(0));
      expect(DecimalHelper.compare(0.3, 0.3), equals(0));
      expect(DecimalHelper.compare(0.5, 0.4), greaterThan(0));
    });
  });

  // ===========================================================================
  // Aggregation
  // ===========================================================================

  group('DecimalHelper - aggregation', () {
    test('sum of small values is precise', () {
      // Sum 0.1 ten times should be exactly 1.0
      final values = List.filled(10, 0.1);
      expect(DecimalHelper.sum(values), equals(1));
    });

    test('average precision', () {
      expect(DecimalHelper.average([0.1, 0.2, 0.3]), equals(0.2));
    });

    test('sum empty list', () {
      expect(DecimalHelper.sum([]), equals(0));
    });

    test('average empty list', () {
      expect(DecimalHelper.average([]), equals(0));
    });
  });

  // ===========================================================================
  // Power
  // ===========================================================================

  group('DecimalHelper - power', () {
    test('integer power', () {
      expect(DecimalHelper.power(2, 10), equals(1024));
    });

    test('decimal base integer exponent', () {
      expect(DecimalHelper.power(1.1, 2), equals(1.21));
    });

    test('power of 0', () {
      expect(DecimalHelper.power(5, 0), equals(1));
    });
  });

  // ===========================================================================
  // End-to-end: evaluator uses DecimalHelper
  // ===========================================================================

  group('Evaluator decimal precision', () {
    late SpreadsheetModel model;
    late SpreadsheetEvaluator evaluator;

    setUp(() {
      model = SpreadsheetModel();
      evaluator = SpreadsheetEvaluator(model);
    });

    tearDown(() => evaluator.dispose());

    test('0.1 + 0.2 via formula = 0.3', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(0.1),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const NumberValue(0.2),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(2, 0),
        const FormulaValue('A1 + B1'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(2, 0)),
        const NumberValue(0.3),
      );
    });

    test('SUM of 0.1 repeated is precise', () {
      for (int i = 0; i < 10; i++) {
        evaluator.setCellAndEvaluate(CellAddress(0, i), const NumberValue(0.1));
      }
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('SUM(A1:A10)'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(1),
      );
    });

    test('ROUND uses Banker\'s rounding', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(2.5),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('ROUND(A1, 0)'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(2), // Banker's: round to even
      );
    });

    test('multiplication precision in formula', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('1.1 * 1.1'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(1.21),
      );
    });
  });
}
