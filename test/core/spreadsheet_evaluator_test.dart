import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/tabular/cell_address.dart';
import 'package:nebula_engine/src/core/tabular/cell_value.dart';
import 'package:nebula_engine/src/core/tabular/spreadsheet_evaluator.dart';
import 'package:nebula_engine/src/core/tabular/spreadsheet_model.dart';

void main() {
  late SpreadsheetModel model;
  late SpreadsheetEvaluator evaluator;

  setUp(() {
    model = SpreadsheetModel();
    evaluator = SpreadsheetEvaluator(model);
  });

  tearDown(() {
    evaluator.dispose();
  });

  // ===========================================================================
  // Basic evaluation
  // ===========================================================================

  group('SpreadsheetEvaluator - basic', () {
    test('numeric value evaluates to itself', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(42),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(0, 0)),
        const NumberValue(42),
      );
    });

    test('text value evaluates to itself', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('hello'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(0, 0)),
        const TextValue('hello'),
      );
    });

    test('empty cell returns EmptyValue', () {
      expect(
        evaluator.getComputedValue(const CellAddress(5, 5)),
        const EmptyValue(),
      );
    });
  });

  // ===========================================================================
  // Formula evaluation
  // ===========================================================================

  group('SpreadsheetEvaluator - formulas', () {
    test('simple addition formula', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 + 5'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(15),
      );
    });

    test('cell reference formula', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 * 2'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(20),
      );
    });

    test('SUM function', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(2),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 2),
        const NumberValue(3),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('SUM(A1:A3)'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(6),
      );
    });

    test('AVERAGE function', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(20),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 2),
        const NumberValue(30),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('AVERAGE(A1:A3)'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(20),
      );
    });

    test('IF function', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(5),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('IF(A1 > 3, "big", "small")'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const TextValue('big'),
      );
    });

    test('division by zero', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('1 / 0'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(0, 0)),
        isA<ErrorValue>(),
      );
      expect(
        (evaluator.getComputedValue(const CellAddress(0, 0)) as ErrorValue)
            .error,
        CellError.divisionByZero,
      );
    });

    test('concatenation operator', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('hello'),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 & " world"'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const TextValue('hello world'),
      );
    });

    test('nested functions', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(-5),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('ABS(A1)'),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(5),
      );
    });
  });

  // ===========================================================================
  // Incremental recalculation
  // ===========================================================================

  group('SpreadsheetEvaluator - incremental', () {
    test('changing a source cell updates dependents', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 * 2'),
      );

      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(20),
      );

      // Change A1.
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(5),
      );

      // B1 should automatically update.
      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(10),
      );
    });

    test('transitive dependency chain recalculates', () {
      // A1 = 10, B1 = A1 * 2, C1 = B1 + 5
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 * 2'),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(2, 0),
        const FormulaValue('B1 + 5'),
      );

      expect(
        evaluator.getComputedValue(const CellAddress(2, 0)),
        const NumberValue(25),
      );

      // Change A1 → cascades to B1 → cascades to C1.
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );

      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(2),
      );
      expect(
        evaluator.getComputedValue(const CellAddress(2, 0)),
        const NumberValue(7),
      );
    });
  });

  // ===========================================================================
  // Cycle detection
  // ===========================================================================

  group('SpreadsheetEvaluator - cycles', () {
    test('direct circular reference detected', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('B1'),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1'),
      );

      final value = evaluator.getComputedValue(const CellAddress(0, 0));
      // At least one of the cycle members should be a circular ref error.
      final a1 = evaluator.getComputedValue(const CellAddress(0, 0));
      final b1 = evaluator.getComputedValue(const CellAddress(1, 0));
      expect(
        a1 is ErrorValue || b1 is ErrorValue,
        true,
        reason: 'At least one cell in a cycle should produce an error',
      );
    });

    test('hasCycle detects circular dependency', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const FormulaValue('B1'),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1'),
      );

      expect(evaluator.hasCycle(const CellAddress(0, 0)), true);
    });

    test('no cycle in valid dependency chain', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 * 2'),
      );

      expect(evaluator.hasCycle(const CellAddress(1, 0)), false);
    });
  });

  // ===========================================================================
  // Change events
  // ===========================================================================

  group('SpreadsheetEvaluator - change events', () {
    test('emits CellChangeEvent on value change', () async {
      final events = <CellChangeEvent>[];
      final sub = evaluator.onCellChanged.listen(events.add);

      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(42),
      );

      // Allow stream to deliver.
      await Future.delayed(Duration.zero);

      expect(events.length, 1);
      expect(events[0].address, const CellAddress(0, 0));
      expect(events[0].newValue, const NumberValue(42));

      sub.cancel();
    });

    test('emits events for transitive dependents', () async {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 * 2'),
      );

      final events = <CellChangeEvent>[];
      final sub = evaluator.onCellChanged.listen(events.add);

      // Change A1 → should also re-evaluate B1.
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(5),
      );

      await Future.delayed(Duration.zero);

      expect(events.any((e) => e.address == const CellAddress(0, 0)), true);
      expect(events.any((e) => e.address == const CellAddress(1, 0)), true);

      sub.cancel();
    });
  });

  // ===========================================================================
  // evaluateAll
  // ===========================================================================

  group('SpreadsheetEvaluator - evaluateAll', () {
    test('recomputes all formulas from scratch', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 + 5'),
      );

      // Create a fresh evaluator on the same model.
      evaluator.dispose();
      evaluator = SpreadsheetEvaluator(model);
      evaluator.evaluateAll();

      expect(
        evaluator.getComputedValue(const CellAddress(1, 0)),
        const NumberValue(15),
      );
    });
  });

  // ===========================================================================
  // clearCellAndEvaluate
  // ===========================================================================

  group('SpreadsheetEvaluator - clearCell', () {
    test('clearing a source cell updates dependents', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 + 5'),
      );

      evaluator.clearCellAndEvaluate(const CellAddress(0, 0));

      // A1 is now empty (0 for SUM), so B1 = 0 + 5 = 5
      // Actually: EmptyValue.asNumber is null, so the formula gets a valueError.
      // Let's verify the behavior.
      final result = evaluator.getComputedValue(const CellAddress(1, 0));
      // When A1 is cleared, the formula 'A1 + 5' tries to add EmptyValue + 5.
      // EmptyValue.asNumber is null, so it should produce an error.
      expect(result, isA<ErrorValue>());
    });
  });
}
