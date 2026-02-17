import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../input/path_pool.dart';
import '../../rendering/optimization/optimization.dart';
import 'fountain_pen_buffers.dart';

// ============================================================================
// 🎨 FOUNTAIN PEN PATH BUILDER — GPU Vertex Tessellation
// ============================================================================

/// Static methods for building variable-width stroke paths using GPU vertex
/// tessellation with triangle strips, semicircular caps, and edge feathering.
///
/// DESIGN PRINCIPLES:
/// - All methods are static — no instance state needed
/// - Single GPU draw call via `drawVertices()` for maximum performance
/// - Chaikin corner-cutting for provably smooth outlines
/// - Edge feathering with semi-transparent fringe for hardware anti-aliasing
/// - Ink grain noise for realistic per-vertex alpha variation
abstract final class FountainPenPathBuilder {
  /// Builds path with variable width, sharp corner filling,
  /// and Catmull-Rom spline.
  /// Draws filled circles at sharp corners to prevent white gaps.
  static Path buildVariableWidthPath(
    List<dynamic> points,
    StrokeWidthBuffer widths,
    Canvas canvas,
    Color color,
    StrokeOffsetBuffer tangentBuf,
    StrokeOffsetBuffer leftBuf,
    StrokeOffsetBuffer rightBuf, {
    bool liveStroke = false,
  }) {
    final path = PathPool.instance.acquire();
    if (points.length < 2) return path;

    // ─── Pass 0: Extract and pre-smooth input positions ──────────
    // Raw touch/stylus points have digitizer noise. Smoothing positions
    // before computing tangents eliminates noise at the source.
    final smoothedPos = List<Offset>.generate(
      points.length,
      (i) => StrokeOptimizer.getOffset(points[i]),
    );
    if (smoothedPos.length >= 4) {
      const double posAlpha = 0.3;
      // 2 bidirectional passes: eliminates digitizer noise thoroughly
      for (int pass = 0; pass < 2; pass++) {
        // Forward — preserve first point
        for (int i = 1; i < smoothedPos.length - 1; i++) {
          smoothedPos[i] = Offset(
            smoothedPos[i - 1].dx * posAlpha +
                smoothedPos[i].dx * (1.0 - posAlpha),
            smoothedPos[i - 1].dy * posAlpha +
                smoothedPos[i].dy * (1.0 - posAlpha),
          );
        }
        // Backward — preserve last point
        for (int i = smoothedPos.length - 2; i > 0; i--) {
          smoothedPos[i] = Offset(
            smoothedPos[i + 1].dx * posAlpha +
                smoothedPos[i].dx * (1.0 - posAlpha),
            smoothedPos[i + 1].dy * posAlpha +
                smoothedPos[i].dy * (1.0 - posAlpha),
          );
        }
      }

      // Curvature-adaptive pass: smooth extra at sharp turns
      for (int i = 2; i < smoothedPos.length - 2; i++) {
        final v1 = smoothedPos[i] - smoothedPos[i - 1];
        final v2 = smoothedPos[i + 1] - smoothedPos[i];
        final cross = (v1.dx * v2.dy - v1.dy * v2.dx).abs();
        final dot = v1.dx * v2.dx + v1.dy * v2.dy;
        final angle = math.atan2(cross, dot);
        final blend = (angle / math.pi).clamp(0.0, 1.0) * 0.4;
        if (blend > 0.02) {
          final avg = (smoothedPos[i - 1] + smoothedPos[i + 1]) / 2.0;
          smoothedPos[i] = Offset(
            smoothedPos[i].dx * (1.0 - blend) + avg.dx * blend,
            smoothedPos[i].dy * (1.0 - blend) + avg.dy * blend,
          );
        }
      }
    }

    // ─── Pass 0b: Arc-length re-parameterization ──────────────────
    // Touchscreen samples at uniform TIME intervals, not SPACE.
    // Fast movements → sparse points (visible corners).
    // Slow movements → dense points (over-smoothing).
    // Re-sample at uniform arc-length for consistent quality.
    if (smoothedPos.length >= 4) {
      // 1. Compute cumulative arc length
      final arcLens = List<double>.filled(smoothedPos.length, 0.0);
      for (int i = 1; i < smoothedPos.length; i++) {
        arcLens[i] =
            arcLens[i - 1] + (smoothedPos[i] - smoothedPos[i - 1]).distance;
      }
      final totalLen = arcLens.last;

      if (totalLen > 1.0) {
        // 2. Target uniform spacing: same point count but uniform distance
        final numSamples = smoothedPos.length;
        final step = totalLen / (numSamples - 1);

        final resampledPos = <Offset>[smoothedPos.first];
        final resampledW = StrokeWidthBuffer();
        resampledW.reset(numSamples);
        resampledW.add(widths[0]);

        int seg = 0; // current segment index
        for (int s = 1; s < numSamples - 1; s++) {
          final targetLen = s * step;

          // Advance segment until we bracket targetLen
          while (seg < smoothedPos.length - 2 && arcLens[seg + 1] < targetLen) {
            seg++;
          }

          // Interpolate within segment [seg, seg+1]
          final segLen = arcLens[seg + 1] - arcLens[seg];
          final frac =
              segLen > 0.001 ? (targetLen - arcLens[seg]) / segLen : 0.0;

          // Lerp position
          final p0 = smoothedPos[seg];
          final p1 = smoothedPos[seg + 1];
          resampledPos.add(
            Offset(
              p0.dx + (p1.dx - p0.dx) * frac,
              p0.dy + (p1.dy - p0.dy) * frac,
            ),
          );

          // Lerp width (map seg to original width buffer)
          final wIdx0 = (seg / (smoothedPos.length - 1) * (widths.length - 1))
              .clamp(0.0, widths.length - 1.0);
          final wIdx1 = ((seg + 1) /
                  (smoothedPos.length - 1) *
                  (widths.length - 1))
              .clamp(0.0, widths.length - 1.0);
          final w0 = widths[wIdx0.floor().clamp(0, widths.length - 1)];
          final w1 = widths[wIdx1.ceil().clamp(0, widths.length - 1)];
          resampledW.add(w0 + (w1 - w0) * frac);
        }

        resampledPos.add(smoothedPos.last);
        resampledW.add(widths[widths.length - 1]);

        // Replace smoothedPos and widths with resampled versions
        smoothedPos.clear();
        smoothedPos.addAll(resampledPos);

        // Copy resampled widths back to widths buffer
        widths.reset(resampledW.length);
        for (int i = 0; i < resampledW.length; i++) {
          widths.add(resampledW[i]);
        }
      }
    }

    // Reset outline buffers to match (possibly resampled) point count
    leftBuf.reset(smoothedPos.length);
    rightBuf.reset(smoothedPos.length);

    computeSmoothedTangentsFromOffsets(smoothedPos, tangentBuf);
    final paint = PaintPool.getFillPaint(color: color);

    // ─── Pass 1: Compute all outline points ──────────────────────
    for (int i = 0; i < smoothedPos.length; i++) {
      final current = smoothedPos[i];
      final halfWidth = widths[i] / 2;
      final tangent = tangentBuf[i];
      final normal = Offset(-tangent.dy, tangent.dx);

      leftBuf.add(current + normal * halfWidth);
      rightBuf.add(current - normal * halfWidth);
    }

    // ─── Pass 1b: Smooth outlines (adaptive EMA) ──────────────────
    // Wider strokes need stronger smoothing (bumps more visible).
    double avgWidth = 0;
    for (int i = 0; i < widths.length; i++) avgWidth += widths[i];
    avgWidth /= widths.length;
    smoothOutlinePoints(leftBuf, avgWidth);
    smoothOutlinePoints(rightBuf, avgWidth);

    // ─── Pass 1c: Chaikin corner-cutting ──────────────────────
    if (leftBuf.length >= 4) {
      applyChaikinSubdivision(leftBuf);
      applyChaikinSubdivision(leftBuf); // 2nd iteration
      applyChaikinSubdivision(rightBuf);
      applyChaikinSubdivision(rightBuf); // 2nd iteration
    }

    // ─── Pass 1c: Fix crossed outlines ───────────────────────────
    // At sharp corners with large widths, left/right outlines can
    // cross each other (self-intersection), creating holes in the
    // fill. Detect this via cross product and collapse both points
    // toward the center to uncross them.
    for (int i = 1; i < leftBuf.length; i++) {
      final currCenter = (leftBuf[i] + rightBuf[i]) / 2.0;

      // Direction from prev to current along left edge
      final prevLR = rightBuf[i - 1] - leftBuf[i - 1];
      final currLR = rightBuf[i] - leftBuf[i];

      // Cross product detects if left-right direction flipped (crossing)
      final cross = prevLR.dx * currLR.dy - prevLR.dy * currLR.dx;
      final dot = prevLR.dx * currLR.dx + prevLR.dy * currLR.dy;

      if (dot < 0 || cross.abs() > (prevLR.distance * currLR.distance * 0.95)) {
        // Outlines crossed: collapse to center
        leftBuf[i] = currCenter;
        rightBuf[i] = currCenter;
      }
    }

    // ═══════════════════════════════════════════════════════════
    // GPU VERTEX TESSELLATION — triangle strip + semicircular caps
    // ═══════════════════════════════════════════════════════════
    // Instead of Path-based rendering (Impeller internal tessellation),
    // we build the triangle mesh ourselves and send it directly
    // to the GPU via drawVertices(). Benefits:
    //   • Hardware sub-pixel precision + MSAA anti-aliasing
    //   • One draw call (no backing fill + path overlay needed)
    //   • Dense Chaikin-subdivided outlines → ultra-smooth edges
    // ═══════════════════════════════════════════════════════════

    final n = leftBuf.length;
    if (n < 2) return path;

    // Estimate: body = 2n positions, each cap ≤ 12 positions
    final positions = <Offset>[];
    final indices = <int>[];
    final colors = <Color>[];

    // Pre-compute per-outline-point alpha from width (pressure proxy).
    // After Chaikin 2x, outline has ~4x original points.
    // Map each outline index back to parametric t ∈ [0,1] and interpolate
    // the original width buffer to get pressure-based alpha.
    final baseAlpha = (color.a * 255.0).round().clamp(0, 255);
    final cR = (color.r * 255.0).round().clamp(0, 255);
    final cG = (color.g * 255.0).round().clamp(0, 255);
    final cB = (color.b * 255.0).round().clamp(0, 255);
    final origLen = widths.length;

    // Pre-compute max width for ink pooling normalization
    double maxW = 0.01;
    for (int i = 0; i < origLen; i++) {
      if (widths[i] > maxW) maxW = widths[i];
    }

    // Deterministic ink grain noise seed (varies per stroke position)
    final noiseSeed = color.hashCode * 0.001;

    // ─── Body: interleave left/right into triangle strip ──────
    for (int i = 0; i < n; i++) {
      // Map outline index → original width buffer via parametric t
      final t = i / (n - 1).toDouble();
      final wIdx = (t * (origLen - 1)).clamp(0.0, origLen - 1.0);
      final wLow = wIdx.floor();
      final wHigh = wIdx.ceil().clamp(0, origLen - 1);
      final wFrac = wIdx - wLow;
      final w = widths[wLow] * (1.0 - wFrac) + widths[wHigh] * wFrac;

      // Ink effects: pooling + grain
      final poolFactor = 0.80 + 0.20 * (w / maxW).clamp(0.0, 1.0);
      final grainL = inkNoise(i * 2, noiseSeed);
      final grainR = inkNoise(i * 2 + 1, noiseSeed);

      // Asymmetric edge depth: left=93%, right=90% (simulates nib tilt)
      final leftAlpha = (baseAlpha * poolFactor * (0.93 + grainL))
          .round()
          .clamp(0, 255);
      final rightAlpha = (baseAlpha * poolFactor * (0.90 + grainR))
          .round()
          .clamp(0, 255);

      positions.add(leftBuf[i]); // index 2*i
      colors.add(Color.fromARGB(leftAlpha, cR, cG, cB));
      positions.add(rightBuf[i]); // index 2*i + 1
      colors.add(Color.fromARGB(rightAlpha, cR, cG, cB));
    }
    for (int i = 0; i < n - 1; i++) {
      final li = 2 * i;
      final ri = 2 * i + 1;
      final lNext = 2 * (i + 1);
      final rNext = 2 * (i + 1) + 1;
      indices.add(li);
      indices.add(ri);
      indices.add(lNext);
      indices.add(ri);
      indices.add(lNext);
      indices.add(rNext);
    }

    // ─── Edge feathering: semi-transparent fringe for AA ──────
    // For each edge vertex, add a fringe vertex 0.75px outward
    // with alpha=0. GPU interpolates → smooth anti-aliased edge.
    {
      const double fringeWidth = 0.75; // px outward
      final fringeAlpha = Color.fromARGB(0, cR, cG, cB); // transparent

      // Left edge fringe
      final leftFringeStart = positions.length;
      for (int i = 0; i < n; i++) {
        // Outward normal at this point (away from stroke center)
        final center = (leftBuf[i] + rightBuf[i]) / 2.0;
        final toLeft = leftBuf[i] - center;
        final dist = toLeft.distance;
        final outward =
            dist > 0.01
                ? Offset(toLeft.dx / dist, toLeft.dy / dist)
                : const Offset(0, -1);

        positions.add(leftBuf[i] + outward * fringeWidth);
        colors.add(fringeAlpha);
      }
      // Triangle strip: edge[i] → fringe[i]
      for (int i = 0; i < n - 1; i++) {
        final eIdx = 2 * i; // left edge vertex in body
        final eNext = 2 * (i + 1);
        final fIdx = leftFringeStart + i;
        final fNext = leftFringeStart + i + 1;
        indices.addAll([eIdx, fIdx, eNext]);
        indices.addAll([fIdx, eNext, fNext]);
      }

      // Right edge fringe
      final rightFringeStart = positions.length;
      for (int i = 0; i < n; i++) {
        final center = (leftBuf[i] + rightBuf[i]) / 2.0;
        final toRight = rightBuf[i] - center;
        final dist = toRight.distance;
        final outward =
            dist > 0.01
                ? Offset(toRight.dx / dist, toRight.dy / dist)
                : const Offset(0, 1);

        positions.add(rightBuf[i] + outward * fringeWidth);
        colors.add(fringeAlpha);
      }
      for (int i = 0; i < n - 1; i++) {
        final eIdx = 2 * i + 1; // right edge vertex in body
        final eNext = 2 * (i + 1) + 1;
        final fIdx = rightFringeStart + i;
        final fNext = rightFringeStart + i + 1;
        indices.addAll([eIdx, fIdx, eNext]);
        indices.addAll([fIdx, eNext, fNext]);
      }
    }

    // ─── End cap: semicircular fan ────────────────────────────
    final lastL = leftBuf[n - 1];
    final lastR = rightBuf[n - 1];
    final endCenter = (lastL + lastR) / 2.0;
    final endRadius = (lastL - lastR).distance / 2.0;
    if (endRadius > 0.1) {
      const int endSegs = 10;
      final baseAngle = math.atan2(
        lastL.dy - endCenter.dy,
        lastL.dx - endCenter.dx,
      );
      final capAlpha = (baseAlpha * 0.95).round().clamp(0, 255);
      final centerIdx = positions.length;
      positions.add(endCenter);
      colors.add(Color.fromARGB(capAlpha, cR, cG, cB));
      final firstArcIdx = positions.length;
      for (int s = 0; s <= endSegs; s++) {
        final a = baseAngle - math.pi * s / endSegs;
        positions.add(
          Offset(
            endCenter.dx + endRadius * math.cos(a),
            endCenter.dy + endRadius * math.sin(a),
          ),
        );
        // Slight fade toward perimeter
        final edgeAlpha = (capAlpha * 0.90).round().clamp(0, 255);
        colors.add(Color.fromARGB(edgeAlpha, cR, cG, cB));
      }
      for (int s = 0; s < endSegs; s++) {
        indices.add(centerIdx);
        indices.add(firstArcIdx + s);
        indices.add(firstArcIdx + s + 1);
      }
    }

    // ─── Start cap: semicircular fan ─────────────────────────
    final firstL = leftBuf[0];
    final firstR = rightBuf[0];
    final startCenter = (firstL + firstR) / 2.0;
    final startRadius = (firstL - firstR).distance / 2.0;
    if (startRadius > 0.1) {
      const int startSegs = 10;
      final baseAngle = math.atan2(
        firstR.dy - startCenter.dy,
        firstR.dx - startCenter.dx,
      );
      final capAlpha = (baseAlpha * 0.95).round().clamp(0, 255);
      final centerIdx = positions.length;
      positions.add(startCenter);
      colors.add(Color.fromARGB(capAlpha, cR, cG, cB));
      final firstArcIdx = positions.length;
      for (int s = 0; s <= startSegs; s++) {
        final a = baseAngle - math.pi * s / startSegs;
        positions.add(
          Offset(
            startCenter.dx + startRadius * math.cos(a),
            startCenter.dy + startRadius * math.sin(a),
          ),
        );
        final edgeAlpha = (capAlpha * 0.90).round().clamp(0, 255);
        colors.add(Color.fromARGB(edgeAlpha, cR, cG, cB));
      }
      for (int s = 0; s < startSegs; s++) {
        indices.add(centerIdx);
        indices.add(firstArcIdx + s);
        indices.add(firstArcIdx + s + 1);
      }
    }

    // ─── GPU draw: single call with per-vertex colors ─────────
    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      indices: indices,
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    vertices.dispose();

    // Return empty path — all rendering done via drawVertices
    return path;
  }

