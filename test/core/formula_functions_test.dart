import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/formula_functions.dart';

/// Helper: invoke a formula function by name with CellValue args.
CellValue call(String name, List<CellValue> args) {
  final fn = FormulaFunctions.lookup(name);
  if (fn == null) throw StateError('Function $name not found');
  return fn(args);
}

/// Extract numeric result.
double num_(CellValue v) => (v as NumberValue).value.toDouble();

/// Extract text result.
String text_(CellValue v) => (v as TextValue).value;

/// Extract bool result.
bool bool_(CellValue v) => (v as BoolValue).value;

void main() {
  // ===========================================================================
  // Math functions
  // ===========================================================================

  group('Math functions', () {
    test('SUM adds numbers', () {
      expect(
        num_(
          call('SUM', [
            const NumberValue(1),
            const NumberValue(2),
            const NumberValue(3),
          ]),
        ),
        closeTo(6, 0.01),
      );
    });

    test('SUM ignores non-numeric', () {
      expect(
        num_(call('SUM', [const NumberValue(10), const TextValue('x')])),
        closeTo(10, 0.01),
      );
    });

    test('AVERAGE computes mean', () {
      expect(
        num_(call('AVERAGE', [const NumberValue(10), const NumberValue(20)])),
        closeTo(15, 0.01),
      );
    });

    test('AVERAGE returns error on empty', () {
      expect(call('AVERAGE', []), isA<ErrorValue>());
    });

    test('MIN finds minimum', () {
      expect(
        num_(
          call('MIN', [
            const NumberValue(5),
            const NumberValue(2),
            const NumberValue(8),
          ]),
        ),
        closeTo(2, 0.01),
      );
    });

    test('MAX finds maximum', () {
      expect(
        num_(
          call('MAX', [
            const NumberValue(5),
            const NumberValue(2),
            const NumberValue(8),
          ]),
        ),
        closeTo(8, 0.01),
      );
    });

    test('ABS returns absolute value', () {
      expect(num_(call('ABS', [const NumberValue(-7)])), closeTo(7, 0.01));
    });

    test('ABS returns error on empty args', () {
      expect(call('ABS', []), isA<ErrorValue>());
    });

    test('ROUND rounds to specified decimals', () {
      expect(
        num_(call('ROUND', [const NumberValue(3.14159), const NumberValue(2)])),
        closeTo(3.14, 0.001),
      );
    });

    test('FLOOR floors value', () {
      expect(num_(call('FLOOR', [const NumberValue(3.7)])), closeTo(3, 0.01));
    });

    test('CEIL ceils value', () {
      expect(num_(call('CEIL', [const NumberValue(3.2)])), closeTo(4, 0.01));
    });

    test('SQRT computes square root', () {
      expect(num_(call('SQRT', [const NumberValue(16)])), closeTo(4, 0.01));
    });

    test('SQRT returns error for negative', () {
      expect(call('SQRT', [const NumberValue(-1)]), isA<ErrorValue>());
    });

    test('POWER computes exponent', () {
      expect(
        num_(call('POWER', [const NumberValue(2), const NumberValue(10)])),
        closeTo(1024, 0.01),
      );
    });

    test('MOD computes remainder', () {
      expect(
        num_(call('MOD', [const NumberValue(10), const NumberValue(3)])),
        closeTo(1, 0.01),
      );
    });

    test('MOD returns error for divisor 0', () {
      expect(
        call('MOD', [const NumberValue(10), const NumberValue(0)]),
        isA<ErrorValue>(),
      );
    });

    test('PI returns pi', () {
      expect(num_(call('PI', [])), closeTo(math.pi, 0.0001));
    });

    test('LOG (base 10)', () {
      expect(num_(call('LOG', [const NumberValue(100)])), closeTo(2, 0.01));
    });

    test('LOG (custom base)', () {
      expect(
        num_(call('LOG', [const NumberValue(8), const NumberValue(2)])),
        closeTo(3, 0.01),
      );
    });

    test('LN (natural log)', () {
      expect(num_(call('LN', [const NumberValue(math.e)])), closeTo(1, 0.01));
    });
  });

  // ===========================================================================
  // Logic functions
  // ===========================================================================

  group('Logic functions', () {
    test('IF true returns then-value', () {
      final result = call('IF', [
        const BoolValue(true),
        const NumberValue(1),
        const NumberValue(0),
      ]);
      expect(num_(result), 1);
    });

    test('IF false returns else-value', () {
      final result = call('IF', [
        const BoolValue(false),
        const NumberValue(1),
        const NumberValue(0),
      ]);
      expect(num_(result), 0);
    });

    test('AND all true', () {
      expect(
        bool_(call('AND', [const BoolValue(true), const BoolValue(true)])),
        isTrue,
      );
    });

    test('AND one false', () {
      expect(
        bool_(call('AND', [const BoolValue(true), const BoolValue(false)])),
        isFalse,
      );
    });

    test('OR one true', () {
      expect(
        bool_(call('OR', [const BoolValue(false), const BoolValue(true)])),
        isTrue,
      );
    });

    test('OR all false', () {
      expect(
        bool_(call('OR', [const BoolValue(false), const BoolValue(false)])),
        isFalse,
      );
    });

    test('NOT true → false', () {
      expect(bool_(call('NOT', [const BoolValue(true)])), isFalse);
    });

    test('NOT false → true', () {
      expect(bool_(call('NOT', [const BoolValue(false)])), isTrue);
    });
  });

  // ===========================================================================
  // Text functions
  // ===========================================================================

  group('Text functions', () {
    test('LEN counts characters', () {
      expect(num_(call('LEN', [const TextValue('Hello')])), 5);
    });

    test('UPPER converts to uppercase', () {
      expect(text_(call('UPPER', [const TextValue('hello')])), 'HELLO');
    });

    test('LOWER converts to lowercase', () {
      expect(text_(call('LOWER', [const TextValue('HELLO')])), 'hello');
    });

    test('CONCAT joins strings', () {
      expect(
        text_(
          call('CONCAT', [
            const TextValue('A'),
            const TextValue('B'),
            const TextValue('C'),
          ]),
        ),
        'ABC',
      );
    });

    test('LEFT extracts left characters', () {
      expect(
        text_(call('LEFT', [const TextValue('Hello'), const NumberValue(3)])),
        'Hel',
      );
    });

    test('RIGHT extracts right characters', () {
      expect(
        text_(call('RIGHT', [const TextValue('Hello'), const NumberValue(3)])),
        'llo',
      );
    });

    test('MID extracts substring (1-indexed)', () {
      expect(
        text_(
          call('MID', [
            const TextValue('Hello World'),
            const NumberValue(7),
            const NumberValue(5),
          ]),
        ),
        'World',
      );
    });

    test('TRIM removes whitespace', () {
      expect(text_(call('TRIM', [const TextValue('  hi  ')])), 'hi');
    });

    test('FIND locates substring (1-indexed)', () {
      expect(
        num_(call('FIND', [const TextValue('ll'), const TextValue('Hello')])),
        3,
      );
    });

    test('FIND returns error if not found', () {
      expect(
        call('FIND', [const TextValue('xyz'), const TextValue('Hello')]),
        isA<ErrorValue>(),
      );
    });

    test('SUBSTITUTE replaces all occurrences', () {
      expect(
        text_(
          call('SUBSTITUTE', [
            const TextValue('aaa'),
            const TextValue('a'),
            const TextValue('b'),
          ]),
        ),
        'bbb',
      );
    });

    test('SUBSTITUTE replaces nth occurrence', () {
      expect(
        text_(
          call('SUBSTITUTE', [
            const TextValue('aaa'),
            const TextValue('a'),
            const TextValue('b'),
            const NumberValue(2),
          ]),
        ),
        'aba',
      );
    });
  });

  // ===========================================================================
  // Info functions
  // ===========================================================================

  group('Info functions', () {
    test('ISBLANK on empty', () {
      expect(bool_(call('ISBLANK', [const EmptyValue()])), isTrue);
    });

    test('ISBLANK on number', () {
      expect(bool_(call('ISBLANK', [const NumberValue(0)])), isFalse);
    });

    test('ISNUMBER on number', () {
      expect(bool_(call('ISNUMBER', [const NumberValue(42)])), isTrue);
    });

    test('ISNUMBER on text', () {
      expect(bool_(call('ISNUMBER', [const TextValue('hi')])), isFalse);
    });

    test('ISTEXT on text', () {
      expect(bool_(call('ISTEXT', [const TextValue('hi')])), isTrue);
    });

    test('ISERROR on error', () {
      expect(
        bool_(call('ISERROR', [const ErrorValue(CellError.divisionByZero)])),
        isTrue,
      );
    });

    test('ISERROR on number', () {
      expect(bool_(call('ISERROR', [const NumberValue(1)])), isFalse);
    });
  });

  // ===========================================================================
  // Statistics functions
  // ===========================================================================

  group('Statistics functions', () {
    test('COUNT counts numbers only', () {
      expect(
        num_(
          call('COUNT', [
            const NumberValue(1),
            const TextValue('a'),
            const NumberValue(2),
          ]),
        ),
        2,
      );
    });

    test('COUNTA counts non-empty', () {
      expect(
        num_(
          call('COUNTA', [
            const NumberValue(1),
            const EmptyValue(),
            const TextValue('a'),
          ]),
        ),
        2,
      );
    });

    test('COUNTBLANK counts empty', () {
      expect(
        num_(
          call('COUNTBLANK', [
            const EmptyValue(),
            const NumberValue(1),
            const EmptyValue(),
          ]),
        ),
        2,
      );
    });

    test('MEDIAN odd count', () {
      expect(
        num_(
          call('MEDIAN', [
            const NumberValue(3),
            const NumberValue(1),
            const NumberValue(2),
          ]),
        ),
        closeTo(2, 0.01),
      );
    });

    test('MEDIAN even count', () {
      expect(
        num_(
          call('MEDIAN', [
            const NumberValue(1),
            const NumberValue(2),
            const NumberValue(3),
            const NumberValue(4),
          ]),
        ),
        closeTo(2.5, 0.01),
      );
    });
  });

  // ===========================================================================
  // Date functions
  // ===========================================================================

  group('Date functions', () {
    test('DATE creates serial date', () {
      final serial = num_(
        call('DATE', [
          const NumberValue(2025),
          const NumberValue(1),
          const NumberValue(1),
        ]),
      );
      expect(serial, isPositive);
    });

    test('YEAR/MONTH/DAY roundtrip', () {
      final serial = call('DATE', [
        const NumberValue(2025),
        const NumberValue(6),
        const NumberValue(15),
      ]);
      expect(num_(call('YEAR', [serial])), 2025);
      expect(num_(call('MONTH', [serial])), 6);
      expect(num_(call('DAY', [serial])), 15);
    });
  });

  // ===========================================================================
  // Error handling
  // ===========================================================================

  group('Error handling', () {
    test('IFERROR returns value if no error', () {
      final result = call('IFERROR', [
        const NumberValue(42),
        const NumberValue(0),
      ]);
      expect(num_(result), 42);
    });

    test('IFERROR returns fallback on error', () {
      final result = call('IFERROR', [
        const ErrorValue(CellError.divisionByZero),
        const NumberValue(-1),
      ]);
      expect(num_(result), -1);
    });
  });

  // ===========================================================================
  // Custom function register/unregister
  // ===========================================================================

  group('Custom functions', () {
    test('register and lookup custom function', () {
      FormulaFunctions.register('DOUBLE', (args) {
        final n = args[0].asNumber ?? 0;
        return NumberValue(n * 2);
      });
      final fn = FormulaFunctions.lookup('DOUBLE');
      expect(fn, isNotNull);
      expect(num_(fn!([const NumberValue(5)])), 10);

      // Clean up
      FormulaFunctions.unregister('DOUBLE');
      expect(FormulaFunctions.lookup('DOUBLE'), isNull);
    });

    test('lookup is case-insensitive', () {
      expect(FormulaFunctions.lookup('sum'), isNotNull);
      expect(FormulaFunctions.lookup('Sum'), isNotNull);
      expect(FormulaFunctions.lookup('SUM'), isNotNull);
    });

    test('registeredNames includes both registries', () {
      expect(FormulaFunctions.registeredNames, contains('SUM'));
      expect(FormulaFunctions.registeredNames, contains('VLOOKUP'));
    });
  });

  // ===========================================================================
  // Utility functions
  // ===========================================================================

  group('Utility functions', () {
    test('CHOOSE selects by index', () {
      final result = call('CHOOSE', [
        const NumberValue(2),
        const TextValue('A'),
        const TextValue('B'),
        const TextValue('C'),
      ]);
      expect(text_(result), 'B');
    });

    test('ROUNDDOWN rounds toward zero', () {
      expect(
        num_(
          call('ROUNDDOWN', [const NumberValue(3.789), const NumberValue(2)]),
        ),
        closeTo(3.78, 0.001),
      );
    });

    test('ROUNDUP rounds away from zero', () {
      expect(
        num_(call('ROUNDUP', [const NumberValue(3.781), const NumberValue(2)])),
        closeTo(3.79, 0.001),
      );
    });

    test('VALUE parses string to number', () {
      expect(
        num_(call('VALUE', [const TextValue('42.5')])),
        closeTo(42.5, 0.01),
      );
    });

    test('VALUE parses percentage', () {
      expect(num_(call('VALUE', [const TextValue('50%')])), closeTo(0.5, 0.01));
    });

    test('TEXT formats number with decimals', () {
      expect(
        text_(
          call('TEXT', [const NumberValue(3.14159), const TextValue('0.00')]),
        ),
        '3.14',
      );
    });

    test('TEXT formats number as percent', () {
      expect(
        text_(call('TEXT', [const NumberValue(0.75), const TextValue('0%')])),
        '75%',
      );
    });
  });
}
