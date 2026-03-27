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
    double surfaceRoughness = 0.0,
    double surfaceAbsorption = 0.0,
    double surfacePigmentRetention = 1.0,
  }) {
    if (!isAvailable || pencilShader == null || points.length < 2) return;

    final shader = pencilShader!;
    final seed = random.nextDouble() * 100.0;
    final hasTexture = textureImage != null && textureScale > 0;

    // Note: pencil_pro.frag has NO sampler2D — texture params are for
    // CPU-side BrushTexture overlay, not for this shader.
    // Do NOT call setImageSampler() — it crashes with "Sampler index out of bounds".

    // Reuse paint object across all segments
    final paint = Paint()..shader = shader;

    // Viewport culling: get clip bounds for segment skipping
    final clipBounds = canvas.getLocalClipBounds();

    // Pre-cache offsets (eliminates redundant getOffset calls)
    final offsets = preComputeOffsets(points);

    // 🚀 LOD: estimate screen-space segment size for skip decision.
    // When zoomed out, each segment occupies < 1px — rendering it is
    // wasted GPU work. Skip every Nth segment based on average screen size.
    int segStep = 1;
    if (offsets.length > 4) {
      final clipW = clipBounds.width;
      // Estimate stroke extent from first/last points
      final strokeExtent = (offsets.last - offsets.first).distance;
      if (strokeExtent > 0 && clipW > 0) {
        final avgSegScreenLen = strokeExtent / offsets.length;
        // If segments are < 0.8px, start skipping
        if (avgSegScreenLen < 0.8) {
          segStep = (0.8 / avgSegScreenLen).ceil().clamp(1, 6);
        }
      }
    }

    // 🚀 Adaptive padding: narrower when no absorption (glass/no surface)
    final paddingScale = surfaceAbsorption > 0.01 ? 0.8 : 0.55;

    // Iterate every consecutive point pair. segStep > 1 when zoomed out.
    for (int k = 0; k < offsets.length - 1; k += segStep) {
      var p1 = offsets[k];
      var p2 = offsets[k + 1];
      final rawSegLen = (p2 - p1).distance;
      if (rawSegLen < 0.01) continue;

      final press1 = getPressure(points[k]);
      final press2 = getPressure(points[k + 1]);

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
      final padding = maxW * paddingScale + 2.0;
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
      shader.setFloat(idx++, seed + k); // uSeed
      shader.setFloat(idx++, hasTexture ? textureScale : 0.0); // uTextureScale

      // Pre-computed cos/sin for texture rotation
      final segDelta = localP2 - localP1;
      final strokeAngle =
          segDelta.distance > 0.01 ? math.atan2(segDelta.dy, segDelta.dx) : 0.0;
      shader.setFloat(idx++, math.cos(strokeAngle)); // uCosAngle
      shader.setFloat(idx++, math.sin(strokeAngle)); // uSinAngle
      // 🧬 Surface material uniforms
      shader.setFloat(idx++, surfaceRoughness); // uRoughness
      shader.setFloat(idx++, surfaceAbsorption); // uAbsorption
      shader.setFloat(idx++, surfacePigmentRetention); // uRetention

      // Eliminate save/restore: paired translate
      canvas.translate(rect.left, rect.top);
      canvas.drawRect(Rect.fromLTWH(0, 0, rect.width, rect.height), paint);
      canvas.translate(-rect.left, -rect.top);
    }
  }
}
