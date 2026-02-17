import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../../drawing/models/pro_drawing_point.dart';
import '../../drawing/models/pro_brush_settings.dart';
import '../../core/models/shape_type.dart';
import './shape_painter.dart';
import '../../drawing/brushes/brushes.dart';
import './paper_pattern_painter.dart';

/// Painter professionale per rendering strokes e geometric shapes
/// Implementa le stesse strategie ottimizzate del test canvas
/// Supporta rendering via BrushEngine centralizzato
class ProStrokePainter extends CustomPainter {
  final List<ProStroke> completedStrokes;
  final List<GeometricShape> completedShapes;
  final List<ProDrawingPoint>? currentStroke;
  final GeometricShape? currentShape;
  final ProPenType currentPenType;
  final Color currentColor;
  final double currentWidth;
  final ProBrushSettings currentSettings;

  // Parametri for the sfondo infinito
  final String paperType;
  final Color backgroundColor;
  final double canvasScale; // Zoom level to optimize il margine

  // Cache statica dello sfondo to avoid ridisegno continuo
  static ui.Picture? _cachedBackground;
  static String? _cachedPaperType;
  static Color? _cachedBackgroundColor;
  static Size? _cachedSize;
  static double? _cachedScale;

  ProStrokePainter({
    required this.completedStrokes,
    required this.completedShapes,
    this.currentStroke,
    this.currentShape,
    required this.currentPenType,
    required this.currentColor,
    required this.currentWidth,
    this.currentSettings = ProBrushSettings.defaultSettings,
    required this.paperType,
    required this.backgroundColor,
    required this.canvasScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Prima disegna lo sfondo infinito
    _drawInfiniteBackground(canvas, size);

    // 1. Draw all completed geometric shapes
    for (final shape in completedShapes) {
      ShapePainter.drawShape(canvas, shape);
    }

    // 2. Draw the current shape in preview
    if (currentShape != null) {
      ShapePainter.drawShape(canvas, currentShape!, isPreview: true);
    }

    // 3. Draw all i completed strokes (puro vettoriale)
    for (final stroke in completedStrokes) {
      _drawStroke(
        canvas,
        stroke.points,
        stroke.color,
        stroke.baseWidth,
        stroke.penType,
        stroke.settings,
      );
    }

    // 4. Draw the current stroke (if present)
    if (currentStroke != null && currentStroke!.isNotEmpty) {
      _drawStroke(
        canvas,
        currentStroke!,
        currentColor,
        currentWidth,
        currentPenType,
        currentSettings,
        isLive: true, // ← Rendering live, deve matchare CurrentStrokePainter
      );
    }
  }

  /// Draws the infinite background with caching for maximum performance
  /// Lo sfondo is drawn una sola volta e poi riutilizzato
  /// The margine si adatta allo zoom to avoid blocchi when dezooma
  void _drawInfiniteBackground(Canvas canvas, Size size) {
    // 🎨 INFINITE CANVAS: draw very large background
    // If size is infinita, usa dimensioni molto grandi (100.000 x 100.000)
    final effectiveSize = size.isInfinite ? const Size(100000, 100000) : size;

    // Margine adattivo: more si dezooma (scale < 1), meno margine serve
    // Più si zooma (scale > 1), more margine serve per pan fluido
    // Formula: margine base * scale, con limiti min/max
    final baseMargin = 1500.0;
    final adaptiveMargin = (baseMargin * canvasScale).clamp(300.0, 3000.0);

    final extendedSize = Size(
      effectiveSize.width + adaptiveMargin * 2,
      effectiveSize.height + adaptiveMargin * 2,
    );

    // Check se dobbiamo rigenerare la cache
    final needsRegeneration =
        _cachedBackground == null ||
        _cachedPaperType != paperType ||
        _cachedBackgroundColor != backgroundColor ||
        _cachedSize != extendedSize ||
        _cachedScale != canvasScale;

    if (needsRegeneration) {
      // 🗑️ Save the old Picture for dispose AFTER rendering
      final oldPicture = _cachedBackground;

      // Genera nuovo background cachato
      final recorder = ui.PictureRecorder();
      final recordCanvas = Canvas(recorder);

      final backgroundPainter = PaperPatternPainter(
        paperType: paperType,
        backgroundColor: backgroundColor,
        scale: 37.8, // 1cm = 37.8px (stessa scala del BackgroundPainter)
      );

      backgroundPainter.paint(recordCanvas, extendedSize);

      // Save in the cache PRIMA di disporre il vecchio
      _cachedBackground = recorder.endRecording();
      _cachedPaperType = paperType;
      _cachedBackgroundColor = backgroundColor;
      _cachedSize = extendedSize;
      _cachedScale = canvasScale;

      // 🗑️ Now dispose the old Picture safely
      // Use scheduleMicrotask per disporre after the current frame
      if (oldPicture != null) {
        Future.microtask(() => oldPicture.dispose());
      }
    }

    // Draw il background cachato (velocissimo!)
    canvas.save();
    canvas.translate(-adaptiveMargin, -adaptiveMargin);
    canvas.drawPicture(_cachedBackground!);
    canvas.restore();
  }

  void _drawStroke(
    Canvas canvas,
    List<ProDrawingPoint> points,
    Color color,
    double baseWidth,
    ProPenType penType,
    ProBrushSettings settings, {
    bool isLive = false,
  }) {
    if (points.isEmpty) return;

    // 🎨 Rendering via unified BrushEngine
    BrushEngine.renderStroke(
      canvas,
      points,
      color,
      baseWidth,
      penType,
      settings,
      isLive: isLive,
    );
  }

  @override
  bool shouldRepaint(ProStrokePainter oldDelegate) {
    return completedStrokes != oldDelegate.completedStrokes ||
        currentStroke != oldDelegate.currentStroke ||
        completedShapes != oldDelegate.completedShapes ||
        currentShape != oldDelegate.currentShape;
  }

  /// 🗑️ Pulisce la cache statica (chiamare when chiude il canvas)
  static void clearCache() {
    _cachedBackground?.dispose();
    _cachedBackground = null;
    _cachedPaperType = null;
    _cachedBackgroundColor = null;
    _cachedSize = null;
    _cachedScale = null;
  }
}
