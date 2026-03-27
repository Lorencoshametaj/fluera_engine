import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// 🎨 Phase 4D: Color Management — Wide-Gamut & HSL Mixing
///
/// Provides:
/// - HSL-based color mixing (more natural than RGB lerp)
/// - Display P3 gamut awareness
/// - Color harmony utilities
/// - High-precision color storage for wide-gamut workflows
class ColorManager {
  ColorManager._(); // Non-instantiable utility

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // WIDE-GAMUT P3 SUPPORT
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Whether the current device supports wide-gamut (Display P3) colors.
  /// On most modern iOS devices and some Android devices this returns true.
  static bool get isWideGamutSupported {
    // Flutter's Color class supports P3 since 3.10+ via the
    // color spaces API. Check by trying to create a P3 color.
    try {
      final testColor = Color.from(
        alpha: 1.0,
        red: 1.0,
        green: 0.0,
        blue: 0.0,
        colorSpace: ui.ColorSpace.displayP3,
      );
      return testColor.colorSpace == ui.ColorSpace.displayP3;
    } catch (_) {
      return false;
    }
  }

  /// Convert an sRGB Color to Display P3 color space.
  /// If P3 is not supported, returns the original color.
  static Color toDisplayP3(Color srgbColor) {
    if (!isWideGamutSupported) return srgbColor;

    return Color.from(
      alpha: srgbColor.a,
      red: srgbColor.r,
      green: srgbColor.g,
      blue: srgbColor.b,
      colorSpace: ui.ColorSpace.displayP3,
    );
  }

  /// Convert a P3 Color back to sRGB.
  static Color toSRGB(Color p3Color) {
    return Color.from(
      alpha: p3Color.a,
      red: p3Color.r.clamp(0.0, 1.0),
      green: p3Color.g.clamp(0.0, 1.0),
      blue: p3Color.b.clamp(0.0, 1.0),
      colorSpace: ui.ColorSpace.sRGB,
    );
  }

