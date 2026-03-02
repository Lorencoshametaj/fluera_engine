import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../drawing/models/pro_drawing_point.dart';
import '../../drawing/models/pro_brush_settings.dart';
import '../../drawing/brushes/brushes.dart';
import '../../drawing/filters/predictive_renderer.dart';
import '../../tools/ruler/ruler_guide_system.dart';
import '../../canvas/infinite_canvas_controller.dart';

/// 🚀 CURRENT STROKE PAINTER - Layer ottimizzato per current stroke
///
/// 🎯 Render il current stroke con DIRTY REGION CACHING:
/// - For short strokes (<20 points): full render every frame
/// - Per stroke lunghi: cache ui.Picture of points precedenti,
///   redraws only the last N new points
///
/// ARCHITETTURA:
/// - Layer separated from completed strokes
/// - Use Stack with 2 CustomPaint:
///   1. CompletedStrokesPainter (ridisegna raramente)
///   2. CurrentStrokePainter (ridisegna at each point)
class CurrentStrokePainter extends CustomPainter {
  final ValueNotifier<List<ProDrawingPoint>> strokeNotifier;
  final ProPenType penType;
  final Color color;
  final double width;
  final ProBrushSettings settings;

  // ✂️ Parametri per clipping
  final bool enableClipping;
  final Size canvasSize;

  // 🚀 Enable/disable predictive rendering (120Hz: disabled for frame budget)
  final bool enablePredictive;

  // 🪞 Live symmetry preview
  final RulerGuideSystem? guideSystem;

  // 🚀 Viewport-level mode: apply canvas transform inside paint()
  final InfiniteCanvasController? controller;

  // 🧬 Surface material — applied to BrushEngine for programmable materiality
  final SurfaceMaterial? surface;

  // ✂️ PDF page clipping: when drawing on a PDF page, clip live stroke
  // to the page rect so ink doesn't overflow outside the page.
  final Rect? pdfClipRect;

  // 🚀 Predictive renderer for anti-lag (ghost trail prediction)
  static final PredictiveRenderer _predictor = PredictiveRenderer(
    predictedPointsCount: 2,
    ghostOpacity: 0.08,
    velocityDecay: 0.7,
  );

  // 🚀 Track last point count fed to predictor (avoid re-feeding same points)
  static int _predictorFedCount = 0;

  // 🚀 Cached paint for ghost trail (reused across frames)
  static final Paint _ghostBasePaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

  // ─── 🚀 PICTURE CACHE ──────────────────────────────────────────
  // Record BrushEngine output as ui.Picture on each new point.
  // Replay cached Picture on idle frames (O(1) GPU blit).
  static const bool _enableIncrementalCache = true;
  static const int _cacheThreshold = 20;

  /// Cached Picture of the full stroke.
  static ui.Picture? _cachedPicture;
  static int _cachedPointCount = 0;
  static int _cachedStyleHash = 0;

  /// Number of points rendered in the last paint() call.
  static int _lastRenderedCount = 0;
  static int get lastRenderedCount => _lastRenderedCount;

  /// Reset rendered count for a new stroke. Must be called from _onDrawStart
  /// to prevent stale values from a previous stroke being used for trimming.
  static void resetForNewStroke() {
    _lastRenderedCount = 0;
    _predictor.reset();
    _predictorFedCount = 0;
  }

  CurrentStrokePainter({
    required this.strokeNotifier,
    required this.penType,
    required this.color,
    required this.width,
    this.settings = ProBrushSettings.defaultSettings,
    this.enableClipping = false,
    this.canvasSize = const Size(100000, 100000),
    this.enablePredictive = true,
    this.guideSystem,
    this.controller,
    this.pdfClipRect,
    this.surface,
  }) : super(repaint: strokeNotifier);

  /// Style hash to detect when cached picture must be invalidated.
  int get _styleHash =>
      Object.hashAll([penType, color.toARGB32(), width, settings.hashCode]);

