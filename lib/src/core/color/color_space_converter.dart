/// 🎨 COLOR SPACE CONVERTER — Multi-space color conversion engine.
///
/// Converts between sRGB, Linear RGB, CIE XYZ, CIE Lab, CMYK, and Adobe RGB
/// using standard illuminant D65 and ICC-compatible matrix transforms.
///
/// ```dart
/// final lab = ColorSpaceConverter.srgbToLab(0.8, 0.2, 0.1);
/// print('L=${lab.l}, a=${lab.a}, b=${lab.b}');
///
/// final cmyk = ColorSpaceConverter.srgbToCmyk(0.8, 0.2, 0.1);
/// ```
library;

import 'dart:math' as math;

// =============================================================================
// COLOR TUPLES
// =============================================================================

/// CIE Lab color (perceptually uniform).
class LabColor {
  /// Lightness (0–100).
  final double l;

  /// Green–red axis (typically -128 to +127).
  final double a;

  /// Blue–yellow axis (typically -128 to +127).
  final double b;

  const LabColor(this.l, this.a, this.b);

  /// Perceptual distance (CIE76 ΔE).
  double deltaE(LabColor other) {
    final dl = l - other.l;
    final da = a - other.a;
    final db = b - other.b;
    return math.sqrt(dl * dl + da * da + db * db);
  }

  @override
  String toString() =>
      'Lab(${l.toStringAsFixed(2)}, ${a.toStringAsFixed(2)}, ${b.toStringAsFixed(2)})';
}

/// CIE XYZ color (device-independent).
class XyzColor {
  final double x, y, z;
  const XyzColor(this.x, this.y, this.z);

  @override
  String toString() =>
      'XYZ(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)}, ${z.toStringAsFixed(4)})';
}

/// CMYK color (subtractive, print).
class CmykColor {
  /// Cyan (0–1).
  final double c;

  /// Magenta (0–1).
  final double m;

  /// Yellow (0–1).
  final double y;

  /// Key/Black (0–1).
  final double k;

  const CmykColor(this.c, this.m, this.y, this.k);

  @override
  String toString() =>
      'CMYK(${(c * 100).toStringAsFixed(0)}%, ${(m * 100).toStringAsFixed(0)}%, '
      '${(y * 100).toStringAsFixed(0)}%, ${(k * 100).toStringAsFixed(0)}%)';
}

/// Simple RGB tuple (0–1 per channel).
class RgbColor {
  final double r, g, b;
  const RgbColor(this.r, this.g, this.b);

  @override
  String toString() =>
      'RGB(${(r * 255).round()}, ${(g * 255).round()}, ${(b * 255).round()})';
}

// =============================================================================
// COLOR SPACE CONVERTER
// =============================================================================

/// Converts between color spaces using standard illuminant D65.
class ColorSpaceConverter {
  const ColorSpaceConverter._();

  // ── D65 reference white ──
  static const _d65X = 0.95047;
  static const _d65Y = 1.00000;
  static const _d65Z = 1.08883;

  // ── Lab constants ──
  static const _epsilon = 0.008856; // (6/29)^3
  static const _kappa = 903.3; // (29/3)^3

  // =========================================================================
  // sRGB ↔ LINEAR RGB
  // =========================================================================

  /// sRGB gamma to linear (inverse companding).
  static double srgbToLinear(double c) {
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  /// Linear to sRGB gamma (companding).
  static double linearToSrgb(double c) {
    return c <= 0.0031308
        ? c * 12.92
        : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
  }

  // =========================================================================
  // sRGB ↔ XYZ (via linear RGB)
  // =========================================================================

  /// sRGB → CIE XYZ (D65).
  static XyzColor srgbToXyz(double r, double g, double b) {
    final lr = srgbToLinear(r);
    final lg = srgbToLinear(g);
    final lb = srgbToLinear(b);

    return XyzColor(
      0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb,
      0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb,
      0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb,
    );
  }

  /// CIE XYZ → sRGB.
  static RgbColor xyzToSrgb(double x, double y, double z) {
    final lr = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
    final lg = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
    final lb = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;

    return RgbColor(
      linearToSrgb(lr).clamp(0.0, 1.0),
      linearToSrgb(lg).clamp(0.0, 1.0),
      linearToSrgb(lb).clamp(0.0, 1.0),
    );
  }

  // =========================================================================
  // XYZ ↔ Lab
  // =========================================================================

  /// CIE XYZ → CIE Lab (D65).
  static LabColor xyzToLab(double x, double y, double z) {
    final fx = _labF(x / _d65X);
    final fy = _labF(y / _d65Y);
    final fz = _labF(z / _d65Z);

    return LabColor(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz));
  }

