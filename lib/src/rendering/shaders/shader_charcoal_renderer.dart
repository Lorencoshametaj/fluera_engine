import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'shader_brush_service.dart';

// ============================================================================
// CHARCOAL SHADER RENDERER — GPU grain erosion + noise
// ============================================================================

extension ShaderCharcoalRenderer on ShaderBrushService {
  /// Render charcoal stroke with GPU grain erosion and speed-dependent noise.
  void renderCharcoalPro(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    double opacity = 0.6,
    double grain = 0.5,
    double surfaceRoughness = 0.0,
    double surfaceAbsorption = 0.0,
    double surfacePigmentRetention = 1.0,
  }) {
    if (!isAvailable || charcoalShader == null || points.length < 2) return;

    final shader = charcoalShader!;
    final paint = Paint()..shader = shader;
    final offsets = preComputeOffsets(points);
    final clipBounds = canvas.getLocalClipBounds();
    final seed = random.nextDouble() * 100.0;
    final charcoalWidth = baseWidth * 2.0;

    // 🚀 LOD: skip segments when zoomed out (sub-pixel)
    int segStep = 1;
    if (offsets.length > 4) {
      final strokeExtent = (offsets.last - offsets.first).distance;
      if (strokeExtent > 0) {
        final avgSegScreenLen = strokeExtent / offsets.length;
        if (avgSegScreenLen < 0.8) {
          segStep = (0.8 / avgSegScreenLen).ceil().clamp(1, 6);
        }
      }
    }

    // 🚀 Adaptive padding: narrower when no halo/scatter needed
    final paddingScale = surfaceAbsorption > 0.01 ? 0.8 : 0.55;

    for (int k = 0; k < offsets.length - 1; k += segStep) {
      var p1 = offsets[k];
      var p2 = offsets[k + 1];
      final rawSegLen = (p2 - p1).distance;
      if (rawSegLen < 0.01) continue;

      final press = getPressure(points[k]);
      final vel = (rawSegLen / (baseWidth * 4.0)).clamp(0.0, 1.0);
      final w1 = charcoalWidth * (0.5 + press * 0.5);
      final w2 = charcoalWidth * (0.5 + getPressure(points[k + 1]) * 0.5);

      // Extend for overlap
      final halfW = (w1 + w2) * 0.25;
      if (rawSegLen > 0.01) {
        final dir = (p2 - p1) / rawSegLen;
        p1 = p1 - dir * halfW;
        p2 = p2 + dir * halfW;
      }

      final maxW = math.max(w1, w2);
      final padding = maxW * paddingScale + 3.0;
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
      if (!rect.overlaps(clipBounds)) continue;

      final localP1 = p1 - rect.topLeft;
      final localP2 = p2 - rect.topLeft;

      int idx = 0;
      shader.setFloat(idx++, localP1.dx);
      shader.setFloat(idx++, localP1.dy);
      shader.setFloat(idx++, localP2.dx);
      shader.setFloat(idx++, localP2.dy);
      shader.setFloat(idx++, w1);
      shader.setFloat(idx++, w2);
      shader.setFloat(idx++, color.r);
      shader.setFloat(idx++, color.g);
      shader.setFloat(idx++, color.b);
      shader.setFloat(idx++, opacity * color.a);
      shader.setFloat(idx++, press);
      shader.setFloat(idx++, vel);
      shader.setFloat(idx++, seed + k);
      shader.setFloat(idx++, grain);
      // 🧬 Surface material uniforms
      shader.setFloat(idx++, surfaceRoughness);
      shader.setFloat(idx++, surfaceAbsorption);
      shader.setFloat(idx++, surfacePigmentRetention);

      canvas.translate(rect.left, rect.top);
      canvas.drawRect(Rect.fromLTWH(0, 0, rect.width, rect.height), paint);
      canvas.translate(-rect.left, -rect.top);
    }
  }
}
