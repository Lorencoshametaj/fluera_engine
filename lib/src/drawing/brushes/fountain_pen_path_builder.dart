import 'dart:math' as math;
import 'dart:typed_data';
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
  // 🚀 Pre-allocated arc-length buffer (avoids per-call allocation + GC)
  static var _arcLenBuf = Float64List(512);

  // 🚀 Pre-allocated GPU vertex buffers (typed arrays for Vertices.raw())
  static var _posBuf = Float32List(4096); // x,y pairs
  static var _colBuf = Int32List(2048); // packed ARGB
  static var _idxBuf = Uint16List(8192); // triangle indices

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
    int drawFromIndex = 0,
    double nibAngleRad = 0.0,
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
      // Always 2 smoothing passes (same as finalized) to prevent snap
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
    // Always applied (same as finalized) to prevent snap.
    // 🚀 PERF: Skip for very short strokes (< 10 pts) — negligible benefit.
    if (smoothedPos.length >= 10) {
      final n = smoothedPos.length;
      if (_arcLenBuf.length < n) _arcLenBuf = Float64List(n * 2);
      _arcLenBuf[0] = 0.0;
      for (int i = 1; i < n; i++) {
        _arcLenBuf[i] =
            _arcLenBuf[i - 1] + (smoothedPos[i] - smoothedPos[i - 1]).distance;
      }
      final totalLen = _arcLenBuf[n - 1];

      if (totalLen > 1.0) {
        final numSamples = smoothedPos.length;
        final step = totalLen / (numSamples - 1);

        final resampledPos = <Offset>[smoothedPos.first];
        final resampledW = StrokeWidthBuffer();
        resampledW.reset(numSamples);
        resampledW.add(widths[0]);

        int seg = 0;
        for (int s = 1; s < numSamples - 1; s++) {
          final targetLen = s * step;
          while (seg < smoothedPos.length - 2 &&
              _arcLenBuf[seg + 1] < targetLen) {
            seg++;
          }
          final segLen = _arcLenBuf[seg + 1] - _arcLenBuf[seg];
          final frac =
              segLen > 0.001 ? (targetLen - _arcLenBuf[seg]) / segLen : 0.0;

          final p0 = smoothedPos[seg];
          final p1 = smoothedPos[seg + 1];
          resampledPos.add(
            Offset(
              p0.dx + (p1.dx - p0.dx) * frac,
              p0.dy + (p1.dy - p0.dy) * frac,
            ),
          );

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

        smoothedPos.clear();
        smoothedPos.addAll(resampledPos);

        widths.reset(resampledW.length);
        for (int i = 0; i < resampledW.length; i++) {
          widths.add(resampledW[i]);
        }
      }
    }

    // Reset outline buffers to match (possibly resampled) point count.
    // Outline is ALWAYS computed for all points — Chaikin needs full context.
    leftBuf.reset(smoothedPos.length);
    rightBuf.reset(smoothedPos.length);

    computeSmoothedTangentsFromOffsets(smoothedPos, tangentBuf);
    final paint = PaintPool.getFillPaint(color: color);

    // ─── Pass 1: Compute ALL outline points ──────────────────────
    // 🖋️ Enhancement 5: Nib shear (parallelogram cross-section).
    // Real broad-edge nibs create a sheared profile — the ink mark
    // is not symmetric around the center line but shifted along
    // the tangent by the nib angle. This adds authentic calligraphic
    // character at larger widths.
    final shearFactor = math.sin(nibAngleRad) * 0.15;
    for (int i = 0; i < smoothedPos.length; i++) {
      final current = smoothedPos[i];
      final halfWidth = widths[i] / 2;
      final tangent = tangentBuf[i];
      final normal = Offset(-tangent.dy, tangent.dx);
      final shear = tangent * (halfWidth * shearFactor);

      leftBuf.add(current + normal * halfWidth + shear);
      rightBuf.add(current - normal * halfWidth - shear);
    }

    // ─── Pass 1b: Smooth outlines (adaptive EMA) ──────────────────
    // Wider strokes need stronger smoothing (bumps more visible).
    double avgWidth = 0;
    for (int i = 0; i < widths.length; i++) avgWidth += widths[i];
    avgWidth /= widths.length;
    smoothOutlinePoints(leftBuf, avgWidth);
    smoothOutlinePoints(rightBuf, avgWidth);

    // ─── Pass 1c: Chaikin corner-cutting ──────────────────────
    // 🚀 LIVE PERF: 1 pass for live strokes (halves outline density),
    // 2 passes for finalized quality.
    if (leftBuf.length >= 4) {
      applyChaikinSubdivision(leftBuf);
      applyChaikinSubdivision(rightBuf);
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

    // ═══════════════════════════════════════════════════════════
    // 🚀 GPU VERTEX TESSELLATION — typed arrays + Vertices.raw()
    // ═══════════════════════════════════════════════════════════
    // Pre-allocated static buffers eliminate thousands of Offset/Color
    // object allocations per frame. Vertices.raw() skips the internal
    // typed-array conversion that ui.Vertices() does.
    //
    // Estimate vertices: body=2*tessLen, caps=2*12, feathering=2*n
    final origLen = widths.length;
    final tessStart =
        drawFromIndex > 0
            ? (drawFromIndex / origLen * n).round().clamp(0, n - 1)
            : 0;
    final tessLen = n - tessStart;
    final maxVerts = 2 * tessLen + 2 * n + 30; // body + feathering + caps
    final maxIndices =
        6 * (tessLen - 1) +
        6 * 2 * (n - 1) +
        6 * 20; // body + feathering + caps

    // Grow static buffers if needed
    if (_posBuf.length < maxVerts * 2) _posBuf = Float32List(maxVerts * 3);
    if (_colBuf.length < maxVerts) _colBuf = Int32List(maxVerts * 2);
    if (_idxBuf.length < maxIndices) _idxBuf = Uint16List(maxIndices * 2);

    int vi = 0; // vertex write index
    int ii = 0; // index write index

    // Pre-compute per-outline-point alpha from width (pressure proxy).
    final baseAlpha = (color.a * 255.0).round().clamp(0, 255);
    final cR = (color.r * 255.0).round().clamp(0, 255);
    final cG = (color.g * 255.0).round().clamp(0, 255);
    final cB = (color.b * 255.0).round().clamp(0, 255);

    // Pre-compute max width for ink pooling normalization
    double maxW = 0.01;
    for (int i = 0; i < origLen; i++) {
      if (widths[i] > maxW) maxW = widths[i];
    }

    // Deterministic ink grain noise seed (varies per stroke position)
    final noiseSeed = color.hashCode * 0.001;

    // ─── Body: interleave left/right into triangle strip ──────
    for (int i = tessStart; i < n; i++) {
      final t = n > 1 ? i / (n - 1) : 0.0;
      final wIdx = (t * (origLen - 1)).clamp(0.0, origLen - 1.0);
      final wLow = wIdx.floor();
      final wHigh = wIdx.ceil().clamp(0, origLen - 1);
      final wFrac = wIdx - wLow;
      final w = widths[wLow] * (1.0 - wFrac) + widths[wHigh] * wFrac;

      // Solid uniform alpha — no ink pooling or grain noise
      final vertexAlpha = baseAlpha;

      // Left vertex
      _posBuf[vi * 2] = leftBuf[i].dx;
      _posBuf[vi * 2 + 1] = leftBuf[i].dy;
      _colBuf[vi] = (vertexAlpha << 24) | (cR << 16) | (cG << 8) | cB;
      vi++;
      // Right vertex
      _posBuf[vi * 2] = rightBuf[i].dx;
      _posBuf[vi * 2 + 1] = rightBuf[i].dy;
      _colBuf[vi] = (vertexAlpha << 24) | (cR << 16) | (cG << 8) | cB;
      vi++;
    }
    for (int i = 0; i < tessLen - 1; i++) {
      final li = 2 * i;
      final ri = 2 * i + 1;
      final lNext = 2 * (i + 1);
      final rNext = 2 * (i + 1) + 1;
      _idxBuf[ii++] = li;
      _idxBuf[ii++] = ri;
      _idxBuf[ii++] = lNext;
      _idxBuf[ii++] = ri;
      _idxBuf[ii++] = lNext;
      _idxBuf[ii++] = rNext;
    }

    // Edge feathering: REMOVED for uniform Vulkan→Dart pipeline.
    // Both live and committed now produce identical geometry.

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
      final capArgb = (baseAlpha << 24) | (cR << 16) | (cG << 8) | cB;
      final edgeArgb = capArgb; // Solid alpha for caps too

      final centerIdx = vi;
      _posBuf[vi * 2] = endCenter.dx;
      _posBuf[vi * 2 + 1] = endCenter.dy;
      _colBuf[vi] = capArgb;
      vi++;
      final firstArcIdx = vi;
      for (int s = 0; s <= endSegs; s++) {
        final a = baseAngle - math.pi * s / endSegs;
        _posBuf[vi * 2] = endCenter.dx + endRadius * math.cos(a);
        _posBuf[vi * 2 + 1] = endCenter.dy + endRadius * math.sin(a);
        _colBuf[vi] = edgeArgb;
        vi++;
      }
      for (int s = 0; s < endSegs; s++) {
        _idxBuf[ii++] = centerIdx;
        _idxBuf[ii++] = firstArcIdx + s;
        _idxBuf[ii++] = firstArcIdx + s + 1;
      }
    }

    // ─── Start cap: semicircular fan ─────────────────────────
    if (drawFromIndex <= 0) {
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
        final capArgb = (baseAlpha << 24) | (cR << 16) | (cG << 8) | cB;
        final edgeArgb = capArgb; // Solid alpha for caps too

        final centerIdx = vi;
        _posBuf[vi * 2] = startCenter.dx;
        _posBuf[vi * 2 + 1] = startCenter.dy;
        _colBuf[vi] = capArgb;
        vi++;
        final firstArcIdx = vi;
        for (int s = 0; s <= startSegs; s++) {
          final a = baseAngle - math.pi * s / startSegs;
          _posBuf[vi * 2] = startCenter.dx + startRadius * math.cos(a);
          _posBuf[vi * 2 + 1] = startCenter.dy + startRadius * math.sin(a);
          _colBuf[vi] = edgeArgb;
          vi++;
        }
        for (int s = 0; s < startSegs; s++) {
          _idxBuf[ii++] = centerIdx;
          _idxBuf[ii++] = firstArcIdx + s;
          _idxBuf[ii++] = firstArcIdx + s + 1;
        }
      }
    }

    // ─── GPU draw: single call with raw typed arrays ──────────
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_posBuf, 0, vi * 2),
      colors: Int32List.sublistView(_colBuf, 0, vi),
      indices: Uint16List.sublistView(_idxBuf, 0, ii),
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
  ///
  /// 🚀 PERF: Uses static scratch list to avoid per-call GC allocation.
  static List<Offset> _chaikinScratch = [];

  static void applyChaikinSubdivision(StrokeOffsetBuffer buf) {
    if (buf.length < 3) return;
    final n = buf.length;
    // Expected output size: 2*(n-1) + 2 (first + last preserved)
    final expectedLen = 2 * (n - 1) + 2;
    if (_chaikinScratch.length < expectedLen) {
      _chaikinScratch = List<Offset>.filled(expectedLen * 2, Offset.zero);
    }

    int outIdx = 0;
    _chaikinScratch[outIdx++] = buf[0];
    for (int i = 0; i < n - 1; i++) {
      final p0 = buf[i];
      final p1 = buf[i + 1];
      // Q = 0.75*P0 + 0.25*P1
      _chaikinScratch[outIdx++] = Offset(
        p0.dx * 0.75 + p1.dx * 0.25,
        p0.dy * 0.75 + p1.dy * 0.25,
      );
      // R = 0.25*P0 + 0.75*P1
      _chaikinScratch[outIdx++] = Offset(
        p0.dx * 0.25 + p1.dx * 0.75,
        p0.dy * 0.25 + p1.dy * 0.75,
      );
    }
    _chaikinScratch[outIdx++] = buf[n - 1];

    // Write back into buffer
    buf.reset(outIdx);
    for (int i = 0; i < outIdx; i++) {
      buf.add(_chaikinScratch[i]);
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
