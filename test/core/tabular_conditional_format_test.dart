import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_node.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/conditional_format.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_model.dart';

void main() {
  late ConditionalFormatEngine engine;

  setUp(() {
    engine = ConditionalFormatEngine();
  });

  // ===========================================================================
  // Condition matching
  // ===========================================================================

  group('ConditionalFormatRule - condition matching', () {
    final range = CellRange(const CellAddress(0, 0), const CellAddress(9, 9));

    test('greaterThan matches correctly', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.greaterThan,
        threshold: 10,
        format: const CellFormat(bold: true),
      );
      expect(rule.matches(const NumberValue(15)), isTrue);
      expect(rule.matches(const NumberValue(10)), isFalse);
      expect(rule.matches(const NumberValue(5)), isFalse);
    });

    test('lessThan matches correctly', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.lessThan,
        threshold: 0,
        format: CellFormat(textColor: const Color(0xFFFF0000)),
      );
      expect(rule.matches(const NumberValue(-5)), isTrue);
      expect(rule.matches(const NumberValue(0)), isFalse);
      expect(rule.matches(const NumberValue(5)), isFalse);
    });

    test('equal matches correctly', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.equal,
        threshold: 42,
        format: const CellFormat(bold: true),
      );
      expect(rule.matches(const NumberValue(42)), isTrue);
      expect(rule.matches(const NumberValue(43)), isFalse);
    });

    test('notEqual matches correctly', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.notEqual,
        threshold: 0,
        format: const CellFormat(italic: true),
      );
      expect(rule.matches(const NumberValue(5)), isTrue);
      expect(rule.matches(const NumberValue(0)), isFalse);
    });

    test('between matches correctly', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.between,
        threshold: 10,
        thresholdMax: 20,
        format: const CellFormat(bold: true),
      );
      expect(rule.matches(const NumberValue(15)), isTrue);
      expect(rule.matches(const NumberValue(10)), isTrue);
      expect(rule.matches(const NumberValue(20)), isTrue);
      expect(rule.matches(const NumberValue(5)), isFalse);
      expect(rule.matches(const NumberValue(25)), isFalse);
    });

    test('notBetween matches correctly', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.notBetween,
        threshold: 10,
        thresholdMax: 20,
        format: const CellFormat(bold: true),
      );
      expect(rule.matches(const NumberValue(5)), isTrue);
      expect(rule.matches(const NumberValue(25)), isTrue);
      expect(rule.matches(const NumberValue(15)), isFalse);
    });

    test('textContains matches correctly', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.textContains,
        threshold: 'error',
        format: CellFormat(textColor: const Color(0xFFFF0000)),
      );
      expect(rule.matches(const TextValue('This is an error')), isTrue);
      expect(rule.matches(const TextValue('All good')), isFalse);
    });

    test('textStartsWith matches correctly', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.textStartsWith,
        threshold: 'WARN',
        format: const CellFormat(bold: true),
      );
      expect(rule.matches(const TextValue('WARNING: issue')), isTrue);
      expect(rule.matches(const TextValue('No warning here')), isFalse);
    });

    test('isBlank matches empty cells', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.isBlank,
        format: CellFormat(backgroundColor: const Color(0xFFEEEEEE)),
      );
      expect(rule.matches(const EmptyValue()), isTrue);
      expect(rule.matches(const NumberValue(0)), isFalse);
    });

    test('isNotBlank matches non-empty cells', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.isNotBlank,
        format: const CellFormat(bold: true),
      );
      expect(rule.matches(const NumberValue(1)), isTrue);
      expect(rule.matches(const EmptyValue()), isFalse);
    });

    test('isError matches error values', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.isError,
        format: CellFormat(textColor: const Color(0xFFFF0000)),
      );
      expect(rule.matches(const ErrorValue(CellError.divisionByZero)), isTrue);
      expect(rule.matches(const NumberValue(42)), isFalse);
    });

    test('non-numeric value fails numeric conditions', () {
      final rule = ConditionalFormatRule(
        appliesTo: range,
        condition: FormatCondition.greaterThan,
        threshold: 10,
        format: const CellFormat(bold: true),
      );
      expect(rule.matches(const TextValue('hello')), isFalse);
    });
  });

  // ===========================================================================
  // Engine — effective format
  // ===========================================================================

  group('ConditionalFormatEngine - effective format', () {
    final range = CellRange(const CellAddress(0, 0), const CellAddress(9, 9));

    test('returns null when no rules match', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.greaterThan,
          threshold: 100,
          format: const CellFormat(bold: true),
        ),
      );
      final fmt = engine.getEffectiveFormat(
        const CellAddress(0, 0),
        const NumberValue(50),
      );
      expect(fmt, isNull);
    });

    test('returns format when rule matches', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: CellFormat(textColor: const Color(0xFFFF0000), bold: true),
        ),
      );
      final fmt = engine.getEffectiveFormat(
        const CellAddress(0, 0),
        const NumberValue(-5),
      );
      expect(fmt, isNotNull);
      expect(fmt!.textColor, const Color(0xFFFF0000));
      expect(fmt.bold, true);
    });

    test('cell outside range does not match', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: CellRange(
            const CellAddress(0, 0),
            const CellAddress(0, 0),
          ),
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: const CellFormat(bold: true),
        ),
      );
      final fmt = engine.getEffectiveFormat(
        const CellAddress(5, 5),
        const NumberValue(-5),
      );
      expect(fmt, isNull);
    });
  });

  // ===========================================================================
  // Priority ordering
  // ===========================================================================

  group('ConditionalFormatEngine - priority', () {
    final range = CellRange(const CellAddress(0, 0), const CellAddress(9, 9));

    test('higher priority (lower number) format wins', () {
      // Priority 1: red text
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: CellFormat(textColor: const Color(0xFFFF0000)),
          priority: 1,
        ),
      );
      // Priority 2: blue text (lower priority)
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: CellFormat(textColor: const Color(0xFF0000FF)),
          priority: 2,
        ),
      );

      final fmt = engine.getEffectiveFormat(
        const CellAddress(0, 0),
        const NumberValue(-5),
      );
      // Priority 1 (red) should win.
      expect(fmt!.textColor, const Color(0xFFFF0000));
    });

    test('formats from multiple rules are merged', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: CellFormat(textColor: const Color(0xFFFF0000)),
          priority: 1,
        ),
      );
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: const CellFormat(bold: true),
          priority: 2,
        ),
      );

      final fmt = engine.getEffectiveFormat(
        const CellAddress(0, 0),
        const NumberValue(-5),
      );
      expect(fmt!.textColor, const Color(0xFFFF0000));
      expect(fmt.bold, true);
    });
  });

  // ===========================================================================
  // stopIfTrue
  // ===========================================================================

  group('ConditionalFormatEngine - stopIfTrue', () {
    final range = CellRange(const CellAddress(0, 0), const CellAddress(9, 9));

    test('stopIfTrue prevents subsequent rules from applying', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: CellFormat(textColor: const Color(0xFFFF0000)),
          priority: 1,
          stopIfTrue: true,
        ),
      );
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: range,
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: const CellFormat(bold: true),
          priority: 2,
        ),
      );

      final fmt = engine.getEffectiveFormat(
        const CellAddress(0, 0),
        const NumberValue(-5),
      );
      expect(fmt!.textColor, const Color(0xFFFF0000));
      // Bold should NOT be applied because first rule has stopIfTrue.
      expect(fmt.bold, isNull);
    });
  });

  // ===========================================================================
  // Rule management
  // ===========================================================================

  group('ConditionalFormatEngine - rule management', () {
    test('rules are sorted by priority', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: CellRange(
            const CellAddress(0, 0),
            const CellAddress(0, 0),
          ),
          condition: FormatCondition.greaterThan,
          threshold: 0,
          format: const CellFormat(bold: true),
          priority: 5,
        ),
      );
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: CellRange(
            const CellAddress(0, 0),
            const CellAddress(0, 0),
          ),
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: const CellFormat(italic: true),
          priority: 1,
        ),
      );

      expect(engine.rules[0].priority, 1);
      expect(engine.rules[1].priority, 5);
    });

    test('removeRule works', () {
      final rule = ConditionalFormatRule(
        appliesTo: CellRange(const CellAddress(0, 0), const CellAddress(0, 0)),
        condition: FormatCondition.greaterThan,
        threshold: 0,
        format: const CellFormat(bold: true),
      );
      engine.addRule(rule);
      expect(engine.ruleCount, 1);
      engine.removeRule(rule);
      expect(engine.ruleCount, 0);
    });

    test('clearRules removes all', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: CellRange(
            const CellAddress(0, 0),
            const CellAddress(0, 0),
          ),
          condition: FormatCondition.greaterThan,
          threshold: 0,
          format: const CellFormat(bold: true),
        ),
      );
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: CellRange(
            const CellAddress(0, 0),
            const CellAddress(0, 0),
          ),
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: const CellFormat(italic: true),
        ),
      );
      engine.clearRules();
      expect(engine.ruleCount, 0);
    });
  });

  // ===========================================================================
  // Serialization
  // ===========================================================================

  group('ConditionalFormatEngine - serialization', () {
    test('toJson/loadFromJson roundtrip', () {
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: CellRange(
            const CellAddress(0, 0),
            const CellAddress(9, 9),
          ),
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: CellFormat(textColor: const Color(0xFFFF0000), bold: true),
          priority: 1,
          stopIfTrue: true,
        ),
      );
      engine.addRule(
        ConditionalFormatRule(
          appliesTo: CellRange(
            const CellAddress(0, 0),
            const CellAddress(9, 9),
          ),
          condition: FormatCondition.greaterThan,
          threshold: 100,
          format: CellFormat(backgroundColor: const Color(0xFF00FF00)),
          priority: 2,
        ),
      );

      final json = engine.toJson();
      final restored = ConditionalFormatEngine();
      restored.loadFromJson(json);

      expect(restored.ruleCount, 2);
      expect(restored.rules[0].priority, 1);
      expect(restored.rules[0].condition, FormatCondition.lessThan);
      expect(restored.rules[0].stopIfTrue, true);
      expect(restored.rules[1].priority, 2);
      expect(restored.rules[1].condition, FormatCondition.greaterThan);
    });
  });

  // ===========================================================================
  // SpreadsheetModel integration
  // ===========================================================================

  group('SpreadsheetModel - conditional format integration', () {
    test('conditional formats survive toJson/fromJson', () {
      final model = SpreadsheetModel();
      model.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(42)),
      );
      model.conditionalFormats.addRule(
        ConditionalFormatRule(
          appliesTo: CellRange(
            const CellAddress(0, 0),
            const CellAddress(9, 9),
          ),
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: const CellFormat(bold: true),
          priority: 1,
        ),
      );

      final json = model.toJson();
      final restored = SpreadsheetModel.fromJson(json);

      expect(restored.conditionalFormats.ruleCount, 1);
      expect(
        restored.conditionalFormats.rules[0].condition,
        FormatCondition.lessThan,
      );
    });

    test('conditional formats survive clone', () {
      final model = SpreadsheetModel();
      model.conditionalFormats.addRule(
        ConditionalFormatRule(
          appliesTo: CellRange(
            const CellAddress(0, 0),
            const CellAddress(0, 0),
          ),
          condition: FormatCondition.greaterThan,
          threshold: 10,
          format: const CellFormat(italic: true),
        ),
      );

      final clone = model.clone();
      expect(clone.conditionalFormats.ruleCount, 1);
    });
  });
}
