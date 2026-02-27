import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/formula_ast.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';

void main() {
  // ===========================================================================
  // Literals
  // ===========================================================================

  group('NumberLiteral', () {
    test('stores value', () {
      const n = NumberLiteral(42);
      expect(n.value, 42);
    });

    test('equality', () {
      expect(const NumberLiteral(3.14), const NumberLiteral(3.14));
      expect(const NumberLiteral(1), isNot(const NumberLiteral(2)));
    });

    test('toString', () {
      expect(const NumberLiteral(7).toString(), contains('7'));
    });
  });

  group('StringLiteral', () {
    test('stores value', () {
      const s = StringLiteral('hello');
      expect(s.value, 'hello');
    });

    test('equality', () {
      expect(const StringLiteral('a'), const StringLiteral('a'));
    });

    test('toString', () {
      expect(const StringLiteral('x').toString(), contains('x'));
    });
  });

  group('BoolLiteral', () {
    test('true and false', () {
      expect(const BoolLiteral(true).value, isTrue);
      expect(const BoolLiteral(false).value, isFalse);
    });

    test('equality', () {
      expect(const BoolLiteral(true), const BoolLiteral(true));
    });
  });

  // ===========================================================================
  // Cell references
  // ===========================================================================

  group('CellRef', () {
    test('creates with address', () {
      final ref = CellRef(CellAddress(0, 0));
      expect(ref.address.row, 0);
      expect(ref.address.column, 0);
    });

    test('absolute flags', () {
      final ref = CellRef(
        CellAddress(0, 0),
        absoluteColumn: true,
        absoluteRow: true,
      );
      expect(ref.absoluteColumn, isTrue);
    });

    test('equality based on address', () {
      expect(CellRef(CellAddress(1, 2)), CellRef(CellAddress(1, 2)));
    });

    test('toString', () {
      expect(CellRef(CellAddress(0, 0)).toString(), contains('CellRef'));
    });
  });

  group('RangeRef', () {
    test('creates with range', () {
      final ref = RangeRef(CellRange(CellAddress(0, 0), CellAddress(9, 0)));
      expect(ref.range, isNotNull);
    });

    test('toString', () {
      expect(
        RangeRef(CellRange(CellAddress(0, 0), CellAddress(1, 1))).toString(),
        contains('RangeRef'),
      );
    });
  });

  // ===========================================================================
  // Operations
  // ===========================================================================

  group('BinaryOp', () {
    test('constructs with left, right, op', () {
      const bin = BinaryOp(
        left: NumberLiteral(1),
        right: NumberLiteral(2),
        op: '+',
      );
      expect(bin.op, '+');
    });

    test('equality', () {
      const a = BinaryOp(
        left: NumberLiteral(1),
        right: NumberLiteral(2),
        op: '+',
      );
      const b = BinaryOp(
        left: NumberLiteral(1),
        right: NumberLiteral(2),
        op: '+',
      );
      expect(a, b);
    });

    test('toString', () {
      const bin = BinaryOp(
        left: NumberLiteral(1),
        right: NumberLiteral(2),
        op: '*',
      );
      expect(bin.toString(), contains('*'));
    });
  });

  group('UnaryOp', () {
    test('negation', () {
      const u = UnaryOp(operand: NumberLiteral(5), op: '-');
      expect(u.op, '-');
    });

    test('equality', () {
      const a = UnaryOp(operand: NumberLiteral(5), op: '-');
      const b = UnaryOp(operand: NumberLiteral(5), op: '-');
      expect(a, b);
    });
  });

  // ===========================================================================
  // Function calls
  // ===========================================================================

  group('FunctionCall', () {
    test('creates SUM with args', () {
      final fc = FunctionCall('SUM', [
        const NumberLiteral(1),
        const NumberLiteral(2),
      ]);
      expect(fc.name, 'SUM');
      expect(fc.args.length, 2);
    });

    test('equality', () {
      final a = FunctionCall('SUM', [const NumberLiteral(1)]);
      final b = FunctionCall('SUM', [const NumberLiteral(1)]);
      expect(a, b);
    });

    test('toString', () {
      final fc = FunctionCall('IF', [const BoolLiteral(true)]);
      expect(fc.toString(), contains('IF'));
    });
  });

  // ===========================================================================
  // Cross-sheet references
  // ===========================================================================

  group('SheetCellRef', () {
    test('creates with sheet name', () {
      final ref = SheetCellRef('Sheet2', CellAddress(0, 0));
      expect(ref.sheetName, 'Sheet2');
    });

    test('equality', () {
      expect(
        SheetCellRef('S1', CellAddress(0, 0)),
        SheetCellRef('S1', CellAddress(0, 0)),
      );
    });
  });

  group('SheetRangeRef', () {
    test('creates with sheet name and range', () {
      final ref = SheetRangeRef(
        'Data',
        CellRange(CellAddress(0, 0), CellAddress(9, 3)),
      );
      expect(ref.sheetName, 'Data');
    });
  });
}
