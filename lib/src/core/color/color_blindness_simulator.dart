/// 🎨 COLOR BLINDNESS SIMULATOR — Accessibility color vision simulation.
///
/// Simulates how colors appear to people with various types of
/// color vision deficiency using Brettel/Viénot 3×3 matrices.
///
/// ```dart
/// final sim = ColorBlindnessSimulator();
/// final result = sim.simulate(
///   0.8, 0.2, 0.3, // sRGB input
///   ColorBlindnessType.protanopia,
/// );
/// print('Simulated: R=${result.r}, G=${result.g}, B=${result.b}');
/// ```
library;

import 'dart:math' as math;

import 'color_space_converter.dart';

// =============================================================================
// COLOR BLINDNESS TYPE
// =============================================================================

/// Types of color vision deficiency.
enum ColorBlindnessType {
  /// No red cones (L-cone absent). ~1% of males.
  protanopia,

  /// No green cones (M-cone absent). ~1% of males.
  deuteranopia,

  /// No blue cones (S-cone absent). Very rare (<0.01%).
  tritanopia,

  /// Total color blindness — luminance only. Extremely rare.
  achromatopsia,

  /// Normal vision (identity transform).
  normal,
}

// =============================================================================
// SIMULATION RESULT
// =============================================================================

/// Result of a color blindness simulation.
class SimulatedColor {
  /// Simulated sRGB red (0–1).
  final double r;

  /// Simulated sRGB green (0–1).
  final double g;

  /// Simulated sRGB blue (0–1).
  final double b;

  /// The type of simulation applied.
  final ColorBlindnessType type;

  const SimulatedColor(this.r, this.g, this.b, this.type);

  @override
  String toString() =>
      'SimulatedColor(${type.name}: '
      'R=${(r * 255).round()}, G=${(g * 255).round()}, B=${(b * 255).round()})';
}

// =============================================================================
// COLOR BLINDNESS SIMULATOR
// =============================================================================

/// Simulates color vision deficiency.
///
/// Uses Brettel/Viénot 3×3 linear-space matrices for dichromacy
/// simulation. Operates in linear RGB to avoid gamma artifacts.
class ColorBlindnessSimulator {
  const ColorBlindnessSimulator();

  /// Simulate how a color appears under the given deficiency.
  ///
  /// Input: sRGB values in [0, 1].
  SimulatedColor simulate(
    double r,
    double g,
    double b,
    ColorBlindnessType type,
  ) {
    if (type == ColorBlindnessType.normal) {
      return SimulatedColor(r, g, b, type);
    }

    if (type == ColorBlindnessType.achromatopsia) {
      // ITU-R BT.709 luminance
      final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      return SimulatedColor(lum, lum, lum, type);
    }

    // Convert to linear RGB
    final lr = ColorSpaceConverter.srgbToLinear(r);
    final lg = ColorSpaceConverter.srgbToLinear(g);
    final lb = ColorSpaceConverter.srgbToLinear(b);

    // Apply simulation matrix
    final matrix = _matrices[type]!;
    final sr = matrix[0] * lr + matrix[1] * lg + matrix[2] * lb;
    final sg = matrix[3] * lr + matrix[4] * lg + matrix[5] * lb;
    final sb = matrix[6] * lr + matrix[7] * lg + matrix[8] * lb;

    // Convert back to sRGB
    return SimulatedColor(
      ColorSpaceConverter.linearToSrgb(sr.clamp(0.0, 1.0)),
      ColorSpaceConverter.linearToSrgb(sg.clamp(0.0, 1.0)),
      ColorSpaceConverter.linearToSrgb(sb.clamp(0.0, 1.0)),
      type,
    );
  }

  /// Simulate a batch of colors.
  List<SimulatedColor> simulateBatch(
    List<RgbColor> colors,
    ColorBlindnessType type,
  ) {
    return colors.map((c) => simulate(c.r, c.g, c.b, type)).toList();
  }

  /// Get severity description for a CVD type.
  static String severity(ColorBlindnessType type) {
    switch (type) {
      case ColorBlindnessType.protanopia:
        return 'Severe — no red cone response';
      case ColorBlindnessType.deuteranopia:
        return 'Severe — no green cone response';
      case ColorBlindnessType.tritanopia:
        return 'Severe — no blue cone response';
      case ColorBlindnessType.achromatopsia:
        return 'Complete — no color discrimination';
      case ColorBlindnessType.normal:
        return 'Normal — full trichromatic vision';
    }
  }

  /// Check if two colors are distinguishable under a given CVD type.
  ///
  /// Uses CIE76 ΔE with a threshold of 3.0 (just noticeable difference).
  bool areDistinguishable(
    double r1,
    double g1,
    double b1,
    double r2,
    double g2,
    double b2,
    ColorBlindnessType type, {
    double threshold = 3.0,
  }) {
    final sim1 = simulate(r1, g1, b1, type);
    final sim2 = simulate(r2, g2, b2, type);
    final de = ColorSpaceConverter.deltaE(
      sim1.r,
      sim1.g,
      sim1.b,
      sim2.r,
      sim2.g,
      sim2.b,
    );
    return de >= threshold;
  }

  // ── Viénot/Brettel simulation matrices (linear RGB) ──
  // Source: Viénot, Brettel & Mollon (1999)
  static const _matrices = {
    ColorBlindnessType.protanopia: [
      0.152286,
      1.052583,
      -0.204868,
      0.114503,
      0.786281,
      0.099216,
      -0.003882,
      -0.048116,
      1.051998,
    ],
    ColorBlindnessType.deuteranopia: [
      0.367322,
      0.860646,
      -0.227968,
      0.280085,
      0.672501,
      0.047413,
      -0.011820,
      0.042940,
      0.968881,
    ],
    ColorBlindnessType.tritanopia: [
      1.255528,
      -0.076749,
      -0.178779,
      -0.078411,
      0.930809,
      0.147602,
      0.004733,
      0.691367,
      0.303900,
    ],
  };

  /// Prevalence percentage for each type.
  static double prevalence(ColorBlindnessType type) {
    switch (type) {
      case ColorBlindnessType.protanopia:
        return 1.0;
      case ColorBlindnessType.deuteranopia:
        return 1.0;
      case ColorBlindnessType.tritanopia:
        return 0.01;
      case ColorBlindnessType.achromatopsia:
        return 0.003;
      case ColorBlindnessType.normal:
        return 92.0;
    }
  }
}
