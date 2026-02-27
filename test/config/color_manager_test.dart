import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/config/color_manager.dart';

void main() {
  group('ColorManager', () {
    // ── HSL Mixing ─────────────────────────────────────────────────────

    group('mixColorsHSL', () {
      test('t=0 returns first color', () {
        const a = Colors.red;
        const b = Colors.blue;
        final mixed = ColorManager.mixColorsHSL(a, b, 0.0);
        // Should be very close to red
        expect(
          HSLColor.fromColor(mixed).hue,
          closeTo(HSLColor.fromColor(a).hue, 1.0),
        );
      });

      test('t=1 returns second color', () {
        const a = Colors.red;
        const b = Colors.blue;
        final mixed = ColorManager.mixColorsHSL(a, b, 1.0);
        expect(
          HSLColor.fromColor(mixed).hue,
          closeTo(HSLColor.fromColor(b).hue, 1.0),
        );
      });

      test('t=0.5 produces intermediate hue', () {
        const a = Color(0xFFFF0000); // pure red
        const b = Color(0xFF00FF00); // pure green
        final mixed = ColorManager.mixColorsHSL(a, b, 0.5);
        // Intermediate hue between red (0°) and green (120°) should be ~60° (yellow)
        final hue = HSLColor.fromColor(mixed).hue;
        expect(hue, closeTo(60, 10));
      });

      test('preserves alpha interpolation', () {
        final a = Colors.red.withValues(alpha: 0.2);
        final b = Colors.red.withValues(alpha: 0.8);
        final mixed = ColorManager.mixColorsHSL(a, b, 0.5);
        expect(mixed.a, closeTo(0.5, 0.05));
      });
    });

    // ── Color Harmonies ────────────────────────────────────────────────

    group('complementary', () {
      test('returns color 180° away on hue wheel', () {
        const color = Color(0xFFFF0000); // red ≈ 0°
        final comp = ColorManager.complementary(color);
        final hsl = HSLColor.fromColor(comp);
        // Complementary of red should be ~180° (cyan)
        expect(hsl.hue, closeTo(180, 5));
      });
    });

    group('analogous', () {
      test('returns 3 colors', () {
        final colors = ColorManager.analogous(Colors.blue);
        expect(colors.length, 3);
      });

      test('middle color is the original', () {
        const original = Colors.blue;
        final colors = ColorManager.analogous(original);
        expect(colors[1], equals(original));
      });
    });

    group('triadic', () {
      test('returns 3 colors', () {
        final colors = ColorManager.triadic(Colors.red);
        expect(colors.length, 3);
      });

      test('first color is the original', () {
        const original = Colors.red;
        final colors = ColorManager.triadic(original);
        expect(colors[0], equals(original));
      });

      test('colors are 120° apart', () {
        const original = Color(0xFFFF0000); // red ≈ 0°
        final colors = ColorManager.triadic(original);
        final hues = colors.map((c) => HSLColor.fromColor(c).hue).toList();
        // Second should be ~120°, third ~240°
        expect(hues[1], closeTo(120, 5));
        expect(hues[2], closeTo(240, 5));
      });
    });

    group('splitComplementary', () {
      test('returns 3 colors', () {
        final colors = ColorManager.splitComplementary(Colors.red);
        expect(colors.length, 3);
      });

      test('middle color is the original', () {
        const original = Colors.red;
        final colors = ColorManager.splitComplementary(original);
        expect(colors[1], equals(original));
      });
    });

    // ── High Precision Serialization ───────────────────────────────────

    group('high precision serialization', () {
      test('round-trips sRGB color', () {
        const original = Color(0xFF4488CC);
        final json = ColorManager.colorToHighPrecisionJson(original);
        final restored = ColorManager.colorFromHighPrecisionJson(json);
        expect(restored.r, closeTo(original.r, 0.001));
        expect(restored.g, closeTo(original.g, 0.001));
        expect(restored.b, closeTo(original.b, 0.001));
        expect(restored.a, closeTo(original.a, 0.001));
      });

      test('sRGB json does not include p3 flag', () {
        const srgb = Color(0xFFFF0000);
        final json = ColorManager.colorToHighPrecisionJson(srgb);
        expect(json.containsKey('p3'), isFalse);
      });

      test('fromJson defaults to full alpha when missing', () {
        final json = {'r': 1.0, 'g': 0.0, 'b': 0.0};
        final color = ColorManager.colorFromHighPrecisionJson(json);
        expect(color.a, 1.0);
      });

      test('fromJson defaults to black when channels missing', () {
        final json = <String, dynamic>{};
        final color = ColorManager.colorFromHighPrecisionJson(json);
        expect(color.r, 0.0);
        expect(color.g, 0.0);
        expect(color.b, 0.0);
      });
    });

    // ── Color Naming ───────────────────────────────────────────────────

    group('colorName', () {
      test('names basic colors correctly', () {
        expect(ColorManager.colorName(Colors.red), 'Red');
        expect(ColorManager.colorName(Colors.blue), 'Blue');
        expect(ColorManager.colorName(Colors.green), 'Green');
        expect(ColorManager.colorName(Colors.yellow), 'Yellow');
        expect(ColorManager.colorName(Colors.orange), 'Orange');
        expect(ColorManager.colorName(const Color(0xFF7700FF)), 'Purple');
        expect(ColorManager.colorName(Colors.cyan), 'Cyan');
      });

      test('names black and white', () {
        expect(ColorManager.colorName(Colors.black), 'Black');
        expect(ColorManager.colorName(Colors.white), 'White');
      });

      test('names gray for low saturation', () {
        expect(ColorManager.colorName(Colors.grey), 'Gray');
      });
    });

    // ── Perceived Brightness ───────────────────────────────────────────

    group('perceivedBrightness', () {
      test('white is bright', () {
        final brightness = ColorManager.perceivedBrightness(Colors.white);
        expect(brightness, greaterThan(0.9));
      });

      test('black is dark', () {
        final brightness = ColorManager.perceivedBrightness(Colors.black);
        expect(brightness, closeTo(0.0, 0.01));
      });
    });

    // ── Contrasting Text ───────────────────────────────────────────────

    group('contrastingTextColor', () {
      test('returns dark text for light background', () {
        final text = ColorManager.contrastingTextColor(Colors.white);
        expect(text, Colors.black87);
      });

      test('returns light text for dark background', () {
        final text = ColorManager.contrastingTextColor(Colors.black);
        expect(text, Colors.white);
      });
    });

    // ── sRGB check ─────────────────────────────────────────────────────

    group('isWithinSRGB', () {
      test('standard color is within sRGB', () {
        expect(ColorManager.isWithinSRGB(Colors.red), isTrue);
        expect(ColorManager.isWithinSRGB(Colors.blue), isTrue);
      });
    });
  });
}
