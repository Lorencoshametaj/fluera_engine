import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/formats/format_registry.dart';

void main() {
  late FormatRegistry registry;

  setUp(() {
    registry = FormatRegistry.withDefaults();
  });

  // ===========================================================================
  // Built-in formats
  // ===========================================================================

  group('FormatRegistry - built-in', () {
    test('has built-in formats registered', () {
      expect(registry.all, isNotEmpty);
    });

    test('PNG format exists', () {
      final png = registry.byId('png');
      expect(png, isNotNull);
      expect(png!.extensions, contains('.png'));
    });

    test('SVG format exists', () {
      final svg = registry.byId('svg');
      expect(svg, isNotNull);
    });

    test('PDF format exists', () {
      final pdf = registry.byId('pdf');
      expect(pdf, isNotNull);
    });
  });

  // ===========================================================================
  // Lookup
  // ===========================================================================

  group('FormatRegistry - lookup', () {
    test('byExtension finds PNG by .png', () {
      final result = registry.byExtension('.png');
      expect(result, isNotNull);
      expect(result!.id, 'png');
    });

    test('byExtension finds PNG by png (no dot)', () {
      final result = registry.byExtension('png');
      expect(result, isNotNull);
    });

    test('byMimeType finds image/png', () {
      final result = registry.byMimeType('image/png');
      expect(result, isNotNull);
    });

    test('byId returns null for unknown', () {
      expect(registry.byId('nonexistent'), isNull);
    });
  });

  // ===========================================================================
  // Capabilities
  // ===========================================================================

  group('FormatRegistry - capabilities', () {
    test('withCapability returns formats with transparency', () {
      final transparent = registry.withCapability(
        FormatCapability.transparency,
      );
      expect(transparent, isNotEmpty);
      for (final f in transparent) {
        expect(f.hasCapability(FormatCapability.transparency), isTrue);
      }
    });

    test('inCategory filters by category', () {
      final raster = registry.inCategory(FormatCategory.raster);
      expect(raster, isNotEmpty);
      for (final f in raster) {
        expect(f.category, FormatCategory.raster);
      }
    });
  });

  // ===========================================================================
  // Register / Unregister
  // ===========================================================================

  group('FormatRegistry - register/unregister', () {
    test('register adds a custom format', () {
      final custom = FileFormatDescriptor(
        id: 'custom_format',
        name: 'Custom',
        extensions: ['.cust'],
        mimeTypes: ['image/x-custom'],
        category: FormatCategory.raster,
        capabilities: {FormatCapability.raster},
      );
      registry.register(custom);
      expect(registry.byId('custom_format'), isNotNull);
    });

    test('unregister removes a format', () {
      registry.unregister('png');
      expect(registry.byId('png'), isNull);
    });
  });

  // ===========================================================================
  // FileFormatDescriptor
  // ===========================================================================

  group('FileFormatDescriptor', () {
    test('hasCapability checks correctly', () {
      final fmt = FileFormatDescriptor(
        id: 'test',
        name: 'Test',
        extensions: ['.tst'],
        mimeTypes: ['test/test'],
        category: FormatCategory.raster,
        capabilities: {FormatCapability.transparency, FormatCapability.layers},
      );
      expect(fmt.hasCapability(FormatCapability.transparency), isTrue);
      expect(fmt.hasCapability(FormatCapability.animation), isFalse);
    });

    test('toJson contains expected keys', () {
      final fmt = FileFormatDescriptor(
        id: 'json_test',
        name: 'JSON Test',
        extensions: ['.jt'],
        mimeTypes: ['test/json'],
        category: FormatCategory.vector,
        capabilities: {},
      );
      final json = fmt.toJson();
      expect(json['id'], 'json_test');
      expect(json['name'], 'JSON Test');
      expect(json['extensions'], contains('.jt'));
    });
  });
}
