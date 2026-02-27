import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/formats/format_converter.dart';
import 'package:fluera_engine/src/core/formats/format_parser.dart';

void main() {
  // ===========================================================================
  // ConversionOptions
  // ===========================================================================

  group('ConversionOptions', () {
    test('defaults are sensible', () {
      const opts = ConversionOptions();
      expect(opts.quality, 100);
      expect(opts.scale, 1.0);
    });

    test('toJson serializes', () {
      const opts = ConversionOptions(quality: 80, scale: 0.5);
      final json = opts.toJson();
      expect(json['quality'], 80);
    });
  });

  // ===========================================================================
  // ConversionStatus
  // ===========================================================================

  group('ConversionStatus', () {
    test('has 3 values', () {
      expect(ConversionStatus.values.length, 3);
    });
  });

  // ===========================================================================
  // FormatConverter - registration
  // ===========================================================================

  group('FormatConverter - paths', () {
    test('registers conversion path', () {
      final c = FormatConverter();
      c.registerPath('png', 'jpg');
      expect(c.canConvert('png', 'jpg'), isTrue);
    });

    test('unknown path returns false', () {
      final c = FormatConverter();
      expect(c.canConvert('xyz', 'abc'), isFalse);
    });

    test('targetFormatsFor returns registered targets', () {
      final c = FormatConverter();
      c.registerPath('png', 'jpg');
      c.registerPath('png', 'webp');
      expect(c.targetFormatsFor('png'), containsAll(['jpg', 'webp']));
    });
  });

  // ===========================================================================
  // FormatConverter.withDefaults
  // ===========================================================================

  group('FormatConverter.withDefaults', () {
    test('has raster-to-raster paths', () {
      final c = FormatConverter.withDefaults();
      expect(c.canConvert('png', 'jpg'), isTrue);
      expect(c.canConvert('jpg', 'webp'), isTrue);
    });

    test('has svg to raster paths', () {
      final c = FormatConverter.withDefaults();
      expect(c.canConvert('svg', 'png'), isTrue);
    });
  });

  // ===========================================================================
  // Convert
  // ===========================================================================

  group('FormatConverter - convert', () {
    test('converts supported format', () {
      final c = FormatConverter.withDefaults();
      final input = ParsedDocument(
        name: 'test',
        width: 100,
        height: 100,
        layers: [],
        sourceFormat: 'png',
      );
      final result = c.convert(input, targetFormat: 'jpg');
      expect(result.success, isTrue);
      expect(result.targetFormat, 'jpg');
    });

    test('fails for unsupported path', () {
      final c = FormatConverter();
      final input = ParsedDocument(
        name: 'test',
        width: 100,
        height: 100,
        layers: [],
        sourceFormat: 'unknown',
      );
      final result = c.convert(input, targetFormat: 'jpg');
      expect(result.status, ConversionStatus.failed);
    });

    test('result toString is readable', () {
      final result = ConversionResult(
        status: ConversionStatus.success,
        sourceFormat: 'png',
        targetFormat: 'jpg',
      );
      expect(result.toString(), contains('png'));
    });
  });
}
