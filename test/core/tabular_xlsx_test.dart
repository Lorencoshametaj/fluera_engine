import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_node.dart';
import 'package:fluera_engine/src/core/tabular/cell_validation.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/conditional_format.dart';
import 'package:fluera_engine/src/core/tabular/merge_region_manager.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_evaluator.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_model.dart';
import 'package:fluera_engine/src/core/tabular/tabular_xlsx.dart';

void main() {
  // ===========================================================================
  // Export
  // ===========================================================================

  group('TabularXlsx.exportBytes', () {
    test('exports empty model without error', () {
      final model = SpreadsheetModel();
      final bytes = TabularXlsx.exportBytes(model);
      expect(bytes, isNotEmpty);
      // ZIP signature: PK\x03\x04
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
    });

    test('exports model with numeric cells', () {
      final model = SpreadsheetModel();
      model.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(42)),
      );
      model.setCell(
        const CellAddress(1, 0),
        CellNode(value: const NumberValue(3.14)),
      );
      final bytes = TabularXlsx.exportBytes(model);
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(100));
    });

    test('exports model with text cells', () {
      final model = SpreadsheetModel();
      model.setCell(
        const CellAddress(0, 0),
        CellNode(value: const TextValue('Hello')),
      );
      model.setCell(
        const CellAddress(1, 0),
        CellNode(value: const TextValue('World')),
      );
      final bytes = TabularXlsx.exportBytes(model);
      expect(bytes, isNotEmpty);
    });

    test('exports model with formulas', () {
      final model = SpreadsheetModel();
      final evaluator = SpreadsheetEvaluator(model);
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 * 2'),
      );
      final bytes = TabularXlsx.exportBytes(model);
      expect(bytes, isNotEmpty);
      evaluator.dispose();
    });

    test('exports model with boolean cells', () {
      final model = SpreadsheetModel();
      model.setCell(
        const CellAddress(0, 0),
        CellNode(value: const BoolValue(true)),
      );
      final bytes = TabularXlsx.exportBytes(model);
      expect(bytes, isNotEmpty);
    });

    test('exports with merge regions', () {
      final model = SpreadsheetModel();
      model.setCell(
        const CellAddress(0, 0),
        CellNode(value: const TextValue('Merged')),
      );
      final mergeManager = MergeRegionManager();
      mergeManager.addRegion(
        CellRange(const CellAddress(0, 0), const CellAddress(2, 0)),
      );
      final bytes = TabularXlsx.exportBytes(model, mergeManager: mergeManager);
      expect(bytes, isNotEmpty);
    });

    test('exports custom sheet name', () {
      final model = SpreadsheetModel();
      model.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(1)),
      );
      final bytes = TabularXlsx.exportBytes(model, sheetName: 'Data');
      expect(bytes, isNotEmpty);
    });
  });

  // ===========================================================================
  // Roundtrip
  // ===========================================================================

  group('TabularXlsx roundtrip', () {
    test('numeric cells survive roundtrip', () {
      final original = SpreadsheetModel();
      original.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(42)),
      );
      original.setCell(
        const CellAddress(1, 0),
        CellNode(value: const NumberValue(3.14)),
      );
      original.setCell(
        const CellAddress(0, 1),
        CellNode(value: const NumberValue(-7)),
      );

      final bytes = TabularXlsx.exportBytes(original);
      final restored = TabularXlsx.importBytes(Uint8List.fromList(bytes));

      expect(
        restored.getCell(const CellAddress(0, 0))?.value,
        const NumberValue(42),
      );
      expect(
        restored.getCell(const CellAddress(1, 0))?.value,
        const NumberValue(3.14),
      );
      expect(
        restored.getCell(const CellAddress(0, 1))?.value,
        const NumberValue(-7),
      );
    });

    test('text cells survive roundtrip via shared strings', () {
      final original = SpreadsheetModel();
      original.setCell(
        const CellAddress(0, 0),
        CellNode(value: const TextValue('Hello')),
      );
      original.setCell(
        const CellAddress(1, 0),
        CellNode(value: const TextValue('World')),
      );

      final bytes = TabularXlsx.exportBytes(original);
      final restored = TabularXlsx.importBytes(Uint8List.fromList(bytes));

      expect(
        restored.getCell(const CellAddress(0, 0))?.value,
        const TextValue('Hello'),
      );
      expect(
        restored.getCell(const CellAddress(1, 0))?.value,
        const TextValue('World'),
      );
    });

    test('boolean cells survive roundtrip', () {
      final original = SpreadsheetModel();
      original.setCell(
        const CellAddress(0, 0),
        CellNode(value: const BoolValue(true)),
      );
      original.setCell(
        const CellAddress(1, 0),
        CellNode(value: const BoolValue(false)),
      );

      final bytes = TabularXlsx.exportBytes(original);
      final restored = TabularXlsx.importBytes(Uint8List.fromList(bytes));

      expect(
        restored.getCell(const CellAddress(0, 0))?.value,
        const BoolValue(true),
      );
      expect(
        restored.getCell(const CellAddress(1, 0))?.value,
        const BoolValue(false),
      );
    });

    test('formula cells survive roundtrip', () {
      final original = SpreadsheetModel();
      final evaluator = SpreadsheetEvaluator(original);
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const FormulaValue('A1 * 2'),
      );

      final bytes = TabularXlsx.exportBytes(original);
      final restored = TabularXlsx.importBytes(Uint8List.fromList(bytes));

      // Formula cell should be restored.
      final cell = restored.getCell(const CellAddress(1, 0));
      expect(cell?.value, isA<FormulaValue>());
      expect((cell?.value as FormulaValue).expression, equals('A1 * 2'));

      evaluator.dispose();
    });

    test('merge regions survive roundtrip', () {
      final original = SpreadsheetModel();
      original.setCell(
        const CellAddress(0, 0),
        CellNode(value: const TextValue('Merged')),
      );
      final mergeOut = MergeRegionManager();
      mergeOut.addRegion(
        CellRange(const CellAddress(0, 0), const CellAddress(2, 0)),
      );

      final bytes = TabularXlsx.exportBytes(original, mergeManager: mergeOut);
      final mergeIn = MergeRegionManager();
      TabularXlsx.importBytes(Uint8List.fromList(bytes), mergeManager: mergeIn);

      expect(mergeIn.regionCount, equals(1));
      expect(mergeIn.isMerged(const CellAddress(1, 0)), isTrue);
    });

    test('mixed types roundtrip', () {
      final original = SpreadsheetModel();
      original.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(42)),
      );
      original.setCell(
        const CellAddress(1, 0),
        CellNode(value: const TextValue('hello')),
      );
      original.setCell(
        const CellAddress(2, 0),
        CellNode(value: const BoolValue(true)),
      );

      final bytes = TabularXlsx.exportBytes(original);
      final restored = TabularXlsx.importBytes(Uint8List.fromList(bytes));

      expect(restored.cellCount, equals(3));
    });
  });

  // ===========================================================================
  // Validation & Conditional Format Roundtrip
  // ===========================================================================

  group('TabularXlsx validation roundtrip', () {
    test('validation rules survive roundtrip', () {
      final original = SpreadsheetModel();
      original.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(50)),
      );
      original.setValidation(
        const CellAddress(0, 0),
        const CellValidation(
          type: CellValidationType.integer,
          min: 1,
          max: 100,
          errorTitle: 'Out of range',
          errorMessage: 'Enter 1-100',
        ),
      );

      final bytes = TabularXlsx.exportBytes(original);
      final restored = TabularXlsx.importBytes(Uint8List.fromList(bytes));

      expect(restored.hasValidation(const CellAddress(0, 0)), isTrue);
      final rule = restored.getValidation(const CellAddress(0, 0))!;
      expect(rule.type, CellValidationType.integer);
      expect(rule.min, 1);
      expect(rule.max, 100);
      expect(rule.errorTitle, 'Out of range');
      expect(rule.errorMessage, 'Enter 1-100');
    });

    test('list validation survives roundtrip', () {
      final original = SpreadsheetModel();
      original.setCell(
        const CellAddress(0, 0),
        CellNode(value: const TextValue('Yes')),
      );
      original.setValidation(
        const CellAddress(0, 0),
        const CellValidation(
          type: CellValidationType.list,
          allowedValues: ['Yes', 'No', 'Maybe'],
        ),
      );

      final bytes = TabularXlsx.exportBytes(original);
      final restored = TabularXlsx.importBytes(Uint8List.fromList(bytes));

      expect(restored.hasValidation(const CellAddress(0, 0)), isTrue);
      final rule = restored.getValidation(const CellAddress(0, 0))!;
      expect(rule.type, CellValidationType.list);
      expect(rule.allowedValues, ['Yes', 'No', 'Maybe']);
    });
  });

  group('TabularXlsx conditional formatting roundtrip', () {
    test('conditional format rules survive roundtrip', () {
      final original = SpreadsheetModel();
      original.setCell(
        const CellAddress(0, 0),
        CellNode(value: const NumberValue(-5)),
      );
      original.conditionalFormats.addRule(
        ConditionalFormatRule(
          appliesTo: CellRange(
            const CellAddress(0, 0),
            const CellAddress(0, 9),
          ),
          condition: FormatCondition.lessThan,
          threshold: 0,
          format: CellFormat(textColor: Color(0xFFFF0000), bold: true),
          priority: 1,
        ),
      );

      final bytes = TabularXlsx.exportBytes(original);
      final restored = TabularXlsx.importBytes(Uint8List.fromList(bytes));

      expect(restored.conditionalFormats.ruleCount, 1);
      final rule = restored.conditionalFormats.rules.first;
      expect(rule.condition, FormatCondition.lessThan);
      expect(rule.threshold, 0);
      expect(rule.priority, 1);
      expect(rule.format.bold, true);
      expect(rule.format.textColor, isNotNull);
    });
  });
}