  /// Check if a color is within sRGB gamut
  static bool isWithinSRGB(Color color) {
    return color.r >= 0.0 &&
        color.r <= 1.0 &&
        color.g >= 0.0 &&
        color.g <= 1.0 &&
        color.b >= 0.0 &&
        color.b <= 1.0;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // HSL MIXING
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Mix two colors in HSL space at ratio [t] (0 = color a, 1 = color b).
  /// This produces more natural/pleasing blends than RGB lerp,
  /// especially for complementary colors.
  static Color mixColorsHSL(Color a, Color b, double t) {
    final hslA = HSLColor.fromColor(a);
    final hslB = HSLColor.fromColor(b);

    // Handle hue interpolation via shortest arc
    final hueA = hslA.hue;
    final hueB = hslB.hue;
    double hueDiff = hueB - hueA;

    // Take shortest path around the hue wheel
    if (hueDiff > 180) hueDiff -= 360;
    if (hueDiff < -180) hueDiff += 360;

    final mixedHue = (hueA + hueDiff * t) % 360;
    final mixedSat = _lerpDouble(hslA.saturation, hslB.saturation, t);
    final mixedLight = _lerpDouble(hslA.lightness, hslB.lightness, t);
    final mixedAlpha = _lerpDouble(a.a, b.a, t);

    return HSLColor.fromAHSL(
      mixedAlpha,
      mixedHue < 0 ? mixedHue + 360 : mixedHue,
      mixedSat,
      mixedLight,
    ).toColor();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // COLOR HARMONIES
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Generate complementary color
  static Color complementary(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withHue((hsl.hue + 180) % 360).toColor();
  }

  /// Generate analogous colors (±30° on hue wheel)
  static List<Color> analogous(Color color) {
    final hsl = HSLColor.fromColor(color);
    return [
      hsl.withHue((hsl.hue - 30) % 360).toColor(),
      color,
      hsl.withHue((hsl.hue + 30) % 360).toColor(),
    ];
  }

  /// Generate triadic colors (120° apart)
  static List<Color> triadic(Color color) {
    final hsl = HSLColor.fromColor(color);
    return [
      color,
      hsl.withHue((hsl.hue + 120) % 360).toColor(),
      hsl.withHue((hsl.hue + 240) % 360).toColor(),
    ];
  }

  /// Generate split-complementary colors
  static List<Color> splitComplementary(Color color) {
    final hsl = HSLColor.fromColor(color);
    return [
      hsl.withHue((hsl.hue + 150) % 360).toColor(),
      color,
      hsl.withHue((hsl.hue + 210) % 360).toColor(),
    ];
  }

  /// Generate tetradic (square) colors (90° apart)
  static List<Color> tetradic(Color color) {
    final hsl = HSLColor.fromColor(color);
    return [
      color,
      hsl.withHue((hsl.hue + 90) % 360).toColor(),
      hsl.withHue((hsl.hue + 180) % 360).toColor(),
      hsl.withHue((hsl.hue + 270) % 360).toColor(),
    ];
  }

  /// Generate monochromatic variations (same hue, varying lightness/saturation)
  static List<Color> monochromatic(Color color) {
    final hsl = HSLColor.fromColor(color);
    return [
      hsl.withLightness((hsl.lightness * 0.3).clamp(0.05, 0.95))
          .withSaturation((hsl.saturation * 1.2).clamp(0.0, 1.0)).toColor(),
      hsl.withLightness((hsl.lightness * 0.6).clamp(0.05, 0.95)).toColor(),
      color,
      hsl.withLightness((hsl.lightness * 1.3).clamp(0.05, 0.95)).toColor(),
      hsl.withLightness((hsl.lightness * 1.6).clamp(0.05, 0.95))
          .withSaturation((hsl.saturation * 0.7).clamp(0.0, 1.0)).toColor(),
    ];
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // HIGH-PRECISION SERIALIZATION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Serialize a color with full precision (for wide-gamut storage).
  /// Standard Color.value only stores 8-bit per channel.
  /// This stores floating-point ARGB for P3 fidelity.
  static Map<String, dynamic> colorToHighPrecisionJson(Color color) {
    return {
      'a': _round4(color.a),
      'r': _round4(color.r),
      'g': _round4(color.g),
      'b': _round4(color.b),
      if (color.colorSpace == ui.ColorSpace.displayP3) 'p3': true,
    };
  }

  /// Deserialize a high-precision color
  static Color colorFromHighPrecisionJson(Map<String, dynamic> json) {
    final isP3 = json['p3'] == true;
    return Color.from(
      alpha: (json['a'] as num?)?.toDouble() ?? 1.0,
      red: (json['r'] as num?)?.toDouble() ?? 0.0,
      green: (json['g'] as num?)?.toDouble() ?? 0.0,
      blue: (json['b'] as num?)?.toDouble() ?? 0.0,
      colorSpace: isP3 ? ui.ColorSpace.displayP3 : ui.ColorSpace.sRGB,
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // UTILITIES
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Get a readable name for a color (for UI labels)
  static String colorName(Color color) {
    final hsl = HSLColor.fromColor(color);

    if (hsl.saturation < 0.1) {
      if (hsl.lightness < 0.2) return 'Black';
      if (hsl.lightness > 0.8) return 'White';
      return 'Gray';
    }

    final hue = hsl.hue;
    if (hue < 15 || hue >= 345) return 'Red';
    if (hue < 45) return 'Orange';
    if (hue < 75) return 'Yellow';
    if (hue < 150) return 'Green';
    if (hue < 195) return 'Cyan';
    if (hue < 255) return 'Blue';
    if (hue < 285) return 'Purple';
    if (hue < 345) return 'Pink';
    return 'Red';
  }

  /// Calculatate perceived brightness (ITU-R BT.709)
  static double perceivedBrightness(Color color) {
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
  }

  /// Suggest a text color (black or white) for contrast against background
  static Color contrastingTextColor(Color background) {
    return perceivedBrightness(background) > 0.5
        ? Colors.black87
        : Colors.white;
  }

  // ───── Private helpers ─────

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  static double _round4(double value) =>
      (value * 10000).roundToDouble() / 10000;
}
