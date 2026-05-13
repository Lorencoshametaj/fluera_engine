part of '../../fluera_canvas_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// ERASER PAINTERS — extracted from _build_ui.dart
//
// ⚠️ The trail + particle painters previously defined here have been
// extracted to `lib/src/rendering/canvas/eraser_overlay_painters.dart`
// as public [EraserTrailPainter] / [EraserParticlePainter] so that
// [FlueraCanvasView] (outside this library) can use the same FX.
// The remaining painters below stay private — they are screen-specific
// (lasso path, protected regions, ghost preview, magnetic snap, ...).
// ═══════════════════════════════════════════════════════════════════

/// 🎯 CustomPainter for crosshair at eraser center
class _CrosshairPainter extends CustomPainter {
  final double radius;
  final Color color;

  _CrosshairPainter({
    required this.radius,
    this.color = const Color.fromRGBO(255, 255, 255, 0.6),
  });

  @override
  void paint(ui.Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final length = radius * 0.35; // Crosshair = 35% of radius

    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round;

    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - length, center.dy),
      Offset(center.dx + length, center.dy),
      paint,
    );
    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - length),
      Offset(center.dx, center.dy + length),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.color != color;
}


// 4 painter privati (lasso path, protected regions, ghost preview, magnetic
// snap) sono stati estratti a `lib/src/rendering/canvas/eraser_overlay_painters.dart`
// come public `EraserLassoPathPainter` / `EraserProtectedRegionPainter` /
// `EraserGhostPreviewPainter` / `MagneticSnapIndicatorPainter` così che
// `FlueraCanvasView` (fuori library screen) possa renderizzarli.