  /// CIE Lab → CIE XYZ (D65).
  static XyzColor labToXyz(double l, double a, double b) {
    final fy = (l + 16.0) / 116.0;
    final fx = a / 500.0 + fy;
    final fz = fy - b / 200.0;

    return XyzColor(
      _d65X * _labFInv(fx),
      _d65Y * _labFInv(fy),
      _d65Z * _labFInv(fz),
    );
  }

  static double _labF(double t) {
    return t > _epsilon
        ? math.pow(t, 1.0 / 3.0).toDouble()
        : (_kappa * t + 16.0) / 116.0;
  }

  static double _labFInv(double t) {
    final t3 = t * t * t;
    return t3 > _epsilon ? t3 : (116.0 * t - 16.0) / _kappa;
  }

  // =========================================================================
  // sRGB ↔ Lab (convenience)
  // =========================================================================

  /// sRGB → CIE Lab.
  static LabColor srgbToLab(double r, double g, double b) {
    final xyz = srgbToXyz(r, g, b);
    return xyzToLab(xyz.x, xyz.y, xyz.z);
  }

  /// CIE Lab → sRGB.
  static RgbColor labToSrgb(double l, double a, double b) {
    final xyz = labToXyz(l, a, b);
    return xyzToSrgb(xyz.x, xyz.y, xyz.z);
  }

  // =========================================================================
  // sRGB ↔ CMYK (basic)
  // =========================================================================

  /// sRGB → CMYK (formula-based, no ICC profile).
  static CmykColor srgbToCmyk(double r, double g, double b) {
    final k = 1.0 - math.max(r, math.max(g, b));
    if (k >= 1.0) return const CmykColor(0, 0, 0, 1);

    return CmykColor(
      (1.0 - r - k) / (1.0 - k),
      (1.0 - g - k) / (1.0 - k),
      (1.0 - b - k) / (1.0 - k),
      k,
    );
  }

  /// CMYK → sRGB.
  static RgbColor cmykToSrgb(double c, double m, double y, double k) {
    return RgbColor(
      ((1.0 - c) * (1.0 - k)).clamp(0.0, 1.0),
      ((1.0 - m) * (1.0 - k)).clamp(0.0, 1.0),
      ((1.0 - y) * (1.0 - k)).clamp(0.0, 1.0),
    );
  }

  // =========================================================================
  // sRGB ↔ Adobe RGB
  // =========================================================================

  /// sRGB → Adobe RGB (1998).
  static RgbColor srgbToAdobeRgb(double r, double g, double b) {
    // sRGB → XYZ → Adobe RGB
    final xyz = srgbToXyz(r, g, b);

    // XYZ → Adobe RGB linear
    final lr = 2.0413690 * xyz.x - 0.5649464 * xyz.y - 0.3446944 * xyz.z;
    final lg = -0.9692660 * xyz.x + 1.8760108 * xyz.y + 0.0415560 * xyz.z;
    final lb = 0.0134474 * xyz.x - 0.1183897 * xyz.y + 1.0154096 * xyz.z;

    // Adobe RGB gamma = 2.2 (simplified)
    return RgbColor(
      math.pow(lr.clamp(0.0, 1.0), 1.0 / 2.19921875).toDouble(),
      math.pow(lg.clamp(0.0, 1.0), 1.0 / 2.19921875).toDouble(),
      math.pow(lb.clamp(0.0, 1.0), 1.0 / 2.19921875).toDouble(),
    );
  }

  /// Adobe RGB → sRGB.
  static RgbColor adobeRgbToSrgb(double r, double g, double b) {
    // Adobe RGB degamma
    final lr = math.pow(r.clamp(0.0, 1.0), 2.19921875).toDouble();
    final lg = math.pow(g.clamp(0.0, 1.0), 2.19921875).toDouble();
    final lb = math.pow(b.clamp(0.0, 1.0), 2.19921875).toDouble();

    // Adobe RGB linear → XYZ
    final x = 0.5767309 * lr + 0.1855540 * lg + 0.1881852 * lb;
    final y = 0.2973769 * lr + 0.6273491 * lg + 0.0752741 * lb;
    final z = 0.0270343 * lr + 0.0706872 * lg + 0.9911085 * lb;

    return xyzToSrgb(x, y, z);
  }

  // =========================================================================
  // PERCEPTUAL DISTANCE
  // =========================================================================

  /// CIE76 ΔE between two sRGB colors (perceptual distance).
  static double deltaE(
    double r1,
    double g1,
    double b1,
    double r2,
    double g2,
    double b2,
  ) {
    final lab1 = srgbToLab(r1, g1, b1);
    final lab2 = srgbToLab(r2, g2, b2);
    return lab1.deltaE(lab2);
  }
}
