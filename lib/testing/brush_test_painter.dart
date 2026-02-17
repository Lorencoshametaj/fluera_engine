import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../src/drawing/brushes/brushes.dart';
import './brush_test_screen.dart';

/// Painter ULTRA-OTTIMIZZATO con Image layer HiDPI + Real-time brush
///
/// STRATEGY: Layer-based rendering come Procreate
/// - Layer 0: Background (Picture cache)
/// - Layer 1: Strokes completati (Image rasterizzata a RISOLUZIONE NATIVA!)
/// - Layer 2: Current stroke (brush reale in tempo reale)
///
/// 🎛️ Ogni stroke ha i suoi BrushSettings salvati at the moment of creazione
class BrushTestPainter extends CustomPainter {
  final List<BrushStroke> strokes;
  final BrushStroke? currentStroke;
  final double devicePixelRatio;
  final bool isDark;
  final int repaintKey; // Force repaint when it changes

  // LAYER 1: Image rasterizzata per strokes completati
  static ui.Image? _completedStrokesImage;
  static int _imageStrokesCount = 0;
  static Size? _imageSize;
  static double? _imagePixelRatio;

  // Background
  static ui.Picture? _backgroundCache;
  static Size? _backgroundSize;
  static bool? _backgroundIsDark;

  // Paint per Image - filterQuality NONE per pixel-perfect 1:1!
  static final Paint _imagePaint = Paint()..filterQuality = FilterQuality.none;

