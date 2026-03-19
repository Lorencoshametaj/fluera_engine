import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 🌀 Cinematic "Wormhole Dive" transition painter — Premium Edition v2.
///
/// Draws the full dive-into-node animation directly on the canvas — zero
/// widget allocation per frame. Used by both PDF and Image viewer entries.
///
/// ANIMATION PHASES (driven by [t] 0.0→1.0):
///
/// **Phase 1 — Lift-Off (t 0.0→0.15, ~135ms):**
///   Card stays in place but scales to 1.05× with intensifying shadow.
///   Creates anticipation: "I've grabbed this object."
///
/// **Phase 2 — Dive (t 0.15→0.92, ~695ms):**
///   Expanding clip with [easeOutExpo] from lifted card to full-screen.
///   All cinematic effects active (glow, motion blur, sweep, vignette).
///
/// **Phase 3 — Cross-Fade (t 0.92→1.0, ~72ms):**
///   Everything fades out, revealing the destination screen behind.
///
/// [accentColor] adapts glow/sweep to content type (amber for PDF, blue
/// for images). Falls back to a warm white if null.
class WormholeDivePainter extends CustomPainter {
  final double t;
  final ui.Image? thumbnail;
  final Rect cardRect;
  final Rect fullRect;

  /// Accent color for glow burst and light sweep. Pass warm amber for
  /// PDFs, cool blue for images, or null for default.
  final Color? accentColor;

  // ── Static paints — allocated once, reused across all frames ──
  static final Paint _scrimPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _bgPaint = Paint()..color = const Color(0xFF0A0A14);
  static final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;
  static final Paint _shadowPaint = Paint()..color = Colors.black;
  static final Paint _sweepPaint = Paint()..blendMode = BlendMode.softLight;
  static final Paint _glowPaint = Paint()..blendMode = BlendMode.screen;
  static final Paint _vignettePaint = Paint()..blendMode = BlendMode.multiply;
  static final Paint _motionBlurPaint = Paint()..blendMode = BlendMode.srcOver;

