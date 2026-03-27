import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/models/color_adjustments.dart';
import '../core/models/gradient_filter.dart';
import '../core/models/perspective_settings.dart';
import '../core/models/tone_curve.dart';
import 'native/image/lut_presets.dart';

// =============================================================================
// 🎨 IMAGE ADJUSTMENT ENGINE — Single Source of Truth
//
// Shared rendering logic for color matrices, overlays, and transforms.
// Used by both PreviewPainter (editor) and ImagePainter (canvas).
// Eliminates the DRY violation of duplicated _getColorMatrix methods.
// =============================================================================

class ImageAdjustmentEngine {
  ImageAdjustmentEngine._();

  /// Static buffer to avoid per-frame allocation (5×4 matrix = 20 doubles)
  static final _buffer = List<double>.filled(20, 0);

  // ─── Color Matrix ───────────────────────────────────────────────────

  /// Compute the full 5×4 color matrix from color adjustments.
  /// This is the single source of truth — no more duplicated logic.
  ///
  /// Includes: brightness, contrast, saturation, temperature, highlights,
  /// shadows, fade, split toning, clarity, hue shift, tone curve, and LUT.
  static List<double> computeColorMatrix(
    ColorAdjustments adj, {
    ToneCurve toneCurve = const ToneCurve(),
    int lutIndex = -1,
  }) {
    final b = adj.brightness * 255;
    final c = adj.contrast + 1.0;
    final t = (1.0 - c) / 2.0 * 255;
    final s = adj.saturation + 1.0;
    const lumR = 0.3086;
    const lumG = 0.6094;
    const lumB = 0.0820;
    final sr = (1.0 - s) * lumR;
    final sg = (1.0 - s) * lumG;
    final sb = (1.0 - s) * lumB;

    // Base saturation + brightness + contrast matrix
    double r0 = (sr + s) * c, r1 = sg * c, r2 = sb * c, r4 = b + t;
    double g0 = sr * c, g1 = (sg + s) * c, g2 = sb * c, g4 = b + t;
    double b0 = sr * c, b1 = sg * c, b2 = (sb + s) * c, b4 = b + t;

    // Temperature tint (warm = +red +green -blue, cool = -red +blue)
    if (adj.temperature != 0) {
      final temp = adj.temperature * 30;
      r4 += temp;
      g4 += temp * 0.4;
      b4 -= temp;
    }

    // Highlights: brighten the light areas
    if (adj.highlights != 0) {
      final h = adj.highlights * 20;
      r4 += h;
      g4 += h;
      b4 += h * 0.8;
    }

    // Shadows: modulate dark area density
    if (adj.shadows != 0) {
      final sh = 1.0 + adj.shadows * 0.3;
      r0 *= sh;
      g1 *= sh;
      b2 *= sh;
    }

    // Fade: lift blacks (cinematic faded look)
    if (adj.fade > 0) {
      final lift = adj.fade * 40;
      r4 += lift;
      g4 += lift;
      b4 += lift;
      final comp = 1.0 - adj.fade * 0.15;
      r0 *= comp;
      r1 *= comp;
      r2 *= comp;
      g0 *= comp;
      g1 *= comp;
      g2 *= comp;
      b0 *= comp;
      b1 *= comp;
      b2 *= comp;
    }

    // Split toning: tint highlights and shadows
    if (adj.splitHighlightColor != 0) {
      final hc = Color(adj.splitHighlightColor);
      r4 += (hc.r * 255 - 128) * 0.15;
      g4 += (hc.g * 255 - 128) * 0.15;
      b4 += (hc.b * 255 - 128) * 0.15;
    }
    if (adj.splitShadowColor != 0) {
      final sc = Color(adj.splitShadowColor);
      r0 *= 1.0 + (sc.r - 0.5) * 0.25;
      g1 *= 1.0 + (sc.g - 0.5) * 0.25;
      b2 *= 1.0 + (sc.b - 0.5) * 0.25;
    }

    // Clarity: midtone contrast
    if (adj.clarity != 0) {
      final cl = 1.0 + adj.clarity * 0.4;
      r0 *= cl;
      g1 *= cl;
      b2 *= cl;
      final offset = (1.0 - cl) * 128;
      r4 += offset;
      g4 += offset;
      b4 += offset;
    }

    // Hue rotation via Rodrigues' formula
    if (adj.hueShift != 0) {
      final angle = adj.hueShift * math.pi;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      const k = 1.0 / 3.0;
      const sq = 0.57735; // 1/sqrt(3)
      final m00 = cosA + (1 - cosA) * k;
      final m01 = k * (1 - cosA) - sq * sinA;
      final m02 = k * (1 - cosA) + sq * sinA;
      final m10 = k * (1 - cosA) + sq * sinA;
      final m11 = cosA + (1 - cosA) * k;
      final m12 = k * (1 - cosA) - sq * sinA;
      final m20 = k * (1 - cosA) - sq * sinA;
      final m21 = k * (1 - cosA) + sq * sinA;
      final m22 = cosA + (1 - cosA) * k;
      final nr0 = m00 * r0 + m01 * g0 + m02 * b0;
      final nr1 = m00 * r1 + m01 * g1 + m02 * b1;
      final nr2 = m00 * r2 + m01 * g2 + m02 * b2;
      final ng0 = m10 * r0 + m11 * g0 + m12 * b0;
      final ng1 = m10 * r1 + m11 * g1 + m12 * b1;
      final ng2 = m10 * r2 + m11 * g2 + m12 * b2;
      final nb0 = m20 * r0 + m21 * g0 + m22 * b0;
      final nb1 = m20 * r1 + m21 * g1 + m22 * b1;
      final nb2 = m20 * r2 + m21 * g2 + m22 * b2;
      r0 = nr0;
      r1 = nr1;
      r2 = nr2;
      g0 = ng0;
      g1 = ng1;
      g2 = ng2;
      b0 = nb0;
      b1 = nb1;
      b2 = nb2;
    }

    // Fill buffer
    _buffer[0] = r0;
    _buffer[1] = r1;
    _buffer[2] = r2;
    _buffer[3] = 0;
    _buffer[4] = r4;
    _buffer[5] = g0;
    _buffer[6] = g1;
    _buffer[7] = g2;
    _buffer[8] = 0;
    _buffer[9] = g4;
    _buffer[10] = b0;
    _buffer[11] = b1;
    _buffer[12] = b2;
    _buffer[13] = 0;
    _buffer[14] = b4;
    _buffer[15] = 0;
    _buffer[16] = 0;
    _buffer[17] = 0;
    _buffer[18] = 1;
    _buffer[19] = 0;

    // Compose tone curve
    if (!toneCurve.isIdentity) {
      final tc = toneCurve.toColorMatrix();
      final result = List<double>.filled(20, 0);
      for (int row = 0; row < 4; row++) {
        for (int col = 0; col < 5; col++) {
          double sum = 0;
          for (int k = 0; k < 4; k++) {
            sum += tc[row * 5 + k] * _buffer[k * 5 + col];
          }
          if (col == 4) sum += tc[row * 5 + 4];
          result[row * 5 + col] = sum;
        }
      }
      for (int i = 0; i < 20; i++) _buffer[i] = result[i];
    }

    // Compose LUT approximation
    if (lutIndex > 0 && lutIndex <= lutPresets.length) {
      final lut = lutPresets[lutIndex - 1].approximateColorMatrix;
      final result = List<double>.filled(20, 0);
      for (int row = 0; row < 4; row++) {
        for (int col = 0; col < 5; col++) {
          double sum = 0;
          for (int k = 0; k < 4; k++) {
            sum += lut[row * 5 + k] * _buffer[k * 5 + col];
          }
          if (col == 4) sum += lut[row * 5 + 4];
          result[row * 5 + col] = sum;
        }
      }
      for (int i = 0; i < 20; i++) _buffer[i] = result[i];
    }

    return _buffer;
  }

