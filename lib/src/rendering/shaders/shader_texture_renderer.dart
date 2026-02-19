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

/// 🚀 Pre-allocated buffers for texture overlay rendering (avoids per-frame GC).
List<Offset> _texOffsetCache = List<Offset>.filled(2048, Offset.zero);
List<int> _texIndexCache = List<int>.filled(512, 0);
int _texIndexCacheLen = 0;
List<double> _texVelCache = List<double>.filled(512, 0.0);
int _texVelCacheLen = 0;

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

    // 🚀 PERF: Pre-cache offsets into static buffer (avoids List allocation)
    final n = points.length;
    if (_texOffsetCache.length < n) {
      _texOffsetCache = List<Offset>.filled(n * 2, Offset.zero);
    }
    for (int i = 0; i < n; i++) {
      _texOffsetCache[i] = StrokeOptimizer.getOffset(points[i]);
    }

    // 🚀 PERF: Coalesce indices into static buffer
    _texIndexCacheLen = _coalesceIndicesInto(n);

    // 🚀 PERF: Calculate velocities into static buffer
    _texVelCacheLen = _calculateVelocitiesInto(n);

    // Viewport culling
    final clipBounds = canvas.getLocalClipBounds();

    for (int k = 0; k < _texIndexCacheLen - 1; k++) {
      final i = _texIndexCache[k];
      final j = _texIndexCache[k + 1];
      var p1 = _texOffsetCache[i];
      var p2 = _texOffsetCache[j];

      final press1 = getPressure(points[i]);
      final press2 = getPressure(points[j]);
      final vel = _texVelCache[k].clamp(0.0, 1.0);

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

  /// 🚀 Coalesce near-collinear points into _texIndexCache (no allocation).
  /// Returns the number of indices written.
  int _coalesceIndicesInto(int pointCount) {
    if (pointCount <= 3) {
      if (_texIndexCache.length < pointCount) {
        _texIndexCache = List<int>.filled(pointCount * 2, 0);
      }
      for (int i = 0; i < pointCount; i++) {
        _texIndexCache[i] = i;
      }
      return pointCount;
    }

    // Reuse threshold from ShaderBrushService.coalesceIndices
    const double threshold = 0.15;
    int writeIdx = 0;

    // Ensure capacity
    if (_texIndexCache.length < pointCount) {
      _texIndexCache = List<int>.filled(pointCount * 2, 0);
    }

    _texIndexCache[writeIdx++] = 0;
    var prevDir = _segDir(0);

    for (int i = 1; i < pointCount - 1; i++) {
      final dir = _segDir(i);
      final cross = (prevDir.dx * dir.dy - prevDir.dy * dir.dx).abs();
      if (cross > threshold) {
        _texIndexCache[writeIdx++] = i;
        prevDir = dir;
      }
    }

    _texIndexCache[writeIdx++] = pointCount - 1;
    return writeIdx;
  }

  /// Normalized direction between _texOffsetCache[i] and [i+1].
  Offset _segDir(int i) {
    final d = _texOffsetCache[i + 1] - _texOffsetCache[i];
    final len = d.distance;
    return len > 0.01 ? Offset(d.dx / len, d.dy / len) : const Offset(1, 0);
  }

  /// 🚀 Calculate velocities into _texVelCache (no allocation).
  /// Returns the number of velocities written.
  int _calculateVelocitiesInto(int pointCount) {
    if (_texIndexCacheLen < 2) {
      if (_texVelCache.isEmpty) {
        _texVelCache = List<double>.filled(8, 0.0);
      }
      _texVelCache[0] = 0.0;
      return 1;
    }

    // Ensure capacity
    if (_texVelCache.length < _texIndexCacheLen) {
      _texVelCache = List<double>.filled(_texIndexCacheLen * 2, 0.0);
    }

    double maxVel = 0.0;
    for (int k = 0; k < _texIndexCacheLen - 1; k++) {
      final vel =
          (_texOffsetCache[_texIndexCache[k + 1]] -
                  _texOffsetCache[_texIndexCache[k]])
              .distance;
      _texVelCache[k] = vel;
      if (vel > maxVel) maxVel = vel;
    }

    if (maxVel > 0) {
      for (int k = 0; k < _texIndexCacheLen; k++) {
        _texVelCache[k] /= maxVel;
      }
    }

    return _texIndexCacheLen;
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
