import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_engine/src/core/color/color_space_converter.dart';

void main() {
  // ===========================================================================
  // sRGB ↔ Linear
  // ===========================================================================

  group('ColorSpaceConverter - gamma', () {
    test('srgbToLinear(0) = 0', () {
      expect(ColorSpaceConverter.srgbToLinear(0), closeTo(0, 0.001));
    });

    test('srgbToLinear(1) = 1', () {
      expect(ColorSpaceConverter.srgbToLinear(1), closeTo(1, 0.001));
    });

    test('linearToSrgb round-trips', () {
      final linear = ColorSpaceConverter.srgbToLinear(0.5);
      final back = ColorSpaceConverter.linearToSrgb(linear);
      expect(back, closeTo(0.5, 0.001));
    });
  });

  // ===========================================================================
  // sRGB ↔ XYZ
  // ===========================================================================

  group('ColorSpaceConverter - XYZ', () {
    test('white sRGB to XYZ is D65 white point', () {
      final xyz = ColorSpaceConverter.srgbToXyz(1, 1, 1);
      expect(xyz.y, closeTo(1.0, 0.05));
    });

    test('black sRGB to XYZ is origin', () {
      final xyz = ColorSpaceConverter.srgbToXyz(0, 0, 0);
      expect(xyz.x, closeTo(0, 0.001));
      expect(xyz.y, closeTo(0, 0.001));
      expect(xyz.z, closeTo(0, 0.001));
    });

    test('sRGB ↔ XYZ round-trips', () {
      final xyz = ColorSpaceConverter.srgbToXyz(0.5, 0.3, 0.7);
      final rgb = ColorSpaceConverter.xyzToSrgb(xyz.x, xyz.y, xyz.z);
      expect(rgb.r, closeTo(0.5, 0.02));
      expect(rgb.g, closeTo(0.3, 0.02));
      expect(rgb.b, closeTo(0.7, 0.02));
    });
  });

  // ===========================================================================
  // sRGB ↔ Lab
  // ===========================================================================

  group('ColorSpaceConverter - Lab', () {
    test('white has L=100', () {
      final lab = ColorSpaceConverter.srgbToLab(1, 1, 1);
      expect(lab.l, closeTo(100, 1));
    });

    test('black has L=0', () {
      final lab = ColorSpaceConverter.srgbToLab(0, 0, 0);
      expect(lab.l, closeTo(0, 1));
    });

    test('sRGB ↔ Lab round-trips', () {
      final lab = ColorSpaceConverter.srgbToLab(0.8, 0.2, 0.5);
      final rgb = ColorSpaceConverter.labToSrgb(lab.l, lab.a, lab.b);
      expect(rgb.r, closeTo(0.8, 0.02));
      expect(rgb.g, closeTo(0.2, 0.02));
    });
  });

  // ===========================================================================
  // sRGB ↔ CMYK
  // ===========================================================================

  group('ColorSpaceConverter - CMYK', () {
    test('pure red has zero cyan', () {
      final cmyk = ColorSpaceConverter.srgbToCmyk(1, 0, 0);
      expect(cmyk.c, closeTo(0, 0.01));
    });

    test('black has K=1', () {
      final cmyk = ColorSpaceConverter.srgbToCmyk(0, 0, 0);
      expect(cmyk.k, closeTo(1, 0.01));
    });

    test('sRGB ↔ CMYK round-trips', () {
      final cmyk = ColorSpaceConverter.srgbToCmyk(0.6, 0.4, 0.8);
      final rgb = ColorSpaceConverter.cmykToSrgb(
        cmyk.c,
        cmyk.m,
        cmyk.y,
        cmyk.k,
      );
      expect(rgb.r, closeTo(0.6, 0.02));
      expect(rgb.g, closeTo(0.4, 0.02));
    });
  });

  // ===========================================================================
  // ΔE (perceptual distance)
  // ===========================================================================

  group('ColorSpaceConverter - deltaE', () {
    test('identical colors have zero deltaE', () {
      final de = ColorSpaceConverter.deltaE(0.5, 0.5, 0.5, 0.5, 0.5, 0.5);
      expect(de, closeTo(0, 0.01));
    });

    test('different colors have positive deltaE', () {
      final de = ColorSpaceConverter.deltaE(1, 0, 0, 0, 1, 0);
      expect(de, greaterThan(0));
    });
  });

  // ===========================================================================
  // LabColor
  // ===========================================================================

  group('LabColor', () {
    test('deltaE between same is zero', () {
      const a = LabColor(50, 0, 0);
      const b = LabColor(50, 0, 0);
      expect(a.deltaE(b), closeTo(0, 0.01));
    });

    test('toString is readable', () {
      const lab = LabColor(50, 10, -20);
      expect(lab.toString(), isNotEmpty);
    });
  });

  // ===========================================================================
  // Color tuples
  // ===========================================================================

  group('Color tuples', () {
    test('XyzColor toString', () {
      const xyz = XyzColor(0.5, 0.5, 0.5);
      expect(xyz.toString(), isNotEmpty);
    });

    test('CmykColor toString', () {
      const cmyk = CmykColor(0.1, 0.2, 0.3, 0.4);
      expect(cmyk.toString(), isNotEmpty);
    });

    test('RgbColor toString', () {
      const rgb = RgbColor(0.5, 0.5, 0.5);
      expect(rgb.toString(), isNotEmpty);
    });
  });
}
