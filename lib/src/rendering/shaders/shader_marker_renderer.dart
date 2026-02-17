import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'shader_brush_service.dart';

// ============================================================================
// MARKER SHADER RENDERER — GPU flat-tip marker with alpha accumulation
// ============================================================================

extension ShaderMarkerRenderer on ShaderBrushService {
  /// Render marker stroke with GPU flat chisel tip and edge darkening.
  void renderMarkerPro(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    double opacity = 0.7,
    double flatness = 0.4,
  }) {
    if (!isAvailable || markerShader == null || points.length < 2) return;

    final shader = markerShader!;
    final paint = Paint()..shader = shader;
    final offsets = preComputeOffsets(points);
    final clipBounds = canvas.getLocalClipBounds();
    final markerWidth = baseWidth * 2.5;

    for (int k = 0; k < offsets.length - 1; k++) {
      var p1 = offsets[k];
      var p2 = offsets[k + 1];
      final rawSegLen = (p2 - p1).distance;
      if (rawSegLen < 0.01) continue;

      final w = markerWidth;

      // Extend for overlap
      final halfW = w * 0.25;
      if (rawSegLen > 0.01) {
        final dir = (p2 - p1) / rawSegLen;
        p1 = p1 - dir * halfW;
        p2 = p2 + dir * halfW;
      }

      final padding = w * 0.6 + 3.0;
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
      shader.setFloat(idx++, w);
      shader.setFloat(idx++, w);
      shader.setFloat(idx++, color.r);
      shader.setFloat(idx++, color.g);
      shader.setFloat(idx++, color.b);
      shader.setFloat(idx++, opacity * color.a);
      shader.setFloat(idx++, flatness);

      canvas.translate(rect.left, rect.top);
      canvas.drawRect(Rect.fromLTWH(0, 0, rect.width, rect.height), paint);
      canvas.translate(-rect.left, -rect.top);
    }
  }
}
