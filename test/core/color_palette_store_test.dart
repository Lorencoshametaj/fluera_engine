import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/color/color_palette_store.dart';

void main() {
  // ===========================================================================
  // ColorSwatch
  // ===========================================================================

  group('ColorSwatch', () {
    test('creates with name and RGB', () {
      const swatch = ColorSwatch(name: 'Red', r: 1.0, g: 0.0, b: 0.0);
      expect(swatch.name, 'Red');
      expect(swatch.r, 1.0);
    });

    test('fromRgb255 normalizes values', () {
      final swatch = ColorSwatch.fromRgb255('White', 255, 255, 255);
      expect(swatch.r, closeTo(1.0, 0.01));
      expect(swatch.g, closeTo(1.0, 0.01));
    });

    test('fromHex parses hex string', () {
      final swatch = ColorSwatch.fromHex('Blue', '#0000FF');
      expect(swatch.b, closeTo(1.0, 0.01));
    });

    test('toHex returns hex string', () {
      const swatch = ColorSwatch(name: 'Green', r: 0.0, g: 1.0, b: 0.0);
      final hex = swatch.toHex();
      expect(hex, isNotEmpty);
    });

    test('toJson round-trips', () {
      const swatch = ColorSwatch(name: 'Cyan', r: 0.0, g: 1.0, b: 1.0);
      final json = swatch.toJson();
      expect(json['name'], 'Cyan');
    });

    test('toString is readable', () {
      const swatch = ColorSwatch(name: 'Test', r: 0.5, g: 0.5, b: 0.5);
      expect(swatch.toString(), contains('Test'));
    });
  });

  // ===========================================================================
  // ColorPalette
  // ===========================================================================

  group('ColorPalette', () {
    test('creates empty palette', () {
      final palette = ColorPalette(id: 'test', name: 'Test');
      expect(palette.count, 0);
    });

    test('add and findByName', () {
      final palette = ColorPalette(id: 'test', name: 'Test');
      palette.add(const ColorSwatch(name: 'Red', r: 1.0, g: 0.0, b: 0.0));
      final found = palette.findByName('Red');
      expect(found, isNotNull);
      expect(found!.name, 'Red');
    });

    test('findByName is case-insensitive', () {
      final palette = ColorPalette(id: 'test', name: 'Test');
      palette.add(const ColorSwatch(name: 'Blue', r: 0.0, g: 0.0, b: 1.0));
      expect(palette.findByName('blue'), isNotNull);
    });

    test('remove works', () {
      final palette = ColorPalette(id: 'test', name: 'Test');
      palette.add(const ColorSwatch(name: 'Red', r: 1.0, g: 0.0, b: 0.0));
      final removed = palette.remove('Red');
      expect(removed, isTrue);
      expect(palette.findByName('Red'), isNull);
    });

    test('toJson serializes palette', () {
      final palette = ColorPalette(id: 'p1', name: 'Palette 1');
      palette.add(const ColorSwatch(name: 'A', r: 0.1, g: 0.1, b: 0.1));
      final json = palette.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });
  });

  // ===========================================================================
  // Built-in palettes
  // ===========================================================================

  group('ColorPalette - built-in', () {
    test('material palette has swatches', () {
      final m = ColorPalette.material();
      expect(m.swatches, isNotEmpty);
    });

    test('pastel palette has swatches', () {
      final p = ColorPalette.pastel();
      expect(p.swatches, isNotEmpty);
    });

    test('grayscale palette has swatches', () {
      final g = ColorPalette.grayscale();
      expect(g.swatches, isNotEmpty);
    });
  });

  // ===========================================================================
  // ColorPaletteStore
  // ===========================================================================

  group('ColorPaletteStore', () {
    test('starts empty', () {
      final store = ColorPaletteStore();
      expect(store.count, 0);
    });

    test('addPalette and getPalette', () {
      final store = ColorPaletteStore();
      final palette = ColorPalette(id: 'test', name: 'Test');
      store.addPalette(palette);
      expect(store.getPalette('test'), isNotNull);
    });

    test('removePalette', () {
      final store = ColorPaletteStore();
      store.addPalette(ColorPalette(id: 'test', name: 'Test'));
      expect(store.removePalette('test'), isTrue);
      expect(store.getPalette('test'), isNull);
    });

    test('findSwatch across palettes', () {
      final store = ColorPaletteStore();
      final p1 = ColorPalette(id: 'p1', name: 'P1');
      p1.add(const ColorSwatch(name: 'UniqueRed', r: 1.0, g: 0.0, b: 0.0));
      store.addPalette(p1);
      final found = store.findSwatch('UniqueRed');
      expect(found, isNotNull);
    });

    test('searchSwatches finds by query', () {
      final store = ColorPaletteStore();
      final p1 = ColorPalette(id: 'p1', name: 'P1');
      p1.add(const ColorSwatch(name: 'Sky Blue', r: 0.53, g: 0.81, b: 0.92));
      p1.add(const ColorSwatch(name: 'Deep Red', r: 0.8, g: 0.0, b: 0.0));
      store.addPalette(p1);
      final results = store.searchSwatches('sky');
      expect(results.length, 1);
    });

    test('clear removes all palettes', () {
      final store = ColorPaletteStore();
      store.addPalette(ColorPalette(id: 'p1', name: 'P1'));
      store.addPalette(ColorPalette(id: 'p2', name: 'P2'));
      store.clear();
      expect(store.count, 0);
    });

    test('toJson exports all palettes', () {
      final store = ColorPaletteStore();
      store.addPalette(ColorPalette(id: 'p1', name: 'P1'));
      final json = store.toJson();
      expect(json, isA<Map<String, dynamic>>());
    });
  });
}
