import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../rendering/optimization/optimization.dart';
import '../input/path_pool.dart';
import 'fountain_pen_buffers.dart';
import 'fountain_pen_path_builder.dart';

/// Stilografica realistica basata su ricerca calligrafica e perfect-freehand.
///
/// Pipeline:
///   Input → Streamline → Pressure (real/simulated) → Nib Angle → Taper → Smooth → Path
///
/// Modello di pressione da perfect-freehand (Steve Ruiz, tldraw):
///   sp = min(1, distance/size)           — speed factor
///   rp = 1 - sp                          — target pressure (slow=high, fast=low)
///   pressure += (rp - pressure) * sp * K — accumulator with K = 0.275
///
/// Angolo pennino: 30° (calligrafia foundational/italic).
///   - 30° → downstroke spessi, crossstroke sottili (ratio ~3:1)
///   - 45° would make vertical = horizontal (flat, less expressive)
///
/// Thinning (perfect-freehand):
///   radius = size * easing(0.5 - thinning * (0.5 - pressure))
///   With thinning=0.65: pressure 0→17.5% size, pressione 1→57.5% size (ratio 3.3:1)
class FountainPenBrush {
  static const String name = 'Stilo';
  static const IconData icon = Icons.brush;
  static const double defaultWidthMultiplier = 1.2;
  static const double opacity = 1.0;
  static const StrokeCap strokeCap = StrokeCap.round;
  static const StrokeJoin strokeJoin = StrokeJoin.round;
  static const bool usePressureForWidth = true;
  static const bool usePressureForOpacity = false;
  static const bool hasBlur = false;

  // Default pressure range
  static const double minPressureFactor = 0.35;
  static const double maxPressureFactor = 1.5;

  // Default tapering (longer for smoother entry/exit at large sizes)
  static const int taperEntryPoints = 12;
  static const int taperExitPoints = 14;

  // Default velocity influence
  static const double velocityInfluence = 0.6;

  // ── Research-backed constants (from perfect-freehand + calligraphy) ──

  /// Rate of pressure change.
  /// perfect-freehand: 0.275 (desktop mouse/stylus).
  /// Professional note apps (MyScript, GoodNotes): ~0.25-0.3.
  /// 0.275 = exact reference. Smooth pressure transitions, no overreaction.
  static const double _rateOfPressureChange = 0.275;

  /// Thinning: how much pressure influences the radius.
  /// perfect-freehand default: 0.7, GoodNotes fountain: ~0.5.
  /// 0.5 → ratio ~3:1 → bilanciato per note-taking quotidiano.
  /// Più naturale di 0.65 (ratio 4.7:1 troppo calligrafico per appunti).
  ///
  /// Formula: radius = size * (0.5 - thinning * (0.5 - pressure))
  ///   thinning=0.5:  p=0 → 25%, p=1 → 75% (ratio 3:1)
  ///   thinning=0.65: p=0 → 17.5%, p=1 → 82.5% (ratio ~4.7:1)
  ///   thinning=0.9:  p=0 → 5%, p=1 → 95% (ratio 19:1) ← too extreme
  static const double _thinning = 0.5;

  /// Nib angle: 30° = π/6 (calligrafia foundational).
  /// 30° → downstroke ≈ 3x crossstroke (standard broad-edge calligrafia).
  /// 45° → lowercase italic (downstroke = crossstroke, less expressive).
  static const double _nibAngle = math.pi / 6; // 30°

  /// Forza dell'effetto calligrafico del pennino.
  /// Defaults when user hasn't set a custom value.
  /// 0.35 per finger → nib angle clearly perceptible.
  /// 0.25 for stylus → complements real pressure.
  static const double _nibStrengthFinger = 0.35;
  static const double _nibStrengthStylus = 0.25;

  /// Streamline: quanto smoothare i punti di input (0.0-1.0).
  /// perfect-freehand default: 0.5. Matches reference.
  static const double _streamline = 0.5;

  /// Default first point pressure.
  /// perfect-freehand: 0.25. Inizi naturali, non troppo sottili.
  /// (Era 0.15 → inizi quasi invisibili.)
  static const double _defaultFirstPressure = 0.25;

