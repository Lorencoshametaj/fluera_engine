import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../drawing/models/pro_drawing_point.dart';
import 'shader_brush_service.dart';

// ============================================================================
// STAMP BRUSH RENDERER — Procreate-style stamp-based rendering
// ============================================================================

/// Data holder for Catmull-Rom spline resampled points.
class SplineResult {
  final List<Offset> offsets;
  final List<double> pressures;
  final List<double> tiltX;
  final List<double> tiltY;

  const SplineResult(this.offsets, this.pressures, this.tiltX, this.tiltY);
}

extension ShaderStampRenderer on ShaderBrushService {
  /// Render stroke using stamp-based brush engine.
  ///
  /// Walks the stroke path and places rotated, pressure-scaled stamps
  /// at uniform intervals — the core technique behind Procreate.
  void renderStampBrush(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    double minPressure = 0.2,
    double maxPressure = 1.0,
    double spacing = 0.25,
    double sizeJitter = 0.0,
    double rotationJitter = 0.0,
    double scatterAmount = 0.0,
    double softness = 0.6,
    double elongation = 1.0,
    double baseOpacity = 0.8,
    double flow = 0.5,
    double opacityJitter = 0.0,
    double minSizePct = 0.15,
    int taperEntry = 6,
    int taperExit = 6,
    double wetEdges = 0.0,
    // Velocity dynamics
    double velocitySizeInfluence = 0.0,
    double velocityFlowInfluence = 0.0,
    // Glaze vs buildup
    bool glazeMode = true,
    // Color dynamics
    double hueJitter = 0.0,
    double saturationJitter = 0.0,
    double brightnessJitter = 0.0,
    // Tilt dynamics (Phase 2)
    double tiltRotation =
        0.0, // 0-1: how much tilt azimuth overrides stroke angle
    double tiltElongation = 0.0, // 0-1: how much tilt altitude stretches stamp
    // Dual brush (Phase 3)
    ui.Image? tipTexture,
    ui.Image? dualTexture,
    double dualScale = 1.0,
    double dualBlend = 0.0,
    // Pressure → Color
    double pressureColorInfluence = 0.0, // 0-1: pressure darkens color
    // Wet mixing
    double wetMixStrength = 0.0, // 0-1: color bleed between stamps
    // Roundness jitter
    double roundnessJitter = 0.0, // 0-1: random elongation variation
    // Color gradient along stroke
    Color? secondaryColor, // null = no gradient
    double colorGradient = 0.0, // 0-1: how much to interpolate toward secondary
    // Accumulation cap
    double accumCap = 0.0, // 0 = uncapped, 0.01-1.0 = max per-stamp alpha
    // Performance
    int maxStampsPerFrame = 2000, // Safety cap
    // Spacing dynamics
    double spacingPressure = 0.0, // 0-1: pressure tightens spacing
    // Transfer dynamics
    double transferVelocity = 0.0, // 0-1: slow→opaque, fast→transparent
    // Symmetry
    int symmetryAxes = 0, // 0=off, 2=bilateral, 3+=radial
    // Eraser stamp
    bool eraserMode = false,
    // Grain mode: false=stamp-space, true=screen-space
    bool grainScreenSpace = false,
    // Procedural shape: 0=circle, 1=square, 2=diamond, 3=star, 4=leaf
    int shapeType = 0,
    // Grain scale
    double grainScale = 1.0, // <1=fine (pencil), >1=coarse (charcoal)
    // Color pressure: interpolate fg→secondary based on pressure
    double colorPressure = 0.0, // 0-1: how much pressure shifts color
  }) {
    final shader = brushStampShader;
    if (shader == null || points.length < 2) return;

    // ── Phase 1: Catmull-Rom spline resampling ──
    final rawOffsets = preComputeOffsets(points);
    final rawPressures = List<double>.generate(
      points.length,
      (i) => getPressure(points[i]),
    );
    final spline = _catmullRomResample(rawOffsets, rawPressures, points);
    final offsets = spline.offsets;
    final splinePressures = spline.pressures;
    final splineTiltX = spline.tiltX;
    final splineTiltY = spline.tiltY;
    final stampSpacing = (baseWidth * spacing).clamp(1.0, 100.0);
    final paint = Paint()..shader = shader;
    // Eraser mode: stamps erase with brush shape
    if (eraserMode) {
      paint.blendMode = BlendMode.clear;
    }

    final hasTip = tipTexture != null;
    if (hasTip) {
      shader.setImageSampler(0, tipTexture);
    }

    // Phase 3: Dual brush — second sampler
    final hasDual = dualTexture != null && dualBlend > 0.001;
    if (hasDual) {
      shader.setImageSampler(1, dualTexture);
    }

    final clipBounds = canvas.getLocalClipBounds();
    final cullPadding = baseWidth * maxPressure + 2.0;

    // Pre-compute total path length for tapering
    double totalPathLen = 0.0;
    for (int i = 0; i < offsets.length - 1; i++) {
      totalPathLen += (offsets[i + 1] - offsets[i]).distance;
    }
    final taperEntryLen = (taperEntry * baseWidth * 0.5).clamp(
      0.0,
      totalPathLen * 0.4,
    );
    final taperExitLen = (taperExit * baseWidth * 0.5).clamp(
      0.0,
      totalPathLen * 0.4,
    );

    // ── Pre-compute per-segment velocities (for velocity dynamics) ──
    final hasVelocity = velocitySizeInfluence > 0 || velocityFlowInfluence > 0;
    List<double>? segVelocities;
    if (hasVelocity) {
      segVelocities = List<double>.filled(offsets.length - 1, 0.0);
      double maxVel = 0.0;
      for (int i = 0; i < offsets.length - 1; i++) {
        // Velocity = distance per segment (normalized later)
        segVelocities[i] = (offsets[i + 1] - offsets[i]).distance;
        if (segVelocities[i] > maxVel) maxVel = segVelocities[i];
      }
      // Normalize to 0-1
      if (maxVel > 0.001) {
        for (int i = 0; i < segVelocities.length; i++) {
          segVelocities[i] = (segVelocities[i] / maxVel).clamp(0.0, 1.0);
        }
      }
    }

    // ── Color dynamics: pre-compute base HSL ──
    final hasColorDynamics =
        hueJitter > 0 || saturationJitter > 0 || brightnessJitter > 0;
    final hasPressureColor = pressureColorInfluence > 0;
    final hasWetMix = wetMixStrength > 0;
    late final HSLColor baseHSL;
    if (hasColorDynamics || hasPressureColor || hasWetMix) {
      baseHSL = HSLColor.fromColor(color);
    }

    // ── Pre-compute per-segment curvature for adaptive spacing ──
    final segCurvatures = List<double>.filled(offsets.length - 1, 0.0);
    for (int i = 0; i < offsets.length - 1; i++) {
      if (i > 0) {
        final d0 = offsets[i] - offsets[i - 1];
        final d1 = offsets[i + 1] - offsets[i];
        final len0 = d0.distance;
        final len1 = d1.distance;
        if (len0 > 0.01 && len1 > 0.01) {
          // Cross product magnitude = sin(angle) between segments
          final cross =
              (d0.dx / len0 * d1.dy / len1 - d0.dy / len0 * d1.dx / len1).abs();
          segCurvatures[i] = cross.clamp(0.0, 1.0);
        }
      }
    }

    // Wet mix: rolling previous stamp color
    Color wetPrevColor = color;

    // ── Phase 4: Bounds-clipped saveLayer ──
    if (glazeMode) {
      // Pre-compute tight stroke bounds for GPU-efficient saveLayer
      double bMinX = double.infinity, bMinY = double.infinity;
      double bMaxX = double.negativeInfinity, bMaxY = double.negativeInfinity;
      for (final o in offsets) {
        if (o.dx < bMinX) bMinX = o.dx;
        if (o.dy < bMinY) bMinY = o.dy;
        if (o.dx > bMaxX) bMaxX = o.dx;
        if (o.dy > bMaxY) bMaxY = o.dy;
      }
      final pad = baseWidth * maxPressure + 4.0;
      final strokeBounds = Rect.fromLTRB(
        bMinX - pad,
        bMinY - pad,
        bMaxX + pad,
        bMaxY + pad,
      );
      canvas.saveLayer(
        strokeBounds,
        Paint()..color = color.withValues(alpha: baseOpacity),
      );
    }

    double remainingDist = 0.0;
    double accumulatedLen = 0.0;
    int stampIdx = 0;

    for (int i = 0; i < offsets.length - 1; i++) {
      final p1 = offsets[i];
      final p2 = offsets[i + 1];
      final segDelta = p2 - p1;
      final segLen = segDelta.distance;
      if (segLen < 0.001) continue;

      final press1 = splinePressures[i];
      final press2 = splinePressures[i + 1];
      final dirX = segDelta.dx / segLen;
      final dirY = segDelta.dy / segLen;
      final strokeAngle = math.atan2(segDelta.dy, segDelta.dx);

      // Per-segment tilt data (interpolated from spline)
      final segTiltX1 = splineTiltX[i];
      final segTiltY1 = splineTiltY[i];
      final segTiltX2 = splineTiltX[i + 1];
      final segTiltY2 = splineTiltY[i + 1];

      // Segment velocity (0=slow, 1=fast)
      final velocity = segVelocities?[i] ?? 0.0;

      double t = (stampSpacing - remainingDist);
      if (t < 0) t = 0;

      // Adaptive spacing: reduce spacing on curves
      final curvature = segCurvatures[i];
      var adaptiveSpacing = stampSpacing * (1.0 - curvature * 0.6);

      // Spacing dynamics: pressure tightens spacing
      if (spacingPressure > 0) {
        final segPress = (press1 + press2) * 0.5;
        adaptiveSpacing *= (1.0 - segPress * spacingPressure * 0.5);
        adaptiveSpacing = adaptiveSpacing.clamp(1.0, 100.0);
      }

      while (t < segLen) {
        final frac = t / segLen;
        final cx = p1.dx + segDelta.dx * frac;
        final cy = p1.dy + segDelta.dy * frac;

        if (cx + cullPadding < clipBounds.left ||
            cx - cullPadding > clipBounds.right ||
            cy + cullPadding < clipBounds.top ||
            cy - cullPadding > clipBounds.bottom) {
          t += adaptiveSpacing;
          continue;
        }

        // Stamp count limiter
        if (stampIdx >= maxStampsPerFrame) break;

        final pathPos = accumulatedLen + t;
        final press = press1 + (press2 - press1) * frac;

        // ── Phase 2: Tilt → Rotation & Elongation ──
        final ptTiltX = segTiltX1 + (segTiltX2 - segTiltX1) * frac;
        final ptTiltY = segTiltY1 + (segTiltY2 - segTiltY1) * frac;
        final pressNorm = minPressure + press * (maxPressure - minPressure);

        // Entry/exit taper (smoothstep)
        double taperMul = 1.0;
        if (taperEntryLen > 0 && pathPos < taperEntryLen) {
          taperMul *= (pathPos / taperEntryLen);
        }
        final distFromEnd = totalPathLen - pathPos;
        if (taperExitLen > 0 && distFromEnd < taperExitLen) {
          taperMul *= (distFromEnd / taperExitLen);
        }
        taperMul = taperMul * taperMul * (3.0 - 2.0 * taperMul);

        // ── Velocity dynamics ──
        // Fast strokes → smaller stamps, less flow (mimics real brush physics)
        double velSizeMul = 1.0;
        double velFlowMul = 1.0;
        if (hasVelocity) {
          // velocity=0 → no change, velocity=1 → shrink by influence amount
          velSizeMul = 1.0 - velocity * velocitySizeInfluence;
          velFlowMul = 1.0 - velocity * velocityFlowInfluence;
        }

        // Size with jitter, taper, velocity, min floor
        double stampSize = baseWidth * pressNorm * taperMul * velSizeMul;
        if (sizeJitter > 0) {
          stampSize *= (1.0 + (random.nextDouble() * 2 - 1) * sizeJitter);
        }
        final minSize = baseWidth * minSizePct;
        stampSize = stampSize.clamp(minSize, baseWidth * maxPressure * 1.5);

        double angle = strokeAngle;
        // Tilt azimuth blended into rotation
        if (tiltRotation > 0 &&
            (ptTiltX.abs() > 0.01 || ptTiltY.abs() > 0.01)) {
          final tiltAzimuth = math.atan2(ptTiltY, ptTiltX);
          angle = angle * (1.0 - tiltRotation) + tiltAzimuth * tiltRotation;
        }
        if (rotationJitter > 0) {
          angle += (random.nextDouble() * 2 - 1) * rotationJitter;
        }

        // Tilt altitude blended into elongation
        double stampElongation = elongation;
        if (tiltElongation > 0) {
          final tiltMag = math
              .sqrt(ptTiltX * ptTiltX + ptTiltY * ptTiltY)
              .clamp(0.0, 1.0);
          stampElongation = elongation + tiltMag * tiltElongation * 1.5;
        }
        // Roundness jitter
        if (roundnessJitter > 0) {
          stampElongation *=
              (1.0 + (random.nextDouble() * 2 - 1) * roundnessJitter * 0.5);
          stampElongation = stampElongation.clamp(0.5, 4.0);
        }

        double scX = cx, scY = cy;
        if (scatterAmount > 0) {
          final perpOff =
              (random.nextDouble() * 2 - 1) * scatterAmount * baseWidth;
          scX += -dirY * perpOff;
          scY += dirX * perpOff;
        }

        // Flow with jitter, taper, velocity
        double stampFlow = flow * press * velFlowMul;
        if (opacityJitter > 0) {
          stampFlow *= (1.0 - random.nextDouble() * opacityJitter);
        }
        stampFlow = (stampFlow * taperMul).clamp(0.0, 1.0);

        // Transfer dynamics: velocity → opacity (slow=opaque, fast=transparent)
        if (transferVelocity > 0) {
          stampFlow *= (1.0 - velocity * transferVelocity * 0.7);
        }

        // In buildup mode, also apply baseOpacity per stamp
        if (!glazeMode) {
          stampFlow *= baseOpacity;
        }

        // ── Color dynamics: per-stamp HSL jitter ──
        Color stampColor = color;
        HSLColor? stampHSL;
        if (hasColorDynamics || hasPressureColor) {
          double h = baseHSL.hue;
          double s = baseHSL.saturation;
          double l = baseHSL.lightness;
          if (hueJitter > 0) {
            h = (h + (random.nextDouble() * 2 - 1) * hueJitter) % 360.0;
            if (h < 0) h += 360.0;
          }
          if (saturationJitter > 0) {
            s = (s + (random.nextDouble() * 2 - 1) * saturationJitter).clamp(
              0.0,
              1.0,
            );
          }
          if (brightnessJitter > 0) {
            l = (l + (random.nextDouble() * 2 - 1) * brightnessJitter).clamp(
              0.0,
              1.0,
            );
          }
          // Pressure → Color: harder pressure = darker
          if (hasPressureColor) {
            l = l * (1.0 - press * pressureColorInfluence * 0.4);
            l = l.clamp(0.0, 1.0);
          }
          stampHSL = HSLColor.fromAHSL(color.a, h, s, l);
          stampColor = stampHSL.toColor();
        }

        // Wet mixing: blend with previous stamp's color
        if (hasWetMix && stampIdx > 0) {
          final mix = wetMixStrength * 0.15;
          stampColor = Color.lerp(stampColor, wetPrevColor, mix) ?? stampColor;
        }
        wetPrevColor = stampColor;

        // Color gradient along stroke (fg → bg)
        if (secondaryColor != null && colorGradient > 0) {
          final pathFrac =
              (totalPathLen > 0)
                  ? (pathPos / totalPathLen).clamp(0.0, 1.0)
                  : 0.0;
          stampColor =
              Color.lerp(
                stampColor,
                secondaryColor,
                pathFrac * colorGradient,
              ) ??
              stampColor;
        }

        // Color pressure: pressure interpolates toward secondaryColor
        if (colorPressure > 0 && secondaryColor != null) {
          stampColor =
              Color.lerp(stampColor, secondaryColor, press * colorPressure) ??
              stampColor;
        }

        final grainSeed = (stampIdx * 0.618033988749).remainder(100.0);

        // Set uniforms (must match brush_stamp.frag)
        int idx = 0;
        shader.setFloat(idx++, scX); // uCenter.x
        shader.setFloat(idx++, scY); // uCenter.y
        shader.setFloat(idx++, stampSize); // uSize
        shader.setFloat(idx++, stampFlow); // uFlow
        shader.setFloat(idx++, stampColor.r); // uColor.r
        shader.setFloat(idx++, stampColor.g); // uColor.g
        shader.setFloat(idx++, stampColor.b); // uColor.b
        shader.setFloat(idx++, stampColor.a); // uColor.a
        shader.setFloat(idx++, math.cos(angle)); // uCosAngle
        shader.setFloat(idx++, math.sin(angle)); // uSinAngle
        shader.setFloat(idx++, softness); // uSoftness
        shader.setFloat(idx++, hasTip ? 1.0 : 0.0); // uTextureScale
        shader.setFloat(idx++, stampElongation); // uElongation
        shader.setFloat(idx++, grainSeed); // uGrainSeed
        shader.setFloat(idx++, wetEdges); // uWetEdges
        // Phase 3: Dual brush uniforms
        shader.setFloat(idx++, dualBlend); // uDualBlend
        shader.setFloat(idx++, dualScale); // uDualScale
        // Grain rotation (stroke-aligned)
        shader.setFloat(idx++, math.cos(angle)); // uGrainCos
        shader.setFloat(idx++, math.sin(angle)); // uGrainSin
        // Accumulation cap
        shader.setFloat(idx++, accumCap); // uAccumCap
        // Grain mode
        shader.setFloat(idx++, grainScreenSpace ? 1.0 : 0.0); // uGrainMode
        // Shape type
        shader.setFloat(idx++, shapeType.toDouble()); // uShapeType
        // Grain scale
        shader.setFloat(idx++, grainScale); // uGrainScale

        final half = stampSize * 0.5 + 1.0;
        // For non-circular shapes, expand rect to cover star/leaf tips
        final shapeExpand = (shapeType >= 3) ? 1.5 : 1.0;
        final rect = Rect.fromCenter(
          center: Offset(scX, scY),
          width: half * 2 * shapeExpand,
          height: half * 2 * stampElongation * shapeExpand,
        );

        canvas.translate(rect.left, rect.top);
        canvas.drawRect(Rect.fromLTWH(0, 0, rect.width, rect.height), paint);
        canvas.translate(-rect.left, -rect.top);

        // ── Symmetry: mirror stamps across axes ──
        if (symmetryAxes >= 2) {
          final centerX = clipBounds.center.dx;
          final centerY = clipBounds.center.dy;
          for (int axis = 1; axis < symmetryAxes; axis++) {
            final symAngle = (axis * 2 * math.pi) / symmetryAxes;
            final cosA = math.cos(symAngle);
            final sinA = math.sin(symAngle);
            // Mirror position around clip center
            final dx = scX - centerX;
            final dy = scY - centerY;
            final mirX = centerX + dx * cosA - dy * sinA;
            final mirY = centerY + dx * sinA + dy * cosA;

            shader.setFloat(0, mirX); // uCenter.x
            shader.setFloat(1, mirY); // uCenter.y

            final mirRect = Rect.fromCenter(
              center: Offset(mirX, mirY),
              width: half * 2 * shapeExpand,
              height: half * 2 * stampElongation * shapeExpand,
            );
            canvas.translate(mirRect.left, mirRect.top);
            canvas.drawRect(
              Rect.fromLTWH(0, 0, mirRect.width, mirRect.height),
              paint,
            );
            canvas.translate(-mirRect.left, -mirRect.top);
          }
          // Restore original center for next stamp
          shader.setFloat(0, scX);
          shader.setFloat(1, scY);
        }

        stampIdx++;
        t += adaptiveSpacing;
      }

      remainingDist = segLen - (t - adaptiveSpacing);
      if (remainingDist < 0) remainingDist = 0;
      accumulatedLen += segLen;
    }

    if (glazeMode) {
      canvas.restore();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CATMULL-ROM SPLINE RESAMPLING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Resample raw input points along a Catmull-Rom spline for smooth curves.
  /// Returns densely spaced points with interpolated position, pressure, and tilt.
  SplineResult _catmullRomResample(
    List<Offset> rawOffsets,
    List<double> rawPressures,
    List<dynamic> rawPoints,
  ) {
    final n = rawOffsets.length;
    if (n < 3) {
      // Too few points for spline — return as-is
      final tiltX = List<double>.generate(
        n,
        (i) =>
            rawPoints[i] is ProDrawingPoint
                ? (rawPoints[i] as ProDrawingPoint).tiltX
                : 0.0,
      );
      final tiltY = List<double>.generate(
        n,
        (i) =>
            rawPoints[i] is ProDrawingPoint
                ? (rawPoints[i] as ProDrawingPoint).tiltY
                : 0.0,
      );
      return SplineResult(rawOffsets, rawPressures, tiltX, tiltY);
    }

    // Extract tilt from raw points
    final rawTiltX = List<double>.generate(
      n,
      (i) =>
          rawPoints[i] is ProDrawingPoint
              ? (rawPoints[i] as ProDrawingPoint).tiltX
              : 0.0,
    );
    final rawTiltY = List<double>.generate(
      n,
      (i) =>
          rawPoints[i] is ProDrawingPoint
              ? (rawPoints[i] as ProDrawingPoint).tiltY
              : 0.0,
    );

    // Output lists
    final outOffsets = <Offset>[];
    final outPressures = <double>[];
    final outTiltX = <double>[];
    final outTiltY = <double>[];

    // Resample spacing: ~2 pixels between output points
    const resampleDist = 2.0;

    // Walk each segment through Catmull-Rom
    for (int i = 0; i < n - 1; i++) {
      // 4 control points: p[i-1], p[i], p[i+1], p[i+2] (clamped)
      final i0 = (i - 1).clamp(0, n - 1);
      final i1 = i;
      final i2 = (i + 1).clamp(0, n - 1);
      final i3 = (i + 2).clamp(0, n - 1);

      final p0 = rawOffsets[i0], p1 = rawOffsets[i1];
      final p2 = rawOffsets[i2], p3 = rawOffsets[i3];

      // Estimate segment arc length for step count
      final chordLen = (p2 - p1).distance;
      final steps = (chordLen / resampleDist).ceil().clamp(1, 200);

      for (int s = 0; s < steps; s++) {
        // Don't duplicate last point of each segment except the very last segment
        if (s == steps && i < n - 2) continue;

        final t = s / steps;
        final t2 = t * t;
        final t3 = t2 * t;

        // Catmull-Rom basis (tau=0.5)
        final dx =
            0.5 *
            ((2.0 * p1.dx) +
                (-p0.dx + p2.dx) * t +
                (2.0 * p0.dx - 5.0 * p1.dx + 4.0 * p2.dx - p3.dx) * t2 +
                (-p0.dx + 3.0 * p1.dx - 3.0 * p2.dx + p3.dx) * t3);
        final dy =
            0.5 *
            ((2.0 * p1.dy) +
                (-p0.dy + p2.dy) * t +
                (2.0 * p0.dy - 5.0 * p1.dy + 4.0 * p2.dy - p3.dy) * t2 +
                (-p0.dy + 3.0 * p1.dy - 3.0 * p2.dy + p3.dy) * t3);

        outOffsets.add(Offset(dx, dy));

        // Linearly interpolate scalar attributes
        final pr = rawPressures[i1] + (rawPressures[i2] - rawPressures[i1]) * t;
        outPressures.add(pr);

        final tx = rawTiltX[i1] + (rawTiltX[i2] - rawTiltX[i1]) * t;
        final ty = rawTiltY[i1] + (rawTiltY[i2] - rawTiltY[i1]) * t;
        outTiltX.add(tx);
        outTiltY.add(ty);
      }
    }

    // Always include the last raw point
    outOffsets.add(rawOffsets.last);
    outPressures.add(rawPressures.last);
    outTiltX.add(rawTiltX.last);
    outTiltY.add(rawTiltY.last);

    return SplineResult(outOffsets, outPressures, outTiltX, outTiltY);
  }
}