  /// Smooth outline points (left or right contour) with adaptive EMA.
  /// Alpha scales with stroke width: wider strokes get stronger smoothing.
  /// Preserves first/last points for correct start/end caps.
  static void smoothOutlinePoints(StrokeOffsetBuffer buf, double avgWidth) {
    if (buf.length < 4) return;
    // Adaptive: thin strokes (1-3px) → alpha 0.35, thick (15+px) → alpha 0.65
    final double alpha = (0.35 + (avgWidth / 40.0).clamp(0.0, 0.30));
    // Number of passes scales with width too (2 for thin, 3 for thick)
    final int passes = avgWidth > 8.0 ? 3 : 2;

    for (int pass = 0; pass < passes; pass++) {
      // Forward
      for (int i = 1; i < buf.length - 1; i++) {
        buf[i] = Offset(
          buf[i - 1].dx * alpha + buf[i].dx * (1.0 - alpha),
          buf[i - 1].dy * alpha + buf[i].dy * (1.0 - alpha),
        );
      }
      // Backward
      for (int i = buf.length - 2; i > 0; i--) {
        buf[i] = Offset(
          buf[i + 1].dx * alpha + buf[i].dx * (1.0 - alpha),
          buf[i + 1].dy * alpha + buf[i].dy * (1.0 - alpha),
        );
      }
    }
  }

