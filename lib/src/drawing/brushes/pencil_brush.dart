import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../rendering/optimization/optimization.dart';
import '../../rendering/shaders/shader_brush_service.dart';
import '../../rendering/shaders/shader_pencil_renderer.dart';

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
  }) {
    if (points.isEmpty) return;

    // GPU Pro path
    final useGpu = isPro || ShaderBrushService.instance.isProEnabled;
    if (useGpu &&
        ShaderBrushService.instance.isAvailable &&
        points.length >= 2) {
      ShaderBrushService.instance.renderPencilPro(
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

      // 2. Tapering (entry + exit)
      _applyTapering(widthBuf, taperEntryPoints, taperExitPoints);

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

  /// Forward EMA smooth in-place — no list copy.
  static void _smoothWidthsInPlace(_WidthBuffer buf) {
    if (buf.length < 3) return;
    const double alpha = 0.4;

    double smoothed = buf[0];
    for (int i = 1; i < buf.length; i++) {
      smoothed = smoothed * alpha + buf[i] * (1.0 - alpha);
      buf[i] = smoothed;
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
    bool liveStroke,
  ) {
    if (points.length < 2) return;
    final n = points.length;

    // ─── Pre-smooth positions (bidirectional EMA) ──────────
    final smoothedPos = <Offset>[];
    for (int i = 0; i < n; i++) {
      smoothedPos.add(StrokeOptimizer.getOffset(points[i]));
    }

    if (n >= 3) {
      const double alpha = 0.35;
      // Forward pass
      for (int i = 1; i < n; i++) {
        smoothedPos[i] = Offset(
          smoothedPos[i - 1].dx * alpha + smoothedPos[i].dx * (1.0 - alpha),
          smoothedPos[i - 1].dy * alpha + smoothedPos[i].dy * (1.0 - alpha),
        );
      }
      // Backward pass
      for (int i = n - 2; i >= 0; i--) {
        smoothedPos[i] = Offset(
          smoothedPos[i + 1].dx * alpha + smoothedPos[i].dx * (1.0 - alpha),
          smoothedPos[i + 1].dy * alpha + smoothedPos[i].dy * (1.0 - alpha),
        );
      }
    }

    // ─── 7-point tangent computation ──────────────────────
    _computeSmoothedTangents(smoothedPos, tangentBuf);

    // ─── Compute outline points ──────────────────────────
    leftBuf.reset(n);
    rightBuf.reset(n);

    for (int i = 0; i < n; i++) {
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

    // ═══════════════════════════════════════════════════════
    // GPU VERTEX TESSELLATION — triangle strip + semicircular caps
    // ═══════════════════════════════════════════════════════

    final outN = leftBuf.length;
    if (outN < 2) return;

    final positions = <Offset>[];
    final indices = <int>[];
    final colors = <Color>[];

    final strokeColor = color.withValues(alpha: avgOpacity * color.a);
    final baseAlpha = (strokeColor.a * 255.0).round().clamp(0, 255);
    final cR = (strokeColor.r * 255.0).round().clamp(0, 255);
    final cG = (strokeColor.g * 255.0).round().clamp(0, 255);
    final cB = (strokeColor.b * 255.0).round().clamp(0, 255);
    final origLen = widths.length;

    // ─── Body: interleave left/right into triangle strip ──
    for (int i = 0; i < outN; i++) {
      final t = i / (outN - 1).toDouble();
      final wIdx = (t * (origLen - 1)).clamp(0.0, origLen - 1.0);
      final wLow = wIdx.floor();
      final wHigh = wIdx.ceil().clamp(0, origLen - 1);
      final wFrac = wIdx - wLow;
      final w = widths[wLow] * (1.0 - wFrac) + widths[wHigh] * wFrac;

      // Pressure-based alpha: wider = more graphite = darker
      double maxW = 0.01;
      for (int j = 0; j < origLen; j++) {
        if (widths[j] > maxW) maxW = widths[j];
      }
      final pressureAlpha = (0.85 + 0.15 * (w / maxW).clamp(0.0, 1.0));

      // Edge AA: 92%
      final leftAlpha = (baseAlpha * pressureAlpha * 0.92).round().clamp(
        0,
        255,
      );
      final rightAlpha = (baseAlpha * pressureAlpha * 0.92).round().clamp(
        0,
        255,
      );

      positions.add(leftBuf[i]);
      colors.add(Color.fromARGB(leftAlpha, cR, cG, cB));
      positions.add(rightBuf[i]);
      colors.add(Color.fromARGB(rightAlpha, cR, cG, cB));
    }
    for (int i = 0; i < outN - 1; i++) {
      final li = 2 * i;
      final ri = 2 * i + 1;
      final lNext = 2 * (i + 1);
      final rNext = 2 * (i + 1) + 1;
      indices.addAll([li, ri, lNext]);
      indices.addAll([ri, lNext, rNext]);
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
        final edgeAlpha = (capAlpha * 0.85).round().clamp(0, 255);
        colors.add(Color.fromARGB(edgeAlpha, cR, cG, cB));
      }
      for (int s = 0; s < endSegs; s++) {
        indices.addAll([centerIdx, firstArcIdx + s, firstArcIdx + s + 1]);
      }
    }

    // ─── Start cap: semicircular fan ─────────────────────
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
        final edgeAlpha = (capAlpha * 0.85).round().clamp(0, 255);
        colors.add(Color.fromARGB(edgeAlpha, cR, cG, cB));
      }
      for (int s = 0; s < startSegs; s++) {
        indices.addAll([centerIdx, firstArcIdx + s, firstArcIdx + s + 1]);
      }
    }

    // ─── GPU draw ────────────────────────────────────────
    final paint = PaintPool.getFillPaint(color: strokeColor);
    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      indices: indices,
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    vertices.dispose();
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
    if (buf.length < 3) return;
    // Wider strokes → stronger smoothing
    final alpha = (0.25 + (avgWidth / 20.0).clamp(0.0, 0.25)).clamp(0.0, 0.5);
    final passes = avgWidth > 4 ? 3 : 2;

    for (int pass = 0; pass < passes; pass++) {
      for (int i = 1; i < buf.length - 1; i++) {
        buf[i] = Offset(
          buf[i - 1].dx * alpha + buf[i].dx * (1.0 - alpha),
          buf[i - 1].dy * alpha + buf[i].dy * (1.0 - alpha),
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
