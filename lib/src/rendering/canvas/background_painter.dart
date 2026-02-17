import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import './paper_pattern_painter.dart';
import '../../canvas/infinite_canvas_controller.dart';

/// 🎨 BACKGROUND PAINTER - Viewport-level rendering per canvas infinito
///
/// ARCHITETTURA:
/// - ✅ Render at viewport level (outside Transform)
/// - ✅ Covers ALL directions (including negative coordinates)
/// - ✅ Only visible tiles printed (~4-9 per frame)
///
/// PERFORMANCE:
/// - 🚀 repaint: controller → paint() called on every pan/zoom frame
/// - 🚀 Per-frame cost: ~10 draw calls (negligible)
/// - 🚀 Wrapped in RepaintBoundary → no cascade to siblings
class BackgroundPainter extends CustomPainter {
  final String paperType;
  final Color backgroundColor;
  final InfiniteCanvasController controller;

  // 🚀 TILE CACHE: a single small tile to print repeatedly
  static ui.Picture? _cachedTile;
  static String? _cachedPaperType;
  static Color? _cachedBackgroundColor;
  static double _cachedTileSize = _tileSize;
  static const double _tileSize = 1000.0;

  // 1cm = 37.8px (96 DPI standard)
  static const double _patternScale = 37.8;

  BackgroundPainter({
    required this.paperType,
    required this.backgroundColor,
    required this.controller,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    // 1️⃣ Solid background on the entire viewport
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    // 2️⃣ Se is blank, non serve disegnare il pattern
    if (paperType == 'blank') return;

    // 3️⃣ Genera/aggiorna tile cache
    _regenerateTileIfNeeded();

    // 4️⃣ Viewport-level tile rendering (~4-9 visible tiles)
    final canvasScale = controller.scale;
    final canvasOffset = controller.offset;
    final scaledTileSize = _cachedTileSize * canvasScale;

    final originScreenX = canvasOffset.dx;
    final originScreenY = canvasOffset.dy;

    // Primo/ultimo tile visibile (supporta coordinate negative)
    final firstTileX = ((0 - originScreenX) / scaledTileSize).floor();
    final firstTileY = ((0 - originScreenY) / scaledTileSize).floor();
    final lastTileX = ((size.width - originScreenX) / scaledTileSize).ceil();
    final lastTileY = ((size.height - originScreenY) / scaledTileSize).ceil();

    // 5️⃣ Print only visible tiles
    for (int ty = firstTileY; ty <= lastTileY; ty++) {
      for (int tx = firstTileX; tx <= lastTileX; tx++) {
        final screenX = originScreenX + tx * scaledTileSize;
        final screenY = originScreenY + ty * scaledTileSize;

        canvas.save();
        canvas.translate(screenX, screenY);
        canvas.scale(canvasScale);
        canvas.drawPicture(_cachedTile!);
        canvas.restore();
      }
    }
  }

  /// Rigenera il tile cache only if necessario
  void _regenerateTileIfNeeded() {
    final needsRegeneration =
        _cachedTile == null ||
        _cachedPaperType != paperType ||
        _cachedBackgroundColor != backgroundColor;

    if (!needsRegeneration) return;

    final oldTile = _cachedTile;

    // 🔧 Calculate tile size aligned to grid to avoid
    // linee spurie ai bordi tra tile adiacenti.
    final alignedTileSize = _computeAlignedTileSize(paperType, _patternScale);

    final recorder = ui.PictureRecorder();
    final recordCanvas = Canvas(recorder);

    final tilePainter = PaperPatternPainter(
      paperType: paperType,
      backgroundColor: backgroundColor,
      scale: _patternScale,
    );

    tilePainter.paint(recordCanvas, Size(alignedTileSize, alignedTileSize));

    _cachedTile = recorder.endRecording();
    _cachedPaperType = paperType;
    _cachedBackgroundColor = backgroundColor;
    _cachedTileSize = alignedTileSize;

    if (oldTile != null) {
      Future.microtask(() => oldTile.dispose());
    }
  }

  /// Calculates la size of the tile allineata allo spacing del pattern.
  static double _computeAlignedTileSize(String paperType, double scale) {
    double? baseSpacing;
    switch (paperType) {
      case 'grid_5mm':
        baseSpacing = 5.0;
        break;
      case 'grid_1cm':
        baseSpacing = 10.0;
        break;
      case 'grid_2cm':
        baseSpacing = 20.0;
        break;
      case 'dots':
        baseSpacing = 20.0;
        break;
      case 'dots_dense':
        baseSpacing = 10.0;
        break;
      case 'graph':
        baseSpacing = 10.0;
        break;
      case 'hex':
        baseSpacing = 20.0;
        break;
      case 'isometric':
        baseSpacing = 20.0;
        break;
      default:
        return _tileSize;
    }

    final gridPitch = baseSpacing * scale;
    final tilesNeeded = (500.0 / gridPitch).ceil().clamp(1, 100);
    return gridPitch * tilesNeeded;
  }

  @override
  bool shouldRepaint(BackgroundPainter oldDelegate) {
    return oldDelegate.paperType != paperType ||
        oldDelegate.backgroundColor != backgroundColor;
  }

  /// 🗑️ Pulisce la cache statica (chiamare when chiude il canvas)
  static void clearCache() {
    _cachedTile?.dispose();
    _cachedTile = null;
    _cachedPaperType = null;
    _cachedBackgroundColor = null;
    _cachedTileSize = _tileSize;
  }
}
