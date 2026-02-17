import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'shader_brush_service.dart';

// ============================================================================
// FOUNTAIN PEN PRO RENDERER — GPU ink bleed + fiber texture rendering
// ============================================================================

extension ShaderFountainPenRenderer on ShaderBrushService {
  /// Render fountain pen stroke with GPU ink bleed and fiber texture.
  ///
  /// [precomputedWidths] contains per-point widths pre-computed by the CPU
  /// width pipeline (accumulator + taper + EMA smooth + rate-limit).
  /// Must support `operator []` with indices matching [points].
  void renderFountainPenPro(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    required dynamic precomputedWidths,
    ui.Image? textureImage,
    double textureScale = 0.0,
  }) {
    if (!isAvailable || fountainPenShader == null || points.length < 2) {
      return;
    }

    final shader = fountainPenShader!;
    final hasTexture = textureImage != null && textureScale > 0;
    final seed = random.nextDouble() * 100.0;

    // Hoist image sampler — MUST always be set (Flutter requires all
    // declared sampler2D to be bound, even if shader guards with uTextureScale)
    shader.setImageSampler(0, hasTexture ? textureImage : fallbackImage);

    // Reuse paint
    final paint = Paint()..shader = shader;

    // Pre-cache offsets
    final offsets = preComputeOffsets(points);

    // Viewport culling
    final clipBounds = canvas.getLocalClipBounds();

    // Iterate over every consecutive point pair (no coalescing — short segments
    // prevent visible round-cap bumps at joints)
    for (int k = 0; k < offsets.length - 1; k++) {
      var p1 = offsets[k];
      var p2 = offsets[k + 1];

      // Skip degenerate segments
      final rawSegLen = (p2 - p1).distance;
      if (rawSegLen < 0.01) continue;

      // Use pre-computed widths from CPU pipeline
      final double w1 = precomputedWidths[k] as double;
      final double w2 = precomputedWidths[k + 1] as double;

      // Pressure still needed for shader uniforms (ink bleed effect)
      final press1 = getPressure(points[k]);
      final press2 = getPressure(points[k + 1]);
      // Velocity: normalized segment length (longer = faster)
      final vel = (rawSegLen / (baseWidth * 4.0)).clamp(0.0, 1.0);

      // Always extend segments by half-width for continuous overlap
      final segLen = (p2 - p1).distance;
      final halfW = (w1 + w2) * 0.25;
      if (segLen > 0.01) {
        final dir = (p2 - p1) / segLen;
        p1 = p1 - dir * halfW;
        p2 = p2 + dir * halfW;
      } else {
        p1 = Offset(p1.dx - halfW, p1.dy);
        p2 = Offset(p2.dx + halfW, p2.dy);
      }

      // Tight bounding box
      final maxW = math.max(w1, w2);
      final padding = maxW * 0.5 + 2.0;
      final rect = Rect.fromPoints(
        Offset(
          math.min(p1.dx, p2.dx) - padding,
          math.min(p1.dy, p2.dy) - padding,
        ),
        Offset(
          math.max(p1.dx, p2.dx) + padding,
          math.max(p1.dy, p2.dy) + padding,
        ),
      );

      // Viewport cull
      if (!rect.overlaps(clipBounds)) continue;

      final localP1 = p1 - rect.topLeft;
      final localP2 = p2 - rect.topLeft;

      int idx = 0;
      shader.setFloat(idx++, localP1.dx); // uP1.x
      shader.setFloat(idx++, localP1.dy); // uP1.y
      shader.setFloat(idx++, localP2.dx); // uP2.x
      shader.setFloat(idx++, localP2.dy); // uP2.y
      shader.setFloat(idx++, w1); // uW1
      shader.setFloat(idx++, w2); // uW2
      shader.setFloat(idx++, color.r); // uColor.r
      shader.setFloat(idx++, color.g); // uColor.g
      shader.setFloat(idx++, color.b); // uColor.b
      shader.setFloat(idx++, color.a); // uColor.a
      shader.setFloat(idx++, press1); // uPressure1
      shader.setFloat(idx++, press2); // uPressure2
      shader.setFloat(idx++, vel); // uVelocity
      shader.setFloat(idx++, seed + k); // uSeed
      shader.setFloat(idx++, hasTexture ? textureScale : 0.0); // uTextureScale

      // Pre-computed cos/sin for fiber rotation
      final segDelta = localP2 - localP1;
      final strokeAngle =
          segDelta.distance > 0.01 ? math.atan2(segDelta.dy, segDelta.dx) : 0.0;
      shader.setFloat(idx++, math.cos(strokeAngle)); // uCosAngle
      shader.setFloat(idx++, math.sin(strokeAngle)); // uSinAngle

      // Paired translate (no save/restore)
      canvas.translate(rect.left, rect.top);
      canvas.drawRect(Rect.fromLTWH(0, 0, rect.width, rect.height), paint);
      canvas.translate(-rect.left, -rect.top);
    }

    // Corner-fill: draw circles at joints to cover gaps at angled curves.
    // Without this, adjacent capsule segments leave visible seams at bends.
    final jointPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;
    for (int k = 1; k < offsets.length - 1; k++) {
      final p = offsets[k];
      final double w = precomputedWidths[k] as double;
      final r = w * 0.5;
      if (r < 0.1) continue;

      // Quick viewport check
      if (p.dx + r < clipBounds.left ||
          p.dx - r > clipBounds.right ||
          p.dy + r < clipBounds.top ||
          p.dy - r > clipBounds.bottom)
        continue;

      canvas.drawCircle(p, r, jointPaint);
    }
  }
}