  // ── Pre-allocated buffers for reduced GC pressure ──
  // NOTE: We use TWO buffer sets (A/B) to handle concurrent calls from
  // DrawingPainter + CurrentStrokePainter on the same frame.
  static final StrokeWidthBuffer _widthBufA = StrokeWidthBuffer();
  static final StrokeWidthBuffer _widthBufB = StrokeWidthBuffer();
  static bool _bufAInUse = false;

  static final StrokeOffsetBuffer _tangentBufA = StrokeOffsetBuffer();
  static final StrokeOffsetBuffer _tangentBufB = StrokeOffsetBuffer();
  static final StrokeOffsetBuffer _leftBufA = StrokeOffsetBuffer();
  static final StrokeOffsetBuffer _leftBufB = StrokeOffsetBuffer();
  static final StrokeOffsetBuffer _rightBufA = StrokeOffsetBuffer();
  static final StrokeOffsetBuffer _rightBufB = StrokeOffsetBuffer();

  /// Draws con parametri default
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
      minPressure: minPressureFactor,
      maxPressure: maxPressureFactor,
      taperEntry: taperEntryPoints,
      taperExit: taperExitPoints,
      velocityInfluence: velocityInfluence,
      curvatureInfluence: 0.0,
      tiltEnable: true,
      tiltInfluence: 1.2,
      tiltEllipseRatio: 1.0,
    );
  }

  /// Draws con parametri personalizzati.
  static void drawStrokeWithSettings(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    required double minPressure,
    required double maxPressure,
    required int taperEntry,
    required int taperExit,
    required double velocityInfluence,
    required double curvatureInfluence,
    required bool tiltEnable,
    required double tiltInfluence,
    required double tiltEllipseRatio,
    // Live stroke mode: skip exit taper, limit smoothing, skip global opacity
    bool liveStroke = false,
    // Legacy — kept for API compatibility
    double jitter = 0.0,
    double velocitySensitivity = 10.0,
    double inkAccumulation = 0.0,
    bool smoothPath = true,
    bool isPro = false,
    // 🆕 Physics v3.0 (user-tunable)
    double? thinning,
    double? pressureRate,
    double? nibAngleRad,
    double? nibStrength,
    ui.Image? textureImage,
    double textureScale = 0.0,
    int drawFromIndex = 0,
  }) {
    if (points.isEmpty) return;

    // Punto singolo: only draw dot for committed taps (not live strokes)
    if (points.length == 1) {
      if (liveStroke) return; // suppress dot during live drawing
      final offset = StrokeOptimizer.getOffset(points.first);
      final pressure = _getPressure(points.first);
      final width =
          baseWidth * (minPressure + pressure * (maxPressure - minPressure));
      canvas.drawCircle(
        offset,
        width * 0.35,
        PaintPool.getFillPaint(color: color),
      );
      return;
    }

    // 🚀 Acquire buffer set (A or B) to avoid cross-painter corruption
    final useA = !_bufAInUse;
    _bufAInUse = true;
    final widthBuf = useA ? _widthBufA : _widthBufB;

    try {
      // 1. Calculate widths with accumulator model + nib angle
      _calculateWidths(
        points,
        baseWidth,
        minPressure,
        maxPressure,
        velocityInfluence,
        tiltEnable,
        tiltInfluence,
        widthBuf,
        thinning: thinning,
        pressureRate: pressureRate,
        nibAngleRad: nibAngleRad,
        nibStrength: nibStrength,
      );

      // 2. Tapering — suppress exit taper ALWAYS (unified pipeline).
      // Exit taper during live was already 0. Applying it only on finalization
      // caused visible snap + visual shortening at the end of the stroke.
      _applyTapering(widthBuf, taperEntry, 0);

      // 3. Smooth — bidirectional EMA
      // 🚀 PERF: Live strokes use 2 passes (F→B) instead of 6 (F→B→F→B + post).
      // 4 extra passes add no perceptible quality for real-time preview
      // but cost 4 × O(N) iterations per frame.
      if (liveStroke) {
        _smoothWidths(widthBuf, forward: true);
        _smoothWidths(widthBuf, forward: false);
      } else {
        _smoothWidths(widthBuf, forward: true);
        _smoothWidths(widthBuf, forward: false);
        _smoothWidths(widthBuf, forward: true);
        _smoothWidths(widthBuf, forward: false);
      }

      // 3b. Rate-limit width change between consecutive points.
      // Very tight limit (0.12) prevents any visible bumps.
      _rateLimitWidths(widthBuf, maxChangeRate: 0.12);

      // 3c. Post-smooth: clean any residual steps from rate-limiting.
      // 🚀 PERF: Skip for live strokes — rate-limiting residuals are
      // imperceptible at drawing speed.
      if (!liveStroke) {
        _smoothWidths(widthBuf, forward: true);
        _smoothWidths(widthBuf, forward: false);
      }

      // NOTE: GPU per-segment rendering (renderFountainPenPro) removed.
      // The capsule-based segment approach creates visible joints at angles
      // and discontinuous edges. The CPU variable-width Path (Catmull-Rom)
      // below produces perfectly smooth geometry, and BrushEngine's
      // _applyTextureOverlay handles GPU texture/fiber effects.

      // 4. Render color
      final renderColor = color;

      // 5. Path with therghezza variabile + Catmull-Rom + corner fill
      final tangentBuf = useA ? _tangentBufA : _tangentBufB;
      final leftBuf = useA ? _leftBufA : _leftBufB;
      final rightBuf = useA ? _rightBufA : _rightBufB;
      final path = FountainPenPathBuilder.buildVariableWidthPath(
        points,
        widthBuf,
        canvas,
        renderColor,
        tangentBuf,
        leftBuf,
        rightBuf,
        liveStroke: liveStroke,
        drawFromIndex: drawFromIndex,
      );

      // 6. Render
      canvas.drawPath(path, PaintPool.getFillPaint(color: renderColor));

      // 🚀 Release path back to pool
      PathPool.instance.release(path);
    } finally {
      if (useA) _bufAInUse = false;
    }
  }

  // ──────────────────────────────────────────────────────────
  // Width Calculation (accumulator model from perfect-freehand)
  // ──────────────────────────────────────────────────────────

  /// Calculates larghezze con pressure accumulator + calligraphic nib angle.
  ///
  /// FINGER MODE: simulatePressure basato su distanza/size (perfect-freehand)
  ///   sp = min(1, distance / size)
  ///   rp = 1 - sp  (slow → high pressure, fast → low pressure)
  ///   pressure += (rp - pressure) * sp * RATE_OF_PRESSURE_CHANGE
  ///   radius = size * easing(0.5 - thinning * (0.5 - pressure))
  ///
  /// STYLUS MODE: actual pressure + velocity modifier
  static void _calculateWidths(
    List<dynamic> points,
    double baseWidth,
    double minPressure,
    double maxPressure,
    double velInfluence,
    bool tiltEnable,
    double tiltInfluence,
    StrokeWidthBuffer buf, {
    double? thinning,
    double? pressureRate,
    double? nibAngleRad,
    double? nibStrength,
  }) {
    // Resolve dynamic vs default constants
    final effThinning = thinning ?? _thinning;
    final effPressureRate = pressureRate ?? _rateOfPressureChange;
    final effNibAngle = nibAngleRad ?? _nibAngle;
    // 🎯 FIX: Clamp user nibStrength so width never goes to zero.
    // At max slider (1.0): finger → 0.7, stylus → 0.75.
    // This gives a dramatic calligraphic effect without degenerate strokes.
    final effNibStrengthFinger =
        (nibStrength != null)
            ? (nibStrength * 0.7).clamp(0.0, 0.7)
            : _nibStrengthFinger;
    final effNibStrengthStylus =
        (nibStrength != null)
            ? (nibStrength * 0.75).clamp(0.0, 0.75)
            : _nibStrengthStylus;

    buf.reset(points.length);

    final isFingerInput = _isConstantPressure(points);

    double accPressure = _defaultFirstPressure;
    double prevSp = 0.0;

    final streamT = 0.15 + (1.0 - _streamline) * 0.85;
    Offset prevStreamlined = StrokeOptimizer.getOffset(points.first);

    for (int i = 0; i < points.length; i++) {
      final rawPoint = StrokeOptimizer.getOffset(points[i]);

      final streamlined =
          i == 0
              ? rawPoint
              : Offset(
                prevStreamlined.dx +
                    (rawPoint.dx - prevStreamlined.dx) * streamT,
                prevStreamlined.dy +
                    (rawPoint.dy - prevStreamlined.dy) * streamT,
              );

      final distance = i > 0 ? (streamlined - prevStreamlined).distance : 0.0;
      prevStreamlined = streamlined;

      Offset direction = Offset.zero;
      if (i > 0 && distance > 0.01) {
        final prev = StrokeOptimizer.getOffset(points[i - 1]);
        final delta = rawPoint - prev;
        final len = delta.distance;
        if (len > 0) direction = delta / len;
      }

      double pressure;
      double acceleration = 0.0;

      if (isFingerInput) {
        final sp = math.min(1.0, distance / (baseWidth * 0.35));
        final rp = math.min(1.0, 1.0 - sp);
        accPressure = math.min(
          1.0,
          accPressure + (rp - accPressure) * sp * effPressureRate,
        );
        pressure = accPressure;
        acceleration = sp - prevSp;
        prevSp = sp;
      } else {
        pressure = _getPressure(points[i]);
      }

      final thinned = (0.5 - effThinning * (0.5 - pressure)).clamp(0.02, 1.0);
      double width = baseWidth * thinned;

      if (isFingerInput) {
        final accelMod = 1.0 - acceleration * 1.8;
        width *= accelMod.clamp(0.65, 1.4);
      }

      if (direction != Offset.zero) {
        final strokeAngle = math.atan2(direction.dy, direction.dx);
        final angleDiff = (strokeAngle - effNibAngle).abs() % math.pi;
        final perpendicularity = math.sin(angleDiff);
        final ns = isFingerInput ? effNibStrengthFinger : effNibStrengthStylus;
        width *= (1.0 - ns + perpendicularity * ns * 2.0);
      }

      if (i >= 2) {
        final p0 = StrokeOptimizer.getOffset(points[i - 2]);
        final p1 = StrokeOptimizer.getOffset(points[i - 1]);
        final d1 = p1 - p0;
        final d2 = rawPoint - p1;
        final cross = d1.dx * d2.dy - d1.dy * d2.dx;
        final dot = d1.dx * d2.dx + d1.dy * d2.dy;
        final angle = math.atan2(cross.abs(), dot);
        final curvature = (angle / math.pi).clamp(0.0, 1.0);
        width *= 1.0 + curvature * 0.35;
      }

      if (!isFingerInput && velInfluence > 0 && distance > 0) {
        final sp = math.min(1.0, distance / baseWidth);
        final velMod = 1.15 - sp * 0.5 * velInfluence;
        width *= velMod.clamp(0.5, 1.3);
      }

      if (tiltEnable && !isFingerInput) {
        final tiltX = _getTiltX(points[i]);
        final tiltY = _getTiltY(points[i]);
        final tiltMagnitude = math
            .sqrt(tiltX * tiltX + tiltY * tiltY)
            .clamp(0.0, 1.0);
        width *= 1.0 + (tiltInfluence * tiltMagnitude);
      }

      buf.add(width.clamp(baseWidth * 0.12, baseWidth * 3.5));
    }
  }

  /// Detects finger input (constant pressure).
  /// CRITICAL: only checks first 10 points to avoid flip mid-stroke.
  /// Threshold 0.15: Android touch reports ~0.9 with micro-variations <0.1,
  /// real stylus varies from 0.0 to 1.0 with range >0.3.
  static bool _isConstantPressure(List<dynamic> points) {
    if (points.length < 3) return true;
    final firstPressure = _getPressure(points.first);
    // Only first 10 points: decision must be STABLE
    final checkLen = math.min(points.length, 10);
    for (int i = 1; i < checkLen; i++) {
      if ((_getPressure(points[i]) - firstPressure).abs() > 0.15) {
        return false;
      }
    }
    return true;
  }

  // ──────────────────────────────────────────────────────────
  // Tapering (easing curves from perfect-freehand)
  // ──────────────────────────────────────────────────────────

  /// Tapering with research-backed easing curves:
  /// - Entry: easeOutQuad → t*(2-t) — fast attack, natural
  /// - Exit: easeOutCubic → --t*t*t+1 — slows down gently (perfect-freehand)
  static void _applyTapering(
    StrokeWidthBuffer buf,
    int taperEntry,
    int taperExit,
  ) {
    if (buf.length < 4) return;

    final entryLen = math.min(taperEntry, buf.length - 1);
    for (int i = 0; i < entryLen; i++) {
      final t = i / taperEntry;
      // easeInOutCubic: smoother acceleration for natural ink flow
      final factor =
          t < 0.5
              ? 4.0 * t * t * t
              : 1.0 -
                  ((-2.0 * t + 2.0) * (-2.0 * t + 2.0) * (-2.0 * t + 2.0)) /
                      2.0;
      buf[i] *= factor.clamp(0.0, 1.0);
    }

    if (taperExit > 0) {
      final exitLen = math.min(taperExit, (buf.length * 0.4).toInt());
      if (exitLen > 0) {
        for (int i = 0; i < exitLen; i++) {
          final idx = buf.length - 1 - i;
          final t = i / exitLen;
          final t1 = t - 1.0;
          final factor = t1 * t1 * t1 + 1.0;
          buf[idx] *= (0.02 + factor * 0.98);
        }
      }
    }
  }

  // ──────────────────────────────────────────────────────────
  // Smoothing (forward-only EMA — new points can't change old ones)
  // ──────────────────────────────────────────────────────────

  /// Bidirectional EMA smooth in-place.
  /// Forward: looks backward only.
  /// Backward: looks forward only.
  /// 4 passes (F→B→F→B) eliminate discontinuities from both sides.
  /// Alpha 0.35 keeps 35% of previous → strongly smoothing.
  static void _smoothWidths(StrokeWidthBuffer buf, {bool forward = true}) {
    if (buf.length < 3) return;

    const double alpha = 0.35;
    if (forward) {
      double smoothed = buf[0];
      for (int i = 1; i < buf.length; i++) {
        smoothed = smoothed * alpha + buf[i] * (1.0 - alpha);
        buf[i] = smoothed;
      }
    } else {
      double smoothed = buf[buf.length - 1];
      for (int i = buf.length - 2; i >= 0; i--) {
        smoothed = smoothed * alpha + buf[i] * (1.0 - alpha);
        buf[i] = smoothed;
      }
    }
  }

  /// Limits the rate of width change between consecutive points.
  /// Prevents the visually jarring "breaks" where width drops to near-zero.
  static void _rateLimitWidths(
    StrokeWidthBuffer buf, {
    double maxChangeRate = 0.35,
  }) {
    if (buf.length < 3) return;

    // Forward pass: each width can't drop/grow more than maxChangeRate
    for (int i = 1; i < buf.length; i++) {
      final prev = buf[i - 1];
      final minW = prev * (1.0 - maxChangeRate);
      final maxW = prev * (1.0 + maxChangeRate);
      buf[i] = buf[i].clamp(minW, maxW);
    }
    // Backward pass: smooth from the other direction too
    for (int i = buf.length - 2; i >= 0; i--) {
      final next = buf[i + 1];
      final minW = next * (1.0 - maxChangeRate);
      final maxW = next * (1.0 + maxChangeRate);
      buf[i] = buf[i].clamp(minW, maxW);
    }
  }

  // ──────────────────────────────────────────────────────────
  // Path Building
  // ──────────────────────────────────────────────────────────

  // ──────────────────────────────────────────────────────────
  // Pressure & Tilt Helpers
  // ──────────────────────────────────────────────────────────

  /// Extract pressure from a dynamic point (Offset → 0.5, DrawingPoint → .pressure).
  static double _getPressure(dynamic point) {
    if (point is Offset) return 0.5;
    return point.pressure ?? 0.5;
  }

  /// Extract tiltX from a dynamic point (0.0 if unavailable).
  static double _getTiltX(dynamic point) {
    if (point is Offset) return 0.0;
    try {
      return (point.tiltX as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Extract tiltY from a dynamic point (0.0 if unavailable).
  static double _getTiltY(dynamic point) {
    if (point is Offset) return 0.0;
    try {
      return (point.tiltY as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }
}