  @override
  void paint(Canvas canvas, Size size) {
    final currentStroke = strokeNotifier.value;

    // If the stroke is empty, reset everything
    if (currentStroke.isEmpty) {
      _predictor.reset();
      _predictorFedCount = 0;
      _invalidateCache();
      return;
    }

    // Skip rendering for single-point strokes to prevent the initial dot flash.
    // Still allow predictor and cache tracking to proceed normally.
    if (currentStroke.length < 2) {
      _lastRenderedCount = currentStroke.length;
      return;
    }

    // 🚀 VIEWPORT-LEVEL MODE: apply canvas transform
    final isViewportLevel = controller != null;
    if (isViewportLevel) {
      canvas.save();
      canvas.translate(controller!.offset.dx, controller!.offset.dy);
      if (controller!.rotation != 0.0) {
        canvas.rotate(controller!.rotation);
      }
      canvas.scale(controller!.scale);
    }

    // ✂️ Applica clipping se abilitato (per editing immagini)
    if (enableClipping) {
      canvas.clipRect(Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height));
    }

    // ✂️ PDF page clipping: clip live stroke to the page bounds
    if (pdfClipRect != null) {
      canvas.clipRect(pdfClipRect!);
    }

    // Determine if symmetry is active (disables incremental caching
    // because mirrored strokes need full re-render)
    final hasSymmetry =
        guideSystem != null &&
        guideSystem!.symmetryEnabled &&
        currentStroke.length >= 2;

    // ─── 🚀 BALLPOINT DIRECT-DRAW: skip PictureRecorder ──────────
    // Ballpoint uses a single drawPath() with incremental path O(ΔN).
    // PictureRecorder adds ~0.3ms of alloc+copy overhead with zero
    // benefit (nothing expensive to cache). Draw straight to canvas.
    final isBallpointFast =
        penType == ProPenType.ballpoint &&
        settings.textureType == 'none' &&
        !settings.stampEnabled;

    // ─── Choose render strategy ──────────────────────────────────
    if (isBallpointFast || hasSymmetry) {
      // Direct draw: ballpoint fast-path or symmetry (needs full re-render)
      _invalidateCache();
      _drawStroke(canvas, currentStroke, color, width, penType, settings);
    } else if (_enableIncrementalCache &&
        currentStroke.length > _cacheThreshold) {
      _paintIncremental(canvas, currentStroke);
    } else {
      _invalidateCache();
      _drawStroke(canvas, currentStroke, color, width, penType, settings);
    }

    // 🎯 FIX: Record how many points were actually rendered on-screen.
    // If PointerMoveEvent + PointerUpEvent arrive in the same event batch,
    // updateStroke() adds a point but clear() cancels the scheduled repaint.
    // Without this tracking, the finalized stroke includes unseen points.
    _lastRenderedCount = currentStroke.length;

    // ─── 🚀 PREDICTIVE GHOST TRAIL ──────────────────────────────────
    // Feed new points into the predictor and draw predicted extension.
    // This reduces perceived latency by ~15-20ms.
    // 🚀 Skip for ballpoint: constant-width stroke has no visual latency
    // to hide, and the predictor costs ~0.2ms/frame in feed + predict.
    if (enablePredictive && !isBallpointFast && currentStroke.length >= 3) {
      final feedStart = _predictorFedCount.clamp(0, currentStroke.length - 1);
      for (int i = feedStart; i < currentStroke.length; i++) {
        final pt = currentStroke[i];
        _predictor.addPoint(
          pt.position,
          pt.timestamp * 1000,
          pressure: pt.pressure,
        );
      }
      _predictorFedCount = currentStroke.length;

      // Predict and render ghost trail
      final predicted = _predictor.predictNextPoints();
      if (predicted.isNotEmpty) {
        _ghostBasePaint
          ..color = color
          ..strokeWidth = width;
        _predictor.drawGhostTrail(canvas, _ghostBasePaint, predicted);
      }
    }

    // 🪞 LIVE SYMMETRY PREVIEW: mirror stroke in real-time
    if (hasSymmetry) {
      final mirroredSets = _mirrorStroke(currentStroke);
      final mirrorColor = color.withValues(
        alpha: (color.a * 0.6).clamp(0.0, 1.0),
      );
      for (final mirroredPoints in mirroredSets) {
        _drawStroke(
          canvas,
          mirroredPoints,
          mirrorColor,
          width,
          penType,
          settings,
        );
      }
    }

