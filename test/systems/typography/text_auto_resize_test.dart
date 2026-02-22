import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/systems/text_auto_resize.dart';
import 'package:flutter/painting.dart';
import 'dart:ui';

// In testing, Flutter's TextPainter needs a valid font to get accurate metrics.
// For pure unit testing without asset loading, we use basic TextStyle.
// The exact pixel values might vary slightly by engine version, so we check
// relative relationships and conceptual constraints.
void main() {
  group('TextAutoResizeEngine Tests', () {
    const textStyle = TextStyle(fontSize: 20.0, height: 1.0);
    const shortText = 'Hello';
    const longText =
        'This is a much longer piece of text that should wrap if constraints are applied correctly.';

    test('fixed mode returns exact constraints', () {
      final constraints = const Size(100, 50);

      final size = TextAutoResizeEngine.computeSize(
        text: shortText,
        style: textStyle,
        mode: TextResizeMode.fixed,
        constraints: constraints,
      );

      expect(size.width, 100);
      expect(size.height, 50);
    });

    test('autoAll mode grows to fit text in single line', () {
      final constraints = const Size(100, 50); // Should be ignored

      final size = TextAutoResizeEngine.computeSize(
        text: shortText,
        style: textStyle,
        mode: TextResizeMode.autoAll,
        constraints: constraints,
      );

      // Auto-all ignores incoming constraints
      expect(size.height, 20.0); // 1 line, fontSize 20 * height 1.0
      expect(size.width, greaterThan(0));
    });

    test(
      'autoWidth mode ignores width constraint but respects height limit',
      () {
        // Give it a short height constraint
        final constraints = const Size(10, 10);

        final size = TextAutoResizeEngine.computeSize(
          text: shortText,
          style: textStyle,
          mode: TextResizeMode.autoWidth,
          constraints: constraints,
        );

        // Width is computed based on text length
        expect(size.width, greaterThan(20.0));
        // Height is capped by constraints.height if finite
        expect(size.height, 10.0);
      },
    );

    test('autoHeight mode wraps text to width constraint', () {
      final constraints = const Size(50, 20); // Narrow width, tight height

      final size = TextAutoResizeEngine.computeSize(
        text: longText,
        style: textStyle,
        mode: TextResizeMode.autoHeight,
        constraints: constraints,
      );

      // Width is fixed to constraints
      expect(size.width, 50.0);
      // Height expands to fit multiple lines
      expect(size.height, greaterThan(50.0)); // Will wrap multiple times
    });

    test('computeMinHeight calculates correct height for given width', () {
      final heightNarrow = TextAutoResizeEngine.computeMinHeight(
        text: longText,
        style: textStyle,
        width: 100,
      );

      final heightWide = TextAutoResizeEngine.computeMinHeight(
        text: longText,
        style: textStyle,
        width: 1000,
      );

      expect(heightNarrow, greaterThan(heightWide));
    });

    test('computeMinWidth calculates single line width', () {
      final width = TextAutoResizeEngine.computeMinWidth(
        text: shortText,
        style: textStyle,
      );

      expect(width, greaterThan(0));

      final doubleWidth = TextAutoResizeEngine.computeMinWidth(
        text: shortText + shortText,
        style: textStyle,
      );

      expect(doubleWidth, greaterThan(width));
    });

    test('isOverflowing detects text overflow', () {
      // Too small constraint
      final overflows = TextAutoResizeEngine.isOverflowing(
        text: longText,
        style: textStyle,
        constraints: const Size(50, 20),
      );
      expect(overflows, isTrue);

      // Large enough constraint
      final fits = TextAutoResizeEngine.isOverflowing(
        text: shortText,
        style: textStyle,
        constraints: const Size(500, 500),
      );
      expect(fits, isFalse);

      // Max lines overflow
      final maxLinesOverflow = TextAutoResizeEngine.isOverflowing(
        text: 'Line 1\nLine 2\nLine 3',
        style: textStyle,
        constraints: const Size(500, 500), // Height is plenty
        maxLines: 2, // But line count is restricted
      );
      expect(maxLinesOverflow, isTrue);
    });
  });
}
