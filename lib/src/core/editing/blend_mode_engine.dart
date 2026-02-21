/// 🔄 BLEND MODE ENGINE — Pixel-level blend mode compositing.
///
/// Implements 16 standard blend modes for compositing layers.
/// Each mode defines how a source pixel combines with a destination pixel.
///
/// ```dart
/// final result = BlendModeEngine.blend(
///   srcR: 0.8, srcG: 0.2, srcB: 0.1, srcA: 1.0,
///   dstR: 0.5, dstG: 0.5, dstB: 0.5, dstA: 1.0,
///   mode: EngineBlendMode.multiply,
/// );
/// ```
library;

import 'dart:math' as math;

// =============================================================================
// BLEND MODE
// =============================================================================

/// Standard blend modes for layer compositing.
enum EngineBlendMode {
  // ── Basic ──
  normal,

  // ── Darken ──
  darken,
  multiply,
  colorBurn,

  // ── Lighten ──
  lighten,
  screen,
  colorDodge,

  // ── Contrast ──
  overlay,
  softLight,
  hardLight,

  // ── Inversion ──
  difference,
  exclusion,

  // ── Component (HSL-based) ──
  hue,
  saturation,
  color,
  luminosity,
}

/// Category grouping for UI display.
enum BlendModeCategory {
  basic,
  darken,
  lighten,
  contrast,
  inversion,
  component,
}

// =============================================================================
// BLENDED PIXEL
// =============================================================================

/// Result of a blend operation.
class BlendedPixel {
  final double r, g, b, a;
  const BlendedPixel(this.r, this.g, this.b, this.a);

  @override
  String toString() =>
      'BlendedPixel(${(r * 255).round()}, ${(g * 255).round()}, '
      '${(b * 255).round()}, ${(a * 100).toStringAsFixed(0)}%)';
}

// =============================================================================
// BLEND MODE ENGINE
// =============================================================================

/// Pixel-level blend mode compositing engine.
class BlendModeEngine {
  const BlendModeEngine._();

  /// Blend source pixel onto destination pixel.
  ///
  /// All values in [0, 1].
  static BlendedPixel blend({
    required double srcR,
    required double srcG,
    required double srcB,
    required double srcA,
    required double dstR,
    required double dstG,
    required double dstB,
    required double dstA,
    required EngineBlendMode mode,
  }) {
    if (srcA <= 0) return BlendedPixel(dstR, dstG, dstB, dstA);

    // Compute blended RGB (before alpha compositing)
    final (br, bg, bb) = _blendChannels(
      srcR,
      srcG,
      srcB,
      dstR,
      dstG,
      dstB,
      mode,
    );

    // Alpha compositing (Porter-Duff src-over)
    final outA = srcA + dstA * (1.0 - srcA);
    if (outA <= 0) return const BlendedPixel(0, 0, 0, 0);

    final outR = (br * srcA + dstR * dstA * (1.0 - srcA)) / outA;
    final outG = (bg * srcA + dstG * dstA * (1.0 - srcA)) / outA;
    final outB = (bb * srcA + dstB * dstA * (1.0 - srcA)) / outA;

    return BlendedPixel(
      outR.clamp(0.0, 1.0),
      outG.clamp(0.0, 1.0),
      outB.clamp(0.0, 1.0),
      outA.clamp(0.0, 1.0),
    );
  }

  /// Blend RGB channels according to mode.
  static (double, double, double) _blendChannels(
    double sr,
    double sg,
    double sb,
    double dr,
    double dg,
    double db,
    EngineBlendMode mode,
  ) {
    switch (mode) {
      case EngineBlendMode.normal:
        return (sr, sg, sb);

      case EngineBlendMode.multiply:
        return (sr * dr, sg * dg, sb * db);

      case EngineBlendMode.screen:
        return (
          1.0 - (1.0 - sr) * (1.0 - dr),
          1.0 - (1.0 - sg) * (1.0 - dg),
          1.0 - (1.0 - sb) * (1.0 - db),
        );

      case EngineBlendMode.overlay:
        return (_overlay(dr, sr), _overlay(dg, sg), _overlay(db, sb));

      case EngineBlendMode.darken:
        return (math.min(sr, dr), math.min(sg, dg), math.min(sb, db));

      case EngineBlendMode.lighten:
        return (math.max(sr, dr), math.max(sg, dg), math.max(sb, db));

      case EngineBlendMode.colorDodge:
        return (_colorDodge(dr, sr), _colorDodge(dg, sg), _colorDodge(db, sb));

      case EngineBlendMode.colorBurn:
        return (_colorBurn(dr, sr), _colorBurn(dg, sg), _colorBurn(db, sb));

      case EngineBlendMode.hardLight:
        return (_overlay(sr, dr), _overlay(sg, dg), _overlay(sb, db));

      case EngineBlendMode.softLight:
        return (_softLight(dr, sr), _softLight(dg, sg), _softLight(db, sb));

      case EngineBlendMode.difference:
        return ((sr - dr).abs(), (sg - dg).abs(), (sb - db).abs());

      case EngineBlendMode.exclusion:
        return (
          sr + dr - 2.0 * sr * dr,
          sg + dg - 2.0 * sg * dg,
          sb + db - 2.0 * sb * db,
        );

      case EngineBlendMode.hue:
        return _setHue(sr, sg, sb, dr, dg, db);

      case EngineBlendMode.saturation:
        return _setSaturation(sr, sg, sb, dr, dg, db);

      case EngineBlendMode.color:
        return _setColor(sr, sg, sb, dr, dg, db);

      case EngineBlendMode.luminosity:
        return _setLuminosity(sr, sg, sb, dr, dg, db);
    }
  }

