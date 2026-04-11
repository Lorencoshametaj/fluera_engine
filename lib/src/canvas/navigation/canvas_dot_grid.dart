import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../infinite_canvas_controller.dart';

/// 🔵 Canvas dot grid — subtle visual reference for orientation and alignment.
///
/// DESIGN PRINCIPLES:
/// - Dots adapt density with zoom: denser at high zoom, sparser at low.
/// - Semi-transparent and non-intrusive — never competes with content.
/// - Rendered in canvas space (moves with pan/zoom).
/// - Color adapts to canvas background for visibility.
/// - Performance: only draws dots visible in the current viewport.
///
/// Major gridlines appear at larger intervals with slightly bigger dots.
class CanvasDotGrid extends StatelessWidget {
  final InfiniteCanvasController controller;
  final Color canvasBackground;

  const CanvasDotGrid({
    super.key,
    required this.controller,
    this.canvasBackground = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return IgnorePointer(
          child: CustomPaint(
            painter: _DotGridPainter(
              offset: controller.offset,
              scale: controller.scale,
              canvasBackground: canvasBackground,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final Offset offset;
  final double scale;
  final Color canvasBackground;

  _DotGridPainter({
    required this.offset,
    required this.scale,
    required this.canvasBackground,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Don't draw grid at very low zoom levels (too dense)
    if (scale < 0.15) return;

    final isLight = canvasBackground.computeLuminance() > 0.5;

    // Adaptive grid spacing based on zoom level.
    // At 1x zoom: 40px spacing. Doubles when zooming out, halves when in.
    double baseSpacing = 40.0;
    // Find a spacing that keeps screen-space distance in [20, 80] px
    double spacing = baseSpacing;
    while (spacing * scale < 20) {
      spacing *= 2;
    }
    while (spacing * scale > 80) {
      spacing /= 2;
    }

    // Major grid every 5 minor dots
    final majorEvery = 5;

    // Dot color and size
    final minorColor =
        isLight
            ? Colors.black.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.06);
    final majorColor =
        isLight
            ? Colors.black.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.12);

    final minorRadius = 1.0;
    final majorRadius = 1.5;

    final minorPaint = Paint()..color = minorColor;
    final majorPaint = Paint()..color = majorColor;

    // Visible area in canvas coordinates
    final topLeftCanvas = Offset(-offset.dx / scale, -offset.dy / scale);
    final bottomRightCanvas = Offset(
      (-offset.dx + size.width) / scale,
      (-offset.dy + size.height) / scale,
    );

    // Calculate grid range
    final startCol = (topLeftCanvas.dx / spacing).floor() - 1;
    final endCol = (bottomRightCanvas.dx / spacing).ceil() + 1;
    final startRow = (topLeftCanvas.dy / spacing).floor() - 1;
    final endRow = (bottomRightCanvas.dy / spacing).ceil() + 1;

    // Safety cap: max 200x200 = 40,000 dots (plenty for any screen)
    final cols = (endCol - startCol).clamp(0, 200);
    final rows = (endRow - startRow).clamp(0, 200);

    for (int c = 0; c < cols; c++) {
      final col = startCol + c;
      final canvasX = col * spacing;
      final screenX = canvasX * scale + offset.dx;

      final isMajorCol = col % majorEvery == 0;

      for (int r = 0; r < rows; r++) {
        final row = startRow + r;
        final canvasY = row * spacing;
        final screenY = canvasY * scale + offset.dy;

        final isMajor = isMajorCol && row % majorEvery == 0;

        canvas.drawCircle(
          Offset(screenX, screenY),
          isMajor ? majorRadius : minorRadius,
          isMajor ? majorPaint : minorPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) =>
      offset != old.offset ||
      scale != old.scale ||
      canvasBackground != old.canvasBackground;
}
