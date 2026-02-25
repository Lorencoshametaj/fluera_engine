import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/tabular/formula_token.dart';

void main() {
  // ===========================================================================
  // Basic arithmetic
  // ===========================================================================

  group('FormulaTokenizer - arithmetic', () {
    test('tokenizes addition', () {
      final tokens = FormulaTokenizer.tokenize('1 + 2');
      expect(tokens.where((t) => t.type == TokenType.number).length, 2);
      expect(tokens.where((t) => t.type == TokenType.plus).length, 1);
    });

    test('tokenizes subtraction', () {
      final tokens = FormulaTokenizer.tokenize('10 - 5');
      expect(tokens.where((t) => t.type == TokenType.minus).length, 1);
    });

    test('tokenizes multiplication and division', () {
      final tokens = FormulaTokenizer.tokenize('3 * 4 / 2');
      expect(tokens.where((t) => t.type == TokenType.multiply).length, 1);
      expect(tokens.where((t) => t.type == TokenType.divide).length, 1);
    });

    test('tokenizes power', () {
      final tokens = FormulaTokenizer.tokenize('2 ^ 10');
      expect(tokens.where((t) => t.type == TokenType.power).length, 1);
    });
  });

  // ===========================================================================
  // Cell references
  // ===========================================================================

  group('FormulaTokenizer - cell references', () {
    test('simple cell ref A1', () {
      final tokens = FormulaTokenizer.tokenize('A1');
      expect(
        tokens.any((t) => t.type == TokenType.cellRef && t.lexeme == 'A1'),
        isTrue,
      );
    });

    test('absolute cell ref', () {
      final tokens = FormulaTokenizer.tokenize('\$B\$3');
      expect(tokens.any((t) => t.type == TokenType.cellRef), isTrue);
    });

    test('range A1:B10', () {
      final tokens = FormulaTokenizer.tokenize('A1:B10');
      expect(tokens.where((t) => t.type == TokenType.cellRef).length, 2);
      expect(tokens.where((t) => t.type == TokenType.rangeOp).length, 1);
    });
  });

  // ===========================================================================
  // Functions
  // ===========================================================================

  group('FormulaTokenizer - functions', () {
    test('SUM function', () {
      final tokens = FormulaTokenizer.tokenize('SUM(A1:A10)');
      expect(
        tokens.any((t) => t.type == TokenType.identifier && t.lexeme == 'SUM'),
        isTrue,
      );
      expect(tokens.any((t) => t.type == TokenType.lparen), isTrue);
      expect(tokens.any((t) => t.type == TokenType.rparen), isTrue);
    });

    test('nested functions', () {
      final tokens = FormulaTokenizer.tokenize('IF(A1>0, SUM(B1:B5), 0)');
      final ids = tokens.where((t) => t.type == TokenType.identifier).toList();
      expect(ids.length, 2); // IF, SUM
    });
  });

  // ===========================================================================
  // String literals
  // ===========================================================================

  group('FormulaTokenizer - strings', () {
    test('string literal', () {
      final tokens = FormulaTokenizer.tokenize('"hello"');
      expect(tokens.any((t) => t.type == TokenType.string), isTrue);
    });
  });

  // ===========================================================================
  // Boolean literals
  // ===========================================================================

  group('FormulaTokenizer - booleans', () {
    test('TRUE literal', () {
      final tokens = FormulaTokenizer.tokenize('TRUE');
      expect(
        tokens.any((t) => t.type == TokenType.boolean && t.lexeme == 'TRUE'),
        isTrue,
      );
    });
  });

  // ===========================================================================
  // Comparison operators
  // ===========================================================================

  group('FormulaTokenizer - comparisons', () {
    test('less than', () {
      final tokens = FormulaTokenizer.tokenize('A1 < 10');
      expect(tokens.any((t) => t.type == TokenType.lt), isTrue);
    });

    test('not equals', () {
      final tokens = FormulaTokenizer.tokenize('A1 <> B1');
      expect(tokens.any((t) => t.type == TokenType.notEquals), isTrue);
    });
  });

  // ===========================================================================
  // EOF
  // ===========================================================================

  group('FormulaTokenizer - eof', () {
    test('last token is eof', () {
      final tokens = FormulaTokenizer.tokenize('1');
      expect(tokens.last.type, TokenType.eof);
    });

    test('empty string produces eof', () {
      final tokens = FormulaTokenizer.tokenize('');
      expect(tokens.length, 1);
      expect(tokens.first.type, TokenType.eof);
    });
  });

  // ===========================================================================
  // FormulaToken
  // ===========================================================================

  group('FormulaToken', () {
    test('toString is readable', () {
      final tokens = FormulaTokenizer.tokenize('42');
      final numToken = tokens.firstWhere((t) => t.type == TokenType.number);
      expect(numToken.toString(), isNotEmpty);
    });

    test('numericValue is set for numbers', () {
      final tokens = FormulaTokenizer.tokenize('3.14');
      final numToken = tokens.firstWhere((t) => t.type == TokenType.number);
      expect(numToken.numericValue, closeTo(3.14, 0.01));
    });
  });
}