  // ── Per-channel helpers ──

  static double _overlay(double base, double blend) {
    return base < 0.5
        ? 2.0 * base * blend
        : 1.0 - 2.0 * (1.0 - base) * (1.0 - blend);
  }

  static double _colorDodge(double base, double blend) {
    if (base <= 0) return 0;
    if (blend >= 1) return 1;
    return (base / (1.0 - blend)).clamp(0.0, 1.0);
  }

  static double _colorBurn(double base, double blend) {
    if (base >= 1) return 1;
    if (blend <= 0) return 0;
    return (1.0 - (1.0 - base) / blend).clamp(0.0, 1.0);
  }

  static double _softLight(double base, double blend) {
    if (blend <= 0.5) {
      return base - (1.0 - 2.0 * blend) * base * (1.0 - base);
    } else {
      final d =
          base <= 0.25
              ? ((16.0 * base - 12.0) * base + 4.0) * base
              : math.sqrt(base);
      return base + (2.0 * blend - 1.0) * (d - base);
    }
  }

  // ── Luminosity ──
  static double _lum(double r, double g, double b) =>
      0.3 * r + 0.59 * g + 0.11 * b;

  static (double, double, double) _clipColor(double r, double g, double b) {
    final l = _lum(r, g, b);
    final n = math.min(r, math.min(g, b));
    final x = math.max(r, math.max(g, b));

    var cr = r, cg = g, cb = b;
    if (n < 0) {
      final d = l - n;
      if (d != 0) {
        cr = l + (cr - l) * l / d;
        cg = l + (cg - l) * l / d;
        cb = l + (cb - l) * l / d;
      }
    }
    if (x > 1) {
      final d = x - l;
      if (d != 0) {
        cr = l + (cr - l) * (1.0 - l) / d;
        cg = l + (cg - l) * (1.0 - l) / d;
        cb = l + (cb - l) * (1.0 - l) / d;
      }
    }
    return (cr, cg, cb);
  }

  static (double, double, double) _setLum(
    double r,
    double g,
    double b,
    double l,
  ) {
    final d = l - _lum(r, g, b);
    return _clipColor(r + d, g + d, b + d);
  }

  static double _sat(double r, double g, double b) =>
      math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));

  static (double, double, double) _setHue(
    double sr,
    double sg,
    double sb,
    double dr,
    double dg,
    double db,
  ) => _setLum(sr, sg, sb, _lum(dr, dg, db));

  static (double, double, double) _setSaturation(
    double sr,
    double sg,
    double sb,
    double dr,
    double dg,
    double db,
  ) {
    // Set src saturation on dst, keep dst luminosity
    final dLum = _lum(dr, dg, db);
    final sSat = _sat(sr, sg, sb);
    final dSat = _sat(dr, dg, db);
    if (dSat == 0) return (dr, dg, db);
    final scale = sSat / dSat;
    return _setLum(
      dLum + (dr - dLum) * scale,
      dLum + (dg - dLum) * scale,
      dLum + (db - dLum) * scale,
      dLum,
    );
  }

  static (double, double, double) _setColor(
    double sr,
    double sg,
    double sb,
    double dr,
    double dg,
    double db,
  ) => _setLum(sr, sg, sb, _lum(dr, dg, db));

  static (double, double, double) _setLuminosity(
    double sr,
    double sg,
    double sb,
    double dr,
    double dg,
    double db,
  ) => _setLum(dr, dg, db, _lum(sr, sg, sb));

  /// Get the category of a blend mode.
  static BlendModeCategory categoryOf(EngineBlendMode mode) {
    switch (mode) {
      case EngineBlendMode.normal:
        return BlendModeCategory.basic;
      case EngineBlendMode.darken:
      case EngineBlendMode.multiply:
      case EngineBlendMode.colorBurn:
        return BlendModeCategory.darken;
      case EngineBlendMode.lighten:
      case EngineBlendMode.screen:
      case EngineBlendMode.colorDodge:
        return BlendModeCategory.lighten;
      case EngineBlendMode.overlay:
      case EngineBlendMode.softLight:
      case EngineBlendMode.hardLight:
        return BlendModeCategory.contrast;
      case EngineBlendMode.difference:
      case EngineBlendMode.exclusion:
        return BlendModeCategory.inversion;
      case EngineBlendMode.hue:
      case EngineBlendMode.saturation:
      case EngineBlendMode.color:
      case EngineBlendMode.luminosity:
        return BlendModeCategory.component;
    }
  }

  /// Get all blend modes in a category.
  static List<EngineBlendMode> modesInCategory(BlendModeCategory category) =>
      EngineBlendMode.values.where((m) => categoryOf(m) == category).toList();
}