  /// Whether the color matrix would be non-identity.
  static bool needsColorMatrix(
    ColorAdjustments adj,
    ToneCurve curve,
    int lutIndex,
  ) => !adj.isDefault || !curve.isIdentity || lutIndex > 0;

  // ─── Gradient Filter ────────────────────────────────────────────────

  /// Draw a gradient filter overlay on the canvas.
  static void drawGradientOverlay(
    Canvas canvas,
    Rect rect,
    GradientFilter filter,
  ) {
    if (!filter.isActive) return;
    final angleRad = filter.angle * math.pi / 180;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    final center = rect.center;
    final halfLen = rect.longestSide;
    final start = Offset(
      center.dx - cosA * halfLen,
      center.dy - sinA * halfLen,
    );
    final end = Offset(center.dx + cosA * halfLen, center.dy + sinA * halfLen);
    final gc = Color(filter.color);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          start,
          end,
          [
            gc.withValues(alpha: filter.strength * (1.0 - filter.position)),
            gc.withValues(alpha: 0),
          ],
          [0.0, 1.0],
        ),
    );
  }

  // ─── Noise Reduction ───────────────────────────────────────────────

  /// Apply soft blur overlay for noise reduction.
  static void drawNoiseReduction(
    Canvas canvas,
    ui.Image image,
    Rect srcRect,
    Rect dstRect,
    double strength,
  ) {
    if (strength <= 0) return;
    final sigma = strength * 3.0;
    canvas.saveLayer(
      dstRect,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        )
        ..color = Color.fromRGBO(255, 255, 255, strength * 0.5),
    );
    canvas.drawImageRect(
      image,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  // ─── Perspective Transform ─────────────────────────────────────────

  /// Apply perspective correction (keystone) to the canvas.
  static void applyPerspective(Canvas canvas, PerspectiveSettings settings) {
    if (!settings.isActive) return;
    canvas.transform(settings.toMatrix4().storage);
  }
}