    // 🚀 Restore canvas if in viewport-level mode
    if (isViewportLevel) {
      canvas.restore();
    }
  }

  /// 🚀 Full-stroke Picture cache with direct-to-canvas optimization.
  ///
  /// Strategy:
  /// - Every new point: render FULL stroke directly to canvas (perfect quality)
  /// - After rendering: record to Picture for O(1) replay on idle frames
  /// - When no new points (idle/zoom/pan): replay cached Picture (zero cost)
  ///
  /// Optimization vs. naive approach:
  /// - Render to canvas FIRST (zero latency), THEN record in same pass
  /// - PictureRecorder captures the same draw calls → single BrushEngine pass
  void _paintIncremental(Canvas canvas, List<ProDrawingPoint> stroke) {
    final currentStyle = _styleHash;
    final pointCount = stroke.length;

    if (currentStyle != _cachedStyleHash) {
      _invalidateCache();
    }

    // 🎯 Detect new stroke: reset on fresh start
    if (_cachedPicture == null && pointCount > 0) {
      _lastRenderedCount = 0;
    }

    final needsRefresh =
        _cachedPicture == null || pointCount != _cachedPointCount;

    if (needsRefresh) {
      // 🚀 RECORD-ONCE: render into PictureRecorder, then replay.
      // The PictureRecorder captures all draw commands in a single pass
      // so BrushEngine only executes once (not twice).
      final recorder = ui.PictureRecorder();
      _drawStroke(Canvas(recorder), stroke, color, width, penType, settings);
      _cachedPicture?.dispose();
      _cachedPicture = recorder.endRecording();
      _cachedPointCount = pointCount;
      _cachedStyleHash = currentStyle;
    }

    if (_cachedPicture != null) {
      canvas.drawPicture(_cachedPicture!);
    }
  }

  /// Invalidate cache.
  static void _invalidateCache() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedPointCount = 0;
    _cachedStyleHash = 0;
  }

  /// 🗑️ Pulisce lo stato (chiamare when chiude il canvas)
  static void clearCache() {
    _predictor.reset();
    _predictorFedCount = 0;
    _invalidateCache();
    _lastRenderedCount = 0;
  }

  /// 🪞 Mirror all points of the current stroke using the guide system
  List<List<ProDrawingPoint>> _mirrorStroke(List<ProDrawingPoint> points) {
    final gs = guideSystem!;
    final segments = gs.symmetrySegments;

    if (segments <= 2) {
      // Simple 2-axis mirror
      final mirrored = <ProDrawingPoint>[];
      for (final p in points) {
        final mp = gs.mirrorPoint(p.position);
        if (mp != null) {
          mirrored.add(
            ProDrawingPoint(
              position: mp,
              pressure: p.pressure,
              timestamp: p.timestamp,
              tiltX: p.tiltX,
              tiltY: p.tiltY,
              orientation: p.orientation,
            ),
          );
        }
      }
      return mirrored.isNotEmpty ? [mirrored] : [];
    }

    // N-segment kaleidoscope mirror
    final result = <List<ProDrawingPoint>>[];
    for (int seg = 1; seg < segments; seg++) {
      result.add([]);
    }

    for (final p in points) {
      final mirrors = gs.mirrorPointMulti(p.position);
      for (int i = 0; i < mirrors.length && i < result.length; i++) {
        result[i].add(
          ProDrawingPoint(
            position: mirrors[i],
            pressure: p.pressure,
            timestamp: p.timestamp,
            tiltX: p.tiltX,
            tiltY: p.tiltY,
            orientation: p.orientation,
          ),
        );
      }
    }

    return result.where((list) => list.isNotEmpty).toList();
  }

  void _drawStroke(
    Canvas canvas,
    List<ProDrawingPoint> points,
    Color color,
    double width,
    ProPenType penType,
    ProBrushSettings settings, {
    int drawFromIndex = 0,
  }) {
    BrushEngine.renderStroke(
      canvas,
      points,
      color,
      width,
      penType,
      settings,
      isLive: true,
      drawFromIndex: drawFromIndex,
      surface: surface,
    );
  }

  @override
  bool shouldRepaint(CurrentStrokePainter oldDelegate) {
    // Short-circuit: empty stroke during navigation → skip repaint.
    if (strokeNotifier.value.isEmpty &&
        oldDelegate.strokeNotifier.value.isEmpty) {
      return penType != oldDelegate.penType ||
          color != oldDelegate.color ||
          width != oldDelegate.width;
    }
    // During active drawing, always repaint (ValueNotifier drives frames).
    return true;
  }
}