  /// Chaikin corner-cutting subdivision (1 iteration).
  /// Replaces each segment with two new points at 25% and 75%,
  /// converging to a quadratic B-spline for provably smooth curves.
  /// Overwrites the buffer with the subdivided (denser) point set.
  static void applyChaikinSubdivision(StrokeOffsetBuffer buf) {
    if (buf.length < 3) return;
    final n = buf.length;
    // Build subdivided list (2*(n-1) + 1 points: keeps first & last)
    final subdivided = <Offset>[buf[0]];
    for (int i = 0; i < n - 1; i++) {
      final p0 = buf[i];
      final p1 = buf[i + 1];
      // Q = 0.75*P0 + 0.25*P1
      subdivided.add(
        Offset(p0.dx * 0.75 + p1.dx * 0.25, p0.dy * 0.75 + p1.dy * 0.25),
      );
      // R = 0.25*P0 + 0.75*P1
      subdivided.add(
        Offset(p0.dx * 0.25 + p1.dx * 0.75, p0.dy * 0.25 + p1.dy * 0.75),
      );
    }
    subdivided.add(buf[n - 1]);

    // Write back into buffer
    buf.reset(subdivided.length);
    for (final p in subdivided) {
      buf.add(p);
    }
  }

  /// Deterministic ink grain noise for per-vertex alpha variation.
  /// Returns [-0.03, +0.03] based on vertex index and seed.
  /// Fast hash — no state, no allocation.
  static double inkNoise(int index, double seed) {
    final x = index * 12.9898 + seed * 78.233;
    // Classic sin-hash: fract(sin(x) * 43758.5453)
    final h = (math.sin(x) * 43758.5453) % 1.0;
    return (h - 0.5) * 0.06; // ±3%
  }

  /// Tangent computation from pre-extracted Offsets (7-point window).
  static void computeSmoothedTangentsFromOffsets(
    List<Offset> pts,
    StrokeOffsetBuffer buf,
  ) {
    final n = pts.length;
    buf.reset(n);

    for (int i = 0; i < n; i++) {
      Offset tangent;
      if (i == 0) {
        tangent = pts[1] - pts[0];
      } else if (i == n - 1) {
        tangent = pts[n - 1] - pts[n - 2];
      } else {
        tangent = pts[i + 1] - pts[i - 1]; // ±1 near

        if (i >= 2 && i < n - 2) {
          final farTangent = pts[i + 2] - pts[i - 2]; // ±2 mid
          tangent = tangent * 0.6 + farTangent * 0.3;

          if (i >= 3 && i < n - 3) {
            final veryFarTangent = pts[i + 3] - pts[i - 3]; // ±3 far
            tangent = tangent + veryFarTangent * 0.1;
          }
        }
      }

      final len = tangent.distance;
      buf.add(len > 0 ? tangent / len : const Offset(1, 0));
    }
  }
}
