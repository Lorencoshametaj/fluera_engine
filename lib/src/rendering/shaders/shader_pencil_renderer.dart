import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'shader_brush_service.dart';

// ============================================================================
// PENCIL PRO RENDERER — GPU graphite texture per-segment rendering
// ============================================================================

extension ShaderPencilRenderer on ShaderBrushService {
  /// Render pencil stroke with GPU graphite texture effect.
  ///
  /// Uses per-segment quad rendering:
  /// - Each segment gets its own drawRect
  /// - Shader computes distance to ONE segment → O(1)
  void renderPencilPro(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    double baseOpacity = 0.4,
    double maxOpacity = 0.8,
    double minPressure = 0.5,
    double maxPressure = 1.2,
    ui.Image? textureImage,
    double textureScale = 0.0,
  }) {
    if (!isAvailable || pencilShader == null || points.length < 2) return;

    final shader = pencilShader!;
    final seed = random.nextDouble() * 100.0;
    final hasTexture = textureImage != null && textureScale > 0;

    // Hoist image sampler — MUST always be set (Flutter requires all
    // declared sampler2D to be bound, even if shader guards with uTextureScale)
    shader.setImageSampler(0, hasTexture ? textureImage : fallbackImage);

    // Reuse paint object across all segments
    final paint = Paint()..shader = shader;

    // Viewport culling: get clip bounds for segment skipping
    final clipBounds = canvas.getLocalClipBounds();

    // Pre-cache offsets (eliminates redundant getOffset calls)
    final offsets = preComputeOffsets(points);

    // Segment coalescing: reduce draw calls for smooth curves
    final indices = coalesceIndices(offsets);

    for (int k = 0; k < indices.length - 1; k++) {
      final i = indices[k];
      final j = indices[k + 1];
      var p1 = offsets[i];
      var p2 = offsets[j];

      final press1 = getPressure(points[i]);
      final press2 = getPressure(points[j]);

      final w1 =
          baseWidth * (minPressure + press1 * (maxPressure - minPressure));
      final w2 =
          baseWidth * (minPressure + press2 * (maxPressure - minPressure));

      final op1 = (baseOpacity + (maxOpacity - baseOpacity) * press1).clamp(
        0.0,
        1.0,
      );
      final op2 = (baseOpacity + (maxOpacity - baseOpacity) * press2).clamp(
        0.0,
        1.0,
      );

      // Always extend segments by half-width for continuous overlap
      // This creates capsule caps that blend seamlessly with neighbors
      final segLen = (p2 - p1).distance;
      final halfW = (w1 + w2) * 0.25; // half of average width
      if (segLen > 0.01) {
        final dir = (p2 - p1) / segLen;
        p1 = p1 - dir * halfW;
        p2 = p2 + dir * halfW;
      } else {
        // Near-zero segment: create a small horizontal capsule
        p1 = Offset(p1.dx - halfW, p1.dy);
        p2 = Offset(p2.dx + halfW, p2.dy);
      }

      // Tight bounding box (early discard in shader handles overflow)
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

      // Viewport cull: skip segments entirely outside clip bounds
      if (!rect.overlaps(clipBounds)) continue;

      // Set uniforms — positions relative to rect origin
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
      shader.setFloat(idx++, op1); // uOpacity1
      shader.setFloat(idx++, op2); // uOpacity2
      shader.setFloat(idx++, seed + i); // uSeed
      shader.setFloat(idx++, hasTexture ? textureScale : 0.0); // uTextureScale

      // Pre-computed cos/sin for texture rotation
      final segDelta = localP2 - localP1;
      final strokeAngle =
          segDelta.distance > 0.01 ? math.atan2(segDelta.dy, segDelta.dx) : 0.0;
      shader.setFloat(idx++, math.cos(strokeAngle)); // uCosAngle
      shader.setFloat(idx++, math.sin(strokeAngle)); // uSinAngle

      // Eliminate save/restore: paired translate
      canvas.translate(rect.left, rect.top);
      canvas.drawRect(Rect.fromLTWH(0, 0, rect.width, rect.height), paint);
      canvas.translate(-rect.left, -rect.top);
    }
  }
}
