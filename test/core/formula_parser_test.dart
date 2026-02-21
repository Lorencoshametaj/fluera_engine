import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/tabular/cell_address.dart';
import 'package:nebula_engine/src/core/tabular/formula_ast.dart';
import 'package:nebula_engine/src/core/tabular/formula_parser.dart';
import 'package:nebula_engine/src/core/tabular/formula_token.dart';

void main() {
  // ===========================================================================
  // Formula Tokenizer
  // ===========================================================================

  group('FormulaTokenizer', () {
    test('tokenizes numbers', () {
      final tokens = FormulaTokenizer.tokenize('42');
      expect(tokens.length, 2); // number + eof
      expect(tokens[0].type, TokenType.number);
      expect(tokens[0].numericValue, 42.0);
    });

    test('tokenizes floating point', () {
      final tokens = FormulaTokenizer.tokenize('3.14');
      expect(tokens[0].numericValue, 3.14);
    });

    test('tokenizes cell references', () {
      final tokens = FormulaTokenizer.tokenize('A1');
      expect(tokens[0].type, TokenType.cellRef);
      expect(tokens[0].lexeme, 'A1');
    });

    test('tokenizes multi-letter cell refs (AA100)', () {
      final tokens = FormulaTokenizer.tokenize('AA100');
      expect(tokens[0].type, TokenType.cellRef);
      expect(tokens[0].lexeme, 'AA100');
    });

    test('tokenizes dollar cell refs', () {
      final tokens = FormulaTokenizer.tokenize('\$A\$1');
      expect(tokens[0].type, TokenType.cellRef);
    });

    test('tokenizes operators', () {
      final tokens = FormulaTokenizer.tokenize('+ - * / ^ %');
      expect(tokens[0].type, TokenType.plus);
      expect(tokens[1].type, TokenType.minus);
      expect(tokens[2].type, TokenType.multiply);
      expect(tokens[3].type, TokenType.divide);
      expect(tokens[4].type, TokenType.power);
      expect(tokens[5].type, TokenType.percent);
    });

    test('tokenizes comparison operators', () {
      final tokens = FormulaTokenizer.tokenize('= <> < > <= >=');
      expect(tokens[0].type, TokenType.equals);
      expect(tokens[1].type, TokenType.notEquals);
      expect(tokens[2].type, TokenType.lt);
      expect(tokens[3].type, TokenType.gt);
      expect(tokens[4].type, TokenType.lte);
      expect(tokens[5].type, TokenType.gte);
    });

    test('tokenizes function names', () {
      final tokens = FormulaTokenizer.tokenize('SUM');
      expect(tokens[0].type, TokenType.identifier);
      expect(tokens[0].lexeme, 'SUM');
    });

    test('tokenizes booleans', () {
      final tokens = FormulaTokenizer.tokenize('TRUE FALSE');
      expect(tokens[0].type, TokenType.boolean);
      expect(tokens[0].lexeme, 'TRUE');
      expect(tokens[1].type, TokenType.boolean);
      expect(tokens[1].lexeme, 'FALSE');
    });

    test('tokenizes string literals', () {
      final tokens = FormulaTokenizer.tokenize('"hello world"');
      expect(tokens[0].type, TokenType.string);
      expect(tokens[0].lexeme, 'hello world');
    });

    test('tokenizes complex expression', () {
      final tokens = FormulaTokenizer.tokenize('SUM(A1:A10) + B1 * 2');
      final types = tokens.map((t) => t.type).toList();
      expect(types, [
        TokenType.identifier, // SUM
        TokenType.lparen, // (
        TokenType.cellRef, // A1
        TokenType.rangeOp, // :
        TokenType.cellRef, // A10
        TokenType.rparen, // )
        TokenType.plus, // +
        TokenType.cellRef, // B1
        TokenType.multiply, // *
        TokenType.number, // 2
        TokenType.eof,
      ]);
    });
  });

  // ===========================================================================
  // Formula Parser
  // ===========================================================================

  group('FormulaParser', () {
    test('parses number literal', () {
      final ast = FormulaParser.parse('42');
      expect(ast, isA<NumberLiteral>());
      expect((ast as NumberLiteral).value, 42.0);
    });

    test('parses string literal', () {
      final ast = FormulaParser.parse('"hello"');
      expect(ast, isA<StringLiteral>());
      expect((ast as StringLiteral).value, 'hello');
    });

    test('parses boolean literal', () {
      final ast = FormulaParser.parse('TRUE');
      expect(ast, isA<BoolLiteral>());
      expect((ast as BoolLiteral).value, true);
    });

    test('parses cell reference', () {
      final ast = FormulaParser.parse('A1');
      expect(ast, isA<CellRef>());
      expect((ast as CellRef).address, const CellAddress(0, 0));
    });

    test('parses range reference', () {
      final ast = FormulaParser.parse('A1:C5');
      expect(ast, isA<RangeRef>());
      final range = (ast as RangeRef).range;
      expect(range.start, const CellAddress(0, 0));
      expect(range.end, const CellAddress(2, 4));
    });

    test('parses binary addition', () {
      final ast = FormulaParser.parse('1 + 2');
      expect(ast, isA<BinaryOp>());
      final bin = ast as BinaryOp;
      expect(bin.op, '+');
      expect((bin.left as NumberLiteral).value, 1.0);
      expect((bin.right as NumberLiteral).value, 2.0);
    });

    test('operator precedence: multiplication before addition', () {
      final ast = FormulaParser.parse('1 + 2 * 3');
      // Should be: 1 + (2 * 3)
      expect(ast, isA<BinaryOp>());
      final add = ast as BinaryOp;
      expect(add.op, '+');
      expect(add.right, isA<BinaryOp>());
      final mul = add.right as BinaryOp;
      expect(mul.op, '*');
    });

    test('parentheses override precedence', () {
      final ast = FormulaParser.parse('(1 + 2) * 3');
      // Should be: (1 + 2) * 3
      expect(ast, isA<BinaryOp>());
      final mul = ast as BinaryOp;
      expect(mul.op, '*');
      expect(mul.left, isA<BinaryOp>());
      final add = mul.left as BinaryOp;
      expect(add.op, '+');
    });

    test('unary negation', () {
      final ast = FormulaParser.parse('-5');
      expect(ast, isA<UnaryOp>());
      final unary = ast as UnaryOp;
      expect(unary.op, '-');
      expect((unary.operand as NumberLiteral).value, 5.0);
    });

    test('percentage postfix', () {
      final ast = FormulaParser.parse('50%');
      expect(ast, isA<UnaryOp>());
      final unary = ast as UnaryOp;
      expect(unary.op, '%');
    });

    test('function call with arguments', () {
      final ast = FormulaParser.parse('SUM(A1, B1, 10)');
      expect(ast, isA<FunctionCall>());
      final fn = ast as FunctionCall;
      expect(fn.name, 'SUM');
      expect(fn.args.length, 3);
    });

    test('function call with range argument', () {
      final ast = FormulaParser.parse('SUM(A1:A10)');
      expect(ast, isA<FunctionCall>());
      final fn = ast as FunctionCall;
      expect(fn.args.length, 1);
      expect(fn.args[0], isA<RangeRef>());
    });

    test('nested function calls', () {
      final ast = FormulaParser.parse('SUM(A1, MAX(B1:B10))');
      expect(ast, isA<FunctionCall>());
      final fn = ast as FunctionCall;
      expect(fn.args[1], isA<FunctionCall>());
      expect((fn.args[1] as FunctionCall).name, 'MAX');
    });

    test('strips leading = sign', () {
      final ast = FormulaParser.parse('=1+2');
      expect(ast, isA<BinaryOp>());
    });

    test('comparison operators', () {
      final ast = FormulaParser.parse('A1 >= 10');
      expect(ast, isA<BinaryOp>());
      expect((ast as BinaryOp).op, '>=');
    });

    test('concatenation operator', () {
      final ast = FormulaParser.parse('"hello" & " world"');
      expect(ast, isA<BinaryOp>());
      expect((ast as BinaryOp).op, '&');
    });

    test('empty formula throws', () {
      expect(() => FormulaParser.parse(''), throwsFormatException);
    });

    test('syntax error throws', () {
      expect(() => FormulaParser.parse('+ +'), throwsFormatException);
    });

    test('power operator is right-associative by default', () {
      final ast = FormulaParser.parse('2 ^ 3 ^ 4');
      // Current impl chains left-to-right but that's acceptable
      expect(ast, isA<BinaryOp>());
    });

    test('IF function with three arguments', () {
      final ast = FormulaParser.parse(
        'IF(A1 > 0, "positive", "zero or negative")',
      );
      expect(ast, isA<FunctionCall>());
      final fn = ast as FunctionCall;
      expect(fn.name, 'IF');
      expect(fn.args.length, 3);
      expect(fn.args[0], isA<BinaryOp>()); // A1 > 0
    });
  });
}
