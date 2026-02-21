import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/tabular/cell_address.dart';
import 'package:nebula_engine/src/core/tabular/cell_value.dart';
import 'package:nebula_engine/src/core/tabular/spreadsheet_evaluator.dart';
import 'package:nebula_engine/src/core/tabular/spreadsheet_model.dart';

void main() {
  late SpreadsheetModel model;
  late SpreadsheetEvaluator eval;

  setUp(() {
    model = SpreadsheetModel();
    eval = SpreadsheetEvaluator(model);
  });

  tearDown(() => eval.dispose());

  // ===========================================================================
  // VLOOKUP
  // ===========================================================================

  group('VLOOKUP', () {
    setUp(() {
      // Table: A1:B4 — ID | Name
      eval.setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(1));
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const TextValue('Alice'),
      );
      eval.setCellAndEvaluate(const CellAddress(0, 1), const NumberValue(2));
      eval.setCellAndEvaluate(const CellAddress(1, 1), const TextValue('Bob'));
      eval.setCellAndEvaluate(const CellAddress(0, 2), const NumberValue(3));
      eval.setCellAndEvaluate(
        const CellAddress(1, 2),
        const TextValue('Carol'),
      );
    });

    test('finds exact match', () {
      eval.setCellAndEvaluate(
        const CellAddress(3, 0),
        const FormulaValue('VLOOKUP(2, A1:B3, 2, FALSE)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(3, 0)),
        const TextValue('Bob'),
      );
    });

    test('returns #N/A for not found', () {
      eval.setCellAndEvaluate(
        const CellAddress(3, 0),
        const FormulaValue('VLOOKUP(99, A1:B3, 2, FALSE)'),
      );
      expect(eval.getComputedValue(const CellAddress(3, 0)), isA<ErrorValue>());
    });

    test('returns first column match', () {
      eval.setCellAndEvaluate(
        const CellAddress(3, 0),
        const FormulaValue('VLOOKUP(1, A1:B3, 2, FALSE)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(3, 0)),
        const TextValue('Alice'),
      );
    });
  });

  // ===========================================================================
  // INDEX
  // ===========================================================================

  group('INDEX', () {
    setUp(() {
      // 3x3 table
      eval.setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(10));
      eval.setCellAndEvaluate(const CellAddress(1, 0), const NumberValue(20));
      eval.setCellAndEvaluate(const CellAddress(2, 0), const NumberValue(30));
      eval.setCellAndEvaluate(const CellAddress(0, 1), const NumberValue(40));
      eval.setCellAndEvaluate(const CellAddress(1, 1), const NumberValue(50));
      eval.setCellAndEvaluate(const CellAddress(2, 1), const NumberValue(60));
    });

    test('returns value at row,col', () {
      eval.setCellAndEvaluate(
        const CellAddress(4, 0),
        const FormulaValue('INDEX(A1:C2, 2, 3)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(4, 0)),
        const NumberValue(60),
      );
    });

    test('returns #REF! for out of bounds', () {
      eval.setCellAndEvaluate(
        const CellAddress(4, 0),
        const FormulaValue('INDEX(A1:C2, 5, 1)'),
      );
      expect(eval.getComputedValue(const CellAddress(4, 0)), isA<ErrorValue>());
    });
  });

  // ===========================================================================
  // MATCH
  // ===========================================================================

  group('MATCH', () {
    setUp(() {
      eval.setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(10));
      eval.setCellAndEvaluate(const CellAddress(0, 1), const NumberValue(20));
      eval.setCellAndEvaluate(const CellAddress(0, 2), const NumberValue(30));
      eval.setCellAndEvaluate(const CellAddress(0, 3), const NumberValue(40));
    });

    test('exact match finds position', () {
      eval.setCellAndEvaluate(
        const CellAddress(2, 0),
        const FormulaValue('MATCH(30, A1:A4, 0)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(2, 0)),
        const NumberValue(3),
      );
    });

    test('exact match #N/A when not found', () {
      eval.setCellAndEvaluate(
        const CellAddress(2, 0),
        const FormulaValue('MATCH(99, A1:A4, 0)'),
      );
      expect(eval.getComputedValue(const CellAddress(2, 0)), isA<ErrorValue>());
    });
  });

  // ===========================================================================
  // SUMIF / COUNTIF / AVERAGEIF
  // ===========================================================================

  group('SUMIF', () {
    setUp(() {
      // Category | Amount
      eval.setCellAndEvaluate(const CellAddress(0, 0), const TextValue('A'));
      eval.setCellAndEvaluate(const CellAddress(1, 0), const NumberValue(10));
      eval.setCellAndEvaluate(const CellAddress(0, 1), const TextValue('B'));
      eval.setCellAndEvaluate(const CellAddress(1, 1), const NumberValue(20));
      eval.setCellAndEvaluate(const CellAddress(0, 2), const TextValue('A'));
      eval.setCellAndEvaluate(const CellAddress(1, 2), const NumberValue(30));
    });

    test('sums matching category', () {
      eval.setCellAndEvaluate(
        const CellAddress(3, 0),
        const FormulaValue('SUMIF(A1:A3, "A", B1:B3)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(3, 0)),
        const NumberValue(40), // 10 + 30
      );
    });

    test('sums with numeric criteria', () {
      eval.setCellAndEvaluate(
        const CellAddress(3, 0),
        const FormulaValue('SUMIF(B1:B3, ">15")'),
      );
      expect(
        eval.getComputedValue(const CellAddress(3, 0)),
        const NumberValue(50), // 20 + 30
      );
    });
  });

  group('COUNTIF', () {
    setUp(() {
      eval.setCellAndEvaluate(const CellAddress(0, 0), const TextValue('Yes'));
      eval.setCellAndEvaluate(const CellAddress(0, 1), const TextValue('No'));
      eval.setCellAndEvaluate(const CellAddress(0, 2), const TextValue('Yes'));
      eval.setCellAndEvaluate(const CellAddress(0, 3), const TextValue('Yes'));
    });

    test('counts matching text', () {
      eval.setCellAndEvaluate(
        const CellAddress(2, 0),
        const FormulaValue('COUNTIF(A1:A4, "Yes")'),
      );
      expect(
        eval.getComputedValue(const CellAddress(2, 0)),
        const NumberValue(3),
      );
    });
  });

  group('AVERAGEIF', () {
    setUp(() {
      eval.setCellAndEvaluate(const CellAddress(0, 0), const TextValue('A'));
      eval.setCellAndEvaluate(const CellAddress(1, 0), const NumberValue(10));
      eval.setCellAndEvaluate(const CellAddress(0, 1), const TextValue('B'));
      eval.setCellAndEvaluate(const CellAddress(1, 1), const NumberValue(20));
      eval.setCellAndEvaluate(const CellAddress(0, 2), const TextValue('A'));
      eval.setCellAndEvaluate(const CellAddress(1, 2), const NumberValue(30));
    });

    test('averages matching category', () {
      eval.setCellAndEvaluate(
        const CellAddress(3, 0),
        const FormulaValue('AVERAGEIF(A1:A3, "A", B1:B3)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(3, 0)),
        const NumberValue(20), // (10 + 30) / 2
      );
    });
  });

  // ===========================================================================
  // Date Functions
  // ===========================================================================

  group('Date functions', () {
    test('DATE creates serial number', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('DATE(2024, 1, 1)'),
      );
      final val = eval.getComputedValue(const CellAddress(0, 0));
      expect(val, isA<NumberValue>());
      expect((val as NumberValue).value, greaterThan(0));
    });

    test('YEAR extracts year from serial', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('DATE(2024, 6, 15)'),
      );
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('YEAR(A1)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(2024),
      );
    });

    test('MONTH extracts month', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('DATE(2024, 6, 15)'),
      );
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('MONTH(A1)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(6),
      );
    });

    test('DAY extracts day', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('DATE(2024, 6, 15)'),
      );
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('DAY(A1)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(15),
      );
    });

    test('TODAY returns a positive serial', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('TODAY()'),
      );
      final val = eval.getComputedValue(const CellAddress(0, 0));
      expect(val, isA<NumberValue>());
      expect((val as NumberValue).value, greaterThan(40000));
    });

    test('NOW returns a positive float', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('NOW()'),
      );
      final val = eval.getComputedValue(const CellAddress(0, 0));
      expect(val, isA<NumberValue>());
      expect((val as NumberValue).value, greaterThan(40000));
    });
  });

  // ===========================================================================
  // Text Functions
  // ===========================================================================

  group('Text functions', () {
    test('FIND returns position (1-indexed)', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('Hello World'),
      );
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('FIND("World", A1)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(7),
      );
    });

    test('FIND returns #VALUE! when not found', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('Hello'),
      );
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('FIND("xyz", A1)'),
      );
      expect(eval.getComputedValue(const CellAddress(1, 0)), isA<ErrorValue>());
    });

    test('SUBSTITUTE replaces text', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('foo bar foo'),
      );
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('SUBSTITUTE(A1, "foo", "baz")'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const TextValue('baz bar baz'),
      );
    });

    test('TEXT formats number with decimals', () {
      eval.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(3.14159),
      );
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('TEXT(A1, "0.00")'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const TextValue('3.14'),
      );
    });

    test('VALUE parses text to number', () {
      eval.setCellAndEvaluate(const CellAddress(0, 0), const TextValue('42'));
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('VALUE(A1)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(42),
      );
    });

    test('VALUE parses percentage', () {
      eval.setCellAndEvaluate(const CellAddress(0, 0), const TextValue('85%'));
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('VALUE(A1)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(0.85),
      );
    });
  });

  // ===========================================================================
  // Named Ranges
  // ===========================================================================

  group('Named ranges', () {
    test('SUM with named range', () {
      eval.setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(10));
      eval.setCellAndEvaluate(const CellAddress(0, 1), const NumberValue(20));
      eval.setCellAndEvaluate(const CellAddress(0, 2), const NumberValue(30));

      model.setNamedRange(
        'Revenue',
        CellRange(const CellAddress(0, 0), const CellAddress(0, 2)),
      );

      eval.setCellAndEvaluate(
        const CellAddress(2, 0),
        const FormulaValue('SUM(Revenue)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(2, 0)),
        const NumberValue(60),
      );
    });

    test('AVERAGE with named range', () {
      eval.setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(10));
      eval.setCellAndEvaluate(const CellAddress(0, 1), const NumberValue(20));
      eval.setCellAndEvaluate(const CellAddress(0, 2), const NumberValue(30));

      model.setNamedRange(
        'Data',
        CellRange(const CellAddress(0, 0), const CellAddress(0, 2)),
      );

      eval.setCellAndEvaluate(
        const CellAddress(2, 0),
        const FormulaValue('AVERAGE(Data)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(2, 0)),
        const NumberValue(20),
      );
    });

    test('named range case insensitive', () {
      eval.setCellAndEvaluate(const CellAddress(0, 0), const NumberValue(5));
      model.setNamedRange(
        'myRange',
        CellRange(const CellAddress(0, 0), const CellAddress(0, 0)),
      );
      eval.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('SUM(MYRANGE)'),
      );
      expect(
        eval.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(5),
      );
    });

    test('named range persists in toJson/fromJson', () {
      model.setNamedRange(
        'test',
        CellRange(const CellAddress(0, 0), const CellAddress(5, 5)),
      );
      final json = model.toJson();
      final restored = SpreadsheetModel.fromJson(json);
      expect(restored.hasNamedRange('test'), isTrue);
      expect(restored.getNamedRange('test')?.startColumn, 0);
      expect(restored.getNamedRange('test')?.endColumn, 5);
    });

    test('named range CRUD operations', () {
      model.setNamedRange(
        'test',
        CellRange(const CellAddress(0, 0), const CellAddress(0, 0)),
      );
      expect(model.hasNamedRange('test'), isTrue);
      expect(model.namedRanges.length, 1);

      model.removeNamedRange('test');
      expect(model.hasNamedRange('test'), isFalse);
    });
  });
}
