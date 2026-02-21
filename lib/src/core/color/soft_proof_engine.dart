/// 🎨 SOFT PROOF ENGINE — Print output simulation.
///
/// Simulates how colors will appear when printed by applying
/// CMYK gamut constraints, paper white shifts, and ink density models.
///
/// ```dart
/// final engine = SoftProofEngine(
///   profile: PrintProfile.coatedFogra39,
/// );
/// final proofed = engine.proof(0.8, 0.2, 0.3);
/// print('Print preview: ${proofed.r}, ${proofed.g}, ${proofed.b}');
/// ```
library;

import 'dart:math' as math;

import 'color_space_converter.dart';

// =============================================================================
// RENDERING INTENT
// =============================================================================

/// ICC rendering intent for gamut mapping.
enum RenderingIntent {
  /// Compress entire gamut proportionally (best for photos).
  perceptual,

  /// Map white point, clip out-of-gamut (best for brand colors).
  relativeColorimetric,

  /// Maximize saturation, may shift hue (best for graphics).
  saturation,

  /// No white point mapping, clip out-of-gamut (proofing only).
  absoluteColorimetric,
}

// =============================================================================
// PRINT PROFILE
// =============================================================================

/// Simulated print profile with ink and paper characteristics.
class PrintProfile {
  /// Profile identifier.
  final String id;

  /// Human-readable name.
  final String name;

  /// Paper white point as sRGB (1.0 = pure white).
  final double paperWhiteR, paperWhiteG, paperWhiteB;

  /// Maximum ink density (0–1). Lower = lighter print.
  final double maxInkDensity;

  /// Total ink limit as percentage (e.g. 300 = 300% max CMYK total).
  final double totalInkLimit;

  /// Dot gain simulation (0 = none, 0.2 = 20% gain).
  final double dotGain;

  const PrintProfile({
    required this.id,
    required this.name,
    this.paperWhiteR = 0.95,
    this.paperWhiteG = 0.93,
    this.paperWhiteB = 0.88,
    this.maxInkDensity = 0.95,
    this.totalInkLimit = 3.0,
    this.dotGain = 0.15,
  });

  /// Coated paper (FOGRA39 approximation).
  static const coatedFogra39 = PrintProfile(
    id: 'coated_fogra39',
    name: 'Coated FOGRA39',
    paperWhiteR: 0.95,
    paperWhiteG: 0.93,
    paperWhiteB: 0.90,
    maxInkDensity: 0.95,
    totalInkLimit: 3.2,
    dotGain: 0.12,
  );

  /// Uncoated paper (FOGRA47 approximation).
  static const uncatedFogra47 = PrintProfile(
    id: 'uncoated_fogra47',
    name: 'Uncoated FOGRA47',
    paperWhiteR: 0.92,
    paperWhiteG: 0.90,
    paperWhiteB: 0.85,
    maxInkDensity: 0.85,
    totalInkLimit: 2.8,
    dotGain: 0.22,
  );

  /// Newsprint (low quality).
  static const newsprint = PrintProfile(
    id: 'newsprint',
    name: 'Newsprint',
    paperWhiteR: 0.85,
    paperWhiteG: 0.82,
    paperWhiteB: 0.75,
    maxInkDensity: 0.70,
    totalInkLimit: 2.4,
    dotGain: 0.30,
  );

  @override
  String toString() => 'PrintProfile($name)';
}

// =============================================================================
// PROOF RESULT
// =============================================================================

/// Result of soft-proofing a color.
class ProofResult {
  /// Simulated sRGB output (0–1 per channel).
  final double r, g, b;

  /// Whether the original color was within the print gamut.
  final bool inGamut;

  /// The CMYK values used for proofing.
  final CmykColor cmyk;

  const ProofResult({
    required this.r,
    required this.g,
    required this.b,
    required this.inGamut,
    required this.cmyk,
  });

  @override
  String toString() =>
      'ProofResult(${inGamut ? "in-gamut" : "OUT-OF-GAMUT"}, '
      'RGB(${(r * 255).round()}, ${(g * 255).round()}, ${(b * 255).round()}))';
}

// =============================================================================
// SOFT PROOF ENGINE
// =============================================================================

/// Simulates print output for soft-proofing workflows.
class SoftProofEngine {
  /// The print profile to simulate.
  final PrintProfile profile;

  /// Rendering intent for gamut mapping.
  final RenderingIntent intent;

