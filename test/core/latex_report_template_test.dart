import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_node.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/latex_report_template.dart';
import 'package:fluera_engine/src/core/tabular/merge_region_manager.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_evaluator.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_model.dart';

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
  // Simple value substitution
  // ===========================================================================

  group('LatexReportTemplate - value substitution', () {
    test('substitutes single cell', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(42),
      );
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'x = {A1}'), 'x = 42');
    });

    test('substitutes formatted cell', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1234.5),
      );
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'Total: {A1:#,##0.00}'), 'Total: 1,234.50');
    });

    test('substitutes range', () {
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
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'Values: {A1:A3}'), 'Values: 1, 2, 3');
    });

    test('substitutes aggregate SUM', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(20),
      );
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'Sum: {SUM(A1:A2)}'), 'Sum: 30');
    });

    test('unrecognized placeholder returned with braces', () {
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'{not_a_cell}'), '{not_a_cell}');
    });
  });

  // ===========================================================================
  // Conditional sections
  // ===========================================================================

  group('LatexReportTemplate - conditionals', () {
    test('IF true branch renders', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(100),
      );
      final tpl = LatexReportTemplate(evaluator);
      final result = tpl.render(r'{IF(A1>0)}Profit{ENDIF}');
      expect(result, 'Profit');
    });

    test('IF false branch does not render', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(-5),
      );
      final tpl = LatexReportTemplate(evaluator);
      final result = tpl.render(r'{IF(A1>0)}Profit{ENDIF}');
      expect(result, '');
    });

    test('IF/ELSE renders correct branch', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(-10),
      );
      final tpl = LatexReportTemplate(evaluator);
      final result = tpl.render(r'{IF(A1>0)}Profit{ELSE}Loss{ENDIF}');
      expect(result, 'Loss');
    });

    test('equality condition', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(42),
      );
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'{IF(A1=42)}match{ELSE}no{ENDIF}'), 'match');
    });

    test('inequality condition', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(10),
      );
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'{IF(A1!=5)}different{ENDIF}'), 'different');
    });

    test('greater-equal condition', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(100),
      );
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'{IF(A1>=100)}ok{ENDIF}'), 'ok');
    });

    test('less-equal condition', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(5),
      );
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'{IF(A1<=5)}ok{ENDIF}'), 'ok');
    });

    test('string comparison with =', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('hello'),
      );
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'{IF(A1=hello)}yes{ELSE}no{ENDIF}'), 'yes');
    });
  });

  // ===========================================================================
  // FOR loops
  // ===========================================================================

  group('LatexReportTemplate - FOR loops', () {
    test('iterates over rows', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('Alice'),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const NumberValue(30),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const TextValue('Bob'),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 1),
        const NumberValue(25),
      );

      final tpl = LatexReportTemplate(evaluator);
      final result = tpl.render(r'{FOR(r in A1:B2)}{r.A}={r.B};{ENDFOR}');

      expect(result, 'Alice=30;Bob=25;');
    });

    test('FOR with single row', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const NumberValue(2),
      );

      final tpl = LatexReportTemplate(evaluator);
      final result = tpl.render(r'{FOR(x in A1:B1)}{x.A},{x.B};{ENDFOR}');
      expect(result, '1,2;');
    });
  });

  // ===========================================================================
  // TABLE auto-generation
  // ===========================================================================

  group('LatexReportTemplate - TABLE directive', () {
    test('generates basic tabular from range', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('Name'),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const TextValue('Age'),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const TextValue('Alice'),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 1),
        const NumberValue(30),
      );

      final tpl = LatexReportTemplate(evaluator);
      final result = tpl.render(r'{TABLE(A1:B2)}');

      expect(result, contains(r'\begin{tabular}'));
      expect(result, contains(r'\end{tabular}'));
      expect(result, contains(r'\hline'));
      expect(result, contains('Name & Age'));
      expect(result, contains('Alice & 30'));
    });

    test('TABLE with headers=true bolds first row', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('Header'),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const TextValue('Data'),
      );

      final tpl = LatexReportTemplate(evaluator);
      final result = tpl.render(r'{TABLE(A1:A2, headers=true)}');

      expect(result, contains(r'\textbf{Header}'));
      expect(result, isNot(contains(r'\textbf{Data}')));
    });

    test('TABLE with custom alignment', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const NumberValue(2),
      );

      final tpl = LatexReportTemplate(evaluator);
      final result = tpl.render(r'{TABLE(A1:B1, align=lr)}');

      expect(result, contains(r'\begin{tabular}{|l|r|}'));
    });

    test('TABLE with merge regions generates multicolumn', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const TextValue('Merged Header'),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(1),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 1),
        const NumberValue(2),
      );

      final mergeManager = MergeRegionManager();
      mergeManager.addRegion(
        CellRange(const CellAddress(0, 0), const CellAddress(1, 0)),
      );

      final tpl = LatexReportTemplate(evaluator, mergeManager: mergeManager);
      final result = tpl.render(r'{TABLE(A1:B2)}');

      expect(result, contains(r'\multicolumn{2}{|c|}{Merged Header}'));
    });
  });

  // ===========================================================================
  // Complex templates
  // ===========================================================================

  group('LatexReportTemplate - complex templates', () {
    test('report with conditionals and values', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1500),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        const NumberValue(0.15),
      );

      final tpl = LatexReportTemplate(evaluator);
      final result = tpl.render(
        r'Revenue: {A1:#,##0}. {IF(B1>0)}Growth: {B1:0%}{ENDIF}',
      );

      expect(result, 'Revenue: 1,500. Growth: 15%');
    });

    test('empty template returns empty string', () {
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(''), '');
    });

    test('template with no placeholders returned as-is', () {
      final tpl = LatexReportTemplate(evaluator);
      final input = r'\frac{a}{b} + \sqrt{c}';
      expect(tpl.render(input), input);
    });
  });

  // ===========================================================================
  // Edge cases
  // ===========================================================================

  group('LatexReportTemplate - edge cases', () {
    test('error value cell', () {
      // Set a formula that references a non-existent function to create error.
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(0),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(1, 0),
        FormulaValue('A1/0'),
      );
      final tpl = LatexReportTemplate(evaluator);
      final result = tpl.render(r'{B1}');
      // Should contain some value (error or INF).
      expect(result, isNotEmpty);
    });

    test('AVG on empty range returns #N/A', () {
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'{AVG(D1:D5)}'), '#N/A');
    });

    test('COUNT on empty range returns 0', () {
      final tpl = LatexReportTemplate(evaluator);
      expect(tpl.render(r'{COUNT(D1:D5)}'), '0');
    });

    test('custom range separator', () {
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 0),
        const NumberValue(1),
      );
      evaluator.setCellAndEvaluate(
        const CellAddress(0, 1),
        const NumberValue(2),
      );
      final tpl = LatexReportTemplate(evaluator, rangeSeparator: ' | ');
      expect(tpl.render(r'{A1:A2}'), '1 | 2');
    });
  });
}
