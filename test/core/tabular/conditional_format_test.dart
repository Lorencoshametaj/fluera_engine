import 'package:flutter_test/flutter_test.dart';
import 'dart:ui';
import 'package:nebula_engine/src/core/tabular/conditional_format.dart';
import 'package:nebula_engine/src/core/tabular/cell_address.dart';
import 'package:nebula_engine/src/core/tabular/cell_node.dart';
import 'package:nebula_engine/src/core/tabular/cell_value.dart';

void main() {
  // CellAddress(column, row) — positional args
  // CellRange(start, end) — positional args
  final range = CellRange(CellAddress(0, 0), CellAddress(10, 10));

  group('ConditionalFormatRule', () {
    group('numeric conditions', () {
      test('greaterThan matches correctly', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThan,
          threshold: 50,
          format: const CellFormat(),
        );
        expect(rule.matches(NumberValue(60)), isTrue);
        expect(rule.matches(NumberValue(50)), isFalse);
        expect(rule.matches(NumberValue(40)), isFalse);
      });

      test('greaterThanOrEqual matches correctly', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThanOrEqual,
          threshold: 50,
          format: const CellFormat(),
        );
        expect(rule.matches(NumberValue(50)), isTrue);
        expect(rule.matches(NumberValue(51)), isTrue);
        expect(rule.matches(NumberValue(49)), isFalse);
      });

      test('lessThan matches correctly', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.lessThan,
          threshold: 10,
          format: const CellFormat(),
        );
        expect(rule.matches(NumberValue(5)), isTrue);
        expect(rule.matches(NumberValue(10)), isFalse);
        expect(rule.matches(NumberValue(15)), isFalse);
      });

      test('lessThanOrEqual matches correctly', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.lessThanOrEqual,
          threshold: 10,
          format: const CellFormat(),
        );
        expect(rule.matches(NumberValue(10)), isTrue);
        expect(rule.matches(NumberValue(5)), isTrue);
        expect(rule.matches(NumberValue(11)), isFalse);
      });

      test('equal matches correctly', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.equal,
          threshold: 42,
          format: const CellFormat(),
        );
        expect(rule.matches(NumberValue(42)), isTrue);
        expect(rule.matches(NumberValue(43)), isFalse);
      });

      test('notEqual matches correctly', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.notEqual,
          threshold: 42,
          format: const CellFormat(),
        );
        expect(rule.matches(NumberValue(42)), isFalse);
        expect(rule.matches(NumberValue(43)), isTrue);
      });

      test('between matches correctly', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.between,
          threshold: 10,
          thresholdMax: 20,
          format: const CellFormat(),
        );
        expect(rule.matches(NumberValue(15)), isTrue);
        expect(rule.matches(NumberValue(10)), isTrue);
        expect(rule.matches(NumberValue(20)), isTrue);
        expect(rule.matches(NumberValue(9)), isFalse);
        expect(rule.matches(NumberValue(21)), isFalse);
      });

      test('notBetween matches correctly', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.notBetween,
          threshold: 10,
          thresholdMax: 20,
          format: const CellFormat(),
        );
        expect(rule.matches(NumberValue(5)), isTrue);
        expect(rule.matches(NumberValue(25)), isTrue);
        expect(rule.matches(NumberValue(15)), isFalse);
      });

      test('numeric conditions return false for non-numeric values', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThan,
          threshold: 50,
          format: const CellFormat(),
        );
        expect(rule.matches(TextValue('hello')), isFalse);
        expect(rule.matches(EmptyValue()), isFalse);
      });
    });

    group('text conditions', () {
      test('textContains matches correctly', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.textContains,
          threshold: 'world',
          format: const CellFormat(),
        );
        expect(rule.matches(TextValue('hello world')), isTrue);
        expect(rule.matches(TextValue('hello')), isFalse);
      });

      test('textStartsWith matches correctly', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.textStartsWith,
          threshold: 'hello',
          format: const CellFormat(),
        );
        expect(rule.matches(TextValue('hello world')), isTrue);
        expect(rule.matches(TextValue('world hello')), isFalse);
      });

      test('textEndsWith matches correctly', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.textEndsWith,
          threshold: 'world',
          format: const CellFormat(),
        );
        expect(rule.matches(TextValue('hello world')), isTrue);
        expect(rule.matches(TextValue('world hello')), isFalse);
      });
    });

    group('special conditions', () {
      test('isBlank matches empty values', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.isBlank,
          format: const CellFormat(),
        );
        expect(rule.matches(EmptyValue()), isTrue);
        expect(rule.matches(TextValue('hi')), isFalse);
        expect(rule.matches(NumberValue(0)), isFalse);
      });

      test('isNotBlank matches non-empty values', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.isNotBlank,
          format: const CellFormat(),
        );
        expect(rule.matches(EmptyValue()), isFalse);
        expect(rule.matches(TextValue('hi')), isTrue);
        expect(rule.matches(NumberValue(0)), isTrue);
      });

      test('isError matches error values', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.isError,
          format: const CellFormat(),
        );
        expect(
          rule.matches(const ErrorValue(CellError.divisionByZero)),
          isTrue,
        );
        expect(rule.matches(NumberValue(42)), isFalse);
      });

      test('custom always matches', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.custom,
          format: const CellFormat(),
        );
        expect(rule.matches(EmptyValue()), isTrue);
        expect(rule.matches(NumberValue(42)), isTrue);
        expect(rule.matches(TextValue('anything')), isTrue);
      });
    });

    group('serialization', () {
      test('toJson and fromJson roundtrip', () {
        final rule = ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThan,
          threshold: 100,
          format: CellFormat(backgroundColor: const Color(0xFFFF0000)),
          priority: 5,
          stopIfTrue: true,
        );
        final json = rule.toJson();
        final restored = ConditionalFormatRule.fromJson(json);
        expect(restored.condition, FormatCondition.greaterThan);
        expect(restored.threshold, 100);
        expect(restored.priority, 5);
        expect(restored.stopIfTrue, isTrue);
      });
    });
  });

  group('ConditionalFormatEngine', () {
    late ConditionalFormatEngine engine;

    setUp(() {
      engine = ConditionalFormatEngine();
    });

    test('no rules returns null format', () {
      final result = engine.getEffectiveFormat(
        CellAddress(0, 0),
        NumberValue(42),
      );
      expect(result, isNull);
    });

    test('matching rule returns its format', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThan,
          threshold: 10,
          format: CellFormat(backgroundColor: const Color(0xFF00FF00)),
        ),
      );
      final result = engine.getEffectiveFormat(
        CellAddress(0, 0),
        NumberValue(20),
      );
      expect(result, isNotNull);
      expect(result!.backgroundColor, const Color(0xFF00FF00));
    });

    test('non-matching rule returns null', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThan,
          threshold: 100,
          format: CellFormat(backgroundColor: const Color(0xFF00FF00)),
        ),
      );
      final result = engine.getEffectiveFormat(
        CellAddress(0, 0),
        NumberValue(5),
      );
      expect(result, isNull);
    });

    test('higher priority rule overrides lower', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThan,
          threshold: 0,
          format: CellFormat(backgroundColor: const Color(0xFFFF0000)),
          priority: 10,
        ),
      );
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThan,
          threshold: 0,
          format: CellFormat(backgroundColor: const Color(0xFF00FF00)),
          priority: 1,
        ),
      );
      final result = engine.getEffectiveFormat(
        CellAddress(0, 0),
        NumberValue(42),
      );
      expect(result, isNotNull);
      expect(result!.backgroundColor, const Color(0xFF00FF00));
    });

    test('cell outside range is not affected', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: CellRange(CellAddress(0, 0), CellAddress(2, 2)),
          condition: FormatCondition.greaterThan,
          threshold: 0,
          format: CellFormat(backgroundColor: const Color(0xFF00FF00)),
        ),
      );
      final result = engine.getEffectiveFormat(
        CellAddress(5, 5),
        NumberValue(42),
      );
      expect(result, isNull);
    });

    test('removeRule works', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.greaterThan,
        threshold: 0,
        format: const CellFormat(),
      );
      engine.addRule(rule);
      expect(engine.rules.length, 1);
      engine.removeRule(rule);
      expect(engine.rules.length, 0);
    });

    test('clearRules works', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThan,
          threshold: 0,
          format: const CellFormat(),
        ),
      );
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.lessThan,
          threshold: 100,
          format: const CellFormat(),
        ),
      );
      expect(engine.rules.length, 2);
      engine.clearRules();
      expect(engine.rules.length, 0);
    });

    test('getMatchingRules returns matched rules', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThan,
          threshold: 10,
          format: const CellFormat(),
        ),
      );
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.lessThan,
          threshold: 100,
          format: const CellFormat(),
        ),
      );
      final matches = engine.getMatchingRules(
        CellAddress(0, 0),
        NumberValue(50),
      );
      expect(matches.length, 2);
    });

    test('toJson and loadFromJson roundtrip', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThan,
          threshold: 42,
          format: const CellFormat(),
          priority: 1,
        ),
      );
      final json = engine.toJson();
      final restored = ConditionalFormatEngine();
      restored.loadFromJson(json);
      expect(restored.rules.length, 1);
      expect(restored.rules[0].threshold, 42);
    });
  });
}