  const SoftProofEngine({
    this.profile = PrintProfile.coatedFogra39,
    this.intent = RenderingIntent.relativeColorimetric,
  });

  /// Proof a single sRGB color.
  ProofResult proof(double r, double g, double b) {
    // 1. Convert to CMYK
    var cmyk = ColorSpaceConverter.srgbToCmyk(r, g, b);

    // 2. Apply total ink limit
    final totalInk = cmyk.c + cmyk.m + cmyk.y + cmyk.k;
    if (totalInk > profile.totalInkLimit) {
      final scale = profile.totalInkLimit / totalInk;
      cmyk = CmykColor(
        cmyk.c * scale,
        cmyk.m * scale,
        cmyk.y * scale,
        cmyk.k * scale,
      );
    }

    // 3. Apply dot gain (ink spread simulation)
    final adjustedCmyk = _applyDotGain(cmyk);

    // 4. Apply max ink density
    final densityCmyk = CmykColor(
      adjustedCmyk.c * profile.maxInkDensity,
      adjustedCmyk.m * profile.maxInkDensity,
      adjustedCmyk.y * profile.maxInkDensity,
      adjustedCmyk.k * profile.maxInkDensity,
    );

    // 5. Convert back to RGB
    final rgb = ColorSpaceConverter.cmykToSrgb(
      densityCmyk.c,
      densityCmyk.m,
      densityCmyk.y,
      densityCmyk.k,
    );

    // 6. Apply paper white simulation
    final proofedR = rgb.r * profile.paperWhiteR;
    final proofedG = rgb.g * profile.paperWhiteG;
    final proofedB = rgb.b * profile.paperWhiteB;

    // 7. Apply rendering intent adjustments
    final (finalR, finalG, finalB) = _applyIntent(
      proofedR,
      proofedG,
      proofedB,
      r,
      g,
      b,
    );

    // 8. Check gamut — colors that change significantly are out of gamut
    final de = ColorSpaceConverter.deltaE(r, g, b, finalR, finalG, finalB);
    final inGamut = de < 5.0;

    return ProofResult(
      r: finalR.clamp(0.0, 1.0),
      g: finalG.clamp(0.0, 1.0),
      b: finalB.clamp(0.0, 1.0),
      inGamut: inGamut,
      cmyk: cmyk,
    );
  }

  /// Proof a batch of colors.
  List<ProofResult> proofBatch(List<RgbColor> colors) {
    return colors.map((c) => proof(c.r, c.g, c.b)).toList();
  }

  /// Check if a color is within the print gamut (without full proofing).
  bool isInGamut(double r, double g, double b) {
    return proof(r, g, b).inGamut;
  }

  /// Apply dot gain (ink spread on paper).
  CmykColor _applyDotGain(CmykColor cmyk) {
    final gain = profile.dotGain;
    return CmykColor(
      _dotGainCurve(cmyk.c, gain),
      _dotGainCurve(cmyk.m, gain),
      _dotGainCurve(cmyk.y, gain),
      _dotGainCurve(cmyk.k, gain),
    );
  }

  /// Murray-Davies dot gain model.
  static double _dotGainCurve(double value, double gain) {
    if (value <= 0 || value >= 1) return value;
    // Simplified: dot gain is strongest at ~50% coverage
    final gainAmount = gain * 4.0 * value * (1.0 - value);
    return (value + gainAmount).clamp(0.0, 1.0);
  }

  /// Apply rendering intent adjustments.
  (double, double, double) _applyIntent(
    double proofR,
    double proofG,
    double proofB,
    double origR,
    double origG,
    double origB,
  ) {
    switch (intent) {
      case RenderingIntent.perceptual:
        // Compress gamut proportionally
        return (proofR, proofG, proofB);

      case RenderingIntent.relativeColorimetric:
        // Already mapped relative to paper white
        return (proofR, proofG, proofB);

      case RenderingIntent.saturation:
        // Boost saturation slightly to preserve vividness
        final avgProof = (proofR + proofG + proofB) / 3.0;
        const boost = 1.1;
        return (
          (avgProof + (proofR - avgProof) * boost).clamp(0.0, 1.0),
          (avgProof + (proofG - avgProof) * boost).clamp(0.0, 1.0),
          (avgProof + (proofB - avgProof) * boost).clamp(0.0, 1.0),
        );

      case RenderingIntent.absoluteColorimetric:
        // No white point mapping — use paper white directly
        return (proofR, proofG, proofB);
    }
  }
}