  WormholeDivePainter({
    required this.t,
    required this.thumbnail,
    required this.cardRect,
    required this.fullRect,
    this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cardRect.isEmpty || fullRect.isEmpty || size.isEmpty) return;

    // ── Resolve accent color ──
    final accent = accentColor ?? const Color(0xFFE8D5B0);

    // ── CROSS-FADE: global opacity for the last 8% ──
    final fadeOutT = ((t - 0.92) / 0.08).clamp(0.0, 1.0);
    final globalOpacity = 1.0 - Curves.easeInCubic.transform(fadeOutT);
    if (globalOpacity < 0.01) return;

    // ═══════════════════════════════════════════════════════════════
    // PHASE MAPPING: t → lift-off (0–0.15) → dive (0.15–1.0)
    // ═══════════════════════════════════════════════════════════════
    final bool isLiftOff = t < 0.15;
    // Lift-off progress [0, 1] during first 15%
    final liftT = isLiftOff ? (t / 0.15).clamp(0.0, 1.0) : 1.0;
    // Dive progress [0, 1] during remaining 85%
    final diveT = isLiftOff ? 0.0 : ((t - 0.15) / 0.85).clamp(0.0, 1.0);

    // ── 1. FULL-SCREEN OPAQUE BACKGROUND ──
    final bgAlpha = (0.97 * globalOpacity * 255).round().clamp(0, 255);
    _scrimPaint.color = Color.fromARGB(bgAlpha, 6, 8, 20);
    canvas.drawRect(Offset.zero & size, _scrimPaint);

    // ── 2. RADIAL ACCENT GLOW ──
    final glowT = ((diveT - 0.05) / 0.60).clamp(0.0, 1.0);
    if (glowT > 0.02 && glowT < 0.98 && globalOpacity > 0.05) {
      final clipT2 = Curves.easeOutExpo.transform(diveT);
      final glowCenter = Rect.lerp(cardRect, fullRect, clipT2)!.center;
      final glowRadius = size.longestSide * 0.7 *
          Curves.easeOutCubic.transform(glowT);
      if (glowRadius > 1.0) {
        final glowAlpha = (0.14 * math.sin(glowT * math.pi) * globalOpacity)
            .clamp(0.0, 0.14);
        final alphaInt = (glowAlpha * 255).round().clamp(0, 255);
        _glowPaint.shader = ui.Gradient.radial(
          glowCenter,
          glowRadius,
          [
            accent.withAlpha(alphaInt),
            const Color(0x00000000),
          ],
          [0.0, 1.0],
        );
        canvas.drawRect(Offset.zero & size, _glowPaint);
        _glowPaint.shader = null;
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // CLIP RECT: lift-off (scale up in place) → dive (expand to full)
    // ═══════════════════════════════════════════════════════════════
    Rect clipRect;
    double borderRadius;

    if (isLiftOff) {
      // Phase 1: Card scales up 1.05× from center, stays in place
      final liftScale = 1.0 + 0.05 * Curves.easeOutCubic.transform(liftT);
      final liftedW = cardRect.width * liftScale;
      final liftedH = cardRect.height * liftScale;
      clipRect = Rect.fromCenter(
        center: cardRect.center,
        width: liftedW,
        height: liftedH,
      );
      borderRadius = 16.0;
    } else {
      // Phase 2: Expand from lifted card to full-screen
      final expandT = Curves.easeOutExpo.transform(diveT);
      // Start from the already-lifted card rect (1.05×)
      final liftedCard = Rect.fromCenter(
        center: cardRect.center,
        width: cardRect.width * 1.05,
        height: cardRect.height * 1.05,
      );
      clipRect = Rect.lerp(liftedCard, fullRect, expandT)!;
      borderRadius = 16.0 * (1.0 - expandT);
    }

    if (clipRect.width < 1.0 || clipRect.height < 1.0) return;

    // ── 3. DROP SHADOW — skip when invisible (diveT > 0.75) ──
    // Shadow alpha approaches 0 as diveT increases; skip expensive
    // MaskFilter.blur() allocation when it won't be visible.
    final bool shadowVisible = isLiftOff || diveT < 0.75;
    double shadowSigma = 0;
    double shadowAlpha = 0;
    double shadowOffset = 0;

    if (shadowVisible) {
      if (isLiftOff) {
        shadowSigma = 4.0 + 20.0 * Curves.easeOutCubic.transform(liftT);
        shadowAlpha = (0.20 + 0.25 * liftT) * globalOpacity;
        shadowOffset = 4.0 + 12.0 * liftT;
      } else {
        shadowSigma = (24.0 + 12.0 * diveT).clamp(0.1, 64.0);
        shadowAlpha = 0.45 * (1.0 - Curves.easeInCubic.transform(
            (diveT / 0.7).clamp(0.0, 1.0))) * globalOpacity;
        shadowOffset = 16.0 + 4.0 * diveT;
      }
    }

    canvas.save();

    if (shadowAlpha > 0.01) {
      _shadowPaint
        ..color = Color.fromARGB(
          (shadowAlpha * 255).round().clamp(0, 255), 0, 0, 0)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowSigma);
      final shadowRect = clipRect.translate(0, shadowOffset);
      if (borderRadius > 0.5) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(shadowRect, Radius.circular(borderRadius)),
          _shadowPaint,
        );
      } else {
        canvas.drawRect(shadowRect, _shadowPaint);
      }
    }

    // Clip to expanding rect
    if (borderRadius > 0.5) {
      canvas.clipRRect(
        RRect.fromRectAndRadius(clipRect, Radius.circular(borderRadius)),
      );
    } else {
      canvas.clipRect(clipRect);
    }

    // ── Dark background ──
    _bgPaint.color = Color.fromARGB(
      (globalOpacity * 255).round().clamp(0, 255), 10, 10, 20);
    canvas.drawRect(clipRect, _bgPaint);

    // ── 4. MOTION BLUR — skip when velocity² is negligible (diveT > 0.85) ──
    final bool motionBlurActive = !isLiftOff && diveT < 0.85;
    double motionBlurSigma = 0;

    if (motionBlurActive) {
      final velocityT = (1.0 - diveT).clamp(0.0, 1.0);
      motionBlurSigma = 2.5 * velocityT * velocityT * globalOpacity;
      if (motionBlurSigma > 0.3) {
        _motionBlurPaint.imageFilter = ui.ImageFilter.blur(
          sigmaX: motionBlurSigma * 0.5,
          sigmaY: motionBlurSigma,
          tileMode: TileMode.clamp,
        );
      } else {
        motionBlurSigma = 0;
      }
    }

