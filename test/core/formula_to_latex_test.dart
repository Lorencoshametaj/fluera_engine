import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/tabular/cell_address.dart';
import 'package:fluera_engine/src/core/tabular/cell_value.dart';
import 'package:fluera_engine/src/core/tabular/formula_to_latex.dart';
import 'package:fluera_engine/src/core/tabular/formula_ast.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_evaluator.dart';
import 'package:fluera_engine/src/core/tabular/spreadsheet_model.dart';

void main() {
  group('FormulaToLatex — AST translation', () {
    late FormulaToLatex translator;

    setUp(() => translator = FormulaToLatex());

    test('number literal', () {
      expect(translator.translate(const NumberLiteral(42)), '42');
      expect(translator.translate(const NumberLiteral(3.14)), '3.14');
    });

    test('string literal', () {
      expect(
        translator.translate(const StringLiteral('hello')),
        '\\text{hello}',
      );
    });

    test('bool literal', () {
      expect(translator.translate(const BoolLiteral(true)), '\\text{TRUE}');
      expect(translator.translate(const BoolLiteral(false)), '\\text{FALSE}');
    });

    test('cell reference → symbolic', () {
      final ref = CellRef(CellAddress(0, 0)); // A1
      expect(translator.translate(ref), 'a_{1}');
    });

    test('cell reference → column letters', () {
      final ref = CellRef(CellAddress(2, 4)); // C5
      expect(translator.translate(ref), 'c_{5}');
    });

    test('addition', () {
      final ast = BinaryOp(
        left: CellRef(CellAddress(0, 0)),
        right: CellRef(CellAddress(1, 0)),
        op: '+',
      );
      expect(translator.translate(ast), 'a_{1} + b_{1}');
    });

    test('division → frac', () {
      final ast = BinaryOp(
        left: CellRef(CellAddress(0, 0)),
        right: CellRef(CellAddress(1, 0)),
        op: '/',
      );
      expect(translator.translate(ast), '\\frac{a_{1}}{b_{1}}');
    });

    test('multiplication → cdot', () {
      final ast = BinaryOp(
        left: const NumberLiteral(3),
        right: CellRef(CellAddress(0, 0)),
        op: '*',
      );
      expect(translator.translate(ast), '3 \\cdot a_{1}');
    });

    test('power → superscript', () {
      final ast = BinaryOp(
        left: CellRef(CellAddress(0, 0)),
        right: const NumberLiteral(2),
        op: '^',
      );
      expect(translator.translate(ast), '{a_{1}}^{2}');
    });

    test('comparison operators', () {
      expect(
        translator.translate(
          BinaryOp(
            left: CellRef(CellAddress(0, 0)),
            right: const NumberLiteral(0),
            op: '>=',
          ),
        ),
        'a_{1} \\geq 0',
      );
      expect(
        translator.translate(
          BinaryOp(
            left: CellRef(CellAddress(0, 0)),
            right: const NumberLiteral(0),
            op: '<=',
          ),
        ),
        'a_{1} \\leq 0',
      );
      expect(
        translator.translate(
          BinaryOp(
            left: CellRef(CellAddress(0, 0)),
            right: const NumberLiteral(0),
            op: '<>',
          ),
        ),
        'a_{1} \\neq 0',
      );
    });

    test('negation', () {
      final ast = UnaryOp(operand: CellRef(CellAddress(0, 0)), op: '-');
      expect(translator.translate(ast), '-a_{1}');
    });

    test('SUM with vertical range', () {
      final ast = FunctionCall('SUM', [
        RangeRef(CellRange(CellAddress(0, 0), CellAddress(0, 4))),
      ]);
      expect(translator.translate(ast), '\\sum_{i=1}^{5} a_{i}');
    });

    test('AVERAGE with vertical range', () {
      final ast = FunctionCall('AVERAGE', [
        RangeRef(CellRange(CellAddress(0, 0), CellAddress(0, 4))),
      ]);
      expect(translator.translate(ast), '\\frac{1}{5}\\sum_{i=1}^{5} a_{i}');
    });

    test('SQRT', () {
      final ast = FunctionCall('SQRT', [CellRef(CellAddress(0, 0))]);
      expect(translator.translate(ast), '\\sqrt{a_{1}}');
    });

    test('ABS', () {
      final ast = FunctionCall('ABS', [CellRef(CellAddress(0, 0))]);
      expect(translator.translate(ast), '\\left|a_{1}\\right|');
    });

    test('MIN and MAX', () {
      final args = [CellRef(CellAddress(0, 0)), CellRef(CellAddress(1, 0))];
      expect(
        translator.translate(FunctionCall('MIN', args)),
        '\\min\\left(a_{1}, b_{1}\\right)',
      );
      expect(
        translator.translate(FunctionCall('MAX', args)),
        '\\max\\left(a_{1}, b_{1}\\right)',
      );
    });

    test('COUNT with range', () {
      final ast = FunctionCall('COUNT', [
        RangeRef(CellRange(CellAddress(0, 0), CellAddress(0, 4))),
      ]);
      expect(translator.translate(ast), '5'); // 5 cells
    });

    test('LOG', () {
      final ast = FunctionCall('LOG', [CellRef(CellAddress(0, 0))]);
      expect(translator.translate(ast), '\\log\\left(a_{1}\\right)');
    });

    test('LOG with base', () {
      final ast = FunctionCall('LOG', [
        CellRef(CellAddress(0, 0)),
        const NumberLiteral(10),
      ]);
      expect(translator.translate(ast), '\\log_{10}\\left(a_{1}\\right)');
    });

    test('LN', () {
      final ast = FunctionCall('LN', [CellRef(CellAddress(0, 0))]);
      expect(translator.translate(ast), '\\ln\\left(a_{1}\\right)');
    });

    test('trig functions', () {
      expect(
        translator.translate(FunctionCall('SIN', [CellRef(CellAddress(0, 0))])),
        '\\sin\\left(a_{1}\\right)',
      );
      expect(
        translator.translate(FunctionCall('COS', [CellRef(CellAddress(0, 0))])),
        '\\cos\\left(a_{1}\\right)',
      );
    });

    test('PI constant', () {
      expect(translator.translate(const FunctionCall('PI', [])), '\\pi');
    });

    test('EXP', () {
      final ast = FunctionCall('EXP', [CellRef(CellAddress(0, 0))]);
      expect(translator.translate(ast), 'e^{a_{1}}');
    });

    test('POWER', () {
      final ast = FunctionCall('POWER', [
        CellRef(CellAddress(0, 0)),
        const NumberLiteral(3),
      ]);
      expect(translator.translate(ast), '{a_{1}}^{3}');
    });

    test('IF → piecewise', () {
      final ast = FunctionCall('IF', [
        BinaryOp(
          left: CellRef(CellAddress(0, 0)),
          right: const NumberLiteral(0),
          op: '>',
        ),
        const NumberLiteral(1),
        const NumberLiteral(0),
      ]);
      final result = translator.translate(ast);
      expect(result, contains('\\begin{cases}'));
      expect(result, contains('\\end{cases}'));
    });

    test('unknown function → operatorname fallback', () {
      final ast = FunctionCall('CUSTOM', [CellRef(CellAddress(0, 0))]);
      expect(
        translator.translate(ast),
        '\\operatorname{custom}\\left(a_{1}\\right)',
      );
    });
  });

  group('FormulaToLatex — evaluated mode', () {
    test('substitutes cell values when evaluator provided', () {
      final model = SpreadsheetModel();
      final evaluator = SpreadsheetEvaluator(model);
      evaluator.setCellAndEvaluate(CellAddress(0, 0), const NumberValue(42));

      final translator = FormulaToLatex(evaluator);
      final ref = CellRef(CellAddress(0, 0));
      expect(
        translator.translate(ref, mode: FormulaTranslateMode.evaluated),
        '42',
      );

      evaluator.dispose();
    });
  });

  group('FormulaToLatex — translateFormula', () {
    test('strips leading = sign', () {
      final translator = FormulaToLatex();
      final result = translator.translateFormula('=1+2');
      expect(result, '1 + 2');
    });

    test('handles empty formula', () {
      expect(FormulaToLatex().translateFormula(''), '');
    });

    test('complex expression: A1/B1 + SQRT(C1)', () {
      final translator = FormulaToLatex();
      final result = translator.translateFormula('=A1/B1+SQRT(C1)');
      expect(result, contains('\\frac'));
      expect(result, contains('\\sqrt'));
    });
  });
}
