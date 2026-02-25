import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/testing/pixel_diff_engine.dart';

void main() {
  late PixelDiffEngine engine;

  setUp(() {
    engine = PixelDiffEngine();
  });

  // ===========================================================================
  // Identical images
  // ===========================================================================

  group('PixelDiffEngine - identical', () {
    test('identical images produce zero diff', () {
      final pixels = Uint8List.fromList(List.generate(4 * 4 * 4, (i) => 128));
      final result = engine.compare(
        actual: pixels,
        expected: Uint8List.fromList(pixels),
        width: 4,
        height: 4,
      );
      expect(result.totalPixels, 16);
      expect(result.differentPixels, 0);
      expect(result.passed, isTrue);
    });
  });

  // ===========================================================================
  // Different images
  // ===========================================================================

  group('PixelDiffEngine - different', () {
    test('completely different images are detected', () {
      final black = Uint8List.fromList(
        List.generate(4 * 4 * 4, (i) => i % 4 == 3 ? 255 : 0),
      );
      final white = Uint8List.fromList(List.generate(4 * 4 * 4, (i) => 255));
      final result = engine.compare(
        actual: black,
        expected: white,
        width: 4,
        height: 4,
      );
      expect(result.differentPixels, greaterThan(0));
    });
  });

  // ===========================================================================
  // Tolerance
  // ===========================================================================

  group('PixelDiffEngine - tolerance', () {
    test('small differences within tolerance pass', () {
      final a = Uint8List.fromList(List.generate(4 * 4 * 4, (i) => 128));
      final b = Uint8List.fromList(List.generate(4 * 4 * 4, (i) => 130));
      final result = engine.compare(
        actual: a,
        expected: b,
        width: 4,
        height: 4,
        config: const PixelDiffConfig(tolerance: 0.1),
      );
      expect(result.differentPixels, 0);
    });
  });

  // ===========================================================================
  // Diff image generation
  // ===========================================================================

  group('PixelDiffEngine - diff image', () {
    test('generates diff image when requested', () {
      final a = Uint8List(4 * 4 * 4);
      final b = Uint8List.fromList(List.generate(4 * 4 * 4, (i) => 255));
      final result = engine.compare(
        actual: a,
        expected: b,
        width: 4,
        height: 4,
        generateDiffImage: true,
      );
      expect(result.diffImageRgba, isNotNull);
      expect(result.diffImageRgba!.length, 4 * 4 * 4);
    });

    test('no diff image when not requested', () {
      final a = Uint8List(4 * 4 * 4);
      final result = engine.compare(
        actual: a,
        expected: Uint8List.fromList(a),
        width: 4,
        height: 4,
        generateDiffImage: false,
      );
      expect(result.diffImageRgba, isNull);
    });
  });

  // ===========================================================================
  // PixelDiffResult
  // ===========================================================================

  group('PixelDiffResult', () {
    test('toString is readable', () {
      final result = engine.compare(
        actual: Uint8List(16),
        expected: Uint8List(16),
        width: 2,
        height: 2,
      );
      expect(result.toString(), isNotEmpty);
    });
  });

  // ===========================================================================
  // PixelDiffConfig
  // ===========================================================================

  group('PixelDiffConfig', () {
    test('default config has zero tolerance', () {
      const config = PixelDiffConfig();
      expect(config.tolerance, 0.0);
    });

    test('lenient preset has positive tolerance', () {
      expect(PixelDiffConfig.lenient.tolerance, greaterThan(0));
    });
  });
}
