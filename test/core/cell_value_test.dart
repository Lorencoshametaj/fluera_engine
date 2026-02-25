import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/tabular/cell_value.dart';

void main() {
  // ===========================================================================
  // EmptyValue
  // ===========================================================================

  group('EmptyValue', () {
    test('creates empty value', () {
      const empty = EmptyValue();
      expect(empty, isA<CellValue>());
    });

    test('toJson returns type', () {
      final json = const EmptyValue().toJson();
      expect(json['type'], 'empty');
    });

    test('toString is readable', () {
      expect(const EmptyValue().toString(), isNotEmpty);
    });
  });

  // ===========================================================================
  // NumberValue
  // ===========================================================================

  group('NumberValue', () {
    test('stores double value', () {
      const num = NumberValue(42.0);
      expect(num.value, 42.0);
    });

    test('toJson round-trips', () {
      final json = const NumberValue(3.14).toJson();
      expect(json['type'], 'number');
      expect(json['value'], 3.14);
    });

    test('equality works', () {
      expect(const NumberValue(1.0), equals(const NumberValue(1.0)));
      expect(const NumberValue(1.0), isNot(equals(const NumberValue(2.0))));
    });
  });

  // ===========================================================================
  // TextValue
  // ===========================================================================

  group('TextValue', () {
    test('stores text', () {
      const t = TextValue('hello');
      expect(t.value, 'hello');
    });

    test('toJson round-trips', () {
      final json = const TextValue('world').toJson();
      expect(json['type'], 'text');
      expect(json['value'], 'world');
    });

    test('equality works', () {
      expect(const TextValue('a'), equals(const TextValue('a')));
    });
  });

  // ===========================================================================
  // BoolValue
  // ===========================================================================

  group('BoolValue', () {
    test('stores boolean', () {
      const b = BoolValue(true);
      expect(b.value, isTrue);
    });

    test('toJson round-trips', () {
      final json = const BoolValue(false).toJson();
      expect(json['type'], 'bool');
      expect(json['value'], isFalse);
    });
  });

  // ===========================================================================
  // FormulaValue
  // ===========================================================================

  group('FormulaValue', () {
    test('stores expression without =', () {
      const f = FormulaValue('SUM(A1:A10)');
      expect(f.expression, 'SUM(A1:A10)');
    });

    test('toJson round-trips', () {
      final json = const FormulaValue('AVERAGE(B1:B5)').toJson();
      expect(json['type'], 'formula');
    });
  });

  // ===========================================================================
  // ErrorValue
  // ===========================================================================

  group('ErrorValue', () {
    test('stores error info', () {
      const e = ErrorValue(CellError.divisionByZero);
      expect(e.error, CellError.divisionByZero);
    });

    test('toJson round-trips', () {
      final json = const ErrorValue(CellError.invalidRef).toJson();
      expect(json['type'], 'error');
    });
  });

  // ===========================================================================
  // ComplexValue
  // ===========================================================================

  group('ComplexValue', () {
    test('stores metadata', () {
      final c = ComplexValue({'key': 'value'});
      expect(c.metadata, containsPair('key', 'value'));
    });

    test('toJson round-trips', () {
      final json = ComplexValue({'amount': 100}).toJson();
      expect(json['type'], 'complex');
    });
  });

  // ===========================================================================
  // Pattern matching
  // ===========================================================================

  group('CellValue - pattern matching', () {
    test('works with switch', () {
      const CellValue v = NumberValue(42);
      final result = switch (v) {
        NumberValue(:final value) => 'num: $value',
        TextValue(:final value) => 'text: $value',
        _ => 'other',
      };
      expect(result, startsWith('num:'));
    });
  });
}