    // ── 5. THUMBNAIL ──
    final img = thumbnail;
    if (img != null && globalOpacity > 0.05) {
      try {
        final imgW = img.width.toDouble();
        final imgH = img.height.toDouble();
        if (imgW > 0 && imgH > 0) {
          final imgAspect = imgW / imgH;
          final clipAspect = clipRect.width / clipRect.height;

          double dstW, dstH;
          if (imgAspect > clipAspect) {
            dstW = clipRect.width;
            dstH = clipRect.width / imgAspect;
          } else {
            dstH = clipRect.height;
            dstW = clipRect.height * imgAspect;
          }

          if (dstW > 0.5 && dstH > 0.5) {
            final dstRect = Rect.fromCenter(
              center: clipRect.center,
              width: dstW,
              height: dstH,
            );
            final srcRect = Rect.fromLTWH(0, 0, imgW, imgH);
            final drawPaint = motionBlurSigma > 0.3
                ? _motionBlurPaint
                : _imagePaint;
            drawPaint.color = Color.fromARGB(
              (globalOpacity * 255).round().clamp(0, 255),
              255, 255, 255,
            );
            canvas.drawImageRect(img, srcRect, dstRect, drawPaint);
          }
        }
      } catch (_) {
        // Image was disposed — dark background is fine.
      }
    }

    // ── 6. ACCENT LIGHT SWEEP — uses content-adaptive color ──
    final sweepT = ((diveT - 0.10) / 0.65).clamp(0.0, 1.0);
    if (sweepT > 0.02 && sweepT < 0.98 && clipRect.width > 2.0 &&
        globalOpacity > 0.05) {
      final sweepProgress = Curves.easeInOutCubic.transform(sweepT);
      final sweepAlpha = 0.18 * math.sin(sweepT * math.pi) * globalOpacity;
      final alphaInt = (sweepAlpha * 255).round().clamp(0, 255);
      final bandWidth = math.max(clipRect.width * 0.35, 2.0);
      final sweepX = clipRect.left + (clipRect.width * 1.5) *
          sweepProgress - clipRect.width * 0.25;
      final startPt = Offset(sweepX, clipRect.top);
      final endPt = Offset(sweepX + bandWidth, clipRect.bottom);
      if ((endPt - startPt).distanceSquared > 1.0) {
        _sweepPaint.shader = ui.Gradient.linear(
          startPt,
          endPt,
          [
            const Color(0x00FFFFFF),
            accent.withAlpha(alphaInt),
            accent.withAlpha((alphaInt * 0.5).round()),
            const Color(0x00FFFFFF),
          ],
          [0.0, 0.3, 0.7, 1.0],
        );
        canvas.drawRect(clipRect, _sweepPaint);
        _sweepPaint.shader = null;
      }
    }

    // ── 7. TUNNEL VIGNETTE — skip when nearly invisible (diveT > 0.9) ──
    if (!isLiftOff && diveT > 0.9) {
      // Vignette intensity ≈ 0 — skip gradient allocation
    } else {
      final vignetteBase = isLiftOff ? 0.30 : (1.0 - diveT);
      final vignetteIntensity = (0.30 * vignetteBase * globalOpacity)
          .clamp(0.0, 0.30);
    if (vignetteIntensity > 0.01) {
      final vignetteCenter = clipRect.center;
      final vignetteRadius = clipRect.shortestSide * 0.6;
      if (vignetteRadius > 1.0) {
        final alphaInt = (vignetteIntensity * 255).round().clamp(0, 255);
        _vignettePaint.shader = ui.Gradient.radial(
          vignetteCenter,
          vignetteRadius,
          [
            const Color(0x00000000),
            const Color(0x00000000),
            Color.fromARGB(alphaInt, 0, 0, 0),
          ],
          [0.0, 0.55, 1.0],
        );
        canvas.drawRect(clipRect, _vignettePaint);
        _vignettePaint.shader = null;
      }
    }
    } // end vignette skip guard

    canvas.restore();
  }

  @override
  bool shouldRepaint(WormholeDivePainter old) =>
      old.t != t || old.accentColor != accentColor;
}
