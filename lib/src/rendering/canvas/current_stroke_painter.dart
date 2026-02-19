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

  // 🚀 Predictive renderer for anti-lag (only 60Hz mode)
  static final PredictiveRenderer _predictor = PredictiveRenderer(
    predictedPointsCount: 2,
    ghostOpacity: 0.08,
    velocityDecay: 0.7,
  );

  // ─── INCREMENTAL CACHE ──────────────────────────────────────────
  // Disabled: the overlap zone between cached body and tail produces
  // a visible double-rendering artifact (thin trailing line) with GPU
  // vertex tessellation brushes. Full re-render per frame is fast
  // enough thanks to drawVertices().
  static const bool _enableIncrementalCache = false;
  static const int _cacheThreshold = 20;

  /// How many new points to accumulate before refreshing the cache.
  static const int _cacheRefreshInterval = 15;

  /// Overlap points between cache and tail for seamless smoothing context.
  /// Must be large enough for the brushes' smoothing window (EMA passes,
  /// tangent computation, Chaikin subdivision context).
  static const int _overlapPoints = 20;

  /// Cached picture of the stroke body.
  static ui.Picture? _cachedPicture;

  /// Number of points baked into _cachedPicture.
  static int _cachedPointCount = 0;

  /// Style fingerprint to detect style changes that invalidate the cache.
  static int _cachedStyleHash = 0;

  /// Number of points rendered in the last paint() call.
  /// Used to trim unseen trailing points on finalization.
  static int _lastRenderedCount = 0;

  /// Returns how many points were in the last paint().
  static int get lastRenderedCount => _lastRenderedCount;

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

    // Determine if symmetry is active (disables incremental caching
    // because mirrored strokes need full re-render)
    final hasSymmetry =
        guideSystem != null &&
        guideSystem!.symmetryEnabled &&
        currentStroke.length >= 2;

    // ─── Choose render strategy ──────────────────────────────────
    if (_enableIncrementalCache &&
        !hasSymmetry &&
        currentStroke.length > _cacheThreshold) {
      _paintIncremental(canvas, currentStroke);
    } else {
      // Full render (default — incremental cache disabled)
      _invalidateCache();
      _drawStroke(canvas, currentStroke, color, width, penType, settings);
    }

    // 🎯 FIX: Record how many points were actually rendered on-screen.
    // If PointerMoveEvent + PointerUpEvent arrive in the same event batch,
    // updateStroke() adds a point but clear() cancels the scheduled repaint.
    // Without this tracking, the finalized stroke includes unseen points.
    _lastRenderedCount = currentStroke.length;

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

  /// Incremental rendering: replay cached body + render only new tail.
  void _paintIncremental(Canvas canvas, List<ProDrawingPoint> stroke) {
    final currentStyle = _styleHash;
    final pointCount = stroke.length;

    // Invalidate cache if style changed
    if (currentStyle != _cachedStyleHash) {
      _invalidateCache();
    }

    // Determine if we should refresh the cache
    final newPointsSinceCache = pointCount - _cachedPointCount;
    final needsRefresh =
        _cachedPicture == null || newPointsSinceCache >= _cacheRefreshInterval;

    if (needsRefresh) {
      // Bake current body (all but last _overlapPoints) into a Picture.
      // We leave _overlapPoints un-cached so the tail overlaps seamlessly
      // with enough smoothing context for EMA/tangent/Chaikin passes.
      final cacheEnd = pointCount - _overlapPoints;
      if (cacheEnd > 0) {
        final bodyPoints = stroke.sublist(0, cacheEnd);
        final recorder = ui.PictureRecorder();
        final recordCanvas = Canvas(recorder);
        _drawStroke(recordCanvas, bodyPoints, color, width, penType, settings);
        _cachedPicture?.dispose();
        _cachedPicture = recorder.endRecording();
        _cachedPointCount = cacheEnd;
        _cachedStyleHash = currentStyle;
      }
    }

    // 1. Replay cached body
    if (_cachedPicture != null) {
      canvas.drawPicture(_cachedPicture!);
    }

    // 2. Render tail (overlap + new points) with full stroke context.
    // The large overlap (20 points) ensures smoothing/tangent computation
    // produces the same geometry as if the full stroke were rendered.
    final tailStart = (_cachedPointCount - _overlapPoints).clamp(
      0,
      pointCount - 1,
    );
    if (tailStart < pointCount) {
      final tailPoints = stroke.sublist(tailStart);
      _drawStroke(canvas, tailPoints, color, width, penType, settings);
    }
  }

  /// Invalidate the dirty region cache.
  static void _invalidateCache() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedPointCount = 0;
    _cachedStyleHash = 0;
  }

  /// 🗑️ Pulisce lo stato (chiamare when chiude il canvas)
  static void clearCache() {
    _predictor.reset();
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
    ProBrushSettings settings,
  ) {
    BrushEngine.renderStroke(
      canvas,
      points,
      color,
      width,
      penType,
      settings,
      isLive: true,
    );
  }

  @override
  bool shouldRepaint(CurrentStrokePainter oldDelegate) {
    // Always repaint when rebuilt — rebuilds are controlled by
    // ValueListenableBuilder (only fires on stroke data changes).
    return true;
  }
}
