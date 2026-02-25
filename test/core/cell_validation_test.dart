import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/tabular/cell_validation.dart';
import 'package:nebula_engine/src/core/tabular/cell_value.dart';

void main() {
  // ===========================================================================
  // Enums
  // ===========================================================================

  group('CellValidationType', () {
    test('has expected values', () {
      expect(CellValidationType.values, contains(CellValidationType.number));
      expect(CellValidationType.values, contains(CellValidationType.list));
      expect(CellValidationType.values, contains(CellValidationType.any));
    });
  });

  group('ValidationErrorStyle', () {
    test('has stop, warning, information', () {
      expect(ValidationErrorStyle.values.length, 3);
    });
  });

  // ===========================================================================
  // Any type
  // ===========================================================================

  group('CellValidation - any', () {
    test('any type accepts everything', () {
      const v = CellValidation(type: CellValidationType.any);
      expect(v.validate(const NumberValue(42)), isTrue);
      expect(v.validate(const TextValue('hello')), isTrue);
    });
  });

  // ===========================================================================
  // Number validation
  // ===========================================================================

  group('CellValidation - number', () {
    test('accepts number within range', () {
      const v = CellValidation(
        type: CellValidationType.number,
        min: 0,
        max: 100,
      );
      expect(v.validate(const NumberValue(50)), isTrue);
    });

    test('rejects number below min', () {
      const v = CellValidation(
        type: CellValidationType.number,
        min: 10,
        max: 100,
      );
      expect(v.validate(const NumberValue(5)), isFalse);
    });

    test('rejects number above max', () {
      const v = CellValidation(
        type: CellValidationType.number,
        min: 0,
        max: 50,
      );
      expect(v.validate(const NumberValue(100)), isFalse);
    });
  });

  // ===========================================================================
  // Integer validation
  // ===========================================================================

  group('CellValidation - integer', () {
    test('accepts integer within range', () {
      const v = CellValidation(
        type: CellValidationType.integer,
        min: 0,
        max: 10,
      );
      expect(v.validate(const NumberValue(5)), isTrue);
    });
  });

  // ===========================================================================
  // List validation
  // ===========================================================================

  group('CellValidation - list', () {
    test('accepts value in list', () {
      const v = CellValidation(
        type: CellValidationType.list,
        allowedValues: ['a', 'b', 'c'],
      );
      expect(v.validate(const TextValue('b')), isTrue);
    });

    test('rejects value not in list', () {
      const v = CellValidation(
        type: CellValidationType.list,
        allowedValues: ['a', 'b'],
      );
      expect(v.validate(const TextValue('z')), isFalse);
    });
  });

  // ===========================================================================
  // Text length validation
  // ===========================================================================

  group('CellValidation - textLength', () {
    test('accepts text within length', () {
      const v = CellValidation(
        type: CellValidationType.textLength,
        min: 1,
        max: 10,
      );
      expect(v.validate(const TextValue('hello')), isTrue);
    });

    test('rejects text too long', () {
      const v = CellValidation(
        type: CellValidationType.textLength,
        min: 0,
        max: 3,
      );
      expect(v.validate(const TextValue('toolong')), isFalse);
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('CellValidation - toJson', () {
    test('serializes', () {
      const v = CellValidation(
        type: CellValidationType.number,
        min: 0,
        max: 100,
      );
      final json = v.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });
  });

  group('CellValidation - toString', () {
    test('is readable', () {
      const v = CellValidation(type: CellValidationType.any);
      expect(v.toString(), isNotEmpty);
    });
  });
}
