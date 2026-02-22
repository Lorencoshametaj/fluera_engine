/// 📐 LAYOUT GRID OVERLAY — Renders layout grids on top of frames.
///
/// Paints column/row/uniform grid lines as a transparent overlay.
/// Drop this into the canvas overlay stack to visualize grid configurations.
///
/// ```dart
/// LayoutGridOverlay(
///   grids: frame.layoutGrids,
///   frameRect: frame.worldBounds,
///   canvasOffset: canvasOffset,
///   canvasScale: canvasScale,
/// )
/// ```
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/layout/layout_grid.dart';

/// Paints layout grids for a single frame on the canvas.
class LayoutGridOverlay extends StatelessWidget {
  /// The grids to render.
  final List<LayoutGrid> grids;

  /// The frame's bounds in canvas coordinates.
  final Rect frameRect;

  /// Current canvas pan offset.
  final Offset canvasOffset;

  /// Current canvas zoom scale.
  final double canvasScale;

  const LayoutGridOverlay({
    super.key,
    required this.grids,
    required this.frameRect,
    required this.canvasOffset,
    required this.canvasScale,
  });

  @override
  Widget build(BuildContext context) {
    final visibleGrids = grids.where((g) => g.isVisible).toList();
    if (visibleGrids.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: CustomPaint(
        painter: _LayoutGridPainter(
          grids: visibleGrids,
          frameRect: frameRect,
          canvasOffset: canvasOffset,
          canvasScale: canvasScale,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _LayoutGridPainter extends CustomPainter {
  final List<LayoutGrid> grids;
  final Rect frameRect;
  final Offset canvasOffset;
  final double canvasScale;

  _LayoutGridPainter({
    required this.grids,
    required this.frameRect,
    required this.canvasOffset,
    required this.canvasScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final grid in grids) {
      _paintGrid(canvas, grid);
    }
  }

  void _paintGrid(Canvas canvas, LayoutGrid grid) {
    final paint =
        Paint()
          ..color = grid.color
          ..style = PaintingStyle.fill;

    final strokePaint =
        Paint()
          ..color = grid.color.withAlpha((grid.color.a * 255 * 0.6).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 / canvasScale;

    switch (grid.type) {
      case LayoutGridType.columns:
        _paintColumns(canvas, grid, paint, strokePaint);
      case LayoutGridType.rows:
        _paintRows(canvas, grid, paint, strokePaint);
      case LayoutGridType.grid:
        _paintUniformGrid(canvas, grid, strokePaint);
    }
  }

  void _paintColumns(Canvas canvas, LayoutGrid grid, Paint fill, Paint stroke) {
    final cells = grid.computeCells(frameRect.width);
    for (final cell in cells) {
      final rect = Rect.fromLTWH(
        (frameRect.left + cell.offset) * canvasScale + canvasOffset.dx,
        frameRect.top * canvasScale + canvasOffset.dy,
        cell.size * canvasScale,
        frameRect.height * canvasScale,
      );
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, stroke);
    }
  }

  void _paintRows(Canvas canvas, LayoutGrid grid, Paint fill, Paint stroke) {
    final cells = grid.computeCells(frameRect.height);
    for (final cell in cells) {
      final rect = Rect.fromLTWH(
        frameRect.left * canvasScale + canvasOffset.dx,
        (frameRect.top + cell.offset) * canvasScale + canvasOffset.dy,
        frameRect.width * canvasScale,
        cell.size * canvasScale,
      );
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, stroke);
    }
  }

  void _paintUniformGrid(Canvas canvas, LayoutGrid grid, Paint stroke) {
    final left = frameRect.left * canvasScale + canvasOffset.dx;
    final top = frameRect.top * canvasScale + canvasOffset.dy;
    final right = frameRect.right * canvasScale + canvasOffset.dx;
    final bottom = frameRect.bottom * canvasScale + canvasOffset.dy;
    final step = grid.cellSize * canvasScale;

    if (step < 2) return; // Skip when too zoomed out.

    // Vertical lines.
    double x = left;
    while (x <= right) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), stroke);
      x += step;
    }
    // Horizontal lines.
    double y = top;
    while (y <= bottom) {
      canvas.drawLine(Offset(left, y), Offset(right, y), stroke);
      y += step;
    }
  }

  @override
  bool shouldRepaint(_LayoutGridPainter old) =>
      grids != old.grids ||
      frameRect != old.frameRect ||
      canvasOffset != old.canvasOffset ||
      canvasScale != old.canvasScale;
}