  BrushTestPainter({
    required this.strokes,
    required this.currentStroke,
    this.devicePixelRatio = 1.0,
    this.isDark = false,
    this.repaintKey = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawCachedBackground(canvas, size);
    _handleCompletedStrokes(canvas, size);

    if (currentStroke != null && currentStroke!.points.isNotEmpty) {
      _drawCurrentStrokeRealtime(canvas, currentStroke!);
    }
  }

  void _handleCompletedStrokes(Canvas canvas, Size size) {
    final needsRebuild =
        _imageSize != size ||
        _imageStrokesCount > strokes.length ||
        _imagePixelRatio != devicePixelRatio;
    final needsAdd = _imageStrokesCount < strokes.length;

    if (needsRebuild) {
      _rebuildImageFromScratch(size);
    } else if (needsAdd) {
      _addStrokesToImage(size);
    }

    if (_completedStrokesImage != null) {
      // Scala l'immagine HiDPI alla dimensione logica del canvas
      canvas.save();
      canvas.scale(1.0 / devicePixelRatio);
      canvas.drawImage(_completedStrokesImage!, Offset.zero, _imagePaint);
      canvas.restore();
    }
  }

  void _addStrokesToImage(Size size) {
    final recorder = ui.PictureRecorder();
    final imgCanvas = Canvas(recorder);

    // Draw immagine esistente
    if (_completedStrokesImage != null) {
      imgCanvas.drawImage(_completedStrokesImage!, Offset.zero, _imagePaint);
    }

    // Scale for HiDPI PRIMA di disegnare i nuovi strokes
    imgCanvas.scale(devicePixelRatio);

    // Aggiungi solo i nuovi strokes
    for (int i = _imageStrokesCount; i < strokes.length; i++) {
      _drawStrokeFull(imgCanvas, strokes[i]);
    }

    final picture = recorder.endRecording();

    // Rasterize a RISOLUZIONE NATIVA del dispositivo!
    final pixelWidth = (size.width * devicePixelRatio).ceil();
    final pixelHeight = (size.height * devicePixelRatio).ceil();

    _completedStrokesImage?.dispose();
    _completedStrokesImage = picture.toImageSync(pixelWidth, pixelHeight);
    _imageStrokesCount = strokes.length;
    _imageSize = size;
    _imagePixelRatio = devicePixelRatio;
  }

  void _rebuildImageFromScratch(Size size) {
    _completedStrokesImage?.dispose();

    if (strokes.isEmpty) {
      _completedStrokesImage = null;
      _imageStrokesCount = 0;
      _imageSize = size;
      _imagePixelRatio = devicePixelRatio;
      return;
    }

    final recorder = ui.PictureRecorder();
    final imgCanvas = Canvas(recorder);

    // Scale for HiDPI
    imgCanvas.scale(devicePixelRatio);

    for (var stroke in strokes) {
      _drawStrokeFull(imgCanvas, stroke);
    }

    final picture = recorder.endRecording();

    // Rasterize a RISOLUZIONE NATIVA del dispositivo!
    final pixelWidth = (size.width * devicePixelRatio).ceil();
    final pixelHeight = (size.height * devicePixelRatio).ceil();

    _completedStrokesImage = picture.toImageSync(pixelWidth, pixelHeight);
    _imageStrokesCount = strokes.length;
    _imageSize = size;
    _imagePixelRatio = devicePixelRatio;
  }

  /// REAL-TIME: Draw lo stroke corrente con il BRUSH REALE!
  void _drawCurrentStrokeRealtime(Canvas canvas, BrushStroke stroke) {
    _drawStrokeFull(canvas, stroke);
  }

  void _drawStrokeFull(Canvas canvas, BrushStroke stroke) {
    if (stroke.points.isEmpty) return;
    final color = stroke.color.withValues(alpha: stroke.opacity);
    // 🎛️ Use settings SAVED in the stroke, not the global ones!
    final settings = stroke.settings;

    switch (stroke.brushType) {
      case BrushType.ballpoint:
        BallpointBrush.drawStrokeWithSettings(
          canvas,
          stroke.points,
          color,
          stroke.width,
          minPressure: settings.ballpointMinPressure,
          maxPressure: settings.ballpointMaxPressure,
        );
      case BrushType.fountainPen:
        FountainPenBrush.drawStrokeWithSettings(
          canvas,
          stroke.points,
          color,
          stroke.width,
          minPressure: settings.fountainMinPressure,
          maxPressure: settings.fountainMaxPressure,
          taperEntry: settings.fountainTaperEntry,
          taperExit: settings.fountainTaperExit,
          velocityInfluence: settings.fountainVelocityInfluence,
          curvatureInfluence: settings.fountainCurvatureInfluence,
          tiltEnable: settings.fountainTiltEnable,
          tiltInfluence: settings.fountainTiltInfluence,
          tiltEllipseRatio: settings.fountainTiltEllipseRatio,
          // 🆕 Realismo v2.0
          jitter: settings.fountainJitter,
          velocitySensitivity: settings.fountainVelocitySensitivity,
          inkAccumulation: settings.fountainInkAccumulation,
          smoothPath: settings.fountainSmoothPath,
          thinning: settings.fountainThinning,
          pressureRate: settings.fountainPressureRate,
          nibAngleRad: settings.fountainNibAngleDeg * 3.14159265 / 180.0,
          nibStrength: settings.fountainNibStrength,
        );
      case BrushType.pencil:
        PencilBrush.drawStrokeWithSettings(
          canvas,
          stroke.points,
          color,
          stroke.width,
          baseOpacity: settings.pencilBaseOpacity,
          maxOpacity: settings.pencilMaxOpacity,
          blurRadius: settings.pencilBlurRadius,
          minPressure: settings.pencilMinPressure,
          maxPressure: settings.pencilMaxPressure,
        );
      case BrushType.highlighter:
        HighlighterBrush.drawStrokeWithSettings(
          canvas,
          stroke.points,
          color,
          stroke.width,
          opacity: settings.highlighterOpacity,
          widthMultiplier: settings.highlighterWidthMultiplier,
        );
    }
  }

  void _drawCachedBackground(Canvas canvas, Size size) {
    // Invalidate cache on size OR theme change
    if (_backgroundCache == null ||
        _backgroundSize != size ||
        _backgroundIsDark != isDark) {
      final recorder = ui.PictureRecorder();
      final bgCanvas = Canvas(recorder);

      // 🌙 Fill background based on theme
      final bgPaint =
          Paint()..color = isDark ? const Color(0xFF1E1E1E) : Colors.white;
      bgCanvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

      // 🔲 Grid with themed colors
      final gridPaint =
          Paint()
            ..color = isDark ? Colors.grey[700]! : Colors.grey[200]!
            ..strokeWidth = 0.5
            ..style = PaintingStyle.stroke;

      for (double x = 0; x < size.width; x += 50) {
        bgCanvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y < size.height; y += 50) {
        bgCanvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }

      _backgroundCache = recorder.endRecording();
      _backgroundSize = size;
      _backgroundIsDark = isDark;
    }
    canvas.drawPicture(_backgroundCache!);
  }

  static void clearCache() {
    _completedStrokesImage?.dispose();
    _completedStrokesImage = null;
    _imageStrokesCount = 0;
    _imageSize = null;
    _imagePixelRatio = null;
    _backgroundCache = null;
    _backgroundSize = null;
    _backgroundIsDark = null;
  }

  @override
  bool shouldRepaint(BrushTestPainter oldDelegate) {
    // 🚀 repaintKey changes on undo/clear to force immediate repaint
    if (oldDelegate.repaintKey != repaintKey) return true;
    if (oldDelegate.strokes.length != strokes.length) return true;
    if (currentStroke != null && currentStroke!.points.isNotEmpty) return true;
    if (oldDelegate.devicePixelRatio != devicePixelRatio) return true;
    if (oldDelegate.isDark != isDark) return true;
    return false;
  }
}
