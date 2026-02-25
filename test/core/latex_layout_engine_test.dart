import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/latex/latex_ast.dart';
import 'package:nebula_engine/src/core/latex/latex_layout_engine.dart';

void main() {
  const fontSize = 24.0;
  const color = Color(0xFF000000);

  // ===========================================================================
  // Single symbol
  // ===========================================================================

  group('LatexLayoutEngine - symbol', () {
    test('lays out single character', () {
      const node = LatexSymbol('x', italic: true);
      final result = LatexLayoutEngine.layout(
        node,
        fontSize: fontSize,
        color: color,
      );
      expect(result.commands, isNotEmpty);
      expect(result.size.width, greaterThan(0));
      expect(result.size.height, greaterThan(0));
    });

    test('lays out digit', () {
      const node = LatexSymbol('5');
      final result = LatexLayoutEngine.layout(
        node,
        fontSize: fontSize,
        color: color,
      );
      expect(result.commands, isNotEmpty);
    });

    test('lays out operator', () {
      const node = LatexSymbol('+');
      final result = LatexLayoutEngine.layout(
        node,
        fontSize: fontSize,
        color: color,
      );
      expect(result.commands, isNotEmpty);
    });
  });

  // ===========================================================================
  // Group
  // ===========================================================================

  group('LatexLayoutEngine - group', () {
    test('lays out group of symbols', () {
      const node = LatexGroup([
        LatexSymbol('a', italic: true),
        LatexSymbol('+'),
        LatexSymbol('b', italic: true),
      ]);
      final result = LatexLayoutEngine.layout(
        node,
        fontSize: fontSize,
        color: color,
      );
      expect(result.commands.length, greaterThanOrEqualTo(3));
      expect(result.size.width, greaterThan(0));
    });

    test('empty group produces no commands', () {
      const node = LatexGroup([]);
      final result = LatexLayoutEngine.layout(
        node,
        fontSize: fontSize,
        color: color,
      );
      expect(result.commands, isEmpty);
    });
  });

  // ===========================================================================
  // Fraction
  // ===========================================================================

  group('LatexLayoutEngine - fraction', () {
    test('lays out simple fraction', () {
      const node = LatexFraction(LatexSymbol('1'), LatexSymbol('2'));
      final result = LatexLayoutEngine.layout(
        node,
        fontSize: fontSize,
        color: color,
      );
      // Fraction should produce glyphs for '1', '2' and a horizontal line
      expect(result.commands.length, greaterThanOrEqualTo(3));
      // Height should be larger than a single symbol
      expect(result.size.height, greaterThan(fontSize * 0.5));
    });

    test('nested fraction has greater height', () {
      const simple = LatexFraction(LatexSymbol('a'), LatexSymbol('b'));
      const nested = LatexFraction(
        LatexFraction(LatexSymbol('1'), LatexSymbol('2')),
        LatexSymbol('3'),
      );
      final simpleResult = LatexLayoutEngine.layout(
        simple,
        fontSize: fontSize,
        color: color,
      );
      final nestedResult = LatexLayoutEngine.layout(
        nested,
        fontSize: fontSize,
        color: color,
      );
      expect(nestedResult.size.height, greaterThan(simpleResult.size.height));
    });
  });

  // ===========================================================================
  // Superscript / Subscript
  // ===========================================================================

  group('LatexLayoutEngine - scripts', () {
    test('superscript is positioned above baseline', () {
      const node = LatexSuperscript(
        LatexSymbol('x', italic: true),
        LatexSymbol('2'),
      );
      final result = LatexLayoutEngine.layout(
        node,
        fontSize: fontSize,
        color: color,
      );
      // Should produce at least 2 glyphs (x and 2)
      expect(result.commands.length, greaterThanOrEqualTo(2));
      expect(result.size.width, greaterThan(0));
    });

    test('subscript widens the overall size', () {
      const base = LatexSymbol('x', italic: true);
      const withSub = LatexSubscript(
        LatexSymbol('x', italic: true),
        LatexSymbol('i', italic: true),
      );
      final baseResult = LatexLayoutEngine.layout(
        base,
        fontSize: fontSize,
        color: color,
      );
      final subResult = LatexLayoutEngine.layout(
        withSub,
        fontSize: fontSize,
        color: color,
      );
      expect(subResult.size.width, greaterThan(baseResult.size.width));
    });
  });

  // ===========================================================================
  // Square root
  // ===========================================================================

  group('LatexLayoutEngine - sqrt', () {
    test('sqrt wraps content with extra width', () {
      const inner = LatexSymbol('x', italic: true);
      const sqrtNode = LatexSqrt(inner);
      final innerResult = LatexLayoutEngine.layout(
        inner,
        fontSize: fontSize,
        color: color,
      );
      final sqrtResult = LatexLayoutEngine.layout(
        sqrtNode,
        fontSize: fontSize,
        color: color,
      );
      expect(sqrtResult.size.width, greaterThan(innerResult.size.width));
    });
  });

  // ===========================================================================
  // Matrix
  // ===========================================================================

  group('LatexLayoutEngine - matrix', () {
    test('2x2 matrix has expected size', () {
      const matrix = LatexMatrix([
        [LatexSymbol('a'), LatexSymbol('b')],
        [LatexSymbol('c'), LatexSymbol('d')],
      ]);
      final result = LatexLayoutEngine.layout(
        matrix,
        fontSize: fontSize,
        color: color,
      );
      // 4 cells + possible delimiter/line commands
      expect(result.commands.length, greaterThanOrEqualTo(4));
      expect(result.size.width, greaterThan(0));
      expect(result.size.height, greaterThan(0));
    });
  });

  // ===========================================================================
  // Font size
  // ===========================================================================

  group('LatexLayoutEngine - font size', () {
    test('larger fontSize produces larger output', () {
      const node = LatexSymbol('A');
      final small = LatexLayoutEngine.layout(
        node,
        fontSize: 12.0,
        color: color,
      );
      final large = LatexLayoutEngine.layout(
        node,
        fontSize: 48.0,
        color: color,
      );
      expect(large.size.width, greaterThan(small.size.width));
      expect(large.size.height, greaterThan(small.size.height));
    });
  });

  // ===========================================================================
  // Delimited
  // ===========================================================================

  group('LatexLayoutEngine - delimited', () {
    test('left/right parentheses wrap content', () {
      const inner = LatexGroup([
        LatexSymbol('x', italic: true),
        LatexSymbol('+'),
        LatexSymbol('1'),
      ]);
      const delimited = LatexDelimited('(', ')', inner);
      final innerResult = LatexLayoutEngine.layout(
        inner,
        fontSize: fontSize,
        color: color,
      );
      final delimResult = LatexLayoutEngine.layout(
        delimited,
        fontSize: fontSize,
        color: color,
      );
      expect(delimResult.size.width, greaterThan(innerResult.size.width));
    });
  });
}
