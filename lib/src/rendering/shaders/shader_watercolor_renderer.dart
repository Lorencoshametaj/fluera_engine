import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'shader_brush_service.dart';

// ============================================================================
// WATERCOLOR SHADER RENDERER — GPU wet-on-wet diffusion
// ============================================================================

extension ShaderWatercolorRenderer on ShaderBrushService {
  /// Render watercolor stroke with GPU diffusion and edge bleed.
  void renderWatercolorPro(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    double opacity = 0.25,
    double spread = 1.0,
  }) {
    if (!isAvailable || watercolorShader == null || points.length < 2) return;

    final shader = watercolorShader!;
    final paint = Paint()..shader = shader;
    final offsets = preComputeOffsets(points);
    final clipBounds = canvas.getLocalClipBounds();
    final seed = random.nextDouble() * 100.0;
    final waterWidth = baseWidth * 3.0;

    for (int k = 0; k < offsets.length - 1; k++) {
      var p1 = offsets[k];
      var p2 = offsets[k + 1];
      final rawSegLen = (p2 - p1).distance;
      if (rawSegLen < 0.01) continue;

      final press = getPressure(points[k]);
      final vel = (rawSegLen / (baseWidth * 4.0)).clamp(0.0, 1.0);
      final w1 = waterWidth * (0.7 + press * 0.3);
      final w2 = waterWidth * (0.7 + getPressure(points[k + 1]) * 0.3);

      // Extend segments for overlap
      final halfW = (w1 + w2) * 0.25 * (1.0 + spread * 0.4);
      if (rawSegLen > 0.01) {
        final dir = (p2 - p1) / rawSegLen;
        p1 = p1 - dir * halfW;
        p2 = p2 + dir * halfW;
      }

      final maxW = math.max(w1, w2) * (1.0 + spread * 0.5);
      final padding = maxW * 0.5 + 4.0;
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
      shader.setFloat(idx++, spread);

      canvas.translate(rect.left, rect.top);
      canvas.drawRect(Rect.fromLTWH(0, 0, rect.width, rect.height), paint);
      canvas.translate(-rect.left, -rect.top);
    }
  }
}
