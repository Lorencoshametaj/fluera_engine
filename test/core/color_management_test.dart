import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/color/color_space_converter.dart';
import 'package:fluera_engine/src/core/color/color_blindness_simulator.dart';
import 'package:fluera_engine/src/core/color/soft_proof_engine.dart';
import 'package:fluera_engine/src/core/color/color_palette_store.dart';

void main() {
  // ===========================================================================
  // COLOR SPACE CONVERTER
  // ===========================================================================

  group('ColorSpaceConverter', () {
    test('sRGB gamma round-trip', () {
      for (final v in [0.0, 0.04, 0.5, 1.0]) {
        final linear = ColorSpaceConverter.srgbToLinear(v);
        final back = ColorSpaceConverter.linearToSrgb(linear);
        expect(back, closeTo(v, 0.001));
      }
    });

    test('sRGB to Lab round-trip', () {
      final lab = ColorSpaceConverter.srgbToLab(0.8, 0.2, 0.1);
      expect(lab.l, greaterThan(0));
      expect(lab.l, lessThan(100));

      final rgb = ColorSpaceConverter.labToSrgb(lab.l, lab.a, lab.b);
      expect(rgb.r, closeTo(0.8, 0.01));
      expect(rgb.g, closeTo(0.2, 0.01));
      expect(rgb.b, closeTo(0.1, 0.01));
    });

    test('white maps to Lab L=100', () {
      final lab = ColorSpaceConverter.srgbToLab(1.0, 1.0, 1.0);
      expect(lab.l, closeTo(100, 0.5));
      expect(lab.a, closeTo(0, 1));
      expect(lab.b, closeTo(0, 1));
    });

    test('black maps to Lab L=0', () {
      final lab = ColorSpaceConverter.srgbToLab(0.0, 0.0, 0.0);
      expect(lab.l, closeTo(0, 0.5));
    });

    test('sRGB to CMYK', () {
      final cmyk = ColorSpaceConverter.srgbToCmyk(1.0, 0.0, 0.0);
      expect(cmyk.c, closeTo(0, 0.01));
      expect(cmyk.m, closeTo(1, 0.01));
      expect(cmyk.y, closeTo(1, 0.01));
      expect(cmyk.k, closeTo(0, 0.01));
    });

    test('CMYK to sRGB round-trip', () {
      final cmyk = ColorSpaceConverter.srgbToCmyk(0.5, 0.3, 0.7);
      final rgb = ColorSpaceConverter.cmykToSrgb(
        cmyk.c,
        cmyk.m,
        cmyk.y,
        cmyk.k,
      );
      expect(rgb.r, closeTo(0.5, 0.01));
      expect(rgb.g, closeTo(0.3, 0.01));
      expect(rgb.b, closeTo(0.7, 0.01));
    });

    test('black CMYK', () {
      final cmyk = ColorSpaceConverter.srgbToCmyk(0.0, 0.0, 0.0);
      expect(cmyk.k, closeTo(1.0, 0.01));
    });

    test('sRGB to Adobe RGB', () {
      final adobe = ColorSpaceConverter.srgbToAdobeRgb(0.5, 0.5, 0.5);
      // Gray should stay approximately gray
      expect(adobe.r, closeTo(adobe.g, 0.05));
      expect(adobe.g, closeTo(adobe.b, 0.05));
    });

    test('deltaE of same color is 0', () {
      final de = ColorSpaceConverter.deltaE(0.5, 0.3, 0.7, 0.5, 0.3, 0.7);
      expect(de, closeTo(0, 0.001));
    });

    test('deltaE of different colors is positive', () {
      final de = ColorSpaceConverter.deltaE(1.0, 0.0, 0.0, 0.0, 1.0, 0.0);
      expect(de, greaterThan(50)); // red vs green = huge difference
    });

    test('XYZ intermediate values', () {
      final xyz = ColorSpaceConverter.srgbToXyz(1.0, 1.0, 1.0);
      // D65 white point
      expect(xyz.x, closeTo(0.9505, 0.01));
      expect(xyz.y, closeTo(1.0000, 0.01));
      expect(xyz.z, closeTo(1.089, 0.01));
    });
  });

  // ===========================================================================
  // COLOR BLINDNESS SIMULATOR
  // ===========================================================================

  group('ColorBlindnessSimulator', () {
    const sim = ColorBlindnessSimulator();

    test('normal vision returns identity', () {
      final result = sim.simulate(0.8, 0.2, 0.3, ColorBlindnessType.normal);
      expect(result.r, 0.8);
      expect(result.g, 0.2);
      expect(result.b, 0.3);
    });

    test('achromatopsia returns grayscale', () {
      final result = sim.simulate(
        1.0,
        0.0,
        0.0,
        ColorBlindnessType.achromatopsia,
      );
      // For pure red: lum = 0.2126
      expect(result.r, closeTo(result.g, 0.001));
      expect(result.g, closeTo(result.b, 0.001));
    });

    test('gray stays gray for all types', () {
      for (final type in ColorBlindnessType.values) {
        final result = sim.simulate(0.5, 0.5, 0.5, type);
        expect(
          result.r,
          closeTo(result.g, 0.05),
          reason: '${type.name}: gray should stay neutral',
        );
      }
    });

    test('protanopia shifts red perception', () {
      final result = sim.simulate(1.0, 0.0, 0.0, ColorBlindnessType.protanopia);
      // Protanopes don't see red — it should shift significantly
      expect(result.type, ColorBlindnessType.protanopia);
      expect(result.r, isNot(closeTo(1.0, 0.1)));
    });

    test('batch simulation', () {
      final colors = [
        const RgbColor(1.0, 0.0, 0.0),
        const RgbColor(0.0, 1.0, 0.0),
        const RgbColor(0.0, 0.0, 1.0),
      ];
      final results = sim.simulateBatch(
        colors,
        ColorBlindnessType.deuteranopia,
      );
      expect(results.length, 3);
    });

    test('severity descriptions exist for all types', () {
      for (final type in ColorBlindnessType.values) {
        expect(ColorBlindnessSimulator.severity(type), isNotEmpty);
      }
    });

    test('prevalence values are positive', () {
      for (final type in ColorBlindnessType.values) {
        expect(ColorBlindnessSimulator.prevalence(type), greaterThan(0));
      }
    });

    test('areDistinguishable works', () {
      // Red vs blue should be distinguishable even for most CVD
      final result = sim.areDistinguishable(
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        ColorBlindnessType.protanopia,
      );
      expect(result, isTrue);
    });
  });

  // ===========================================================================
  // SOFT PROOF ENGINE
  // ===========================================================================

  group('SoftProofEngine', () {
    test('proofing alters colors', () {
      const engine = SoftProofEngine();
      final result = engine.proof(1.0, 0.0, 0.0);
      // Print simulation should darken/shift colors
      expect(result.r, lessThan(1.0));
      expect(result.cmyk.m, greaterThan(0));
    });

    test('white maps to paper white', () {
      const engine = SoftProofEngine(profile: PrintProfile.coatedFogra39);
      final result = engine.proof(1.0, 1.0, 1.0);
      // Paper isn't pure white — proofed white is tinted
      expect(result.r, lessThan(1.0));
      expect(result.r, greaterThan(0.8));
    });

    test('black stays very dark', () {
      const engine = SoftProofEngine();
      final result = engine.proof(0.0, 0.0, 0.0);
      expect(result.r, closeTo(0, 0.05));
      expect(result.g, closeTo(0, 0.05));
    });

    test('different profiles produce different results', () {
      final coated = const SoftProofEngine(
        profile: PrintProfile.coatedFogra39,
      ).proof(0.8, 0.2, 0.3);

      final newsprint = const SoftProofEngine(
        profile: PrintProfile.newsprint,
      ).proof(0.8, 0.2, 0.3);

      // Newsprint should be more muted
      expect(newsprint.r, isNot(closeTo(coated.r, 0.01)));
    });

    test('batch proofing', () {
      const engine = SoftProofEngine();
      final results = engine.proofBatch([
        const RgbColor(1.0, 0.0, 0.0),
        const RgbColor(0.0, 1.0, 0.0),
      ]);
      expect(results.length, 2);
    });

    test('rendering intents differ', () {
      final perceptual = const SoftProofEngine(
        intent: RenderingIntent.perceptual,
      ).proof(0.9, 0.1, 0.5);

      final saturation = const SoftProofEngine(
        intent: RenderingIntent.saturation,
      ).proof(0.9, 0.1, 0.5);

      // Saturation intent boosts vividness
      expect(saturation.r, isNot(closeTo(perceptual.r, 0.001)));
    });

    test('isInGamut returns a result', () {
      const engine = SoftProofEngine();
      // isInGamut is a convenience wrapper — just verify it runs
      final result = engine.isInGamut(0.5, 0.5, 0.5);
      expect(result, isA<bool>());
    });
  });

  // ===========================================================================
  // COLOR PALETTE STORE
  // ===========================================================================

  group('ColorPaletteStore', () {
    test('ColorSwatch from hex', () {
      final swatch = ColorSwatch.fromHex('Red', 'FF0000');
      expect(swatch.r, closeTo(1.0, 0.01));
      expect(swatch.g, closeTo(0.0, 0.01));
      expect(swatch.toHex(), '#FF0000');
    });

    test('ColorSwatch from RGB 255', () {
      final swatch = ColorSwatch.fromRgb255('Half Gray', 128, 128, 128);
      expect(swatch.r, closeTo(0.502, 0.01));
    });

    test('ColorSwatch serialization', () {
      final original = ColorSwatch.fromHex('Blue', '0000FF');
      final json = original.toJson();
      final restored = ColorSwatch.fromJson(json);
      expect(restored.name, original.name);
      expect(restored.r, closeTo(original.r, 0.01));
    });

    test('ColorPalette preset - material', () {
      final palette = ColorPalette.material();
      expect(palette.count, 12);
      expect(palette.findByName('Red'), isNotNull);
      expect(palette.findByName('nonexistent'), isNull);
    });

    test('ColorPalette add/remove', () {
      final palette = ColorPalette(id: 'test', name: 'Test');
      palette.add(ColorSwatch.fromHex('A', 'FF0000'));
      expect(palette.count, 1);
      palette.remove('A');
      expect(palette.count, 0);
    });

    test('ColorPalette serialization', () {
      final original = ColorPalette.pastel();
      final json = original.toJson();
      final restored = ColorPalette.fromJson(json);
      expect(restored.count, original.count);
      expect(restored.name, original.name);
    });

    test('store with built-ins', () {
      final store = ColorPaletteStore.withBuiltIns();
      expect(store.count, 3);
      expect(
        store.paletteIds,
        containsAll(['material', 'pastel', 'grayscale']),
      );
    });

    test('store CRUD', () {
      final store = ColorPaletteStore();
      store.addPalette(ColorPalette(id: 'x', name: 'X'));
      expect(store.count, 1);
      expect(store.getPalette('x'), isNotNull);
      expect(store.removePalette('x'), isTrue);
      expect(store.count, 0);
    });

    test('findSwatch across palettes', () {
      final store = ColorPaletteStore.withBuiltIns();
      final swatch = store.findSwatch('Red');
      expect(swatch, isNotNull);
      expect(swatch!.name, 'Red');
    });

    test('searchSwatches', () {
      final store = ColorPaletteStore.withBuiltIns();
      final grays = store.searchSwatches('Gray');
      expect(grays.length, greaterThan(5));
    });

    test('store JSON round-trip', () {
      final store = ColorPaletteStore.withBuiltIns();
      final json = store.toJson();
      final restored = ColorPaletteStore.fromJson(json);
      expect(restored.count, store.count);
    });
  });
}
