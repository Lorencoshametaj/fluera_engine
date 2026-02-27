import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../rendering/optimization/optimization.dart';
import '../../rendering/shaders/shader_brush_service.dart';
import '../../core/engine_scope.dart';
import '../../rendering/shaders/shader_pencil_renderer.dart';
import 'fountain_pen_path_builder.dart';

/// ✏️ Pencil Brush — Realistic graphite rendering
///
/// Pipeline (aligned with FountainPenBrush):
///   Input → Finger/Stylus detect → Pre-smooth → Pressure → Taper →
///   Width smooth → 7-pt tangent → Outline → Outline smooth →
///   GPU tessellation (drawVertices)
///
/// Features:
/// - Pressure-variable width and opacity
/// - Velocity-based opacity (slow = darker = more graphite)
/// - Entry/exit tapering for natural endpoints
/// - Finger vs stylus detection (simulated pressure for finger)
/// - Pre-allocated buffers for zero-GC rendering
/// - GPU vertex tessellation with per-vertex alpha
/// - Position pre-smoothing (bidirectional EMA)
/// - 7-point multi-tier tangent computation
/// - Adaptive outline smoothing
class PencilBrush {
  // 🚀 Pre-allocated arc-length buffer (avoids per-call allocation + GC)
  static var _arcLenBuf = Float64List(512);

  // 🚀 Pre-allocated GPU vertex buffers (typed arrays for Vertices.raw())
  static var _posBuf = Float32List(4096); // x,y pairs
  static var _colBuf = Int32List(2048); // packed ARGB
  static var _idxBuf = Uint16List(8192); // triangle indices
  static const String name = 'Matita';
  static const IconData icon = Icons.create;
  static const double defaultWidthMultiplier = 1.0;
  static const double baseOpacity = 0.4;
  static const double maxOpacity = 0.8;
  static const StrokeCap strokeCap = StrokeCap.round;
  static const StrokeJoin strokeJoin = StrokeJoin.round;
  static const bool usePressureForWidth = true;
  static const bool usePressureForOpacity = true;
  static const bool hasBlur = true;
  static const double blurRadius = 0.3;
  static const double minPressureFactor = 0.5;
  static const double maxPressureFactor = 1.2;

  // Tapering defaults (shorter than fountain pen — pencil is simpler)
  static const int taperEntryPoints = 4;
  static const int taperExitPoints = 5;

  // ── Pre-allocated buffers (dual A/B for concurrent painters) ──
  static final _WidthBuffer _widthBufA = _WidthBuffer();
  static final _WidthBuffer _widthBufB = _WidthBuffer();
  static bool _bufAInUse = false;

  static final _OffsetBuffer _leftBufA = _OffsetBuffer();
  static final _OffsetBuffer _leftBufB = _OffsetBuffer();
  static final _OffsetBuffer _rightBufA = _OffsetBuffer();
  static final _OffsetBuffer _rightBufB = _OffsetBuffer();
  static final _OffsetBuffer _tangentBufA = _OffsetBuffer();
  static final _OffsetBuffer _tangentBufB = _OffsetBuffer();

  /// ✏️ Draw with default parameters
  static void drawStroke(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth,
  ) {
    drawStrokeWithSettings(
      canvas,
      points,
      color,
      baseWidth,
      baseOpacity: baseOpacity,
      maxOpacity: maxOpacity,
      blurRadius: blurRadius,
      minPressure: minPressureFactor,
      maxPressure: maxPressureFactor,
    );
  }

