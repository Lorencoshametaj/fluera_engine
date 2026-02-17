import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../drawing/brushes/brush_texture.dart';
import '../../drawing/models/pro_brush_settings.dart';
import '../optimization/optimization.dart';
import 'shader_brush_service.dart';

// ============================================================================
// TEXTURE OVERLAY RENDERER — GPU texture erosion per-segment rendering
// ============================================================================

extension ShaderTextureRenderer on ShaderBrushService {
  /// Render texture erosion overlay using GPU shader.
  ///
  /// Replaces CPU _applyTextureOverlay in BrushEngine.
  /// Each segment gets per-pixel texture sampling with local
  /// pressure/velocity interpolation.
  void renderTextureOverlay(
    Canvas canvas,
    List<dynamic> points,
    ProBrushSettings settings,
    ui.Image textureImage,
    double baseWidth,
  ) {
    if (!isAvailable || textureOverlayShader == null || points.length < 2) {
      return;
    }

    final shader = textureOverlayShader!;

    // Texture scale based on type + width
    final textureType = _textureTypeFromString(settings.textureType);
    final typeScale = switch (textureType) {
      TextureType.charcoal => 2.5,
      TextureType.kraft => 2.0,
      TextureType.watercolor => 1.8,
      TextureType.canvas => 1.5,
      TextureType.pencilGrain => 1.0,
      _ => 1.0,
    };
    final widthScale = (baseWidth / 3.0).clamp(0.5, 4.0);
    final totalScale = typeScale * widthScale;
    final invScale = 1.0 / totalScale;

    // Rotation based on textureRotationMode
    final firstPos = StrokeOptimizer.getOffset(points.first);
    final lastPos = StrokeOptimizer.getOffset(points.last);
    final rng = math.Random(firstPos.dx.toInt() ^ firstPos.dy.toInt());
    final offsetX = rng.nextDouble() * textureImage.width;
    final offsetY = rng.nextDouble() * textureImage.height;

    double rotation;
    switch (settings.textureRotationMode) {
      case 'fixed':
        rotation = 0.0;
      case 'random':
        rotation = rng.nextDouble() * math.pi * 2;
      case 'followStroke':
      default:
        final delta = lastPos - firstPos;
        final strokeAngle =
            delta.distance > 1.0 ? math.atan2(delta.dy, delta.dx) : 0.0;
        final jitter = (rng.nextDouble() - 0.5) * 0.174; // ±5°
        rotation = strokeAngle + jitter;
    }

    final cosAngle = math.cos(rotation);
    final sinAngle = math.sin(rotation);
    final intensity = settings.textureIntensity;
    final wetEdge = settings.textureWetEdge;

    // Hoist image sampler (texture is constant per stroke)
    shader.setImageSampler(0, textureImage);

    // Reuse paint with blendMode
    final paint =
        Paint()
          ..shader = shader
          ..blendMode = ui.BlendMode.dstOut;

    // Pre-cache offsets
    final offsets = preComputeOffsets(points);

    // Velocities only for coalesced indices
    final indices = coalesceIndices(offsets);
    final velocities = calculateVelocitiesForIndices(offsets, indices);

    // Viewport culling
    final clipBounds = canvas.getLocalClipBounds();

    for (int k = 0; k < indices.length - 1; k++) {
      final i = indices[k];
      final j = indices[k + 1];
      var p1 = offsets[i];
      var p2 = offsets[j];

      final press1 = getPressure(points[i]);
      final press2 = getPressure(points[j]);
      final vel = velocities[k].clamp(0.0, 1.0);

      // Pressure-based width interpolation (like pencil/fountain pen)
      final w1 = baseWidth * (0.5 + press1 * 0.5);
      final w2 = baseWidth * (0.5 + press2 * 0.5);

      // Extend segments for seamless overlap
      final segLen = (p2 - p1).distance;
      final halfW = baseWidth * 0.5;
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

      // Set uniforms matching texture_overlay.frag layout
      int idx = 0;
      shader.setFloat(idx++, localP1.dx); // uP1.x
      shader.setFloat(idx++, localP1.dy); // uP1.y
      shader.setFloat(idx++, localP2.dx); // uP2.x
      shader.setFloat(idx++, localP2.dy); // uP2.y
      shader.setFloat(idx++, w1); // uW1
      shader.setFloat(idx++, w2); // uW2
      shader.setFloat(idx++, press1); // uPressure1
      shader.setFloat(idx++, press2); // uPressure2
      shader.setFloat(idx++, vel); // uVelocity
      shader.setFloat(idx++, intensity); // uIntensity
      shader.setFloat(idx++, invScale); // uTextureScale
      shader.setFloat(idx++, offsetX); // uTextureOffset.x
      shader.setFloat(idx++, offsetY); // uTextureOffset.y
      shader.setFloat(idx++, cosAngle); // uCosAngle (pre-computed)
      shader.setFloat(idx++, sinAngle); // uSinAngle (pre-computed)
      shader.setFloat(idx++, wetEdge); // uWetEdge

      // Paired translate (no save/restore)
      canvas.translate(rect.left, rect.top);
      canvas.drawRect(Rect.fromLTWH(0, 0, rect.width, rect.height), paint);
      canvas.translate(-rect.left, -rect.top);
    }
  }

  /// Convert textureType string → TextureType enum.
  static TextureType _textureTypeFromString(String type) {
    return switch (type) {
      'pencilGrain' => TextureType.pencilGrain,
      'charcoal' => TextureType.charcoal,
      'watercolor' => TextureType.watercolor,
      'canvas' => TextureType.canvas,
      'kraft' => TextureType.kraft,
      _ => TextureType.none,
    };
  }
}
