import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/latex/latex_parser.dart';
import 'package:nebula_engine/src/core/latex/latex_layout_engine.dart';
import 'package:nebula_engine/src/core/latex/latex_draw_command.dart';
import 'package:nebula_engine/src/core/latex/latex_layout_cache.dart';

void main() {
  const testColor = Color(0xFFFFFFFF);
  const testFontSize = 24.0;

  // ===========================================================================
  // Layout Engine — Basic
  // ===========================================================================

  group('LatexLayoutEngine — basic', () {
    test('single symbol produces 1 GlyphDrawCommand', () {
      final ast = LatexParser.parse('x');
      final result = LatexLayoutEngine.layout(
        ast,
        fontSize: testFontSize,
        color: testColor,
      );

      expect(result.commands, isNotEmpty);
      expect(result.commands.length, 1);
      expect(result.commands.first, isA<GlyphDrawCommand>());
      expect((result.commands.first as GlyphDrawCommand).text, 'x');
    });

    test('layout produces non-zero size', () {
      final ast = LatexParser.parse('x');
      final result = LatexLayoutEngine.layout(
        ast,
        fontSize: testFontSize,
        color: testColor,
      );

      expect(result.size.width, greaterThan(0));
      expect(result.size.height, greaterThan(0));
    });

    test('larger fontSize produces larger size', () {
      final ast = LatexParser.parse('x');
      final small = LatexLayoutEngine.layout(
        ast,
        fontSize: 12.0,
        color: testColor,
      );
      final large = LatexLayoutEngine.layout(
        ast,
        fontSize: 48.0,
        color: testColor,
      );

      expect(large.size.width, greaterThan(small.size.width));
      expect(large.size.height, greaterThan(small.size.height));
    });
  });

  // ===========================================================================
  // Layout Engine — Fractions
  // ===========================================================================

  group('LatexLayoutEngine — fractions', () {
    test('fraction produces glyph + line commands', () {
      final ast = LatexParser.parse(r'\frac{a}{b}');
      final result = LatexLayoutEngine.layout(
        ast,
        fontSize: testFontSize,
        color: testColor,
      );

      // Should have at least: numerator glyph + fraction bar + denominator glyph
      expect(result.commands.length, greaterThanOrEqualTo(3));

      // Check there's a LineDrawCommand (the fraction bar)
      final lineCommands =
          result.commands.whereType<LineDrawCommand>().toList();
      expect(lineCommands, isNotEmpty);
    });

    test('fraction height is larger than single symbol', () {
      final symbolResult = LatexLayoutEngine.layout(
        LatexParser.parse('x'),
        fontSize: testFontSize,
        color: testColor,
      );
      final fracResult = LatexLayoutEngine.layout(
        LatexParser.parse(r'\frac{x}{y}'),
        fontSize: testFontSize,
        color: testColor,
      );

      expect(fracResult.size.height, greaterThan(symbolResult.size.height));
    });
  });

  // ===========================================================================
  // Layout Engine — Superscripts
  // ===========================================================================

  group('LatexLayoutEngine — superscripts', () {
    test('superscript produces 2 glyph commands', () {
      final ast = LatexParser.parse(r'x^2');
      final result = LatexLayoutEngine.layout(
        ast,
        fontSize: testFontSize,
        color: testColor,
      );

      final glyphs = result.commands.whereType<GlyphDrawCommand>().toList();
      expect(glyphs.length, 2);
    });

    test('superscript glyph has smaller fontSize', () {
      final ast = LatexParser.parse(r'x^2');
      final result = LatexLayoutEngine.layout(
        ast,
        fontSize: testFontSize,
        color: testColor,
      );

      final glyphs = result.commands.whereType<GlyphDrawCommand>().toList();
      // The exponent ('2') should have a smaller font size
      final exponentGlyph = glyphs.firstWhere((g) => g.text == '2');
      expect(exponentGlyph.fontSize, lessThan(testFontSize));
    });
  });

  // ===========================================================================
  // Layout Engine — Square Roots
  // ===========================================================================

  group('LatexLayoutEngine — square roots', () {
    test('sqrt produces path + line + glyph commands', () {
      final ast = LatexParser.parse(r'\sqrt{x}');
      final result = LatexLayoutEngine.layout(
        ast,
        fontSize: testFontSize,
        color: testColor,
      );

      // Should have: radical path + horizontal bar + radicand glyph
      expect(result.commands.length, greaterThanOrEqualTo(3));
      expect(
        result.commands.whereType<PathDrawCommand>().length,
        greaterThanOrEqualTo(1),
      );
      expect(
        result.commands.whereType<LineDrawCommand>().length,
        greaterThanOrEqualTo(1),
      );
    });
  });

  // ===========================================================================
  // Layout Engine — Error Handling
  // ===========================================================================

  group('LatexLayoutEngine — error handling', () {
    test('empty expression produces empty commands', () {
      final ast = LatexParser.parse('');
      final result = LatexLayoutEngine.layout(
        ast,
        fontSize: testFontSize,
        color: testColor,
      );
      expect(result.commands, isEmpty);
    });

    test('error node produces red glyph', () {
      final ast = LatexParser.parse(r'\unknowncmd');
      final result = LatexLayoutEngine.layout(
        ast,
        fontSize: testFontSize,
        color: testColor,
      );

      expect(result.commands, isNotEmpty);
      final glyph = result.commands.first as GlyphDrawCommand;
      // Error color is red
      expect(glyph.color, const Color(0xFFFF4444));
    });
  });

  // ===========================================================================
  // Layout Cache
  // ===========================================================================

  group('LatexLayoutCache', () {
    test('cache miss returns null', () {
      final cache = LatexLayoutCache();
      expect(cache.get('x', 24.0, testColor), isNull);
    });

    test('cache hit returns stored result', () {
      final cache = LatexLayoutCache();
      final result = const LatexLayoutResult(commands: [], size: Size(10, 10));
      cache.put('x', 24.0, testColor, result);
      expect(cache.get('x', 24.0, testColor), isNotNull);
    });

    test('different source is cache miss', () {
      final cache = LatexLayoutCache();
      final result = const LatexLayoutResult(commands: [], size: Size(10, 10));
      cache.put('x', 24.0, testColor, result);
      expect(cache.get('y', 24.0, testColor), isNull);
    });

    test('different fontSize is cache miss', () {
      final cache = LatexLayoutCache();
      final result = const LatexLayoutResult(commands: [], size: Size(10, 10));
      cache.put('x', 24.0, testColor, result);
      expect(cache.get('x', 32.0, testColor), isNull);
    });

    test('evicts LRU when at capacity', () {
      final cache = LatexLayoutCache(maxEntries: 2);
      final r = const LatexLayoutResult(commands: [], size: Size(1, 1));

      cache.put('a', 24.0, testColor, r);
      cache.put('b', 24.0, testColor, r);
      cache.put('c', 24.0, testColor, r); // should evict 'a'

      expect(cache.get('a', 24.0, testColor), isNull);
      expect(cache.get('b', 24.0, testColor), isNotNull);
      expect(cache.get('c', 24.0, testColor), isNotNull);
    });

    test('clear removes all entries', () {
      final cache = LatexLayoutCache();
      final r = const LatexLayoutResult(commands: [], size: Size(1, 1));
      cache.put('a', 24.0, testColor, r);
      cache.put('b', 24.0, testColor, r);
      cache.clear();
      expect(cache.isEmpty, true);
    });
  });
}