  /// 🎛️ Draw with custom parameters
  static void drawStrokeWithSettings(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    required double baseOpacity,
    required double maxOpacity,
    required double blurRadius,
    required double minPressure,
    required double maxPressure,
    bool isPro = false,
    ui.Image? textureImage,
    double textureScale = 0.0,
    bool liveStroke = false,
    int drawFromIndex = 0,
    double surfaceRoughness = 0.0,
    double surfaceAbsorption = 0.0,
    double surfacePigmentRetention = 1.0,
  }) {
    if (points.isEmpty) return;

    // GPU Pro path
    final _shaderSvc =
        EngineScope.hasScope
            ? EngineScope.current.drawingModule?.shaderBrushService
            : null;
    final useGpu = isPro || (_shaderSvc?.isProEnabled ?? false);
    if (useGpu && (_shaderSvc?.isAvailable ?? false) && points.length >= 2) {
      _shaderSvc!.renderPencilPro(
        canvas,
        points,
        color,
        baseWidth,
        baseOpacity: baseOpacity,
        maxOpacity: maxOpacity,
        minPressure: minPressure,
        maxPressure: maxPressure,
        textureImage: textureImage,
        textureScale: textureScale,
        surfaceRoughness: surfaceRoughness,
        surfaceAbsorption: surfaceAbsorption,
        surfacePigmentRetention: surfacePigmentRetention,
      );
      return;
    }

    // Single point: dot
    if (points.length == 1) {
      final offset = StrokeOptimizer.getOffset(points.first);
      final pressure = _getPressure(points.first);
      final opacity = baseOpacity + (pressure * (maxOpacity - baseOpacity));
      final width =
          baseWidth * (minPressure + pressure * (maxPressure - minPressure));
      final paint = PaintPool.getBlurPaint(
        color: color.withValues(alpha: opacity),
        strokeWidth: width,
        blurRadius: blurRadius,
      );
      canvas.drawCircle(offset, width * 0.4, paint);
      return;
    }

    // === PIPELINE ===

    // Acquire buffer set (A or B)
    final useA = !_bufAInUse;
    _bufAInUse = true;
    final widthBuf = useA ? _widthBufA : _widthBufB;
    final leftBuf = useA ? _leftBufA : _leftBufB;
    final rightBuf = useA ? _rightBufA : _rightBufB;
    final tangentBuf = useA ? _tangentBufA : _tangentBufB;

    try {
      // 1. Calculate widths with finger/stylus detection
      _calculateWidths(points, baseWidth, minPressure, maxPressure, widthBuf);

      // 2. Tapering — suppress exit taper ALWAYS (unified pipeline).
      // Exit taper during live was already 0. Applying it only on finalization
      // caused visible snap + visual shortening at the end of the stroke.
      _applyTapering(widthBuf, taperEntryPoints, 0);

      // 3. Smooth widths in-place (forward EMA)
      _smoothWidthsInPlace(widthBuf);

      // 4. Calculate average opacity from pressure
      double totalPressure = 0;
      for (final point in points) {
        totalPressure += _getPressure(point);
      }
      final avgPressure = totalPressure / points.length;
      final avgOpacity = (baseOpacity +
              (maxOpacity - baseOpacity) * avgPressure)
          .clamp(0.0, 1.0);

      // 5. Build variable-width path with GPU tessellation
      _buildVariableWidthPath(
        canvas,
        points,
        widthBuf,
        leftBuf,
        rightBuf,
        tangentBuf,
        color,
        avgOpacity,
        liveStroke,
        drawFromIndex: drawFromIndex,
      );
    } finally {
      if (useA) _bufAInUse = false;
    }
  }

  // ──────────────────────────────────────────────────────────
  // Width Calculation
  // ──────────────────────────────────────────────────────────

  /// Calculatate widths with finger/stylus detection (inspired by FountainPen).
  static void _calculateWidths(
    List<dynamic> points,
    double baseWidth,
    double minPressure,
    double maxPressure,
    _WidthBuffer buf,
  ) {
    buf.reset(points.length);
    final isFingerInput = _isConstantPressure(points);

    double accPressure = 0.4; // Slightly higher default for pencil

    for (int i = 0; i < points.length; i++) {
      double pressure;

      if (isFingerInput) {
        // Simulate pressure from velocity (slow = heavy press)
        if (i > 0) {
          final prev = StrokeOptimizer.getOffset(points[i - 1]);
          final curr = StrokeOptimizer.getOffset(points[i]);
          final distance = (curr - prev).distance;
          final sp = math.min(1.0, distance / (baseWidth * 0.4));
          final rp = math.min(1.0, 1.0 - sp);
          accPressure = math.min(
            1.0,
            accPressure + (rp - accPressure) * sp * 0.3,
          );
        }
        pressure = accPressure;
      } else {
        pressure = _getPressure(points[i]);
      }

      final width =
          baseWidth * (minPressure + pressure * (maxPressure - minPressure));
      buf.add(width);
    }
  }

  /// Detect finger input (constant pressure).
  /// Checks first 10 points — must be stable after that.
  static bool _isConstantPressure(List<dynamic> points) {
    if (points.length < 3) return true;
    final firstPressure = _getPressure(points.first);
    final checkLen = math.min(points.length, 10);
    for (int i = 1; i < checkLen; i++) {
      if ((_getPressure(points[i]) - firstPressure).abs() > 0.15) {
        return false;
      }
    }
    return true;
  }

  // ──────────────────────────────────────────────────────────
  // Tapering
  // ──────────────────────────────────────────────────────────

  /// Apply entry/exit tapering with easing curves.
  static void _applyTapering(_WidthBuffer buf, int taperEntry, int taperExit) {
    if (buf.length < 4) return;

    final entryLen = math.min(taperEntry, buf.length - 1);
    for (int i = 0; i < entryLen; i++) {
      final t = i / taperEntry;
      final factor = t * (2.0 - t); // easeOutQuad
      buf[i] *= (0.15 + factor * 0.85);
    }

    if (taperExit > 0) {
      final exitLen = math.min(taperExit, (buf.length * 0.35).toInt());
      if (exitLen > 0) {
        for (int i = 0; i < exitLen; i++) {
          final idx = buf.length - 1 - i;
          final t = i / exitLen;
          final t1 = t - 1.0;
          final factor = t1 * t1 * t1 + 1.0; // easeOutCubic
          buf[idx] *= (0.1 + factor * 0.9);
        }
      }
    }
  }

  // ──────────────────────────────────────────────────────────
  // Smoothing (in-place, no allocation)
  // ──────────────────────────────────────────────────────────

  /// Bidirectional EMA smooth in-place + rate-limiting.
  /// 4 passes (F→B→F→B) eliminate discontinuities from both sides.
  /// Matches FountainPenBrush's proven pipeline.
  static void _smoothWidthsInPlace(_WidthBuffer buf) {
    if (buf.length < 3) return;
    const double alpha = 0.4;

    // 4 bidirectional passes
    for (int pass = 0; pass < 4; pass++) {
      if (pass.isEven) {
        // Forward
        double smoothed = buf[0];
        for (int i = 1; i < buf.length; i++) {
          smoothed = smoothed * alpha + buf[i] * (1.0 - alpha);
          buf[i] = smoothed;
        }
      } else {
        // Backward
        double smoothed = buf[buf.length - 1];
        for (int i = buf.length - 2; i >= 0; i--) {
          smoothed = smoothed * alpha + buf[i] * (1.0 - alpha);
          buf[i] = smoothed;
        }
      }
    }

    // Rate-limit: prevent jarring width jumps between consecutive points
    const double maxChangeRate = 0.25;
    // Forward
    for (int i = 1; i < buf.length; i++) {
      final prev = buf[i - 1];
      buf[i] = buf[i].clamp(
        prev * (1.0 - maxChangeRate),
        prev * (1.0 + maxChangeRate),
      );
    }
    // Backward
    for (int i = buf.length - 2; i >= 0; i--) {
      final next = buf[i + 1];
      buf[i] = buf[i].clamp(
        next * (1.0 - maxChangeRate),
        next * (1.0 + maxChangeRate),
      );
    }

    // Post-smooth: clean residual steps from rate-limiting
    double s = buf[0];
    for (int i = 1; i < buf.length; i++) {
      s = s * alpha + buf[i] * (1.0 - alpha);
      buf[i] = s;
    }
    s = buf[buf.length - 1];
    for (int i = buf.length - 2; i >= 0; i--) {
      s = s * alpha + buf[i] * (1.0 - alpha);
      buf[i] = s;
    }
  }

  // ──────────────────────────────────────────────────────────
  // GPU Tessellation Pipeline
  // ──────────────────────────────────────────────────────────

  /// Build variable-width stroke with GPU tessellation.
  ///
  /// Pipeline: pre-smooth → tangent → outline → outline-smooth → drawVertices
  static void _buildVariableWidthPath(
    Canvas canvas,
    List<dynamic> points,
    _WidthBuffer widths,
    _OffsetBuffer leftBuf,
    _OffsetBuffer rightBuf,
    _OffsetBuffer tangentBuf,
    Color color,
    double avgOpacity,
    bool liveStroke, {
    int drawFromIndex = 0,
  }) {
    if (points.length < 2) return;
    final n = points.length;

    // ─── Pre-smooth positions (bidirectional EMA) ──────────
    final smoothedPos = <Offset>[];
    for (int i = 0; i < n; i++) {
      smoothedPos.add(StrokeOptimizer.getOffset(points[i]));
    }

    if (n >= 4) {
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

    // ─── B5: Arc-length reparameterization ──────────────────
    // Always applied (same as finalized) to prevent snap.
    // 🚀 PERF: Skip for very short strokes (< 10 pts).
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
        final resampledW = _WidthBuffer();
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

    // ─── 7-point tangent computation ──────────────────────
    _computeSmoothedTangents(smoothedPos, tangentBuf);

    // ─── Compute ALL outline points ──────────────────────────
    // Outline is ALWAYS full — Chaikin needs global context.
    leftBuf.reset(smoothedPos.length);
    rightBuf.reset(smoothedPos.length);

    for (int i = 0; i < smoothedPos.length; i++) {
      final current = smoothedPos[i];
      final halfWidth = widths[i] / 2;
      final tangent = tangentBuf[i];
      final normal = Offset(-tangent.dy, tangent.dx);

      leftBuf.add(current + normal * halfWidth);
      rightBuf.add(current - normal * halfWidth);
    }

    // ─── Smooth outlines (adaptive EMA) ──────────────────
    double avgWidth = 0;
    for (int i = 0; i < widths.length; i++) {
      avgWidth += widths[i];
    }
    avgWidth /= widths.length;
    _smoothOutlinePoints(leftBuf, avgWidth);
    _smoothOutlinePoints(rightBuf, avgWidth);

    // ─── B3: Chaikin corner-cutting subdivision ──────────
    if (leftBuf.length >= 4) {
      _applyChaikinSubdivision(leftBuf);
      _applyChaikinSubdivision(rightBuf);
    }

    // ─── B4: Fix crossed outlines at sharp corners ───────
    for (int i = 1; i < leftBuf.length; i++) {
      final currCenter = (leftBuf[i] + rightBuf[i]) / 2.0;
      final prevLR = rightBuf[i - 1] - leftBuf[i - 1];
      final currLR = rightBuf[i] - leftBuf[i];
      final cross = prevLR.dx * currLR.dy - prevLR.dy * currLR.dx;
      final dot = prevLR.dx * currLR.dx + prevLR.dy * currLR.dy;
      if (dot < 0 || cross.abs() > (prevLR.distance * currLR.distance * 0.95)) {
        leftBuf[i] = currCenter;
        rightBuf[i] = currCenter;
      }
    }

    // ═══════════════════════════════════════════════════════
    // GPU VERTEX TESSELLATION — triangle strip + semicircular caps
    // ═══════════════════════════════════════════════════════

    final outN = leftBuf.length;
    if (outN < 2) return;

    // ═══════════════════════════════════════════════════════════
    // 🚀 GPU VERTEX TESSELLATION — typed arrays + Vertices.raw()
    // ═══════════════════════════════════════════════════════════
    final origLen = widths.length;
    final tessStart =
        drawFromIndex > 0
            ? (drawFromIndex / origLen * outN).round().clamp(0, outN - 1)
            : 0;
    final tessLen = outN - tessStart;
    final maxVerts = 2 * tessLen + 30; // body + caps (no feathering for pencil)
    final maxIndices = 6 * (tessLen - 1) + 6 * 20;

    // Grow static buffers if needed
    if (_posBuf.length < maxVerts * 2) _posBuf = Float32List(maxVerts * 3);
    if (_colBuf.length < maxVerts) _colBuf = Int32List(maxVerts * 2);
    if (_idxBuf.length < maxIndices) _idxBuf = Uint16List(maxIndices * 2);

    int vi = 0; // vertex write index
    int ii = 0; // index write index

    final strokeColor = color.withValues(alpha: avgOpacity * color.a);
    final baseAlpha = (strokeColor.a * 255.0).round().clamp(0, 255);
    final cR = (strokeColor.r * 255.0).round().clamp(0, 255);
    final cG = (strokeColor.g * 255.0).round().clamp(0, 255);
    final cB = (strokeColor.b * 255.0).round().clamp(0, 255);

    // B1: Pre-compute maxW once instead of per-vertex O(N²)
    double maxW = 0.01;
    for (int j = 0; j < origLen; j++) {
      if (widths[j] > maxW) maxW = widths[j];
    }

    // ─── Body: interleave left/right into triangle strip ──
    for (int i = tessStart; i < outN; i++) {
      final t = outN > 1 ? i / (outN - 1) : 0.0;
      final wIdx = (t * (origLen - 1)).clamp(0.0, origLen - 1.0);
      final wLow = wIdx.floor();
      final wHigh = wIdx.ceil().clamp(0, origLen - 1);
      final wFrac = wIdx - wLow;
      final w = widths[wLow] * (1.0 - wFrac) + widths[wHigh] * wFrac;

      final pressureAlpha = (0.85 + 0.15 * (w / maxW).clamp(0.0, 1.0));
      final vertAlpha = (baseAlpha * pressureAlpha * 0.92).round().clamp(
        0,
        255,
      );
      final argb = (vertAlpha << 24) | (cR << 16) | (cG << 8) | cB;

      // Left vertex
      _posBuf[vi * 2] = leftBuf[i].dx;
      _posBuf[vi * 2 + 1] = leftBuf[i].dy;
      _colBuf[vi] = argb;
      vi++;
      // Right vertex
      _posBuf[vi * 2] = rightBuf[i].dx;
      _posBuf[vi * 2 + 1] = rightBuf[i].dy;
      _colBuf[vi] = argb;
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

    // ─── End cap: semicircular fan ────────────────────────
    final lastL = leftBuf[outN - 1];
    final lastR = rightBuf[outN - 1];
    final endCenter = (lastL + lastR) / 2.0;
    final endRadius = (lastL - lastR).distance / 2.0;
    if (endRadius > 0.1) {
      const int endSegs = 8;
      final baseAngle = math.atan2(
        lastL.dy - endCenter.dy,
        lastL.dx - endCenter.dx,
      );
      final capAlpha = (baseAlpha * 0.90).round().clamp(0, 255);
      final capArgb = (capAlpha << 24) | (cR << 16) | (cG << 8) | cB;
      final edgeAlpha = (capAlpha * 0.85).round().clamp(0, 255);
      final edgeArgb = (edgeAlpha << 24) | (cR << 16) | (cG << 8) | cB;

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

    // ─── Start cap: semicircular fan ─────────────────────
    if (drawFromIndex <= 0) {
      final firstL = leftBuf[0];
      final firstR = rightBuf[0];
      final startCenter = (firstL + firstR) / 2.0;
      final startRadius = (firstL - firstR).distance / 2.0;
      if (startRadius > 0.1) {
        const int startSegs = 8;
        final baseAngle = math.atan2(
          firstR.dy - startCenter.dy,
          firstR.dx - startCenter.dx,
        );
        final capAlpha = (baseAlpha * 0.90).round().clamp(0, 255);
        final capArgb = (capAlpha << 24) | (cR << 16) | (cG << 8) | cB;
        final edgeAlpha = (capAlpha * 0.85).round().clamp(0, 255);
        final edgeArgb = (edgeAlpha << 24) | (cR << 16) | (cG << 8) | cB;

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

    // ─── GPU draw: single call with raw typed arrays ──────
    final paint = PaintPool.getFillPaint(color: strokeColor);
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_posBuf, 0, vi * 2),
      colors: Int32List.sublistView(_colBuf, 0, vi),
      indices: Uint16List.sublistView(_idxBuf, 0, ii),
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    vertices.dispose();
  }

  // ──────────────────────────────────────────────────────────
  // Chaikin Subdivision (B3)
  // ──────────────────────────────────────────────────────────

  /// Chaikin corner-cutting subdivision (1 iteration).
  /// Replaces each segment with two new points at 25% and 75%,
  /// converging to a quadratic B-spline for provably smooth curves.
  static void _applyChaikinSubdivision(_OffsetBuffer buf) {
    if (buf.length < 3) return;
    final n = buf.length;
    final subdivided = <Offset>[buf[0]];
    for (int i = 0; i < n - 1; i++) {
      final p0 = buf[i];
      final p1 = buf[i + 1];
      subdivided.add(
        Offset(p0.dx * 0.75 + p1.dx * 0.25, p0.dy * 0.75 + p1.dy * 0.25),
      );
      subdivided.add(
        Offset(p0.dx * 0.25 + p1.dx * 0.75, p0.dy * 0.25 + p1.dy * 0.75),
      );
    }
    subdivided.add(buf[n - 1]);

    buf.reset(subdivided.length);
    for (final p in subdivided) {
      buf.add(p);
    }
  }

  // ──────────────────────────────────────────────────────────
  // Tangent computation (7-point, 3-tier)
  // ──────────────────────────────────────────────────────────

  static void _computeSmoothedTangents(List<Offset> pts, _OffsetBuffer buf) {
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

  // ──────────────────────────────────────────────────────────
  // Outline smoothing (adaptive EMA)
  // ──────────────────────────────────────────────────────────

  static void _smoothOutlinePoints(_OffsetBuffer buf, double avgWidth) {
    if (buf.length < 4) return;
    // Adaptive: thin strokes (1-3px) → alpha 0.35, thick (15+px) → alpha 0.65
    final double alpha = (0.35 + (avgWidth / 40.0).clamp(0.0, 0.30));
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

  // ──────────────────────────────────────────────────────────
  // Point accessors
  // ──────────────────────────────────────────────────────────

  static double _getPressure(dynamic point) {
    if (point is Offset) return 0.5;
    return point.pressure ?? 0.5;
  }

  /// Legacy width calculation
  static double calculateWidth(double baseWidth, double pressure) {
    final factor =
        minPressureFactor +
        (pressure * (maxPressureFactor - minPressureFactor));
    return baseWidth * factor;
  }

  /// Legacy opacity calculation
  static double calculateOpacity(double pressure) {
    return baseOpacity + (pressure * (maxOpacity - baseOpacity));
  }
}

// ─── Buffer classes (same pattern as FountainPenBrush) ───────────────

/// Pre-allocated double buffer for width calculations.
class _WidthBuffer {
  static const int _initialCapacity = 2048;
  List<double> _data = List<double>.filled(_initialCapacity, 0.0);
  int _length = 0;

  int get length => _length;

  void reset(int expectedSize) {
    if (expectedSize > _data.length) {
      _data = List<double>.filled(expectedSize * 2, 0.0);
    }
    _length = 0;
  }

  void add(double value) {
    if (_length >= _data.length) {
      final newData = List<double>.filled(_data.length * 2, 0.0);
      newData.setRange(0, _data.length, _data);
      _data = newData;
    }
    _data[_length++] = value;
  }

  double operator [](int index) => _data[index];
  void operator []=(int index, double value) => _data[index] = value;
}

/// Pre-allocated Offset buffer for outline points.
class _OffsetBuffer {
  static const int _initialCapacity = 2048;
  List<Offset> _data = List<Offset>.filled(_initialCapacity, Offset.zero);
  int _length = 0;

  int get length => _length;
  List<Offset> get view => _data.sublist(0, _length);

  void reset(int expectedSize) {
    if (expectedSize > _data.length) {
      _data = List<Offset>.filled(expectedSize * 2, Offset.zero);
    }
    _length = 0;
  }

  void add(Offset value) {
    if (_length >= _data.length) {
      final newData = List<Offset>.filled(_data.length * 2, Offset.zero);
      newData.setRange(0, _data.length, _data);
      _data = newData;
    }
    _data[_length++] = value;
  }

  Offset operator [](int index) => _data[index];
  void operator []=(int index, Offset value) => _data[index] = value;
}
