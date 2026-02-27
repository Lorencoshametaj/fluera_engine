import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_node.dart';
import 'package:fluera_engine/src/core/tabular/cell_validation.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_model.dart';

void main() {
  // ===========================================================================
  // CellValidation — number
  // ===========================================================================

  group('CellValidation - number type', () {
    test('accepts valid number in range', () {
      final rule = CellValidation(
        type: CellValidationType.number,
        min: 1,
        max: 100,
      );
      expect(rule.validate(const NumberValue(50)), isTrue);
    });

    test('rejects number below min', () {
      final rule = CellValidation(
        type: CellValidationType.number,
        min: 1,
        max: 100,
      );
      expect(rule.validate(const NumberValue(0)), isFalse);
    });

    test('rejects number above max', () {
      final rule = CellValidation(
        type: CellValidationType.number,
        min: 1,
        max: 100,
      );
      expect(rule.validate(const NumberValue(200)), isFalse);
    });

    test('accepts boundary values', () {
      final rule = CellValidation(
        type: CellValidationType.number,
        min: 1,
        max: 100,
      );
      expect(rule.validate(const NumberValue(1)), isTrue);
      expect(rule.validate(const NumberValue(100)), isTrue);
    });

    test('rejects non-numeric values', () {
      final rule = CellValidation(
        type: CellValidationType.number,
        min: 0,
        max: 100,
      );
      expect(rule.validate(const TextValue('hello')), isFalse);
    });

    test('accepts decimals for number type', () {
      final rule = CellValidation(
        type: CellValidationType.number,
        min: 0,
        max: 10,
      );
      expect(rule.validate(const NumberValue(3.14)), isTrue);
    });

    test('min only', () {
      final rule = CellValidation(type: CellValidationType.number, min: 0);
      expect(rule.validate(const NumberValue(-1)), isFalse);
      expect(rule.validate(const NumberValue(0)), isTrue);
      expect(rule.validate(const NumberValue(999999)), isTrue);
    });

    test('max only', () {
      final rule = CellValidation(type: CellValidationType.number, max: 100);
      expect(rule.validate(const NumberValue(-999)), isTrue);
      expect(rule.validate(const NumberValue(101)), isFalse);
    });
  });

  // ===========================================================================
  // CellValidation — integer
  // ===========================================================================

  group('CellValidation - integer type', () {
    test('accepts integer values', () {
      final rule = CellValidation(type: CellValidationType.integer);
      expect(rule.validate(const NumberValue(42)), isTrue);
    });

    test('rejects decimal values', () {
      final rule = CellValidation(type: CellValidationType.integer);
      expect(rule.validate(const NumberValue(3.14)), isFalse);
    });

    test('integer with range', () {
      final rule = CellValidation(
        type: CellValidationType.integer,
        min: 1,
        max: 10,
      );
      expect(rule.validate(const NumberValue(5)), isTrue);
      expect(rule.validate(const NumberValue(11)), isFalse);
      expect(rule.validate(const NumberValue(3.5)), isFalse);
    });
  });

  // ===========================================================================
  // CellValidation — list
  // ===========================================================================

  group('CellValidation - list type', () {
    test('accepts values in list', () {
      final rule = CellValidation(
        type: CellValidationType.list,
        allowedValues: ['Red', 'Green', 'Blue'],
      );
      expect(rule.validate(const TextValue('Red')), isTrue);
      expect(rule.validate(const TextValue('Green')), isTrue);
    });

    test('rejects values not in list', () {
      final rule = CellValidation(
        type: CellValidationType.list,
        allowedValues: ['Red', 'Green', 'Blue'],
      );
      expect(rule.validate(const TextValue('Yellow')), isFalse);
    });

    test('empty allowed list accepts everything', () {
      final rule = CellValidation(
        type: CellValidationType.list,
        allowedValues: [],
      );
      expect(rule.validate(const TextValue('anything')), isTrue);
    });
  });

  // ===========================================================================
  // CellValidation — textLength
  // ===========================================================================

  group('CellValidation - textLength type', () {
    test('accepts text within length range', () {
      final rule = CellValidation(
        type: CellValidationType.textLength,
        min: 2,
        max: 10,
      );
      expect(rule.validate(const TextValue('hello')), isTrue);
    });

    test('rejects too short text', () {
      final rule = CellValidation(type: CellValidationType.textLength, min: 5);
      expect(rule.validate(const TextValue('hi')), isFalse);
    });

    test('rejects too long text', () {
      final rule = CellValidation(type: CellValidationType.textLength, max: 3);
      expect(rule.validate(const TextValue('toolong')), isFalse);
    });
  });

  // ===========================================================================
  // CellValidation — blank handling
  // ===========================================================================

  group('CellValidation - blank handling', () {
    test('ignoreBlank=true allows empty values', () {
      final rule = CellValidation(
        type: CellValidationType.number,
        min: 1,
        max: 100,
        ignoreBlank: true,
      );
      expect(rule.validate(const EmptyValue()), isTrue);
    });

    test('ignoreBlank=false rejects empty values', () {
      final rule = CellValidation(
        type: CellValidationType.number,
        min: 1,
        max: 100,
        ignoreBlank: false,
      );
      expect(rule.validate(const EmptyValue()), isFalse);
    });
  });

  // ===========================================================================
  // CellValidation — any type
  // ===========================================================================

  group('CellValidation - any type', () {
    test('accepts everything', () {
      const rule = CellValidation(type: CellValidationType.any);
      expect(rule.validate(const NumberValue(42)), isTrue);
      expect(rule.validate(const TextValue('hello')), isTrue);
      expect(rule.validate(const EmptyValue()), isTrue);
      expect(rule.validate(const BoolValue(true)), isTrue);
    });
  });

  // ===========================================================================
  // CellValidation — serialization
  // ===========================================================================

  group('CellValidation - serialization', () {
    test('toJson/fromJson roundtrip for number', () {
      final rule = CellValidation(
        type: CellValidationType.number,
        min: 0,
        max: 100,
        errorTitle: 'Error',
        errorMessage: 'Must be 0-100',
      );
      final json = rule.toJson();
      final restored = CellValidation.fromJson(json);
      expect(restored.type, CellValidationType.number);
      expect(restored.min, 0);
      expect(restored.max, 100);
      expect(restored.errorTitle, 'Error');
      expect(restored.errorMessage, 'Must be 0-100');
    });

    test('toJson/fromJson roundtrip for list', () {
      final rule = CellValidation(
        type: CellValidationType.list,
        allowedValues: ['A', 'B', 'C'],
      );
      final json = rule.toJson();
      final restored = CellValidation.fromJson(json);
      expect(restored.type, CellValidationType.list);
      expect(restored.allowedValues, ['A', 'B', 'C']);
    });

    test('error style serialization', () {
      final rule = CellValidation(
        type: CellValidationType.number,
        errorStyle: ValidationErrorStyle.warning,
      );
      final json = rule.toJson();
      final restored = CellValidation.fromJson(json);
      expect(restored.errorStyle, ValidationErrorStyle.warning);
    });
  });

  // ===========================================================================
  // SpreadsheetModel integration
  // ===========================================================================

  group('SpreadsheetModel - validation integration', () {
    test('set and get validation', () {
      final model = SpreadsheetModel();
      const addr = CellAddress(0, 0);
      const rule = CellValidation(
        type: CellValidationType.number,
        min: 0,
        max: 100,
      );
      model.setValidation(addr, rule);
      expect(model.getValidation(addr), equals(rule));
      expect(model.hasValidation(addr), isTrue);
    });

    test('validateCell passes for valid value', () {
      final model = SpreadsheetModel();
      const addr = CellAddress(0, 0);
      model.setValidation(
        addr,
        const CellValidation(type: CellValidationType.number, min: 0, max: 100),
      );
      expect(model.validateCell(addr, const NumberValue(50)), isTrue);
    });

    test('validateCell fails for invalid value', () {
      final model = SpreadsheetModel();
      const addr = CellAddress(0, 0);
      model.setValidation(
        addr,
        const CellValidation(type: CellValidationType.number, min: 0, max: 100),
      );
      expect(model.validateCell(addr, const NumberValue(200)), isFalse);
    });

    test('validateCell returns true when no rule', () {
      final model = SpreadsheetModel();
      expect(
        model.validateCell(const CellAddress(0, 0), const NumberValue(999)),
        isTrue,
      );
    });

    test('remove validation', () {
      final model = SpreadsheetModel();
      const addr = CellAddress(0, 0);
      model.setValidation(
        addr,
        const CellValidation(type: CellValidationType.number),
      );
      model.removeValidation(addr);
      expect(model.hasValidation(addr), isFalse);
    });

    test('validation survives toJson/fromJson', () {
      final model = SpreadsheetModel();
      model.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(42)),
      );
      model.setValidation(
        const CellAddress(0, 0),
        const CellValidation(type: CellValidationType.number, min: 0, max: 100),
      );

      final json = model.toJson();
      final restored = SpreadsheetModel.fromJson(json);

      expect(restored.hasValidation(const CellAddress(0, 0)), isTrue);
      expect(
        restored.getValidation(const CellAddress(0, 0))?.type,
        CellValidationType.number,
      );
      expect(restored.getValidation(const CellAddress(0, 0))?.min, 0);
      expect(restored.getValidation(const CellAddress(0, 0))?.max, 100);
    });

    test('validation survives clone', () {
      final model = SpreadsheetModel();
      model.setValidation(
        const CellAddress(0, 0),
        const CellValidation(
          type: CellValidationType.list,
          allowedValues: ['A', 'B'],
        ),
      );

      final clone = model.clone();
      expect(clone.hasValidation(const CellAddress(0, 0)), isTrue);
    });
  });

  // ===========================================================================
  // Error messages
  // ===========================================================================

  group('CellValidation - error messages', () {
    test('auto-generated number range message', () {
      const rule = CellValidation(
        type: CellValidationType.number,
        min: 1,
        max: 100,
      );
      expect(rule.effectiveErrorMessage, contains('1'));
      expect(rule.effectiveErrorMessage, contains('100'));
    });

    test('custom error message overrides auto-generated', () {
      const rule = CellValidation(
        type: CellValidationType.number,
        errorMessage: 'Custom error',
      );
      expect(rule.effectiveErrorMessage, 'Custom error');
    });
  });
}
