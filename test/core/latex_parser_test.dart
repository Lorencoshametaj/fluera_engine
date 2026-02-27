import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/latex/latex_parser.dart';
import 'package:fluera_engine/src/core/latex/latex_ast.dart';

void main() {
  // ===========================================================================
  // Simple Symbols
  // ===========================================================================

  group('LatexParser — symbols', () {
    test('single letter parses to LatexSymbol', () {
      final ast = LatexParser.parse('x');
      expect(ast, isA<LatexSymbol>());
      expect((ast as LatexSymbol).value, 'x');
      expect(ast.italic, true);
    });

    test('single digit parses to LatexSymbol (non-italic)', () {
      final ast = LatexParser.parse('2');
      expect(ast, isA<LatexSymbol>());
      expect((ast as LatexSymbol).value, '2');
      expect(ast.italic, false);
    });

    test('operator parses to LatexSymbol', () {
      final ast = LatexParser.parse('+');
      expect(ast, isA<LatexSymbol>());
      expect((ast as LatexSymbol).value, '+');
    });

    test('empty string parses to empty LatexGroup', () {
      final ast = LatexParser.parse('');
      expect(ast, isA<LatexGroup>());
      expect((ast as LatexGroup).children, isEmpty);
    });
  });

  // ===========================================================================
  // Greek Letters
  // ===========================================================================

  group('LatexParser — Greek letters', () {
    test(r'\alpha parses to α', () {
      final ast = LatexParser.parse(r'\alpha');
      expect(ast, isA<LatexSymbol>());
      expect((ast as LatexSymbol).value, 'α');
    });

    test(r'\Omega parses to Ω', () {
      final ast = LatexParser.parse(r'\Omega');
      expect(ast, isA<LatexSymbol>());
      expect((ast as LatexSymbol).value, 'Ω');
    });

    test(r'\pi parses to π', () {
      final ast = LatexParser.parse(r'\pi');
      expect(ast, isA<LatexSymbol>());
      expect((ast as LatexSymbol).value, 'π');
    });
  });

  // ===========================================================================
  // Fractions
  // ===========================================================================

  group('LatexParser — fractions', () {
    test(r'\frac{a}{b} parses correctly', () {
      final ast = LatexParser.parse(r'\frac{a}{b}');
      expect(ast, isA<LatexFraction>());
      final frac = ast as LatexFraction;
      expect(frac.numerator, isA<LatexSymbol>());
      expect((frac.numerator as LatexSymbol).value, 'a');
      expect(frac.denominator, isA<LatexSymbol>());
      expect((frac.denominator as LatexSymbol).value, 'b');
    });

    test(r'\frac{x+1}{y} parses with group numerator', () {
      final ast = LatexParser.parse(r'\frac{x+1}{y}');
      expect(ast, isA<LatexFraction>());
      final frac = ast as LatexFraction;
      expect(frac.numerator, isA<LatexGroup>());
      expect(frac.denominator, isA<LatexSymbol>());
    });
  });

  // ===========================================================================
  // Superscripts and Subscripts
  // ===========================================================================

  group('LatexParser — super/subscripts', () {
    test(r'x^2 parses as superscript', () {
      final ast = LatexParser.parse(r'x^2');
      expect(ast, isA<LatexSuperscript>());
      final sup = ast as LatexSuperscript;
      expect((sup.base as LatexSymbol).value, 'x');
      expect((sup.exponent as LatexSymbol).value, '2');
    });

    test(r'x_i parses as subscript', () {
      final ast = LatexParser.parse(r'x_i');
      expect(ast, isA<LatexSubscript>());
      final sub = ast as LatexSubscript;
      expect((sub.base as LatexSymbol).value, 'x');
      expect((sub.subscript as LatexSymbol).value, 'i');
    });

    test(r'x_i^2 parses as sub+superscript', () {
      final ast = LatexParser.parse(r'x_i^2');
      expect(ast, isA<LatexSubSuperscript>());
      final ss = ast as LatexSubSuperscript;
      expect((ss.base as LatexSymbol).value, 'x');
      expect((ss.subscript as LatexSymbol).value, 'i');
      expect((ss.superscript as LatexSymbol).value, '2');
    });

    test(r'x^{n+1} parses compound exponent', () {
      final ast = LatexParser.parse(r'x^{n+1}');
      expect(ast, isA<LatexSuperscript>());
      final sup = ast as LatexSuperscript;
      expect(sup.exponent, isA<LatexGroup>());
    });
  });

  // ===========================================================================
  // Square Roots
  // ===========================================================================

  group('LatexParser — square roots', () {
    test(r'\sqrt{x} parses correctly', () {
      final ast = LatexParser.parse(r'\sqrt{x}');
      expect(ast, isA<LatexSqrt>());
      final sqrt = ast as LatexSqrt;
      expect((sqrt.radicand as LatexSymbol).value, 'x');
      expect(sqrt.degree, isNull);
    });

    test(r'\sqrt[3]{x} parses with degree', () {
      final ast = LatexParser.parse(r'\sqrt[3]{x}');
      expect(ast, isA<LatexSqrt>());
      final sqrt = ast as LatexSqrt;
      expect(sqrt.degree, isNotNull);
    });
  });

  // ===========================================================================
  // Big Operators
  // ===========================================================================

  group('LatexParser — big operators', () {
    test(r'\int parses to big operator', () {
      final ast = LatexParser.parse(r'\int');
      expect(ast, isA<LatexBigOperator>());
      expect((ast as LatexBigOperator).operator, '∫');
    });

    test(r'\sum parses to big operator', () {
      final ast = LatexParser.parse(r'\sum');
      expect(ast, isA<LatexBigOperator>());
      expect((ast as LatexBigOperator).operator, '∑');
    });
  });

  // ===========================================================================
  // Special Symbols
  // ===========================================================================

  group('LatexParser — special symbols', () {
    test(r'\infty parses to ∞', () {
      final ast = LatexParser.parse(r'\infty');
      expect(ast, isA<LatexSymbol>());
      expect((ast as LatexSymbol).value, '∞');
    });

    test(r'\partial parses to ∂', () {
      final ast = LatexParser.parse(r'\partial');
      expect(ast, isA<LatexSymbol>());
      expect((ast as LatexSymbol).value, '∂');
    });

    test(r'\leq parses to ≤', () {
      final ast = LatexParser.parse(r'\leq');
      expect(ast, isA<LatexSymbol>());
      expect((ast as LatexSymbol).value, '≤');
    });

    test(r'\times parses to ×', () {
      final ast = LatexParser.parse(r'\times');
      expect(ast, isA<LatexSymbol>());
      expect((ast as LatexSymbol).value, '×');
    });

    test(r'\rightarrow parses to →', () {
      final ast = LatexParser.parse(r'\rightarrow');
      expect(ast, isA<LatexSymbol>());
      expect((ast as LatexSymbol).value, '→');
    });
  });

  // ===========================================================================
  // Spacing
  // ===========================================================================

  group('LatexParser — spacing', () {
    test(r'\quad parses to space', () {
      final ast = LatexParser.parse(r'\quad');
      expect(ast, isA<LatexSpace>());
      expect((ast as LatexSpace).emWidth, 1.0);
    });

    test(r'\, parses to thin space', () {
      final ast = LatexParser.parse(r'\,');
      expect(ast, isA<LatexSpace>());
    });
  });

  // ===========================================================================
  // Text
  // ===========================================================================

  group('LatexParser — text', () {
    test(r'\text{hello} parses correctly', () {
      final ast = LatexParser.parse(r'\text{hello}');
      expect(ast, isA<LatexText>());
      expect((ast as LatexText).text, 'hello');
    });
  });

  // ===========================================================================
  // Accents
  // ===========================================================================

  group('LatexParser — accents', () {
    test(r'\hat{x} parses correctly', () {
      final ast = LatexParser.parse(r'\hat{x}');
      expect(ast, isA<LatexAccent>());
      final accent = ast as LatexAccent;
      expect(accent.accentType, 'hat');
      expect((accent.base as LatexSymbol).value, 'x');
    });
  });

  // ===========================================================================
  // Complex Expressions
  // ===========================================================================

  group('LatexParser — complex expressions', () {
    test(r'\frac{x^2}{y} parses nested structure', () {
      final ast = LatexParser.parse(r'\frac{x^2}{y}');
      expect(ast, isA<LatexFraction>());
      final frac = ast as LatexFraction;
      expect(frac.numerator, isA<LatexSuperscript>());
      expect(frac.denominator, isA<LatexSymbol>());
    });

    test(r'a + b parses as group of 3', () {
      final ast = LatexParser.parse('a + b');
      expect(ast, isA<LatexGroup>());
      expect((ast as LatexGroup).children.length, 3);
    });
  });

  // ===========================================================================
  // Error Recovery
  // ===========================================================================

  group('LatexParser — error recovery', () {
    test('unknown command produces LatexErrorNode', () {
      final ast = LatexParser.parse(r'\unknowncmd');
      expect(ast, isA<LatexErrorNode>());
      expect((ast as LatexErrorNode).rawText, r'\unknowncmd');
    });
  });
}
